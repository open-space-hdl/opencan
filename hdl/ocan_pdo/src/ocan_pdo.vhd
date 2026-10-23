---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- PDO block of OpenCAN: the SYNC consumer, the receive PDOs passed to the user logic at once or at the next SYNC,
-- and the transmit PDOs requested at the SYNC or at a request of the user logic, with their transmit handshake and
-- its time-out (ECSS-E-ST-50-15C clauses 6.2, 6.3, 6.9, 9.3 and 9.4).
--
-- Documentation: hdl/ocan_pdo/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_pdo is
    generic (
        NumRpdo_g : natural range 0 to 4 := 4;
        NumTpdo_g : natural range 0 to 4 := 4
    );
    port (
        -- Control
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        Tick_Ms         : in    std_logic;
        -- SYNC and receive PDOs from ocan_dispatch
        RxSync_Valid    : in    std_logic;
        RxSync_Dlc      : in    std_logic_vector(3 downto 0);
        RxRpdo_Valid    : in    std_logic;
        RxRpdo_Num      : in    std_logic_vector(1 downto 0);
        RxRpdo_Dlc      : in    std_logic_vector(3 downto 0);
        RxRpdo_Data     : in    std_logic_vector(63 downto 0);
        -- Transmit PDOs to ocan_dispatch (PDO n in bit n - 1, bits 4 n - 1 and 64 n - 1 downto 4 (n - 1), 64 (n - 1))
        TxTpdo_Valid    : out   std_logic_vector(3 downto 0);
        TxTpdo_Ready    : in    std_logic_vector(3 downto 0);
        TxTpdo_Dlc      : out   std_logic_vector(15 downto 0);
        TxTpdo_Data     : out   std_logic_vector(255 downto 0);
        TxTpdo_Done     : in    std_logic_vector(3 downto 0);
        TxTpdo_Aborted  : in    std_logic_vector(3 downto 0);
        -- Transmission types of ocan_od (PDO n in bits 8 n - 1 downto 8 (n - 1))
        Cfg_RpdoType    : in    std_logic_vector(31 downto 0);
        Cfg_TpdoType    : in    std_logic_vector(31 downto 0);
        -- ocan_nmt
        Nmt_EnaPdo      : in    std_logic;
        Nmt_ResetComm   : in    std_logic;
        -- User logic
        Sync_Valid      : out   std_logic;
        Rpdo_Valid      : out   std_logic_vector(3 downto 0);
        Rpdo_Data       : out   std_logic_vector(255 downto 0);
        Tpdo_Req        : in    std_logic_vector(3 downto 0)   := (others => '0');
        Tpdo_Data       : in    std_logic_vector(255 downto 0) := (others => '0');
        -- Status and events
        Stat_TpdoBusy   : out   std_logic_vector(3 downto 0);
        Stat_PdoEnabled : out   std_logic;
        Evt_TpdoSent    : out   std_logic_vector(3 downto 0);
        Evt_TpdoAborted : out   std_logic_vector(3 downto 0);
        Err_RxLength    : out   std_logic_vector(3 downto 0);
        Err_TxBusy      : out   std_logic_vector(3 downto 0);
        Err_TxTimeout   : out   std_logic_vector(3 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_pdo is

    -- Ticks without the completion of a taken transmit PDO until the time-out (PD-TX-08)
    constant TxTimeout_c : positive := 256;

    subtype Data_t is std_logic_vector(63 downto 0);

    type Data_a is array (0 to 3) of Data_t;

    type Cnt_a is array (0 to 3) of unsigned(7 downto 0);

    type Type_a is array (0 to 3) of std_logic_vector(7 downto 0);

    -- *** Transmit handshake per transmit PDO ***
    type TxFsm_t is (TIdle_s, TReq_s, TWait_s);

    type TxFsm_a is array (0 to 3) of TxFsm_t;

    -- *** Two process method ***
    type TwoProcess_r is record
        -- SYNC (PD-1)
        SyncEvt  : std_logic;
        -- Receive PDOs (PD-2)
        RxOut    : Data_a;
        RxEvt    : std_logic_vector(3 downto 0);
        Hold     : Data_a;
        HoldV    : std_logic_vector(3 downto 0);
        ErrLen   : std_logic_vector(3 downto 0);
        -- Triggers of the transmit PDOs (PD-3)
        SyncCnt  : Cnt_a;
        TypeReg  : Type_a;
        ReqPend  : std_logic_vector(3 downto 0);
        -- Request and handshake of the transmit PDOs (PD-3)
        Tx       : TxFsm_a;
        TxData   : Data_a;
        TxTmo    : Cnt_a;
        EvtSent  : std_logic_vector(3 downto 0);
        EvtAbort : std_logic_vector(3 downto 0);
        ErrBusy  : std_logic_vector(3 downto 0);
        ErrTmo   : std_logic_vector(3 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable SyncOk_v  : boolean;
        variable Ena_v     : boolean;
        variable RxNum_v   : natural range 0 to 3;
        variable T_v       : natural range 0 to 255;
        variable Restart_v : boolean;
        variable Due_v     : boolean;
        variable Cpl_v     : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.RxEvt    := (others => '0');
        v.ErrLen   := (others => '0');
        v.EvtSent  := (others => '0');
        v.EvtAbort := (others => '0');
        v.ErrBusy  := (others => '0');
        v.ErrTmo   := (others => '0');

        -- *** SYNC (PD-SY-01, PD-SY-02) ***
        SyncOk_v  := RxSync_Valid = '1' and unsigned(RxSync_Dlc) <= 1;
        v.SyncEvt := '0';
        if SyncOk_v then
            v.SyncEvt := '1';
        end if;

        -- PDOs are processed while the PDO enable is set and not in the cycle of a reset communication
        -- (PD-RS-01 to PD-RS-03)
        Ena_v := Nmt_EnaPdo = '1' and Nmt_ResetComm = '0';

        -- *** Receive PDOs (PD-RX-01 to PD-RX-07) ***
        -- The SYNC passes the held data first, so that a receive PDO of the same cycle is held for the next SYNC
        -- (PD-RX-06)
        for N in 0 to NumRpdo_g - 1 loop
            if not Ena_v then
                -- No data held outside Operational and after a reset communication (PD-RS-02, PD-RS-03)
                v.HoldV(N) := '0';
            elsif SyncOk_v and r.HoldV(N) = '1' then
                v.RxOut(N) := r.Hold(N);
                v.RxEvt(N) := '1';
                v.HoldV(N) := '0';
            end if;
        end loop;

        RxNum_v := to_integer(unsigned(RxRpdo_Num));
        if RxRpdo_Valid = '1' and Ena_v and RxNum_v < NumRpdo_g then
            T_v := to_integer(unsigned(Cfg_RpdoType(8 * RxNum_v + 7 downto 8 * RxNum_v)));
            if unsigned(RxRpdo_Dlc) < 8 then
                v.ErrLen(RxNum_v) := '1';                 -- PD-RX-02
            elsif T_v >= 254 then
                v.RxOut(RxNum_v) := RxRpdo_Data;          -- PD-RX-03
                v.RxEvt(RxNum_v) := '1';
            elsif T_v <= 240 then
                v.Hold(RxNum_v)  := RxRpdo_Data;          -- PD-RX-04, the last value wins
                v.HoldV(RxNum_v) := '1';
            end if;                                       -- 241 to 253: not processed (PD-RX-05)
        end if;

        -- *** Transmit PDOs (PD-TX-01 to PD-TX-09) ***
        for N in 0 to NumTpdo_g - 1 loop
            T_v          := to_integer(unsigned(Cfg_TpdoType(8 * N + 7 downto 8 * N)));
            v.TypeReg(N) := Cfg_TpdoType(8 * N + 7 downto 8 * N);
            Due_v        := false;
            Cpl_v        := false;

            -- Triggers (architecture, section 4.1). A reset communication or a change of the type clears the count
            -- and the request that waits from the previous cycles; a SYNC of that cycle is not counted, and a
            -- request of that cycle acts with the type of that cycle (PD-TX-02, PD-TX-03)
            Restart_v := Nmt_ResetComm = '1' or Cfg_TpdoType(8 * N + 7 downto 8 * N) /= r.TypeReg(N);
            if T_v >= 1 and T_v <= 240 then
                v.ReqPend(N) := '0';
                if Restart_v then
                    v.SyncCnt(N) := (others => '0');
                elsif SyncOk_v then
                    if r.SyncCnt(N) >= T_v - 1 then
                        Due_v        := true;
                        v.SyncCnt(N) := (others => '0');
                    else
                        v.SyncCnt(N) := r.SyncCnt(N) + 1;
                    end if;
                end if;
            elsif T_v = 0 then
                v.SyncCnt(N) := (others => '0');
                if Restart_v then
                    v.ReqPend(N) := '0';
                elsif SyncOk_v and r.ReqPend(N) = '1' then
                    Due_v        := true;
                    v.ReqPend(N) := '0';
                end if;
                -- A request in the cycle of a SYNC applies to the next SYNC
                if Tpdo_Req(N) = '1' and Nmt_EnaPdo = '1' then
                    v.ReqPend(N) := '1';
                end if;
            else
                v.SyncCnt(N) := (others => '0');
                v.ReqPend(N) := '0';
                if T_v >= 254 and Tpdo_Req(N) = '1' then
                    Due_v := true;
                end if;
            end if;
            -- No waiting request while the PDO enable is cleared (PD-RS-02)
            if Nmt_EnaPdo = '0' then
                v.ReqPend(N) := '0';
            end if;

            -- Handshake (architecture, section 4.2)
            case r.Tx(N) is

                when TIdle_s =>
                    null;

                when TReq_s =>
                    if TxTpdo_Ready(N) = '1' then
                        if TxTpdo_Aborted(N) = '1' then
                            -- Reject path of ocan_dispatch
                            v.EvtAbort(N) := '1';
                            Cpl_v         := true;
                            v.Tx(N)       := TIdle_s;
                        else
                            v.Tx(N)    := TWait_s;
                            v.TxTmo(N) := (others => '0');
                        end if;
                    end if;

                when TWait_s =>
                    if TxTpdo_Done(N) = '1' then
                        v.EvtSent(N) := '1';
                        Cpl_v        := true;
                        v.Tx(N)      := TIdle_s;
                    elsif TxTpdo_Aborted(N) = '1' then
                        v.EvtAbort(N) := '1';
                        Cpl_v         := true;
                        v.Tx(N)       := TIdle_s;
                    elsif Tick_Ms = '1' then
                        if r.TxTmo(N) >= TxTimeout_c - 1 then
                            -- No completion: the wait ends, the PDO is not repeated (PD-TX-08)
                            v.ErrTmo(N) := '1';
                            Cpl_v       := true;
                            v.Tx(N)     := TIdle_s;
                        else
                            v.TxTmo(N) := r.TxTmo(N) + 1;
                        end if;
                    end if;

                -- coverage off
                when others =>
                    v.Tx(N) := TIdle_s;
                -- coverage on

            end case;

            -- Request: only while the PDO enable is set (PD-RS-01), at most one pending (PD-TX-07)
            if Due_v and Nmt_EnaPdo = '1' then
                if r.Tx(N) = TIdle_s or Cpl_v then
                    v.Tx(N)     := TReq_s;
                    v.TxData(N) := Tpdo_Data(64 * N + 63 downto 64 * N);
                else
                    v.ErrBusy(N) := '1';
                end if;
            end if;
        end loop;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs (the bits of absent PDOs at 0)
    -----------------------------------------------------------------------------------------------
    Sync_Valid      <= r.SyncEvt;
    Stat_PdoEnabled <= Nmt_EnaPdo;

    g_rpdo : for N in 0 to 3 generate

        g_present : if N < NumRpdo_g generate
            Rpdo_Valid(N)                        <= r.RxEvt(N);
            Rpdo_Data(64 * N + 63 downto 64 * N) <= r.RxOut(N);
            Err_RxLength(N)                      <= r.ErrLen(N);
        end generate;

        g_absent : if N >= NumRpdo_g generate
            Rpdo_Valid(N)                        <= '0';
            Rpdo_Data(64 * N + 63 downto 64 * N) <= (others => '0');
            Err_RxLength(N)                      <= '0';
        end generate;

    end generate;

    g_tpdo : for N in 0 to 3 generate

        g_present : if N < NumTpdo_g generate
            TxTpdo_Valid(N)                        <= '1' when r.Tx(N) = TReq_s else '0';
            TxTpdo_Dlc(4 * N + 3 downto 4 * N)     <= "1000";
            TxTpdo_Data(64 * N + 63 downto 64 * N) <= r.TxData(N);
            Stat_TpdoBusy(N)                       <= '0' when r.Tx(N) = TIdle_s else '1';
            Evt_TpdoSent(N)                        <= r.EvtSent(N);
            Evt_TpdoAborted(N)                     <= r.EvtAbort(N);
            Err_TxBusy(N)                          <= r.ErrBusy(N);
            Err_TxTimeout(N)                       <= r.ErrTmo(N);
        end generate;

        g_absent : if N >= NumTpdo_g generate
            TxTpdo_Valid(N)                        <= '0';
            TxTpdo_Dlc(4 * N + 3 downto 4 * N)     <= "0000";
            TxTpdo_Data(64 * N + 63 downto 64 * N) <= (others => '0');
            Stat_TpdoBusy(N)                       <= '0';
            Evt_TpdoSent(N)                        <= '0';
            Evt_TpdoAborted(N)                     <= '0';
            Err_TxBusy(N)                          <= '0';
            Err_TxTimeout(N)                       <= '0';
        end generate;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.SyncEvt  <= '0';
                r.RxOut    <= (others => (others => '0'));
                r.RxEvt    <= (others => '0');
                r.HoldV    <= (others => '0');
                r.ErrLen   <= (others => '0');
                r.SyncCnt  <= (others => (others => '0'));
                r.ReqPend  <= (others => '0');
                r.Tx       <= (others => TIdle_s);
                r.TxTmo    <= (others => (others => '0'));
                r.EvtSent  <= (others => '0');
                r.EvtAbort <= (others => '0');
                r.ErrBusy  <= (others => '0');
                r.ErrTmo   <= (others => '0');

                for N in 0 to 3 loop
                    r.TypeReg(N) <= Cfg_TpdoType(8 * N + 7 downto 8 * N);
                end loop;

            end if;
        end if;
    end process;

end architecture;
