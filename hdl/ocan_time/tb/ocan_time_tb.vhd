---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_time: the events, the configuration, the writes and the requests are driven cycle by
-- cycle, a responder answers the transmit handshake like ocan_dispatch, and a reference model derived from the
-- specification predicts every output in every cycle: the local time as the last setting plus floor(n * 2^F / f),
-- computed in closed form. One run block per test case of the verification plan.
--
-- Documentation: hdl/ocan_time/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_context;

library work;
    use work.ocan_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_time_tb is
    generic (
        runner_cfg     : string;
        ClkFrequency_g : positive := 100000000;
        FineBits_g     : natural  := 24
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_time_tb is

    constant F_c     : natural  := FineBits_g;
    constant Freq_c  : positive := ClkFrequency_g;
    constant TimeW_c : positive := 32 + F_c;

    subtype Time_t is unsigned(TimeW_c - 1 downto 0);

    -- Fine time units in n clock cycles: floor(n * 2^F / f) (TM-CT-02), modulo 2^(32 + F). Exact in double
    -- precision for n < 2^28, since n * 2^F is then below 2^52
    function advance (n : natural) return Time_t is
        variable Q_v  : real;
        variable Hi_v : natural;
        variable Lo_v : natural;
        variable U_v  : unsigned(63 downto 0);
    begin
        assert n < 2 ** 28
            report "advance: n out of the exact range"
            severity failure;
        Q_v  := floor(real(n) * 2.0 ** F_c / real(Freq_c));
        Hi_v := natural(floor(Q_v / 2.0 ** 30));
        Lo_v := natural(Q_v - real(Hi_v) * 2.0 ** 30);
        U_v  := to_unsigned(Hi_v, 34) & to_unsigned(Lo_v, 30);
        return resize(U_v, TimeW_c);
    end function;

    -- Local time of cycle c after a base value that the local time had in cycle bc (TM-CT-02)
    function timeOf (base : Time_t; bc : natural; c : natural) return Time_t is
    begin
        return base + advance(c - bc);
    end function;

    -- Local time from and to the 56-bit value of the ports: coarse time in bits 55 to 24, fine time aligned to bit 23
    function fromScet (s : std_logic_vector(55 downto 0)) return Time_t is
        variable T_v : Time_t;
    begin
        T_v(TimeW_c - 1 downto F_c) := unsigned(s(55 downto 24));
        T_v(F_c - 1 downto 0)       := unsigned(s(23 downto 24 - F_c));
        return T_v;
    end function;

    function toScet (t : Time_t) return std_logic_vector is
        variable S_v : std_logic_vector(55 downto 0) := (others => '0');
    begin
        S_v(55 downto 24)       := std_logic_vector(t(TimeW_c - 1 downto F_c));
        S_v(23 downto 24 - F_c) := std_logic_vector(t(F_c - 1 downto 0));
        return S_v;
    end function;

    -- Frame data of a 56-bit SCET (specification, section 2.6): bytes 0 to 2 the fine time and bytes 3 to 6 the
    -- coarse time, least significant byte first; byte 0 in bits 63 to 56; byte 7 at 0
    function frameOf (s : std_logic_vector(55 downto 0)) return std_logic_vector is
    begin
        return s(7 downto 0) & s(15 downto 8) & s(23 downto 16) & s(31 downto 24) & s(39 downto 32) &
               s(47 downto 40) & s(55 downto 48) & x"00";
    end function;

    -- SCET of a frame, the inverse of frameOf
    function scetOf (d : std_logic_vector(63 downto 0)) return std_logic_vector is
    begin
        return d(15 downto 8) & d(23 downto 16) & d(31 downto 24) & d(39 downto 32) & d(47 downto 40) &
               d(55 downto 48) & d(63 downto 56);
    end function;

    function u8 (n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 8));
    end function;

    -- *** DUT signals ***
    signal Clk           : std_logic;
    signal Rst           : std_logic                     := '1';
    signal Tick_Ms       : std_logic                     := '0';
    signal Rx_SyncValid  : std_logic                     := '0';
    signal Rx_SyncDlc    : std_logic_vector(3 downto 0)  := (others => '0');
    signal Rx_TimeValid  : std_logic                     := '0';
    signal Rx_TimeDlc    : std_logic_vector(3 downto 0)  := x"7";
    signal Rx_TimeData   : std_logic_vector(63 downto 0) := (others => '0');
    signal Tx_Valid      : std_logic;
    signal Tx_Ready      : std_logic;
    signal Tx_Dlc        : std_logic_vector(3 downto 0);
    signal Tx_Data       : std_logic_vector(63 downto 0);
    signal Tx_Done       : std_logic;
    signal Tx_Aborted    : std_logic;
    signal Cfg_RxType    : std_logic_vector(7 downto 0)  := u8(254);
    signal Cfg_TxType    : std_logic_vector(7 downto 0)  := u8(254);
    signal Cfg_SetValid  : std_logic                     := '0';
    signal Cfg_SetScet   : std_logic_vector(55 downto 0) := (others => '0');
    signal Stat_Scet     : std_logic_vector(55 downto 0);
    signal Nmt_ResetComm : std_logic                     := '0';
    signal Req_Valid     : std_logic                     := '0';
    signal Time_Coarse   : std_logic_vector(31 downto 0);
    signal Time_Fine     : std_logic_vector(23 downto 0);
    signal Stat_TimeSet  : std_logic;
    signal Evt_Set       : std_logic;
    signal Evt_Sync      : std_logic;
    signal Err_TxBusy    : std_logic;
    signal Err_RxDrop    : std_logic;
    signal Err_TxTimeout : std_logic;

    -- *** Cycle counter and tick generator (period TickPer cycles, 0: no tick) ***
    signal Cyc     : natural := 0;
    signal TickPer : natural := 16;

    -- *** Responder of the transmit handshake (behaviour of ocan_dispatch at its source port) ***
    signal RespHold  : boolean   := false;  -- never take a request
    signal RespRdy   : natural   := 0;      -- cycles of Tx_Valid before Tx_Ready
    signal RespCpl   : natural   := 3;      -- cycles from Tx_Ready to the completion
    signal RespAbort : boolean   := false;  -- complete with Tx_Aborted
    signal RespRej   : boolean   := false;  -- reject path: Tx_Ready and Tx_Aborted together
    signal VCnt      : natural   := 0;
    signal Grant     : std_logic;
    signal RejNow    : std_logic;
    signal CplDone   : std_logic := '0';
    signal CplAbort  : std_logic := '0';
    signal RespBusy  : boolean   := false;

    type Data_a is array (0 to 4095) of std_logic_vector(63 downto 0);
    type Nat_a is array (0 to 4095) of natural;

    signal TxCnt   : natural := 0;  -- frames taken (granted or rejected)
    signal LogData : Data_a;
    signal LogCyc  : Nat_a;

    -- *** Monitors ***
    signal CntSet  : natural := 0;
    signal CntSync : natural := 0;
    signal CntBusy : natural := 0;
    signal CntDrop : natural := 0;
    signal CntTmo  : natural := 0;
    signal CycTmo  : natural := 0;

    -- *** Reference model ***
    signal CheckEn    : boolean := false;
    signal ExpScet    : std_logic_vector(55 downto 0);
    signal ExpTimeSet : std_logic;
    signal ExpEvtSet  : std_logic;
    signal ExpEvtSync : std_logic;
    signal ExpErrBusy : std_logic;
    signal ExpErrDrop : std_logic;
    signal ExpErrTmo  : std_logic;
    signal ExpTxValid : std_logic;
    signal ExpTxData  : std_logic_vector(63 downto 0);

