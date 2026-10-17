---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Self-test of the CAN network model: known-answer tests of the frame encoding and of the receiver against frames
-- of real buses (ocan_tb_kat_pkg), frame exchange between two model nodes, arbitration, error and overload frames,
-- bit times that differ in ppm, and the start of a frame in the third bit of the intermission.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_context;

library work;
    use work.ocan_tb_pkg.all;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_kat_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_tb_can_model_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_tb_can_model_tb is

    constant Bit_c : time := 1 us;

    signal RawTx  : std_logic := '1';
    signal BusOut : std_logic;

begin

    i_th : entity work.ocan_tb_can_model_th
        port map (
            RawTx  => RawTx,
            BusOut => BusOut
        );

    p_control : process is
        -- Frame of a known-answer record
        function katCan (K : KatFrame_t) return CanFrame_t is
            variable F_v : CanFrame_t;
        begin
            F_v.Ide  := K.Ide;
            F_v.Id   := K.Id;
            F_v.Rtr  := K.Rtr;
            F_v.Dlc  := K.Dlc;
            F_v.Data := K.Data;
            return F_v;
        end function;

        -- Waits until both transmit queues are empty and the bus has been idle for 12 bit times
        procedure waitDone (timeout : time := 20 ms) is
            constant End_c : time := now + timeout;
        begin

            while Net_v.txCount(0) > 0 or Net_v.txCount(1) > 0 loop
                wait for Bit_c;
                if now > End_c then
                    alert(TB_ERROR, "waitDone: timeout");
                    exit;
                end if;
            end loop;

            wait for 12 * Bit_c;
        end procedure;

        -- Number of log entries of a kind (own frames, frames of others, errors, overloads)
        impure function entries (
            idx  : natural;
            kind : TbLogKind_t;
            own  : boolean := false) return natural is
            variable N_v : natural := 0;
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(idx) - 1 loop
                E_v := Net_v.logGet(idx, I);
                if E_v.Kind = kind and (kind /= TbFrame or E_v.Own = own) then
                    N_v := N_v + 1;
                end if;
            end loop;

            return N_v;
        end function;

        -- n-th frame of others in the log of a node
        impure function rxFrame (
            idx : natural;
            n   : natural) return TbLog_t is
            variable N_v : natural := 0;
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(idx) - 1 loop
                E_v := Net_v.logGet(idx, I);
                if E_v.Kind = TbFrame and not E_v.Own then
                    if N_v = n then
                        return E_v;
                    end if;
                    N_v := N_v + 1;
                end if;
            end loop;

            alert(TB_ERROR, "rxFrame: no frame " & integer'image(n) & " in the log of node " & integer'image(idx));
            return E_v;
        end function;

        procedure checkFrame (
            got : CanFrame_t;
            exp : CanFrame_t;
            msg : string) is
        begin
            check_value(canEqual(got, exp), ERROR, msg & ": got " & canImage(got) & ", expected " & canImage(exp));
        end procedure;

        procedure setRate (
            idx : natural;
            ppm : integer := 0) is
            variable Cfg_v : TbNodeCfg_t := TbNodeCfgInit_c;
        begin
            Cfg_v.BitPeriod := Bit_c;
            Cfg_v.Ppm       := ppm;
            Net_v.setCfg(idx, Cfg_v);
        end procedure;

        -- Random frame of a node: the identifier ends with the node index, so frames of both nodes never have the
        -- same identifier
        impure function randomFrame (idx : natural) return CanFrame_t is
            variable Data_v : std_logic_vector(63 downto 0);
            variable Dlc_v  : natural;
            variable Rtr_v  : std_logic;
        begin
            Data_v := std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 32)) &
                      std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 32));
            Dlc_v  := random(0, 15);
            Rtr_v  := '0';
            if random(0, 7) = 0 then
                Rtr_v := '1';
            end if;
            if random(0, 1) = 0 then
                return canStd(2 * random(0, 1023) + idx, Dlc_v, Data_v, Rtr_v);
            else
                return canExt(2 * random(0, 2 ** 27 - 1) + idx, Dlc_v, Data_v, Rtr_v);
            end if;
        end function;

        type FrameList_t is array (0 to 63) of CanFrame_t;

        variable K_v     : KatFrame_t;
        variable W_v     : CanBits_t;
        variable E_v     : TbLog_t;
        variable List0_v : FrameList_t;
        variable List1_v : FrameList_t;
        variable A_v     : CanFrame_t;
        variable B_v     : CanFrame_t;
        variable T0_v    : time;
        variable T1_v    : time;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            setRate(0);
            setRate(1);
            wait for 20 * Bit_c;

            -- *** Known-answer test of the encoding ***
            if run("test_kat_encode") then

                for I in 0 to KatCount_c - 1 loop
                    K_v := katFrame(I);
                    W_v := canWire(katCan(K_v), '0');
                    check_value(W_v.Len, K_v.Len, ERROR, "KAT " & integer'image(I) & ": length");
                    check_value(W_v.Bits(0 to K_v.Len - 1) = K_v.Bits(0 to K_v.Len - 1), ERROR,
                                "KAT " & integer'image(I) & ": bits");
                    check_value(W_v.Stuff(0 to K_v.Len - 1) = K_v.Stuff(0 to K_v.Len - 1), ERROR,
                                "KAT " & integer'image(I) & ": stuff bits");
                    check_value(canFrameCrc(katCan(K_v)) = K_v.Crc, ERROR, "KAT " & integer'image(I) & ": CRC");
                end loop;

            -- *** Known-answer test of the receiver: the frames are driven bit by bit ***
            elsif run("test_kat_receive") then

                for I in 0 to KatCount_c - 1 loop
                    K_v := katFrame(I);

                    for B in 0 to K_v.Len - 1 loop
                        RawTx <= K_v.Bits(B);
                        wait for Bit_c;
                    end loop;

                    RawTx <= '1';
                    wait for 20 * Bit_c;
                end loop;

                for N in 0 to 1 loop
                    check_value(entries(N, TbFrame), KatCount_c, ERROR, "frames received");
                    check_value(entries(N, TbError), 0, ERROR, "no error");

                    for I in 0 to KatCount_c - 1 loop
                        E_v := rxFrame(N, I);
                        checkFrame(E_v.Frame, katCan(katFrame(I)), "KAT " & integer'image(I));
                        check_value(E_v.Acked, ERROR, "KAT " & integer'image(I) & ": acknowledged");
                    end loop;

                end loop;

            -- *** Random frames in both directions at the same time ***
            elsif run("test_exchange") then

                for I in 0 to 39 loop
                    List0_v(I) := randomFrame(0);
                    List1_v(I) := randomFrame(1);
                    Net_v.txPush(0, List0_v(I));
                    Net_v.txPush(1, List1_v(I));
                end loop;

                waitDone;
                check_value(entries(0, TbFrame, true), 40, ERROR, "frames sent by node 0");
                check_value(entries(1, TbFrame, true), 40, ERROR, "frames sent by node 1");
                check_value(entries(0, TbError) + entries(1, TbError), 0, ERROR, "no error");

                for I in 0 to 39 loop
                    checkFrame(rxFrame(1, I).Frame, List0_v(I), "node 1 frame " & integer'image(I));
                    checkFrame(rxFrame(0, I).Frame, List1_v(I), "node 0 frame " & integer'image(I));
                end loop;

            -- *** Arbitration: both nodes start in the same bit ***
            elsif run("test_arbitration") then

                -- Lower identifier wins; standard before extended with the same base; data before remote
                for Case_v in 0 to 2 loop

                    case Case_v is
                        when 0 =>
                            A_v := canStd(16#100#, 1, x"AA00000000000000");
                            B_v := canStd(16#0FF#, 1, x"5500000000000000");
                        when 1 =>
                            A_v := canExt(16#123# * 2 ** 18, 2, x"1122000000000000");
                            B_v := canStd(16#123#, 2, x"3344000000000000");
                        when others =>
                            A_v := canStd(16#456#, 0, Rtr => '1');
                            B_v := canStd(16#456#, 1, x"7700000000000000");
                    end case;

                    Net_v.logClear(0);
                    Net_v.logClear(1);
                    -- A long frame of node 0 occupies the bus while both nodes queue their frame
                    Net_v.txPush(0, canStd(16#7F0# - 1, 8, x"0123456789ABCDEF"));
                    wait for 30 * Bit_c;
                    Net_v.txPush(0, A_v);
                    Net_v.txPush(1, B_v);
                    waitDone;
                    check_value(Net_v.count(0, TbCntArbLost), Case_v + 1, ERROR,
                                "case " & integer'image(Case_v) & ": node 0 lost the arbitration");
                    check_value(Net_v.count(1, TbCntArbLost), 0, ERROR, "node 1 never lost");
                    checkFrame(rxFrame(0, 0).Frame, B_v, "case " & integer'image(Case_v) & ": winner at node 0");
                    checkFrame(rxFrame(1, 1).Frame, A_v, "case " & integer'image(Case_v) & ": loser at node 1");
                    T0_v := rxFrame(0, 0).T;
                    T1_v := rxFrame(1, 1).T;
                    check_value(T0_v < T1_v, ERROR, "the winner is sent first");
                    check_value(entries(0, TbError) + entries(1, TbError), 0, ERROR, "no error");
                end loop;

            -- *** Error frames: injected error flag, corrupted bit, overload frame ***
            elsif run("test_error_frames") then
                -- Node 1 destroys the first attempt of a frame of node 0
                A_v := canStd(16#321#, 4, x"DEADBEEF00000000");
                Net_v.setErrFlag(1, 25, 1);
                Net_v.txPush(0, A_v);
                waitDone;
                check_value(entries(1, TbError), 1, ERROR, "node 1: one injected error flag");
                check_value(entries(0, TbError), 1, ERROR, "node 0: one error");
                check_value(Net_v.count(0, TbCntSent), 1, ERROR, "node 0: sent once");
                check_value(entries(1, TbFrame), 1, ERROR, "node 1: received once");
                checkFrame(rxFrame(1, 0).Frame, A_v, "retransmitted frame");
                -- Node 0 sends one bit inverted: node 1 detects it, both send error flags, node 0 retransmits
                Net_v.logClear(0);
                Net_v.logClear(1);
                B_v := canExt(16#1ABCDE#, 8, x"0011223344556677");
                Net_v.setCorrupt(0, 60, 1);
                Net_v.txPush(0, B_v);
                waitDone;
                check_value(entries(1, TbError) >= 1, ERROR, "node 1 detected the corrupted bit");
                check_value(entries(0, TbError) >= 1, ERROR, "node 0 saw the error frame");
                check_value(entries(1, TbFrame), 1, ERROR, "node 1: received once");
                checkFrame(rxFrame(1, 0).Frame, B_v, "frame after the corruption");
                -- Overload flag of node 1 after the next frame
                Net_v.logClear(0);
                Net_v.logClear(1);
                Net_v.setOverload(1, 1);
                Net_v.txPush(0, A_v);
                Net_v.txPush(0, B_v);
                waitDone;
                check_value(entries(1, TbOverload), 1, ERROR, "node 1 sent an overload flag");
                check_value(entries(0, TbOverload), 1, ERROR, "node 0 saw the overload condition");
                check_value(entries(0, TbError) + entries(1, TbError), 0, ERROR, "no error");
                check_value(entries(1, TbFrame), 2, ERROR, "both frames received");

            -- *** CRC error: only the CRC sequence shows the corrupted bit; the raw driver acknowledges ***
            elsif run("test_crc_error") then
                -- Data bit 3 of the first data byte (stuffed bit 22, no stuff bit before it) sent inverted: the
                -- runs stay below five bits, so neither the stuffing nor the frame format reveals it
                A_v   := canStd(16#2AA#, 8, x"5555555555555555");
                W_v   := canWire(A_v, '1');
                Net_v.setCorrupt(0, 22, 1);
                Net_v.txPush(0, A_v);
                wait until BusOut = '0';
                wait for (W_v.Len - 9) * Bit_c;
                RawTx <= '0';
                wait for Bit_c;
                RawTx <= '1';
                waitDone;
                check_value(entries(1, TbError), 1, ERROR, "node 1: one error");

                for I in 0 to Net_v.logCount(1) - 1 loop
                    E_v := Net_v.logGet(1, I);
                    if E_v.Kind = TbError then
                        check_value(E_v.Err = TbErrCrc, ERROR, "node 1: CRC error, got " & tbErrImage(E_v.Err));
                        check_value(E_v.ErrBit, W_v.Len - 8, ERROR, "node 1: detected in the acknowledge delimiter");
                    end if;
                end loop;

                check_value(entries(0, TbError), 1, ERROR, "node 0: error flag in the end of frame");
                check_value(entries(1, TbFrame), 1, ERROR, "node 1: received once");
                checkFrame(rxFrame(1, 0).Frame, A_v, "frame after the CRC error");

            -- *** Bit times of the nodes 0.5 % longer and shorter; then 5 % apart: errors ***
            elsif run("test_ppm") then
                setRate(0, 5000);
                setRate(1, -5000);

                for I in 0 to 19 loop

                    case I mod 4 is
                        when 0 =>
                            List0_v(I) := canStd(2 * I, 8, x"0000000000000000");
                        when 1 =>
                            List0_v(I) := canExt(2 * I, 8, x"FFFFFFFFFFFFFFFF");
                        when others =>
                            List0_v(I) := randomFrame(0);
                    end case;

                    List1_v(I) := randomFrame(1);
                    Net_v.txPush(0, List0_v(I));
                    Net_v.txPush(1, List1_v(I));
                end loop;

                waitDone;
                check_value(entries(0, TbError) + entries(1, TbError), 0, ERROR, "no error at +/- 5000 ppm");

                for I in 0 to 19 loop
                    checkFrame(rxFrame(1, I).Frame, List0_v(I), "node 1 frame " & integer'image(I));
                    checkFrame(rxFrame(0, I).Frame, List1_v(I), "node 0 frame " & integer'image(I));
                end loop;

                Net_v.logClear(0);
                Net_v.logClear(1);
                setRate(0, -50000);
                setRate(1, 50000);
                Net_v.txPush(0, canStd(16#155#, 8, x"0000000000000000"));
                wait for 400 * Bit_c;
                check_value(entries(1, TbError) >= 1, ERROR, "errors at 5 % deviation");
                Net_v.txClear(0);
                Net_v.txClear(1);

            -- *** Start of a frame in the third bit of the intermission ***
            elsif run("test_early_start") then
                Net_v.setCfg(1, (BitPeriod => Bit_c, Ppm => 0, SamplePct => 75, Ack => true, Listen => false,
                                 EarlyStart => true, RecDelay => 0 ns));
                A_v  := canStd(16#200#, 1, x"5A00000000000000");
                B_v  := canStd(16#300#, 2, x"A5C3000000000000");
                Net_v.txPush(0, A_v);
                wait for 20 * Bit_c;
                Net_v.txPush(1, B_v);
                waitDone;
                T0_v := rxFrame(1, 0).T;
                T1_v := rxFrame(0, 0).T;
                W_v  := canWire(B_v);
                -- From the sixth bit of the end of frame of A to the same bit of B: one bit of A, two bits of the
                -- intermission and the bits of B up to the sixth bit of its end of frame
                check_value_in_range(T1_v - T0_v, (W_v.Len + 2) * Bit_c - Bit_c / 4,
                                     (W_v.Len + 2) * Bit_c + Bit_c / 4, ERROR, "distance of the frames");
                check_value(entries(0, TbError) + entries(1, TbError), 0, ERROR, "no error");

            end if;

        end loop;

        ocanTestEnd(runner);

    end process;

end architecture;
