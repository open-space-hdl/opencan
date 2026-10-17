---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Bit-level model of a CAN node of the network model (Bosch CAN Specification 2.0 part B), written from the
-- specification and independent of the RTL. The node runs in continuous time with its own bit time (bit rate and
-- deviation in ppm of the control object). It synchronises on recessive-to-dominant edges only: on every such edge
-- in a bit in which it does not drive dominant, the bit restarts at the edge. It sends the frames of its transmit
-- queue, arbitrates and retransmits, acknowledges correct frames, detects bit, stuff, CRC, form and acknowledge
-- errors, sends active error flags and overload flags, and logs every frame and error it observes. The node is
-- always error active (no fault confinement). Fault injection and configuration: ocan_tb_net_pkg.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_tb_can_node is
    generic (
        Index_g : natural := 0
    );
    port (
        Tx : out   std_logic := '1';
        Rx : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_tb_can_node is

begin

    p_node : process is
        -- Field of the current bit
        type Field_t is (FIntegrate, FIdle, FFrame, FCrcDel, FAckSlot, FAckDel, FEof, FInter, FFlag, FDelim);

        variable Field_v     : Field_t   := FIntegrate;
        variable Cfg_v       : TbNodeCfg_t;
        variable Period_v    : time;
        variable BitStart_v  : time      := 0 ns;
        variable Drive_v     : std_logic := '1';
        variable LastDrive_v : std_logic := '1';
        variable Bit_v       : std_logic := '1';
        variable PrevBit_v   : std_logic := '1';
        variable Cnt_v       : natural   := 0;
        -- Transmitter
        variable IsTx_v      : boolean := false;
        variable TxFrame_v   : CanFrame_t;
        variable Wire_v      : CanBits_t;
        variable Corrupt_v   : integer := -1;
        -- Receiver
        variable Si_v        : natural   := 0;
        variable Run_v       : natural   := 0;
        variable Last_v      : std_logic := 'X';
        variable U_v         : CanBits_t;
        variable Need_v      : natural   := 0;
        variable Header_v    : natural   := 0;
        variable Done_v      : boolean   := false;
        variable CrcOk_v     : boolean   := false;
        variable CrcErr_v    : boolean   := false;
        variable AckNext_v   : boolean   := false;
        variable Acked_v     : boolean   := false;
        variable InjBit_v    : integer   := -1;
        variable OvlNext_v   : boolean   := false;
        variable Seen1_v     : boolean   := false;
        variable StuffBit_v  : boolean   := false;

        -- Decoded frame of the destuffed bits
        impure function decoded return CanFrame_t is
            variable F_v : CanFrame_t;
            variable D_v : natural;
        begin
            F_v.Id   := (others => '0');
            F_v.Data := (others => '0');
            F_v.Ide  := U_v.Bits(13);

            for I in 0 to 10 loop
                F_v.Id(28 - I) := U_v.Bits(1 + I);
            end loop;

            if F_v.Ide = '1' then

                for I in 0 to 17 loop
                    F_v.Id(17 - I) := U_v.Bits(14 + I);
                end loop;

                F_v.Rtr := U_v.Bits(32);
            else
                F_v.Rtr := U_v.Bits(12);
            end if;
            F_v.Dlc := to_integer(unsigned(U_v.Bits(Header_v - 4 to Header_v - 1)));
            D_v     := canDataBytes(F_v);

            for I in 0 to 8 * D_v - 1 loop
                F_v.Data(63 - I) := U_v.Bits(Header_v + I);
            end loop;

            return F_v;
        end function;

        procedure log (
            kind : TbLogKind_t;
            err  : TbErrKind_t;
            own  : boolean) is
            variable E_v : TbLog_t;
        begin
            E_v.Kind   := kind;
            E_v.Own    := own;
            E_v.Acked  := Acked_v;
            E_v.Err    := err;
            E_v.ErrBit := Si_v;
            E_v.T      := now;
            if kind = TbFrame then
                E_v.Frame := decoded;
            else
                E_v.Frame := canStd(0, 0);
            end if;
            Net_v.logPush(Index_g, E_v);
        end procedure;

        -- End of a transmission attempt (sent or failed): a corruption is used once per attempt
        procedure endAttempt is
        begin
            if IsTx_v and Corrupt_v >= 0 then
                Net_v.useCorrupt(Index_g);
            end if;
            IsTx_v    := false;
            Corrupt_v := -1;
        end procedure;

        -- Error detected in the current bit: error flag from the next bit on (or integration for a listening node)
        procedure error (
            err : TbErrKind_t) is
        begin
            log(TbError, err, IsTx_v);
            Net_v.countUp(Index_g, TbCntErrors);
            endAttempt;
            Cnt_v := 0;
            if Cfg_v.Listen then
                Field_v := FIntegrate;
            else
                Field_v := FFlag;
            end if;
        end procedure;

        -- Overload condition in the current bit: overload flag from the next bit on
        procedure overload is
        begin
            log(TbOverload, TbErrNone, false);
            Net_v.countUp(Index_g, TbCntOverloads);
            Cnt_v := 0;
            if Cfg_v.Listen then
                Field_v := FIntegrate;
            else
                Field_v := FFlag;
            end if;
        end procedure;

        -- Start of a frame (the current bit is its start of frame)
        procedure frameBegin is
        begin
            Field_v   := FFrame;
            Si_v      := 0;
            Run_v     := 0;
            Last_v    := 'X';
            U_v.Len   := 0;
            U_v.Bits  := (others => '1');
            Need_v    := 0;
            Header_v  := 0;
            Done_v    := false;
            CrcOk_v   := false;
            CrcErr_v  := false;
            AckNext_v := false;
            Acked_v   := false;
            InjBit_v  := -1;
            if not IsTx_v then
                InjBit_v := Net_v.errFlagBit(Index_g);
            end if;
        end procedure;

        -- Takes the head of the transmit queue
        procedure txBegin is
        begin
            IsTx_v    := true;
            TxFrame_v := Net_v.txPeek(Index_g);
            Wire_v    := canWire(TxFrame_v, '1');
            Corrupt_v := Net_v.corruptBit(Index_g);
        end procedure;

        -- Bit of the stuffed part of a frame
        procedure frameBit is
            variable Pos_v : natural;
        begin
            StuffBit_v := Run_v = 5;
            Pos_v      := U_v.Len;
            -- Transmitter: monitoring and arbitration
            if IsTx_v and Bit_v /= Drive_v then
                if Drive_v = '1' and not StuffBit_v and Pos_v >= 1 and Pos_v <= canArbBits(TxFrame_v) then
                    Net_v.countUp(Index_g, TbCntArbLost);
                    IsTx_v    := false;
                    Corrupt_v := -1;
                else
                    error(TbErrBit);
                    return;
                end if;
            end if;
            -- Destuffing
            if StuffBit_v then
                if Bit_v = Last_v then
                    error(TbErrStuff);
                    return;
                end if;
                Last_v := Bit_v;
                Run_v  := 1;
                if Done_v then
                    Field_v := FCrcDel;
                end if;
                return;
            end if;
            U_v.Bits(U_v.Len) := Bit_v;
            U_v.Len           := U_v.Len + 1;
            if Bit_v = Last_v then
                Run_v := Run_v + 1;
            else
                Run_v := 1;
            end if;
            Last_v := Bit_v;
            -- Length of the frame once the IDE bit and the DLC are known
            if U_v.Len = 14 then
                if U_v.Bits(13) = '1' then
                    Header_v := 39;
                else
                    Header_v := 19;
                end if;
            end if;
            if Header_v > 0 and U_v.Len = Header_v then
                Need_v := Header_v + 8 * canDataBytes(decoded) + 15;
            end if;
            -- End of the CRC sequence
            if Need_v > 0 and U_v.Len = Need_v then
                CrcOk_v := canCrc15(U_v.Bits, Need_v - 15) = U_v.Bits(Need_v - 15 to Need_v - 1);
                Done_v  := true;
                if Run_v < 5 then
                    Field_v := FCrcDel;
                end if;
            end if;
        end procedure;

        -- Injected error flag in the current bit
        variable Inj_v : boolean := false;
    begin

        loop
            Cfg_v    := Net_v.getCfg(Index_g);
            Period_v := Cfg_v.BitPeriod + (Cfg_v.BitPeriod * Cfg_v.Ppm) / 1000000;

            -- *** Bit to drive in this bit ***
            Drive_v := '1';

            case Field_v is
                when FIdle =>
                    if Net_v.txCount(Index_g) > 0 and not Cfg_v.Listen then
                        txBegin;
                        frameBegin;
                    end if;
                when FInter =>
                    if Cnt_v = 0 and OvlNext_v then
                        OvlNext_v := false;
                        overload;
                    elsif Cnt_v = 2 and Cfg_v.EarlyStart and Net_v.txCount(Index_g) > 0 and not Cfg_v.Listen then
                        txBegin;
                        frameBegin;
                    end if;
                when FFrame =>
                    -- Injected error flag, optionally only in frames with a given base identifier
                    Inj_v := not IsTx_v and InjBit_v >= 0 and Si_v = InjBit_v;
                    if Inj_v and Net_v.errFlagId(Index_g) >= 0 then
                        Inj_v := U_v.Len >= 12 and to_integer(unsigned(U_v.Bits(1 to 11))) = Net_v.errFlagId(Index_g);
                    end if;
                    if Inj_v then
                        Net_v.useErrFlag(Index_g);
                        log(TbError, TbErrInjected, false);
                        Net_v.countUp(Index_g, TbCntErrors);
                        Field_v := FFlag;
                        Cnt_v   := 0;
                    end if;
                when others =>
                    null;
            end case;

            case Field_v is
                when FFrame | FCrcDel | FAckSlot | FAckDel | FEof =>
                    if IsTx_v then
                        Drive_v := Wire_v.Bits(Si_v);
                        if Si_v = Corrupt_v then
                            Drive_v := not Drive_v;
                        end if;
                    elsif Field_v = FAckSlot and AckNext_v then
                        Drive_v := '0';
                    end if;
                when FFlag =>
                    if not Cfg_v.Listen then
                        Drive_v := '0';
                    end if;
                when others =>
                    null;
            end case;

            if Drive_v = '1' and LastDrive_v = '0' and Cfg_v.RecDelay > 0 ns then
                Tx <= transport '1' after Cfg_v.RecDelay;
            else
                Tx <= Drive_v;
            end if;
            LastDrive_v := Drive_v;

            -- *** Wait for the sample point; a recessive-to-dominant edge restarts the bit ***
            loop
                exit when now >= BitStart_v + (Period_v * Cfg_v.SamplePct) / 100;
                wait on Rx for BitStart_v + (Period_v * Cfg_v.SamplePct) / 100 - now;
                if Rx'event and to_X01(Rx) = '0' and PrevBit_v = '1' and Drive_v = '1' and now > BitStart_v then
                    BitStart_v := now;
                end if;
            end loop;

            Bit_v := to_X01(Rx);
            if Bit_v = 'X' then
                Bit_v := '1';
            end if;

            -- *** Process the sampled bit ***
            case Field_v is

                when FIntegrate =>
                    if Bit_v = '1' then
                        Cnt_v := Cnt_v + 1;
                        if Cnt_v >= 11 then
                            Field_v := FIdle;
                        end if;
                    else
                        Cnt_v := 0;
                    end if;

                when FIdle =>
                    if Bit_v = '0' then
                        -- Start of frame of another node
                        frameBegin;
                        frameBit;
                        Si_v := Si_v + 1;
                    end if;

                when FFrame =>
                    frameBit;
                    Si_v := Si_v + 1;

                when FCrcDel =>
                    if Bit_v = '0' then
                        error(TbErrForm);
                    else
                        AckNext_v := not IsTx_v and CrcOk_v and Cfg_v.Ack and not Cfg_v.Listen;
                        CrcErr_v  := not IsTx_v and not CrcOk_v;
                        Field_v   := FAckSlot;
                        Si_v      := Si_v + 1;
                    end if;

                when FAckSlot =>
                    Acked_v   := Bit_v = '0';
                    AckNext_v := false;
                    if IsTx_v and Bit_v = '1' then
                        error(TbErrAck);
                    else
                        Field_v := FAckDel;
                        Si_v    := Si_v + 1;
                    end if;

                when FAckDel =>
                    if Bit_v = '0' then
                        error(TbErrForm);
                    elsif CrcErr_v then
                        error(TbErrCrc);
                    else
                        Field_v := FEof;
                        Cnt_v   := 0;
                        Si_v    := Si_v + 1;
                    end if;

                when FEof =>
                    if Bit_v = '0' and (IsTx_v or Cnt_v < 6) then
                        error(TbErrForm);
                    elsif Bit_v = '0' then
                        -- Receiver: dominant bit in the last bit of the end of frame (overload condition)
                        overload;
                    else
                        if Cnt_v = 5 and not IsTx_v then
                            log(TbFrame, TbErrNone, false);
                            Net_v.countUp(Index_g, TbCntRxFrames);
                        end if;
                        if Cnt_v = 6 then
                            if IsTx_v then
                                log(TbFrame, TbErrNone, true);
                                Net_v.countUp(Index_g, TbCntSent);
                                Net_v.txPop(Index_g);
                                endAttempt;
                            end if;
                            Field_v   := FInter;
                            Cnt_v     := 0;
                            OvlNext_v := Net_v.takeOverload(Index_g);
                        else
                            Cnt_v := Cnt_v + 1;
                        end if;
                        Si_v := Si_v + 1;
                    end if;

                when FInter =>
                    if Bit_v = '0' and Cnt_v < 2 then
                        overload;
                    elsif Bit_v = '0' then
                        -- Third bit of the intermission: start of frame (of this node with EarlyStart or of another
                        -- one; a node with a pending frame then sends it from the identifier on)
                        if not IsTx_v and Net_v.txCount(Index_g) > 0 and not Cfg_v.Listen then
                            txBegin;
                            Drive_v := '0';
                        end if;
                        frameBegin;
                        frameBit;
                        Si_v := Si_v + 1;
                    else
                        Cnt_v := Cnt_v + 1;
                        if Cnt_v = 3 then
                            Field_v := FIdle;
                        end if;
                    end if;

                when FFlag =>
                    Cnt_v := Cnt_v + 1;
                    if Cnt_v = 6 then
                        Field_v := FDelim;
                        Cnt_v   := 0;
                        Seen1_v := false;
                    end if;

                when FDelim =>
                    if Bit_v = '1' then
                        Seen1_v := true;
                        Cnt_v   := Cnt_v + 1;
                        if Cnt_v = 8 then
                            Field_v := FInter;
                            Cnt_v   := 0;
                        end if;
                    elsif Seen1_v then
                        error(TbErrForm);
                    end if;

            end case;

            PrevBit_v := Bit_v;

            -- *** Wait for the end of the bit; a recessive-to-dominant edge after a recessive bit starts the next ***
            loop
                exit when now >= BitStart_v + Period_v;
                wait on Rx for BitStart_v + Period_v - now;
                if Rx'event and to_X01(Rx) = '0' and Bit_v = '1' then
                    exit;
                end if;
            end loop;

            if now < BitStart_v + Period_v then
                BitStart_v := now;
            else
                BitStart_v := BitStart_v + Period_v;
            end if;
        end loop;

    end process;

end architecture;