begin

    test_runner_watchdog(runner, 2000 ms);

    i_th : entity work.ocan_time_th
        generic map (
            ClkFrequency_g => ClkFrequency_g,
            FineBits_g     => FineBits_g
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            Tick_Ms       => Tick_Ms,
            Rx_SyncValid  => Rx_SyncValid,
            Rx_SyncDlc    => Rx_SyncDlc,
            Rx_TimeValid  => Rx_TimeValid,
            Rx_TimeDlc    => Rx_TimeDlc,
            Rx_TimeData   => Rx_TimeData,
            Tx_Valid      => Tx_Valid,
            Tx_Ready      => Tx_Ready,
            Tx_Dlc        => Tx_Dlc,
            Tx_Data       => Tx_Data,
            Tx_Done       => Tx_Done,
            Tx_Aborted    => Tx_Aborted,
            Cfg_RxType    => Cfg_RxType,
            Cfg_TxType    => Cfg_TxType,
            Cfg_SetValid  => Cfg_SetValid,
            Cfg_SetScet   => Cfg_SetScet,
            Stat_Scet     => Stat_Scet,
            Nmt_ResetComm => Nmt_ResetComm,
            Req_Valid     => Req_Valid,
            Time_Coarse   => Time_Coarse,
            Time_Fine     => Time_Fine,
            Stat_TimeSet  => Stat_TimeSet,
            Evt_Set       => Evt_Set,
            Evt_Sync      => Evt_Sync,
            Err_TxBusy    => Err_TxBusy,
            Err_RxDrop    => Err_RxDrop,
            Err_TxTimeout => Err_TxTimeout
        );

    -----------------------------------------------------------------------------------------------
    -- Cycle counter and millisecond tick
    -----------------------------------------------------------------------------------------------
    p_tick : process (Clk) is
        variable Cnt_v : natural := 0;
    begin
        if rising_edge(Clk) then
            Cyc <= Cyc + 1;
            if TickPer > 0 and Cnt_v >= TickPer - 1 then
                Tick_Ms <= '1';
                Cnt_v   := 0;
            else
                Tick_Ms <= '0';
                Cnt_v   := Cnt_v + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Responder (one frame at a time, no grant in the cycle of a completion event, DS-TX-03)
    -----------------------------------------------------------------------------------------------
    Grant      <= '1' when Tx_Valid = '1' and not RespHold and not RespRej and not RespBusy and VCnt >= RespRdy and
                           CplDone = '0' and CplAbort = '0' else
                  '0';
    RejNow     <= '1' when Tx_Valid = '1' and RespRej and not RespBusy and VCnt >= 1 and CplDone = '0' and
                           CplAbort = '0' else
                  '0';
    Tx_Ready   <= Grant or RejNow;
    Tx_Done    <= CplDone;
    Tx_Aborted <= CplAbort or RejNow;

    p_resp : process (Clk) is
        variable Left_v : integer := -1;
        variable Abt_v  : boolean := false;
    begin
        if rising_edge(Clk) then
            CplDone  <= '0';
            CplAbort <= '0';
            if Left_v > 0 then
                Left_v := Left_v - 1;
            end if;
            if Left_v = 0 then
                if Abt_v then
                    CplAbort <= '1';
                else
                    CplDone <= '1';
                end if;
                Left_v := -1;
            end if;
            if Tx_Valid = '1' and Tx_Ready = '1' then
                LogData(TxCnt) <= Tx_Data;
                LogCyc(TxCnt)  <= Cyc;
                TxCnt          <= TxCnt + 1;
                VCnt           <= 0;
                if Grant = '1' then
                    Left_v := RespCpl - 1;
                    Abt_v  := RespAbort;
                    if Left_v = 0 then
                        if Abt_v then
                            CplAbort <= '1';
                        else
                            CplDone <= '1';
                        end if;
                        Left_v := -1;
                    end if;
                end if;
            elsif Tx_Valid = '1' then
                VCnt <= VCnt + 1;
            else
                VCnt <= 0;
            end if;
            RespBusy <= Left_v >= 0;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------------------------
    p_mon : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Evt_Set = '1' then
                CntSet <= CntSet + 1;
            end if;
            if Evt_Sync = '1' then
                CntSync <= CntSync + 1;
            end if;
            if Err_TxBusy = '1' then
                CntBusy <= CntBusy + 1;
            end if;
            if Err_RxDrop = '1' then
                CntDrop <= CntDrop + 1;
            end if;
            if Err_TxTimeout = '1' then
                CntTmo <= CntTmo + 1;
                CycTmo <= Cyc;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Reference model, derived from the specification and the rules of the architecture at the corners
    -- (sections 4 and 5.1). The local time of cycle c is Base + floor((c - BaseCyc) * 2^F / f).
    -----------------------------------------------------------------------------------------------
    p_model : process is
        type Tx_t is (MIdle, MReq, MWait);

        -- Local time: the base value and the cycle in which the local time equals it
        variable Base_v    : Time_t  := (others => '0');
        variable BaseCyc_v : natural := 0;
        variable Set_v     : boolean := false;
        -- SYNC sample (TM-SY-01)
        variable Samp_v    : Time_t  := (others => '0');
        variable SampCyc_v : natural := 0;
        variable SampOk_v  : boolean := false;
        -- High-resolution setting registered for the next cycle (TM-RX-04)
        variable Pend_v    : boolean := false;
        variable PendT_v   : Time_t  := (others => '0');
        variable PendCyc_v : natural := 0;
        variable NewPend_v : boolean;
        -- Local Time PDO (TM-TX-02 to TM-TX-07)
        variable Cnt_v     : natural                       := 0;
        variable ReqPend_v : boolean                       := false;
        variable PrevT_v   : std_logic_vector(7 downto 0)  := (others => '0');
        variable Tx_v      : Tx_t                          := MIdle;
        variable Tmo_v     : natural                       := 0;
        variable TxData_v  : std_logic_vector(63 downto 0) := (others => '0');
        -- Cycle of the inputs, events
        variable K_v       : natural := 0;
        variable Cur_v     : Time_t;
        variable S_v       : Time_t;
        variable Ev_v      : std_logic_vector(4 downto 0); -- Set, Sync, Busy, Drop, Tmo
        variable SyncOk_v  : boolean;
        variable RxT_v     : natural;
        variable TxT_v     : natural;
        variable HighRes_v : boolean;
        variable Due_v     : boolean;
        variable DueT_v    : Time_t;
        variable Cpl_v     : boolean;
        variable Free_v    : boolean;
        variable Byte_v    : std_logic_vector(55 downto 0);
    begin
        wait until rising_edge(Clk);
        K_v := K_v + 1;  -- the inputs belong to cycle K_v - 1, the expectations to cycle K_v

        if Rst = '1' then
            -- After the hardware reset: local time 0, set flag cleared, no sample (TM-CT-04)
            Base_v    := (others => '0');
            BaseCyc_v := K_v;
            Set_v     := false;
            SampOk_v  := false;
            Pend_v    := false;
            Cnt_v     := 0;
            ReqPend_v := false;
            PrevT_v   := Cfg_TxType;
            Tx_v      := MIdle;
            Tmo_v     := 0;
            Ev_v      := (others => '0');
        else
            Ev_v      := (others => '0');
            Cur_v     := timeOf(Base_v, BaseCyc_v, K_v - 1);
            RxT_v     := to_integer(unsigned(Cfg_RxType));
            TxT_v     := to_integer(unsigned(Cfg_TxType));
            HighRes_v := RxT_v <= 240;

            -- SYNC with DLC 0 or 1: the sample is the local time of the cycle of the event (TM-SY-01, TM-SY-02)
            SyncOk_v := Rx_SyncValid = '1' and unsigned(Rx_SyncDlc) <= 1;
            if SyncOk_v then
                Samp_v    := Cur_v;
                SampCyc_v := K_v - 1;
                SampOk_v  := true;
                Ev_v(1)   := '1';
            end if;

            -- Settings in the order of their precedence: the high-resolution setting of the previous cycle, the
            -- Spacecraft Time PDO of this cycle, the write of Local SCET Set
            NewPend_v := false;
            if Pend_v then
                -- The local time at the SYNC is the received SCET (TM-RX-04)
                Base_v    := PendT_v;
                BaseCyc_v := PendCyc_v;
                Set_v     := true;
                Ev_v(0)   := '1';
            end if;
            if Rx_TimeValid = '1' then
                -- First seven bytes, least significant byte first, the fine time cut to F bits (TM-RX-01)
                Byte_v := scetOf(Rx_TimeData);
                S_v    := fromScet(Byte_v);
                if unsigned(Rx_TimeDlc) < 7 then
                    Ev_v(3) := '1';                                      -- TM-RX-02
                elsif RxT_v >= 241 and RxT_v <= 253 then
                    Ev_v(3) := '1';                                      -- TM-RX-06
                elsif RxT_v >= 254 then
                    Base_v    := S_v;                                    -- TM-RX-03
                    BaseCyc_v := K_v;
                    Set_v     := true;
                    Ev_v(0)   := '1';
                elsif not SampOk_v then
                    Ev_v(3) := '1';                                      -- TM-RX-05
                else
                    NewPend_v := true;
                    PendT_v   := S_v;
                    PendCyc_v := SampCyc_v;
                end if;
            end if;
            if Cfg_SetValid = '1' then
                Base_v    := fromScet(Cfg_SetScet);                      -- TM-CT-05
                BaseCyc_v := K_v;
                Set_v     := true;
                Ev_v(0)   := '1';
                NewPend_v := false;
            end if;
            Pend_v := NewPend_v;

            -- Triggers of the Local Time PDO (TM-TX-02 to TM-TX-05, architecture section 5.1)
            Due_v  := false;
            DueT_v := Cur_v;
            if Nmt_ResetComm = '1' or Cfg_TxType /= PrevT_v then
                -- The count starts at the next SYNC; a SYNC of this cycle is not counted (TM-IF-07, TM-TX-02)
                Cnt_v     := 0;
                ReqPend_v := false;
            elsif TxT_v >= 1 and TxT_v <= 240 then
                ReqPend_v := false;
                if SyncOk_v then
                    Cnt_v := Cnt_v + 1;
                    if Cnt_v = TxT_v then
                        Cnt_v := 0;
                        Due_v := true;
                    end if;
                end if;
            elsif TxT_v = 0 then
                Cnt_v := 0;
                if SyncOk_v and ReqPend_v then
                    Due_v     := true;
                    ReqPend_v := false;
                end if;
                if Req_Valid = '1' then
                    ReqPend_v := true;
                end if;
            else
                Cnt_v     := 0;
                ReqPend_v := false;
                if TxT_v >= 254 and Req_Valid = '1' then
                    Due_v := true;
                    if HighRes_v and SampOk_v then
                        DueT_v := Samp_v;
                    end if;
                end if;
            end if;
            PrevT_v := Cfg_TxType;

            -- Transmit handshake with the time-out of 256 ticks (TM-IF-02, TM-TX-07)
            Cpl_v := false;

            case Tx_v is
                when MReq =>
                    if Tx_Ready = '1' then
                        if Tx_Done = '1' or Tx_Aborted = '1' then
                            Cpl_v := true;
                            Tx_v  := MIdle;
                        else
                            Tx_v  := MWait;
                            Tmo_v := 0;
                        end if;
                    end if;
                when MWait =>
                    if Tx_Done = '1' or Tx_Aborted = '1' then
                        Cpl_v := true;
                        Tx_v  := MIdle;
                    elsif Tick_Ms = '1' then
                        Tmo_v := Tmo_v + 1;
                        if Tmo_v = 256 then
                            Ev_v(4) := '1';
                            Cpl_v   := true;
                            Tx_v    := MIdle;
                        end if;
                    end if;
                when others =>
                    null;
            end case;

            -- At most one pending request (TM-TX-06)
            Free_v := Tx_v = MIdle;
            if Due_v then
                if Free_v then
                    Tx_v     := MReq;
                    TxData_v := frameOf(toScet(DueT_v));
                else
                    Ev_v(2) := '1';
                end if;
            end if;
        end if;

        ExpScet    <= toScet(timeOf(Base_v, BaseCyc_v, K_v));
        ExpTimeSet <= '1' when Set_v else '0';
        ExpEvtSet  <= Ev_v(0);
        ExpEvtSync <= Ev_v(1);
        ExpErrBusy <= Ev_v(2);
        ExpErrDrop <= Ev_v(3);
        ExpErrTmo  <= Ev_v(4);
        ExpTxValid <= '1' when Tx_v = MReq else '0';
        ExpTxData  <= TxData_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Checkers in every cycle
    -----------------------------------------------------------------------------------------------
    p_check : process is
        variable Data_v : std_logic_vector(63 downto 0);

        procedure cmp (dut : std_logic_vector; exp : std_logic_vector; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & to_string(dut, HEX) & ", reference model " & to_string(exp, HEX));
            end if;
        end procedure;

        procedure cmp (dut : std_logic; exp : std_logic; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & std_logic'image(dut) & ", reference model " & std_logic'image(exp));
            end if;
        end procedure;

        variable Seen_v : boolean := false;
    begin
        wait until falling_edge(Clk);
        if CheckEn and Rst = '0' then
            cmp(Time_Coarse & Time_Fine, ExpScet, "Time_Coarse & Time_Fine");
            cmp(Stat_Scet, ExpScet, "Stat_Scet");
            if F_c < 24 and unsigned(Time_Fine(23 - F_c downto 0)) /= 0 then
                alert(ERROR, "Time_Fine below FineBits_g not 0");
            end if;
            cmp(Stat_TimeSet, ExpTimeSet, "Stat_TimeSet");
            cmp(Evt_Set, ExpEvtSet, "Evt_Set");
            cmp(Evt_Sync, ExpEvtSync, "Evt_Sync");
            cmp(Err_TxBusy, ExpErrBusy, "Err_TxBusy");
            cmp(Err_RxDrop, ExpErrDrop, "Err_RxDrop");
            cmp(Err_TxTimeout, ExpErrTmo, "Err_TxTimeout");
            cmp(Tx_Valid, ExpTxValid, "Tx_Valid");
            if Tx_Valid = '1' then
                cmp(Tx_Data, ExpTxData, "Tx_Data");
                cmp(Tx_Dlc, "0111", "Tx_Dlc");
            end if;
            -- The frame stable while Tx_Valid is '1'
            if Tx_Valid = '1' and Seen_v and Tx_Data /= Data_v then
                alert(ERROR, "Tx_Data changed while Tx_Valid = '1'");
            end if;
        end if;
        Seen_v := Tx_Valid = '1' and Tx_Ready = '0';
        Data_v := Tx_Data;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable C0_v : natural;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        procedure doReset is
        begin
            wait until rising_edge(Clk);
            Rst <= '1';
            clocks(3);
            Rst <= '0';
        end procedure;

        procedure waitCnt (signal s : natural; n : natural; timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while s < n loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- One event in the next cycle: SYNC, Spacecraft Time PDO, write, user request, reset communication
        procedure sync (dlc : natural := 0) is
        begin
            wait until rising_edge(Clk);
            Rx_SyncValid <= '1';
            Rx_SyncDlc   <= std_logic_vector(to_unsigned(dlc, 4));
            wait until rising_edge(Clk);
            Rx_SyncValid <= '0';
        end procedure;

        procedure pdo (scet : std_logic_vector(55 downto 0); dlc : natural := 7) is
        begin
            wait until rising_edge(Clk);
            Rx_TimeValid <= '1';
            Rx_TimeDlc   <= std_logic_vector(to_unsigned(dlc, 4));
            Rx_TimeData  <= frameOf(scet);
            wait until rising_edge(Clk);
            Rx_TimeValid <= '0';
        end procedure;

        procedure write (scet : std_logic_vector(55 downto 0)) is
        begin
            wait until rising_edge(Clk);
            Cfg_SetValid <= '1';
            Cfg_SetScet  <= scet;
            wait until rising_edge(Clk);
            Cfg_SetValid <= '0';
        end procedure;

        procedure request is
        begin
            wait until rising_edge(Clk);
            Req_Valid <= '1';
            wait until rising_edge(Clk);
            Req_Valid <= '0';
        end procedure;

        procedure resetComm is
        begin
            wait until rising_edge(Clk);
            Nmt_ResetComm <= '1';
            wait until rising_edge(Clk);
            Nmt_ResetComm <= '0';
        end procedure;

        -- A random 56-bit SCET
        impure function rndScet return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(random(0, 2 ** 28 - 1), 28)) &
                   std_logic_vector(to_unsigned(random(0, 2 ** 28 - 1), 28));
        end function;

        -- Cycles for k fine time units: ceil(k * f / 2^F)
        function cyclesFor (k : natural) return natural is
        begin
            return natural(ceil(real(k) * real(Freq_c) / 2.0 ** F_c));
        end function;

        variable N_v   : natural;
        variable K_v   : natural;
        variable T_v   : std_logic_vector(55 downto 0);
        variable U_v   : std_logic_vector(55 downto 0);
        variable Max_v : natural;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            -- Defaults of every test
            CheckEn       <= false;
            TickPer       <= 16;
            RespHold      <= false;
            RespRdy       <= 0;
            RespCpl       <= 3;
            RespAbort     <= false;
            RespRej       <= false;
            Cfg_RxType    <= u8(254);
            Cfg_TxType    <= u8(254);
            Rx_SyncValid  <= '0';
            Rx_TimeValid  <= '0';
            Cfg_SetValid  <= '0';
            Req_Valid     <= '0';
            Nmt_ResetComm <= '0';
            doReset;
            CheckEn       <= true;

            -- *** TC-TM-01: rate of the counter ***
            if run("test_counter_rate") then
                -- At least three fine time units and 100000 cycles
                write(x"12345678ABCDEF");
                clocks(maximum(100000, cyclesFor(3) + 10));
                check_value(Stat_TimeSet, '1', ERROR, "Stat_TimeSet after the write");

            -- *** TC-TM-02: long run ***
            elsif run("test_long_run_rate") then

                for I in 1 to 16 loop
                    clocks(2 ** 20);
                    wait until falling_edge(Clk);
                    check_value(Stat_Scet, ExpScet, ERROR, "local time after " & to_string(I) & " x 2^20 cycles");
                end loop;

                clocks(12345);
                wait until falling_edge(Clk);
                check_value(Stat_Scet, ExpScet, ERROR, "local time after 2^24 + 12345 cycles");

            -- *** TC-TM-03: wrap of the coarse time ***
            elsif run("test_coarse_wrap") then
                -- Coarse time 2^32 - 1, fine time a few units below its maximum (all ones, minus 2)
                T_v := (others => '1');
                if F_c >= 2 then
                    T_v(23 - F_c + 1 + 1) := '0';
                end if;
                write(T_v);
                Max_v := cyclesFor(4) + 10;
                N_v   := 0;

                while unsigned(Time_Coarse) /= 0 and N_v < Max_v loop
                    wait until rising_edge(Clk);
                    N_v := N_v + 1;
                end loop;

                check_value(unsigned(Time_Coarse) = 0, true, ERROR, "the coarse time wraps to 0");
                clocks(10);

            -- *** TC-TM-04: reset and reset communication ***
            elsif run("test_reset_time") then
                wait until falling_edge(Clk);
                check_value(Stat_TimeSet, '0', ERROR, "set flag after Rst");
                check_value(Stat_Scet, x"00000000000000", ERROR, "local time 0 after Rst");
                -- No sample since Rst: a high-resolution PDO is not processed (TM-RX-05)
                Cfg_RxType <= u8(1);
                C0_v       := CntDrop;
                pdo(x"00000100000000");
                clocks(2);
                check_value(CntDrop, C0_v + 1, ERROR, "high-resolution PDO without a sample");
                -- A setting and a sample, then a reset communication: nothing of it changes
                write(x"00001000000000");
                sync;
                clocks(10);
                resetComm;
                clocks(10);
                check_value(Stat_TimeSet, '1', ERROR, "set flag kept at a reset communication");
                -- The sample of before the reset communication still counts for a high-resolution PDO
                C0_v := CntSet;
                pdo(x"00002000000000");
                clocks(3);
                check_value(CntSet, C0_v + 1, ERROR, "high-resolution setting with the sample before it");

            -- *** TC-TM-05: writes of Local SCET Set ***
            elsif run("test_scet_set") then

                for I in 1 to 1000 loop
                    write(rndScet);
                    clocks(random(0, 30));
                end loop;

                -- A write in the cycle of a basic setting: the write wins
                Cfg_RxType   <= u8(254);
                wait until rising_edge(Clk);
                Cfg_SetValid <= '1';
                Cfg_SetScet  <= x"11111111111111";
                Rx_TimeValid <= '1';
                Rx_TimeDlc   <= x"7";
                Rx_TimeData  <= frameOf(x"22222222222222");
                wait until rising_edge(Clk);
                Cfg_SetValid <= '0';
                Rx_TimeValid <= '0';
                wait until falling_edge(Clk);
                check_value(Stat_Scet(55 downto 24), x"11111111", ERROR, "the write wins over the basic setting");
                -- A write in the second cycle of a high-resolution setting: the write wins
                Cfg_RxType   <= u8(1);
                sync;
                clocks(5);
                pdo(x"33333333333333");
                Cfg_SetValid <= '1';
                Cfg_SetScet  <= x"44444444444444";
                wait until rising_edge(Clk);
                Cfg_SetValid <= '0';
                wait until falling_edge(Clk);
                check_value(Stat_Scet(55 downto 24), x"44444444", ERROR, "the write wins over the load");

            -- *** TC-TM-06: SYNC sample ***
            elsif run("test_sync_sample") then
                -- Type 1: every SYNC gives a Local Time PDO with its sample
                Cfg_TxType <= u8(1);
                write(x"0000ABCD000000");
                clocks(5);

                for Dlc in 0 to 15 loop
                    C0_v         := CntSync;
                    N_v          := TxCnt;
                    wait until rising_edge(Clk);
                    Rx_SyncValid <= '1';
                    Rx_SyncDlc   <= std_logic_vector(to_unsigned(Dlc, 4));
                    wait until falling_edge(Clk);
                    T_v          := Stat_Scet;
                    wait until rising_edge(Clk);
                    Rx_SyncValid <= '0';
                    clocks(10);
                    if Dlc <= 1 then
                        check_value(CntSync, C0_v + 1, ERROR, "Evt_Sync for DLC " & to_string(Dlc));
                        check_value(TxCnt, N_v + 1, ERROR, "frame of the SYNC, DLC " & to_string(Dlc));
                        check_value(scetOf(LogData(N_v)), T_v, ERROR, "the sample is the time of the SYNC cycle");
                    else
                        check_value(CntSync, C0_v, ERROR, "no sample for DLC " & to_string(Dlc));
                        check_value(TxCnt, N_v, ERROR, "no frame for DLC " & to_string(Dlc));
                    end if;
                end loop;

            -- *** TC-TM-07: format of the Spacecraft Time PDO ***
            elsif run("test_rx_format") then
                Cfg_RxType <= u8(254);
                -- The example of the specification (section 2.6)
                pdo(x"12345678ABCDEF");
                wait until falling_edge(Clk);
                check_value(Time_Coarse, x"12345678", ERROR, "coarse time of the example");
                U_v := x"12345678ABCDEF";
                T_v := (others => '0');
                if F_c > 0 then
                    T_v(23 downto 24 - F_c) := U_v(23 downto 24 - F_c);
                end if;
                check_value(Time_Fine, T_v(23 downto 0), ERROR, "fine time of the example, cut to F bits");

                for I in 1 to 200 loop
                    pdo(rndScet, random(7, 8));
                    clocks(random(0, 5));
                end loop;

                -- DLC 0 to 6: not processed
                for Dlc in 0 to 6 loop
                    C0_v := CntDrop;
                    pdo(rndScet, Dlc);
                    clocks(2);
                    check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop for DLC " & to_string(Dlc));
                end loop;

            -- *** TC-TM-08: basic protocol ***
            elsif run("test_rx_basic") then

                for Ty in 254 to 255 loop
                    Cfg_RxType <= u8(Ty);
                    C0_v       := CntSet;
                    pdo(x"00ABCDEF123456");
                    wait until falling_edge(Clk);
                    check_value(Stat_Scet(55 downto 24), x"00ABCDEF", ERROR, "the received SCET from the next cycle");
                    clocks(1000);
                    check_value(CntSet, C0_v + 1, ERROR, "Evt_Set");
                end loop;

            -- *** TC-TM-09: high-resolution protocol ***
            elsif run("test_rx_high_res") then

                for Ty in 0 to 3 loop

                    case Ty is
                        when 0 =>
                            Cfg_RxType <= u8(0);
                        when 1 =>
                            Cfg_RxType <= u8(1);
                        when 2 =>
                            Cfg_RxType <= u8(120);
                        when others =>
                            Cfg_RxType <= u8(240);
                    end case;

                    for D in 0 to 4 loop
                        sync;

                        case D is
                            when 0 =>
                                null;
                            when 1 =>
                                clocks(1);
                            when 2 =>
                                clocks(998);
                            when 3 =>
                                if Ty = 0 then
                                    clocks(999998);
                                end if;
                            when others =>
                                clocks(random(0, 5000));
                        end case;

                        pdo(rndScet);
                        clocks(100);
                    end loop;

                end loop;

            -- *** TC-TM-10: types 241 to 253 of the Spacecraft Time PDO ***
            elsif run("test_rx_types_none") then
                sync;

                for Ty in 241 to 253 loop
                    Cfg_RxType <= u8(Ty);
                    C0_v       := CntDrop;
                    K_v        := CntSet;
                    pdo(rndScet);
                    clocks(3);
                    check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop for type " & to_string(Ty));
                    check_value(CntSet, K_v, ERROR, "no setting for type " & to_string(Ty));
                end loop;

            -- *** TC-TM-11: format of the Local Time PDO ***
            elsif run("test_tx_format") then
                -- The example of the specification (section 2.6): written, sampled at the next SYNC and sent with
                -- the sample (types 254 and 1: the high-resolution protocol)
                Cfg_RxType <= u8(1);
                Cfg_TxType <= u8(254);
                write(x"12345678ABCDEF");
                sync;
                N_v        := TxCnt;
                request;
                waitCnt(TxCnt, N_v + 1, 10, "frame of the example");
                if F_c = 24 then
                    check_value(LogData(N_v), x"EFCDAB7856341200", ERROR, "frame of the example, FineBits_g = 24");
                elsif F_c = 16 then
                    check_value(LogData(N_v), x"00CDAB7856341200", ERROR, "frame of the example, FineBits_g = 16");
                end if;
                Cfg_RxType <= u8(254);

                for I in 1 to 100 loop
                    write(rndScet);
                    clocks(random(0, 5));
                    request;
                    clocks(10);
                end loop;

            -- *** TC-TM-12: SYNC types 1 to 240 ***
            elsif run("test_tx_sync_types") then

                for Ty in 0 to 3 loop

                    case Ty is
                        when 0 =>
                            K_v := 1;
                        when 1 =>
                            K_v := 2;
                        when 2 =>
                            K_v := 7;
                        when others =>
                            K_v := 240;
                    end case;

                    Cfg_TxType <= u8(K_v);
                    clocks(2);
                    N_v        := TxCnt;

                    -- 2 x T SYNCs with SYNCs of a wrong DLC between them
                    for S in 1 to 2 * K_v loop
                        sync;
                        sync(2);
                        clocks(2);
                    end loop;

                    clocks(10);
                    check_value(TxCnt - N_v, 2, ERROR, "a frame at every T-th SYNC, T = " & to_string(K_v));
                    -- Counted from the first SYNC after a reset communication: T - 1 SYNCs give no frame, the T-th one
                    sync;
                    clocks(5);
                    resetComm;
                    clocks(5);
                    N_v := TxCnt;

                    for S in 1 to K_v - 1 loop
                        sync;
                        clocks(2);
                    end loop;

                    clocks(10);
                    check_value(TxCnt, N_v, ERROR, "count restarts at a reset communication, T = " & to_string(K_v));
                    sync;
                    clocks(10);
                    check_value(TxCnt, N_v + 1, ERROR, "frame at the T-th SYNC after it, T = " & to_string(K_v));
                end loop;

                -- Counted from the first SYNC after a change of the type
                Cfg_TxType <= u8(3);
                clocks(2);
                sync;
                Cfg_TxType <= u8(2);
                clocks(2);
                N_v        := TxCnt;
                sync;
                clocks(10);
                check_value(TxCnt, N_v, ERROR, "count restarts at a change of the type");
                sync;
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "frame at the second SYNC after the change");

            -- *** TC-TM-13: type 0 ***
            elsif run("test_tx_type0") then
                Cfg_TxType <= u8(0);
                clocks(2);
                N_v        := TxCnt;
                sync;
                clocks(5);
                check_value(TxCnt, N_v, ERROR, "no frame without a request");
                request;
                request;
                request;
                clocks(5);
                check_value(TxCnt, N_v, ERROR, "no frame before the SYNC");
                sync;
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "one frame at the SYNC after the requests");
                sync;
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "no frame at the next SYNC");
                -- A reset communication between the request and the SYNC discards it
                request;
                resetComm;
                sync;
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "request discarded by the reset communication");

            -- *** TC-TM-14: types 254 and 255 ***
            elsif run("test_tx_on_request") then

                for Ty in 254 to 255 loop
                    Cfg_TxType <= u8(Ty);
                    -- Basic protocol: the time of the cycle of the request
                    Cfg_RxType <= u8(254);
                    clocks(2);
                    N_v        := TxCnt;
                    request;
                    clocks(10);
                    check_value(TxCnt, N_v + 1, ERROR, "frame at the request");
                    -- High-resolution protocol with a sample: the last sample
                    Cfg_RxType <= u8(1);
                    sync;
                    clocks(500);
                    request;
                    clocks(10);
                    check_value(TxCnt, N_v + 2, ERROR, "frame with the last sample");
                end loop;

            -- *** TC-TM-15: types 241 to 253 of the Local Time PDO ***
            elsif run("test_tx_types_none") then

                for Ty in 241 to 253 loop
                    Cfg_TxType <= u8(Ty);
                    clocks(2);
                    N_v        := TxCnt;
                    sync;
                    request;
                    clocks(5);
                    check_value(TxCnt, N_v, ERROR, "no frame for type " & to_string(Ty));
                end loop;

            -- *** TC-TM-16: pending request ***
            elsif run("test_tx_pending") then
                Cfg_TxType <= u8(254);
                -- Held Tx_Ready: the requests meanwhile give Err_TxBusy
                RespHold <= true;
                request;
                C0_v     := CntBusy;
                request;
                request;
                clocks(2);
                check_value(CntBusy, C0_v + 2, ERROR, "Err_TxBusy while Tx_Ready is held");
                RespHold <= false;
                clocks(10);
                -- Held completion
                RespCpl <= 100;
                request;
                clocks(5);
                C0_v    := CntBusy;
                request;
                clocks(2);
                check_value(CntBusy, C0_v + 1, ERROR, "Err_TxBusy while the completion is held");
                clocks(120);
                -- Completion by Tx_Aborted and by the reject path; no repetition
                RespCpl   <= 3;
                RespAbort <= true;
                N_v       := TxCnt;
                request;
                clocks(20);
                check_value(TxCnt, N_v + 1, ERROR, "an aborted frame is not repeated");
                RespAbort <= false;
                RespRej   <= true;
                request;
                clocks(20);
                check_value(TxCnt, N_v + 2, ERROR, "a rejected frame is not repeated");
                RespRej   <= false;
                -- A request in the cycle of a completion is made
                RespCpl   <= 10;
                request;
                wait until CplDone = '1' for 1 us;
                Req_Valid <= '1';
                wait until rising_edge(Clk);
                Req_Valid <= '0';
                clocks(30);
                -- Reset communication while a request is pending: it completes
                RespCpl <= 50;
                N_v     := TxCnt;
                request;
                clocks(5);
                resetComm;
                clocks(60);
                check_value(TxCnt, N_v + 1, ERROR, "the pending request completes after a reset communication");

            -- *** TC-TM-17: back-to-back events ***
            elsif run("test_back_to_back") then
                Cfg_RxType <= u8(1);
                Cfg_TxType <= u8(1);

                for D in 1 to 3 loop
                    sync;
                    clocks(D - 1);
                    pdo(rndScet);
                    clocks(10);
                end loop;

                pdo(rndScet);
                sync;
                clocks(10);

                for I in 1 to 2000 loop
                    wait until rising_edge(Clk);
                    Rx_SyncValid  <= '0';
                    Rx_TimeValid  <= '0';
                    Cfg_SetValid  <= '0';
                    Req_Valid     <= '0';
                    Nmt_ResetComm <= '0';

                    case random(0, 7) is
                        when 0 =>
                            Rx_SyncValid <= '1';
                            Rx_SyncDlc   <= std_logic_vector(to_unsigned(random(0, 2), 4));
                        when 1 =>
                            Rx_TimeValid <= '1';
                            Rx_TimeDlc   <= std_logic_vector(to_unsigned(random(6, 8), 4));
                            Rx_TimeData  <= frameOf(rndScet);
                        when 2 =>
                            Cfg_SetValid <= '1';
                            Cfg_SetScet  <= rndScet;
                        when 3 =>
                            Req_Valid <= '1';
                        when 4 =>
                            Cfg_RxType <= u8(random(0, 1) * 254);
                        when 5 =>
                            Cfg_TxType <= u8(random(0, 2));
                        when others =>
                            null;
                    end case;

                end loop;

                wait until rising_edge(Clk);
                Rx_SyncValid <= '0';
                Rx_TimeValid <= '0';
                Cfg_SetValid <= '0';
                Req_Valid    <= '0';
                clocks(20);

            -- *** TC-TM-19: time-out of the Local Time PDO ***
            elsif run("test_tx_timeout") then
                TickPer    <= 4;
                Cfg_TxType <= u8(254);
                RespCpl    <= 3000;
                clocks(1);
                N_v        := TxCnt;
                request;
                waitCnt(TxCnt, N_v + 1, 10, "frame taken");
                RespCpl    <= 3;
                C0_v       := Cyc;
                -- A request while the frame is awaited: Err_TxBusy
                clocks(100);
                K_v := CntBusy;
                request;
                clocks(2);
                check_value(CntBusy, K_v + 1, ERROR, "Err_TxBusy while the frame is awaited");
                waitCnt(CntTmo, 1, 256 * 4 + 20, "time-out");
                check_value(CycTmo - C0_v >= 255 * 4 and CycTmo - C0_v <= 256 * 4 + 4, true, ERROR,
                            "time-out after 256 ticks");
                clocks(20);
                check_value(TxCnt, N_v + 1, ERROR, "no repetition after the time-out");
                -- The next request: taken after the late completion of the old frame
                request;
                waitCnt(TxCnt, N_v + 2, 3000, "next frame after the late completion");

            -- *** TC-TM-20: same-cycle rules ***
            elsif run("test_same_cycle") then
                Cfg_RxType <= u8(1);
                Cfg_TxType <= u8(254);
                -- A SYNC and a high-resolution PDO in one cycle, as the first SYNC after Rst
                wait until rising_edge(Clk);
                Rx_SyncValid <= '1';
                Rx_SyncDlc   <= x"0";
                Rx_TimeValid <= '1';
                Rx_TimeDlc   <= x"7";
                Rx_TimeData  <= frameOf(x"01000000000000");
                wait until rising_edge(Clk);
                Rx_SyncValid <= '0';
                Rx_TimeValid <= '0';
                clocks(20);
                -- A SYNC in the cycle after a high-resolution PDO
                sync;
                clocks(50);
                pdo(x"02000000000000");
                Rx_SyncValid <= '1';
                wait until rising_edge(Clk);
                Rx_SyncValid <= '0';
                clocks(20);

                -- Write, basic setting and high-resolution load in one cycle, in every combination
                for M in 1 to 7 loop
                    sync;
                    clocks(5);
                    if M mod 2 = 1 then
                        -- A high-resolution PDO, loaded in the next cycle
                        Cfg_RxType <= u8(1);
                        pdo(x"03000000000000");
                    else
                        wait until rising_edge(Clk);
                    end if;
                    Cfg_RxType <= u8(254);
                    if (M / 2) mod 2 = 1 then
                        Rx_TimeValid <= '1';
                        Rx_TimeDlc   <= x"7";
                        Rx_TimeData  <= frameOf(x"04000000000000");
                    end if;
                    if M / 4 = 1 then
                        Cfg_SetValid <= '1';
                        Cfg_SetScet  <= x"05000000000000";
                    end if;
                    wait until rising_edge(Clk);
                    Rx_TimeValid <= '0';
                    Cfg_SetValid <= '0';
                    Cfg_RxType   <= u8(1);
                    clocks(10);
                end loop;

                -- A SYNC in the cycle of a reset communication and of a change of the type: not counted
                Cfg_TxType    <= u8(2);
                clocks(2);
                N_v           := TxCnt;
                wait until rising_edge(Clk);
                Rx_SyncValid  <= '1';
                Nmt_ResetComm <= '1';
                wait until rising_edge(Clk);
                Rx_SyncValid  <= '0';
                Nmt_ResetComm <= '0';
                sync;
                clocks(10);
                check_value(TxCnt, N_v, ERROR, "SYNC of the reset communication cycle not counted");
                sync;
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "frame at the second SYNC after the reset communication");
                wait until rising_edge(Clk);
                Rx_SyncValid  <= '1';
                Cfg_TxType    <= u8(1);
                wait until rising_edge(Clk);
                Rx_SyncValid  <= '0';
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "SYNC of the type change cycle not counted");
                -- Type 0: a request in the cycle of a SYNC applies to the next SYNC
                Cfg_TxType   <= u8(0);
                clocks(2);
                N_v          := TxCnt;
                wait until rising_edge(Clk);
                Rx_SyncValid <= '1';
                Req_Valid    <= '1';
                wait until rising_edge(Clk);
                Rx_SyncValid <= '0';
                Req_Valid    <= '0';
                clocks(10);
                check_value(TxCnt, N_v, ERROR, "no frame at the SYNC of the request cycle");
                sync;
                clocks(10);
                check_value(TxCnt, N_v + 1, ERROR, "frame at the next SYNC");

            end if;

            clocks(10);

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
