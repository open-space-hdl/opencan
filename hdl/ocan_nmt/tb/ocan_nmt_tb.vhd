---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_nmt: the inputs are driven cycle by cycle, a responder answers the transmit handshake like
-- ocan_dispatch, and a reference model written from the specification predicts every output in every cycle. One run
-- block per test case of the verification plan.
--
-- Documentation: hdl/ocan_nmt/docs/verification_plan.md

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
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_nmt_tb is
    generic (
        runner_cfg   : string;
        MinimalSet_g : boolean := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_nmt_tb is

    constant NodeId_c : natural := 5;

    function slv7 (n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 7));
    end function;

    -- *** DUT signals ***
    signal Clk            : std_logic;
    signal Rst            : std_logic                     := '1';
    signal Pin_NodeId     : std_logic_vector(6 downto 0)  := slv7(NodeId_c);
    signal Pin_NodeIdCode : std_logic_vector(6 downto 0)  := not slv7(NodeId_c);
    signal Tick_Ms        : std_logic                     := '0';
    signal Cfg_HbTime     : std_logic_vector(15 downto 0) := (others => '0');
    signal Rx_Valid       : std_logic                     := '0';
    signal Rx_Cs          : std_logic_vector(7 downto 0)  := (others => '0');
    signal Tx_Valid       : std_logic;
    signal Tx_Ready       : std_logic;
    signal Tx_Data        : std_logic_vector(7 downto 0);
    signal Tx_Done        : std_logic;
    signal Tx_Aborted     : std_logic;
    signal Node_Id        : std_logic_vector(6 downto 0);
    signal Node_IdValid   : std_logic;
    signal Ena_Sdo        : std_logic;
    signal Ena_Pdo        : std_logic;
    signal Ena_Sync       : std_logic;
    signal Red_PreopReq   : std_logic                     := '0';
    signal Red_Switched   : std_logic                     := '0';
    signal Red_Selecting  : std_logic                     := '0';
    signal Stat_State     : std_logic_vector(1 downto 0);
    signal Reset_App      : std_logic;
    signal Reset_Comm     : std_logic;
    signal Err_Cs         : std_logic;
    signal Err_NodeId     : std_logic;
    signal Err_TxTimeout  : std_logic;
    signal ErrInj_BitFlip : std_logic_vector(13 downto 0) := (others => '0');
    signal ErrInj_Valid   : std_logic                     := '0';

    -- *** Cycle counter and tick generator (period TickPer cycles, 0: no tick) ***
    signal Cyc     : natural := 0;
    signal TickPer : natural := 16;

    -- *** Responder of the transmit handshake ***
    signal RespHold  : boolean   := false;  -- never take a request
    signal RespRdy   : natural   := 0;      -- cycles of Tx_Valid before Tx_Ready
    signal RespCpl   : natural   := 3;      -- cycles from Tx_Ready to the completion
    signal RespAbort : boolean   := false;  -- complete with Tx_Aborted
    signal RespRej   : boolean   := false;  -- reject path: Tx_Ready and Tx_Aborted one cycle after Tx_Valid
    signal VCnt      : natural   := 0;
    signal Grant     : std_logic;
    signal RejNow    : std_logic;
    signal CplDone   : std_logic := '0';
    signal CplAbort  : std_logic := '0';
    signal RespBusy  : boolean   := false;  -- a completion is to come

    type Byte_a is array (0 to 4095) of std_logic_vector(7 downto 0);
    type Nat_a is array (0 to 4095) of natural;

    signal TxCnt   : natural := 0;  -- requests taken (granted or rejected)
    signal LogData : Byte_a;
    signal LogCyc  : Nat_a;

    -- *** Reference model ***
    signal CheckEn    : boolean := false;
    signal ExpState   : std_logic_vector(1 downto 0);
    signal ExpEnaSdo  : std_logic;
    signal ExpEnaPdo  : std_logic;
    signal ExpEnaSync : std_logic;
    signal ExpIdValid : std_logic;
    signal ExpNodeId  : std_logic_vector(6 downto 0);
    signal ExpRstApp  : std_logic;
    signal ExpRstComm : std_logic;
    signal ExpErrCs   : std_logic;
    signal ExpErrId   : std_logic;
    signal ExpErrTmo  : std_logic;
    signal ExpTxValid : std_logic;
    signal ExpTxData  : std_logic_vector(7 downto 0);

begin

    test_runner_watchdog(runner, 500 ms);

    i_th : entity work.ocan_nmt_th
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Pin_NodeId     => Pin_NodeId,
            Pin_NodeIdCode => Pin_NodeIdCode,
            Tick_Ms        => Tick_Ms,
            Cfg_HbTime     => Cfg_HbTime,
            Rx_Valid       => Rx_Valid,
            Rx_Cs          => Rx_Cs,
            Tx_Valid       => Tx_Valid,
            Tx_Ready       => Tx_Ready,
            Tx_Data        => Tx_Data,
            Tx_Done        => Tx_Done,
            Tx_Aborted     => Tx_Aborted,
            Node_Id        => Node_Id,
            Node_IdValid   => Node_IdValid,
            Ena_Sdo        => Ena_Sdo,
            Ena_Pdo        => Ena_Pdo,
            Ena_Sync       => Ena_Sync,
            Red_PreopReq   => Red_PreopReq,
            Red_Switched   => Red_Switched,
            Red_Selecting  => Red_Selecting,
            Stat_State     => Stat_State,
            Reset_App      => Reset_App,
            Reset_Comm     => Reset_Comm,
            Err_Cs         => Err_Cs,
            Err_NodeId     => Err_NodeId,
            Err_TxTimeout  => Err_TxTimeout,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid
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
    -- Responder (behaviour of ocan_dispatch at its NMT transmit port: one frame at a time)
    -----------------------------------------------------------------------------------------------
    -- No grant while a completion is to come and none in the cycle of a completion event (DS-TX-03)
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
        variable Left_v : integer := -1;  -- cycles to the completion, -1: none
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
    -- Reference model, written from the specification and the architecture tables
    -----------------------------------------------------------------------------------------------
    p_model : process is
        type St_t is (MInit, MResetApp, MResetComm, MWaitId, MPreOp, MOp, MStopped);
        type Tx_t is (MIdle, MReq, MWait);

        function isInit (s : St_t) return boolean is
        begin
            return s = MInit or s = MResetApp or s = MResetComm or s = MWaitId;
        end function;

        function isOper (s : St_t) return boolean is
        begin
            return s = MPreOp or s = MOp or s = MStopped;
        end function;

        variable St_v      : St_t                          := MInit;
        variable Nxt_v     : St_t;
        variable InitCnt_v : natural                       := 0;
        variable S1_v      : std_logic_vector(13 downto 0) := (others => '0');
        variable S2_v      : std_logic_vector(13 downto 0) := (others => '0');
        variable IdC_v     : std_logic_vector(6 downto 0)  := (others => '0');
        variable IdN_v     : std_logic_vector(6 downto 0)  := (others => '0');
        variable ErrCs_v   : std_logic                     := '0';
        variable ErrTmo_v  : std_logic                     := '0';
        variable PrevP_v   : natural                       := 0;
        variable HbRem_v   : natural                       := 0;
        variable Tx_v      : Tx_t                          := MIdle;
        variable TxTicks_v : natural                       := 0;
        variable TxData_v  : std_logic_vector(7 downto 0)  := (others => '0');
        variable TxBoot_v  : boolean                       := false;
        variable BootDue_v : boolean                       := false;
        variable Retry_v   : boolean                       := false;
        variable Sel_v     : std_logic                     := '0';
        variable P_v       : natural;
        variable CopyOk_v  : boolean;
        variable SampOk_v  : boolean;
        variable Boot_v    : boolean;
        variable HbNow_v   : boolean;
        variable Due_v     : boolean;
        variable DoRetry_v : boolean;
        variable Cpl_v     : boolean;
        variable Blk_v     : boolean;
        variable Cs_v      : natural;
    begin
        wait until rising_edge(Clk);

        if Rst = '1' then
            St_v      := MInit;
            InitCnt_v := 0;
            IdC_v     := (others => '0');
            IdN_v     := (others => '0');
            ErrCs_v   := '0';
            ErrTmo_v  := '0';
            PrevP_v   := 0;
            HbRem_v   := 0;
            Tx_v      := MIdle;
            TxTicks_v := 0;
            TxBoot_v  := false;
            BootDue_v := false;
            Retry_v   := false;
            Sel_v     := '0';
        else
            P_v       := to_integer(unsigned(Cfg_HbTime));
            CopyOk_v  := IdN_v = not IdC_v;
            SampOk_v  := S2_v(13 downto 7) = not S2_v(6 downto 0) and unsigned(S2_v(6 downto 0)) /= 0;
            Cs_v      := to_integer(unsigned(Rx_Cs));
            Nxt_v     := St_v;
            Boot_v    := false;
            HbNow_v   := false;
            Due_v     := false;
            DoRetry_v := false;
            ErrCs_v   := '0';
            ErrTmo_v  := '0';

            -- Upsets of the copies, visible from the next cycle on
            if ErrInj_Valid = '1' then
                IdC_v := IdC_v xor ErrInj_BitFlip(6 downto 0);
                IdN_v := IdN_v xor ErrInj_BitFlip(13 downto 7);
            end if;

            if isInit(St_v) then
                BootDue_v := false;
                Retry_v   := false;
            end if;

            -- NMT state (NM-SM-01 to NM-SM-05, NM-ID-03, NM-ID-04, NM-MS-01 to NM-MS-03)
            case St_v is
                when MInit =>
                    if InitCnt_v = 1 then
                        Nxt_v := MResetApp;
                    else
                        InitCnt_v := InitCnt_v + 1;
                    end if;
                when MResetApp =>
                    Nxt_v := MResetComm;
                when MResetComm | MWaitId =>
                    if St_v = MResetComm or Tick_Ms = '1' then
                        if SampOk_v then
                            IdC_v := S2_v(6 downto 0);
                            IdN_v := S2_v(13 downto 7);
                            if MinimalSet_g then
                                Nxt_v   := MOp;
                                HbNow_v := true;
                            else
                                Nxt_v  := MPreOp;
                                Boot_v := true;
                            end if;
                        else
                            Nxt_v := MWaitId;
                        end if;
                    end if;
                when others =>
                    if Rx_Valid = '1' and not MinimalSet_g and Cs_v = 129 then
                        Nxt_v := MResetApp;
                    elsif (Rx_Valid = '1' and not MinimalSet_g and Cs_v = 130) or not CopyOk_v then
                        Nxt_v := MResetComm;
                    else
                        if Rx_Valid = '1' and not MinimalSet_g then
                            if Cs_v = 1 then
                                Nxt_v := MOp;
                            elsif Cs_v = 2 then
                                Nxt_v := MStopped;
                            elsif Cs_v = 128 then
                                Nxt_v := MPreOp;
                            end if;
                        end if;
                        if Red_PreopReq = '1' and (Nxt_v = MOp or Nxt_v = MStopped) then
                            Nxt_v := MPreOp;
                        end if;
                        if MinimalSet_g and St_v = MPreOp and Sel_v = '1' and Red_Selecting = '0' then
                            Nxt_v := MOp;
                        end if;
                    end if;
                    if Rx_Valid = '1' and not MinimalSet_g and Cs_v /= 1 and Cs_v /= 2 and Cs_v < 128 then
                        ErrCs_v := '1';
                    elsif Rx_Valid = '1' and not MinimalSet_g and Cs_v > 130 then
                        ErrCs_v := '1';
                    end if;
            end case;

            -- Transmit handshake; a completion and a time-out count for the requests of this cycle
            Cpl_v := false;
            if Tx_v = MReq and Tx_Ready = '1' then
                if Tx_Done = '1' or Tx_Aborted = '1' then
                    Cpl_v := true;
                    Tx_v  := MIdle;
                else
                    Tx_v      := MWait;
                    TxTicks_v := 0;
                end if;
            elsif Tx_v = MWait then
                if Tx_Done = '1' or Tx_Aborted = '1' then
                    Cpl_v := true;
                    Tx_v  := MIdle;
                elsif St_v = MResetComm then
                    -- Reset communication: the taken frame is no longer awaited (NM-HB-06)
                    Tx_v := MIdle;
                elsif Tick_Ms = '1' then
                    TxTicks_v := TxTicks_v + 1;
                    if TxTicks_v = 256 then
                        -- Time-out (NM-HB-08)
                        ErrTmo_v := '1';
                        Tx_v     := MIdle;
                    end if;
                end if;
            end if;
            if Cpl_v and TxBoot_v and Tx_Aborted = '1' and not isInit(Nxt_v) and not MinimalSet_g then
                Retry_v := true;
            end if;

            -- Heartbeat: remaining ticks to the next one (NM-HB-03 to NM-HB-05), repeated boot-up (NM-HB-07)
            if isInit(Nxt_v) then
                HbRem_v := 0;
            elsif Boot_v then
                HbRem_v := P_v;
            else
                if HbNow_v or P_v /= PrevP_v or Red_Switched = '1' then
                    HbRem_v := P_v;
                    if P_v /= 0 and (HbNow_v or Red_Switched = '1' or PrevP_v = 0) then
                        Due_v := true;
                    end if;
                elsif Tick_Ms = '1' and HbRem_v > 0 then
                    HbRem_v := HbRem_v - 1;
                    if HbRem_v = 0 then
                        Due_v   := true;
                        HbRem_v := P_v;
                    end if;
                end if;
                if Red_Switched = '1' and Retry_v then
                    DoRetry_v := true;
                    Due_v     := false;
                end if;
            end if;
            PrevP_v := P_v;

            -- Requests: one pending (NM-HB-06); every boot-up request ends a pending repetition (NM-HB-07)
            if Boot_v or DoRetry_v then
                Retry_v := false;
                if Tx_v = MIdle then
                    Tx_v     := MReq;
                    TxData_v := x"00";
                    TxBoot_v := true;
                else
                    BootDue_v := true;
                end if;
            elsif TxBoot_v and ErrTmo_v = '1' then
                Retry_v  := false;
                Tx_v     := MReq;
                TxData_v := x"00";
            elsif BootDue_v and Tx_v = MIdle and not isInit(Nxt_v) then
                Retry_v   := false;
                Tx_v      := MReq;
                TxData_v  := x"00";
                TxBoot_v  := true;
                BootDue_v := false;
            elsif Due_v and Tx_v = MIdle then
                Tx_v     := MReq;
                TxBoot_v := false;
                if Nxt_v = MStopped then
                    TxData_v := x"04";
                elsif Nxt_v = MOp then
                    TxData_v := x"05";
                else
                    TxData_v := x"7F";
                end if;
            end if;

            St_v  := Nxt_v;
            Sel_v := Red_Selecting;
        end if;

        -- Pin synchroniser
        if Rst = '1' then
            S2_v := (others => '0');
            S1_v := (others => '0');
        else
            S2_v := S1_v;
            S1_v := Pin_NodeIdCode & Pin_NodeId;
        end if;

        -- Outputs, with the encoding of the specification written as literals (PKG-01)
        Blk_v := BootDue_v or (TxBoot_v and Tx_v /= MIdle);

        case St_v is
            when MPreOp =>
                ExpState <= "01";
            when MOp =>
                ExpState <= "10";
            when MStopped =>
                ExpState <= "11";
            when others =>
                ExpState <= "00";
        end case;

        if (St_v = MPreOp or St_v = MOp) and not Blk_v then
            ExpEnaSdo  <= '1';
            ExpEnaSync <= '1';
        else
            ExpEnaSdo  <= '0';
            ExpEnaSync <= '0';
        end if;
        if St_v = MOp and not Blk_v then
            ExpEnaPdo <= '1';
        else
            ExpEnaPdo <= '0';
        end if;
        -- Valid after a valid sample (not in MInit or MWaitId) while the copies are complementary (NM-ID-02)
        if St_v /= MInit and St_v /= MWaitId and IdN_v = not IdC_v then
            ExpIdValid <= '1';
        else
            ExpIdValid <= '0';
        end if;
        if isOper(St_v) and IdN_v /= not IdC_v then
            ExpErrId <= '1';
        else
            ExpErrId <= '0';
        end if;
        if St_v = MResetApp then
            ExpRstApp <= '1';
        else
            ExpRstApp <= '0';
        end if;
        if St_v = MResetComm then
            ExpRstComm <= '1';
        else
            ExpRstComm <= '0';
        end if;
        if Tx_v = MReq then
            ExpTxValid <= '1';
        else
            ExpTxValid <= '0';
        end if;
        ExpNodeId <= IdC_v;
        ExpErrCs  <= ErrCs_v;
        ExpErrTmo <= ErrTmo_v;
        ExpTxData <= TxData_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Checkers in every cycle
    -----------------------------------------------------------------------------------------------
    p_check : process is
        variable Data_v : std_logic_vector(7 downto 0);

        procedure cmp (dut : std_logic_vector; exp : std_logic_vector; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & to_string(dut, BIN) & ", reference model " & to_string(exp, BIN));
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
            cmp(Stat_State, ExpState, "Stat_State");
            cmp(Ena_Sdo, ExpEnaSdo, "Ena_Sdo");
            cmp(Ena_Pdo, ExpEnaPdo, "Ena_Pdo");
            cmp(Ena_Sync, ExpEnaSync, "Ena_Sync");
            cmp(Node_IdValid, ExpIdValid, "Node_IdValid");
            cmp(Reset_App, ExpRstApp, "Reset_App");
            cmp(Reset_Comm, ExpRstComm, "Reset_Comm");
            cmp(Err_Cs, ExpErrCs, "Err_Cs");
            cmp(Err_NodeId, ExpErrId, "Err_NodeId");
            cmp(Err_TxTimeout, ExpErrTmo, "Err_TxTimeout");
            cmp(Tx_Valid, ExpTxValid, "Tx_Valid");
            if Tx_Valid = '1' then
                cmp(Tx_Data, ExpTxData, "Tx_Data");
            end if;
            if Node_IdValid = '1' then
                cmp(Node_Id, ExpNodeId, "Node_Id");
            end if;
            -- Tx_Data stable while Tx_Valid is '1'
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
        variable Valid_v : boolean;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- Reset; returns right after the edge that ends the reset, so that the next cycle is cycle 0
        procedure doReset is
        begin
            wait until rising_edge(Clk);
            Rst <= '1';
            clocks(3);
            Rst <= '0';
        end procedure;

        procedure setPins (id : natural; code : std_logic_vector(6 downto 0)) is
        begin
            Pin_NodeId     <= slv7(id);
            Pin_NodeIdCode <= code;
        end procedure;

        -- One NMT message in the next cycle
        procedure nmt (cs : natural) is
        begin
            wait until rising_edge(Clk);
            Rx_Valid <= '1';
            Rx_Cs    <= std_logic_vector(to_unsigned(cs, 8));
            wait until rising_edge(Clk);
            Rx_Valid <= '0';
        end procedure;

        procedure preopReq is
        begin
            wait until rising_edge(Clk);
            Red_PreopReq <= '1';
            wait until rising_edge(Clk);
            Red_PreopReq <= '0';
        end procedure;

        procedure switched is
        begin
            wait until rising_edge(Clk);
            Red_Switched <= '1';
            wait until rising_edge(Clk);
            Red_Switched <= '0';
        end procedure;

        procedure waitFor (signal s : std_logic; val : std_logic; timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while s /= val loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        procedure waitState (st : std_logic_vector(1 downto 0); timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while Stat_State /= st loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- Waits until n requests have been taken in total
        procedure waitTx (n : natural; timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while TxCnt < n loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- Reset with valid pins and wait for the completion of the boot-up message
        procedure startNode is
        begin
            doReset;
            if MinimalSet_g then
                waitState(NmtOp_c, 100, "Operational after the reset");
            else
                waitFor(Ena_Sdo, '1', 200, "boot-up message completed");
            end if;
            clocks(2);
        end procedure;

        -- Brings the node into Pre-operational (st 0), Operational (1) or Stopped (2)
        procedure goState (st : natural) is
        begin
            startNode;
            if st = 1 then
                nmt(1);
            elsif st = 2 then
                nmt(2);
            end if;
            clocks(2);
        end procedure;

        function stCode (st : natural) return std_logic_vector is
        begin
            if st = 1 then
                return NmtOp_c;
            elsif st = 2 then
                return NmtStopped_c;
            else
                return NmtPreOp_c;
            end if;
        end function;

        -- Waits for the next tick and returns in the cycle after it plus k cycles
        procedure afterTick (k : natural) is
        begin
            wait until rising_edge(Clk) and Tick_Ms = '1';
            clocks(k);
        end procedure;

        variable N_v    : natural;
        variable C0_v   : natural;
        variable Id_v   : natural;
        variable Cs_v   : natural;
        variable Code_v : std_logic_vector(6 downto 0);
        variable Ids_v  : Nat_a;
        variable NIds_v : natural;
        variable Flip_v : std_logic_vector(13 downto 0);
        variable Gap_v  : natural;
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
            Cfg_HbTime    <= (others => '0');
            setPins(NodeId_c, not slv7(NodeId_c));
            Rx_Valid      <= '0';
            Red_PreopReq  <= '0';
            Red_Switched  <= '0';
            Red_Selecting <= '0';
            ErrInj_Valid  <= '0';
            doReset;
            CheckEn       <= true;

            -- *** TC-NM-01: reset sequence ***
            if run("test_reset_sequence") then

                for K in 0 to 2 loop
                    RespAbort <= K = 1;
                    RespRej   <= K = 2;
                    doReset;
                    -- Cycle 0 begins now

                    for C in 0 to 5 loop
                        wait until falling_edge(Clk);
                        check_value(Reset_App = '1', C = 2, ERROR, "Reset_App in cycle " & to_string(C));
                        check_value(Reset_Comm = '1', C = 3, ERROR, "Reset_Comm in cycle " & to_string(C));
                        check_value(Tx_Valid = '1', C = 4 or (C = 5 and K = 2), ERROR, "boot-up request in cycle " & to_string(C));
                        check_value(Node_IdValid = '1', C >= 4, ERROR, "Node_IdValid in cycle " & to_string(C));
                        check_value(Ena_Sdo, '0', ERROR, "Ena_Sdo until the boot-up message completes");
                        if C >= 4 then
                            check_value(Stat_State, NmtPreOp_c, ERROR, "Pre-operational from the request");
                            check_value(Tx_Data, x"00", ERROR, "boot-up data byte");
                            check_value(Node_Id, slv7(NodeId_c), ERROR, "Node_Id");
                        else
                            check_value(Stat_State, NmtInit_c, ERROR, "Initialisation");
                        end if;
                    end loop;

                    waitFor(Ena_Sdo, '1', 20, "enables after the completion of the boot-up message");
                    check_value(Ena_Sync, '1', ERROR, "Ena_Sync in Pre-operational");
                    check_value(Ena_Pdo, '0', ERROR, "Ena_Pdo in Pre-operational");
                end loop;

            -- *** TC-NM-02: every valid NODE-ID ***
            elsif run("test_node_id_valid") then

                for Id in 1 to 127 loop
                    setPins(Id, not slv7(Id));
                    startNode;
                    check_value(Node_Id, slv7(Id), ERROR, "Node_Id " & to_string(Id));
                    check_value(Node_IdValid, '1', ERROR, "Node_IdValid " & to_string(Id));
                end loop;

                -- Another valid NODE-ID before a reset communication and a reset node: the valid flag stays set
                for K in 0 to 1 loop
                    Id_v := 77 + K;
                    setPins(Id_v, not slv7(Id_v));
                    clocks(4);
                    if K = 0 then
                        nmt(130);
                    else
                        nmt(129);
                    end if;

                    for C in 0 to 8 loop
                        wait until falling_edge(Clk);
                        check_value(Node_IdValid, '1', ERROR, "Node_IdValid through the NMT reset");
                    end loop;

                    check_value(Node_Id, slv7(Id_v), ERROR, "new NODE-ID after the sample");
                    waitFor(Ena_Sdo, '1', 50, "boot-up message after the NMT reset");
                end loop;

            -- *** TC-NM-03: invalid NODE-ID samples ***
            elsif run("test_node_id_invalid") then
                NIds_v   := 0;
                Ids_v(0) := 1;
                Ids_v(1) := 127;

                for I in 2 to 15 loop
                    Ids_v(I) := random(2, 126);
                end loop;

                -- Cases: index 0 NODE-ID 0; 1 code = NODE-ID; 2 all '0'; 3 all '1'; then the single-bit errors
                for Case_v in 0 to 3 + 16 * 14 - 1 loop
                    if Case_v = 0 then
                        setPins(0, "1111111");
                    elsif Case_v = 1 then
                        setPins(NodeId_c, slv7(NodeId_c));
                    elsif Case_v = 2 then
                        setPins(0, "0000000");
                    elsif Case_v = 3 then
                        setPins(127, "1111111");
                    else
                        Id_v                        := Ids_v((Case_v - 4) / 14);
                        Flip_v                      := (others => '0');
                        Flip_v((Case_v - 4) mod 14) := '1';
                        Pin_NodeId                  <= slv7(Id_v) xor Flip_v(6 downto 0);
                        Pin_NodeIdCode              <= (not slv7(Id_v)) xor Flip_v(13 downto 7);
                    end if;
                    C0_v := TxCnt;
                    doReset;
                    clocks(3 * 16 + 5);
                    check_value(Node_IdValid, '0', ERROR, "Node_IdValid with an invalid code, case " & to_string(Case_v));
                    check_value(Stat_State, NmtInit_c, ERROR, "Initialisation with an invalid code");
                    check_value(TxCnt, C0_v, ERROR, "no frame with an invalid code");
                end loop;

                -- A valid code between two ticks takes effect at the next tick
                afterTick(4);
                setPins(NodeId_c, not slv7(NodeId_c));
                clocks(8);
                check_value(Node_IdValid, '0', ERROR, "no sample between two ticks");
                wait until rising_edge(Clk) and Tick_Ms = '1';
                wait until falling_edge(Clk);
                check_value(Node_IdValid, '1', ERROR, "sample at the tick");
                waitFor(Ena_Sdo, '1', 50, "boot-up message after the valid sample");

                -- Reset communication after the pins changed to an invalid code
                setPins(NodeId_c, slv7(NodeId_c));
                clocks(4);
                nmt(130);
                clocks(2);
                check_value(Node_IdValid, '0', ERROR, "Node_IdValid cleared by the invalid sample");

            -- *** TC-NM-04: upsets of the NODE-ID copies ***
            elsif run("test_node_id_upset") then

                for St in 0 to 2 loop

                    for B in 0 to 13 loop
                        goState(St);
                        Flip_v         := (others => '0');
                        Flip_v(B)      := '1';
                        C0_v           := TxCnt;
                        wait until rising_edge(Clk);
                        ErrInj_BitFlip <= Flip_v;
                        ErrInj_Valid   <= '1';
                        wait until rising_edge(Clk);
                        ErrInj_Valid   <= '0';
                        wait until falling_edge(Clk);
                        check_value(Node_IdValid, '0', ERROR, "Node_IdValid in the cycle of the upset");
                        check_value(Err_NodeId, '1', ERROR, "Err_NodeId in the cycle of the upset");
                        wait until falling_edge(Clk);
                        check_value(Reset_Comm, '1', ERROR, "reset communication after the upset");
                        waitTx(C0_v + 1, 50, "boot-up message after the upset");
                        check_value(LogData(C0_v), x"00", ERROR, "boot-up message after the upset");
                        check_value(Node_Id, slv7(NodeId_c), ERROR, "NODE-ID of the pins after the new sample");
                    end loop;

                end loop;

            -- *** TC-NM-05: node control services ***
            elsif run("test_node_control") then

                for St in 0 to 2 loop

                    for K in 0 to 4 loop
                        goState(St);
                        C0_v := TxCnt;

                        case K is
                            when 0 =>
                                Cs_v := 1;
                            when 1 =>
                                Cs_v := 2;
                            when 2 =>
                                Cs_v := 128;
                            when 3 =>
                                Cs_v := 129;
                            when others =>
                                Cs_v := 130;
                        end case;

                        nmt(Cs_v);
                        wait until falling_edge(Clk);
                        if K < 3 then
                            check_value(Stat_State, stCode((K + 1) mod 3), ERROR, "state after the command");
                        elsif K = 3 then
                            check_value(Reset_App, '1', ERROR, "Reset_App after reset node");
                            wait until falling_edge(Clk);
                            check_value(Reset_Comm, '1', ERROR, "Reset_Comm after reset node");
                            waitTx(C0_v + 1, 50, "boot-up message after reset node");
                        else
                            check_value(Reset_App, '0', ERROR, "no Reset_App at reset communication");
                            check_value(Reset_Comm, '1', ERROR, "Reset_Comm after reset communication");
                            waitTx(C0_v + 1, 50, "boot-up message after reset communication");
                        end if;
                        clocks(8);
                    end loop;

                end loop;

            -- *** TC-NM-06: unknown command specifiers ***
            elsif run("test_unknown_cs") then

                for St in 0 to 2 loop
                    goState(St);

                    for Cs in 0 to 255 loop
                        if Cs /= 1 and Cs /= 2 and Cs /= 128 and Cs /= 129 and Cs /= 130 then
                            nmt(Cs);
                            wait until falling_edge(Clk);
                            check_value(Err_Cs, '1', ERROR, "Err_Cs for " & to_string(Cs));
                            check_value(Stat_State, stCode(St), ERROR, "no change for " & to_string(Cs));
                        end if;
                    end loop;

                end loop;

                -- NMT messages in the Initialisation: no change, no error
                setPins(0, "1111111");
                doReset;

                for Cs in 0 to 255 loop
                    nmt(Cs);
                end loop;

                check_value(Stat_State, NmtInit_c, ERROR, "Initialisation unchanged by NMT messages");

            -- *** TC-NM-07: NMT messages back to back ***
            elsif run("test_nmt_back_to_back") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(3, 16));
                startNode;

                for I in 1 to 2000 loop
                    N_v := random(0, 9);
                    if N_v < 2 then
                        Cs_v := 1;
                    elsif N_v < 4 then
                        Cs_v := 2;
                    elsif N_v < 6 then
                        Cs_v := 128;
                    elsif N_v = 6 then
                        Cs_v := 129;
                    elsif N_v = 7 then
                        Cs_v := 130;
                    else
                        Cs_v := random(0, 255);
                    end if;
                    wait until rising_edge(Clk);
                    Rx_Valid <= '1';
                    Rx_Cs    <= std_logic_vector(to_unsigned(Cs_v, 8));
                    Gap_v    := random(0, 3);
                    if Gap_v > 0 then
                        wait until rising_edge(Clk);
                        Rx_Valid <= '0';
                        clocks(Gap_v - 1);
                    end if;
                end loop;

                wait until rising_edge(Clk);
                Rx_Valid <= '0';
                clocks(50);

            -- *** TC-NM-08: request of ocan_redundancy to enter Pre-operational ***
            elsif run("test_preop_request") then

                for St in 0 to 2 loop
                    goState(St);
                    preopReq;
                    wait until falling_edge(Clk);
                    check_value(Stat_State, NmtPreOp_c, ERROR, "Pre-operational after the request");
                end loop;

                -- No effect in the Initialisation
                setPins(0, "1111111");
                doReset;
                clocks(10);
                preopReq;
                clocks(2);
                check_value(Stat_State, NmtInit_c, ERROR, "request without effect in the Initialisation");
                setPins(NodeId_c, not slv7(NodeId_c));

                -- Same cycle as an NMT message
                for K in 0 to 5 loop
                    goState(1);

                    case K is
                        when 0 =>
                            Cs_v := 1;
                        when 1 =>
                            Cs_v := 2;
                        when 2 =>
                            Cs_v := 128;
                        when 3 =>
                            Cs_v := 129;
                        when 4 =>
                            Cs_v := 130;
                        when others =>
                            Cs_v := 7;
                    end case;

                    wait until rising_edge(Clk);
                    Rx_Valid     <= '1';
                    Rx_Cs        <= std_logic_vector(to_unsigned(Cs_v, 8));
                    Red_PreopReq <= '1';
                    wait until rising_edge(Clk);
                    Rx_Valid     <= '0';
                    Red_PreopReq <= '0';
                    wait until falling_edge(Clk);
                    if K = 3 then
                        check_value(Reset_App, '1', ERROR, "reset node discards the request");
                    elsif K = 4 then
                        check_value(Reset_Comm, '1', ERROR, "reset communication discards the request");
                    else
                        check_value(Stat_State, NmtPreOp_c, ERROR, "command first, then the request");
                    end if;
                    clocks(10);
                end loop;

            -- *** TC-NM-09: heartbeat period and the bounds of the first interval ***
            elsif run("test_heartbeat_period") then
                RespCpl <= 1;

                for K in 0 to 4 loop

                    case K is
                        when 0 =>
                            N_v := 1;
                        when 1 =>
                            N_v := 2;
                        when 2 =>
                            N_v := 7;
                        when 3 =>
                            N_v := 1000;
                        when others =>
                            N_v := 65535;
                    end case;

                    if N_v >= 1000 then
                        TickPer <= 4;
                    else
                        TickPer <= 16;
                    end if;
                    Cfg_HbTime <= std_logic_vector(to_unsigned(N_v, 16));
                    startNode;

                    for St in 0 to 2 loop
                        if St = 1 then
                            nmt(1);
                        elsif St = 2 then
                            nmt(2);
                        end if;
                        C0_v := TxCnt;
                        waitTx(C0_v + 3, 3 * N_v * 16 + 100, "three heartbeats");
                        check_value(LogCyc(C0_v + 2) - LogCyc(C0_v + 1), N_v * TickPer, ERROR,
                                    "heartbeat period for P = " & to_string(N_v));
                        if St = 0 then
                            check_value(LogData(C0_v + 1), x"7F", ERROR, "Pre-operational state byte");
                        elsif St = 1 then
                            check_value(LogData(C0_v + 1), x"05", ERROR, "Operational state byte");
                        else
                            check_value(LogData(C0_v + 1), x"04", ERROR, "Stopped state byte");
                        end if;
                    end loop;

                end loop;

                -- P = 0: no heartbeat
                TickPer    <= 2;
                Cfg_HbTime <= (others => '0');
                startNode;
                C0_v       := TxCnt;
                clocks(200000);
                check_value(TxCnt, C0_v, ERROR, "no heartbeat with P = 0");

                -- Bounds of the first interval after a restart (Red_Switched), P = 3 and M = 16
                TickPer    <= 16;
                Cfg_HbTime <= std_logic_vector(to_unsigned(3, 16));
                startNode;

                for K in 0 to 2 loop
                    -- K = 0: switch one cycle after a tick; 1: one cycle before a tick; 2: in the cycle of a tick
                    if K = 0 then
                        wait until rising_edge(Clk) and Tick_Ms = '1';
                    elsif K = 1 then
                        afterTick(14);
                    else
                        afterTick(15);
                    end if;
                    Red_Switched <= '1';
                    wait until rising_edge(Clk);
                    Red_Switched <= '0';
                    C0_v         := TxCnt;
                    waitTx(C0_v + 2, 200, "heartbeats after the switch");
                    if K = 0 then
                        check_value(LogCyc(C0_v + 1) - LogCyc(C0_v), 3 * 16 - 1, ERROR, "upper bound P x M - 1");
                    elsif K = 1 then
                        check_value(LogCyc(C0_v + 1) - LogCyc(C0_v), 2 * 16 + 1, ERROR, "lower bound (P - 1) x M + 1");
                    else
                        check_value(LogCyc(C0_v + 1) - LogCyc(C0_v), 3 * 16, ERROR, "restart in the cycle of a tick");
                    end if;
                end loop;

            -- *** TC-NM-10: restarts of the heartbeat cycle ***
            elsif run("test_heartbeat_restart") then
                RespCpl <= 1;
                startNode;
                C0_v    := TxCnt;
                -- 0 to 5: a heartbeat at once
                wait until rising_edge(Clk);
                Cfg_HbTime <= std_logic_vector(to_unsigned(5, 16));
                clocks(3);
                check_value(TxCnt, C0_v + 1, ERROR, "heartbeat at once after P from 0 to 5");
                waitTx(C0_v + 3, 20 * 16, "heartbeats every 5 ticks");
                check_value(LogCyc(C0_v + 2) - LogCyc(C0_v + 1), 5 * 16, ERROR, "period of 5 ticks");
                -- 5 to 3: the next heartbeat 3 ticks after the change
                afterTick(2);
                Cfg_HbTime <= std_logic_vector(to_unsigned(3, 16));
                C0_v       := TxCnt;
                N_v        := Cyc + 1;
                waitTx(C0_v + 1, 10 * 16, "heartbeat after the change to 3");
                check_value(LogCyc(C0_v) - N_v, 3 * 16 - 2, ERROR, "3 ticks after the change");
                -- to 0: no more heartbeats
                Cfg_HbTime <= (others => '0');
                C0_v       := TxCnt;
                clocks(20 * 16);
                check_value(TxCnt, C0_v, ERROR, "no heartbeat after P = 0");
                -- Red_Switched with P = 0: none; with P = 3: at once
                switched;
                clocks(4);
                check_value(TxCnt, C0_v, ERROR, "no heartbeat at a switch with P = 0");
                Cfg_HbTime <= std_logic_vector(to_unsigned(3, 16));
                clocks(4);
                C0_v       := TxCnt;
                switched;
                clocks(3);
                check_value(TxCnt, C0_v + 1, ERROR, "heartbeat at once after a switch");
                -- A change of P, a switch and a tick in one cycle: one request
                wait until rising_edge(Clk) and Tick_Ms = '1';
                clocks(TickPer - 1);
                C0_v         := TxCnt;
                Cfg_HbTime   <= std_logic_vector(to_unsigned(4, 16));
                Red_Switched <= '1';
                wait until rising_edge(Clk);
                Red_Switched <= '0';
                clocks(4);
                check_value(TxCnt, C0_v + 1, ERROR, "one request for several restarts");
                -- In the Initialisation: no heartbeat at a switch
                setPins(0, "1111111");
                doReset;
                clocks(10);
                C0_v := TxCnt;
                switched;
                clocks(10);
                check_value(TxCnt, C0_v, ERROR, "no heartbeat in the Initialisation");

            -- *** TC-NM-11: at most one pending request ***
            elsif run("test_request_pending") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(2, 16));
                startNode;
                RespHold   <= true;
                waitFor(Tx_Valid, '1', 4 * 16, "heartbeat request");
                C0_v       := TxCnt;
                clocks(3 * 2 * 16);
                check_value(Tx_Valid, '1', ERROR, "the heartbeat stays pending");
                check_value(TxCnt, C0_v, ERROR, "no further request while one is pending");
                -- Reset communication while the heartbeat is pending: the boot-up message follows its completion
                nmt(130);
                clocks(4);
                RespHold <= false;
                waitTx(C0_v + 2, 50, "heartbeat completed and boot-up message requested");
                check_value(LogData(C0_v), x"7F", ERROR, "pending heartbeat completed first");
                check_value(LogData(C0_v + 1), x"00", ERROR, "then the boot-up message");
                check_value(Ena_Sdo, '0', ERROR, "enables cleared until the boot-up message completes");
                waitFor(Ena_Sdo, '1', 20, "enables after the boot-up message");
                -- The completion held for 3 P after Tx_Ready: no request while the heartbeat waits for it
                RespCpl <= 3 * 2 * 16 + 10;
                C0_v    := TxCnt;
                waitTx(C0_v + 1, 4 * 16, "heartbeat taken");
                clocks(3 * 2 * 16);
                check_value(TxCnt, C0_v + 1, ERROR, "no request while the completion is pending");
                check_value(Tx_Valid, '0', ERROR, "no Tx_Valid while the completion is pending");

            -- *** TC-NM-12: aborted frames ***
            elsif run("test_abort") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(3, 16));
                startNode;

                -- Heartbeat aborted through the reject path and after Tx_Ready: not repeated
                for K in 0 to 1 loop
                    RespRej   <= K = 0;
                    RespAbort <= K = 1;
                    C0_v      := TxCnt;
                    waitTx(C0_v + 1, 5 * 16, "heartbeat");
                    clocks(16);
                    check_value(TxCnt, C0_v + 1, ERROR, "aborted heartbeat not repeated");
                    waitTx(C0_v + 2, 5 * 16, "next heartbeat at its time");
                    check_value(LogCyc(C0_v + 1) - LogCyc(C0_v), 3 * 16, ERROR, "next heartbeat after P");
                end loop;

                RespRej <= false;

                -- Boot-up message aborted: the enables return; at the next switch the boot-up message again
                for K in 0 to 1 loop
                    if K = 1 then
                        Cfg_HbTime <= (others => '0');
                    end if;
                    RespAbort <= true;
                    doReset;
                    waitFor(Ena_Sdo, '1', 50, "enables after the aborted boot-up message");
                    RespAbort <= false;
                    if K = 0 then
                        waitFor(Tx_Done, '1', 5 * 16, "heartbeat completed");
                    else
                        clocks(5);
                    end if;
                    C0_v := TxCnt;
                    switched;
                    wait until falling_edge(Clk);
                    check_value(Tx_Valid, '1', ERROR, "request at the switch");
                    check_value(Tx_Data, x"00", ERROR, "boot-up message repeated at the switch");
                    check_value(Ena_Sdo, '0', ERROR, "enables cleared during the repeated boot-up message");
                    waitFor(Ena_Sdo, '1', 20, "enables after the repeated boot-up message");
                    if K = 0 then
                        clocks(2);
                        switched;
                        wait until falling_edge(Clk);
                        check_value(Tx_Data, x"7F", ERROR, "heartbeat at the next switch");
                    end if;
                    clocks(10);
                end loop;

            -- *** TC-NM-16: no stale repetition of the boot-up message ***
            elsif run("test_boot_retry_stale") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(1000, 16));

                for K in 0 to 2 loop
                    RespRej   <= false;
                    RespAbort <= false;
                    RespCpl   <= 3;
                    if K /= 1 then
                        -- The boot-up request waits for Tx_Ready
                        RespHold <= true;
                    else
                        -- The boot-up message is taken and aborted later
                        RespHold  <= false;
                        RespCpl   <= 200;
                        RespAbort <= true;
                    end if;
                    doReset;
                    waitFor(Tx_Valid, '1', 20, "boot-up request");
                    clocks(2);
                    -- Upset of a copy: reset communication and a new boot-up message
                    ErrInj_BitFlip <= (0 => '1', others => '0');
                    ErrInj_Valid   <= '1';
                    wait until rising_edge(Clk);
                    ErrInj_Valid   <= '0';
                    if K = 2 then
                        -- The old request ends through the reject path in the cycle of the reset communication, in
                        -- which the new boot-up message is requested at once
                        wait until rising_edge(Clk);
                        RespRej  <= true;
                        wait until falling_edge(Clk);
                        check_value(Reset_Comm, '1', ERROR, "reject in the cycle of the reset communication");
                        check_value(RejNow, '1', ERROR, "reject in the cycle of the reset communication");
                        wait until rising_edge(Clk);
                        RespRej  <= false;
                        RespHold <= false;
                        wait until falling_edge(Clk);
                        check_value(Tx_Valid, '1', ERROR, "new boot-up request");
                        check_value(Tx_Data, x"00", ERROR, "new boot-up request");
                    else
                        waitFor(Reset_Comm, '1', 10, "reset communication after the upset");
                        clocks(3);
                    end if;
                    if K = 0 then
                        -- The old request ends through the reject path in the cycle the deferred new one is
                        -- registered
                        RespHold <= false;
                        RespRej  <= true;
                        waitFor(RejNow, '1', 10, "reject path");
                        RespRej  <= false;
                    elsif K = 2 then
                        null;
                    else
                        wait until CplAbort = '1' for 20 us;
                        check_value(CplAbort, '1', ERROR, "late abort of the old boot-up message");
                        RespAbort <= false;
                        RespCpl   <= 3;
                    end if;
                    waitFor(Ena_Sdo, '1', 300, "the new boot-up message completed");
                    clocks(2);
                    switched;
                    wait until falling_edge(Clk);
                    check_value(Tx_Valid, '1', ERROR, "request at the switch");
                    check_value(Tx_Data, x"7F", ERROR, "heartbeat at the switch, not a stale boot-up message");
                    clocks(10);
                end loop;

            -- *** TC-NM-17: boot-up message aborted in the cycle of a bus switch ***
            elsif run("test_abort_and_switch") then
                Cfg_HbTime   <= std_logic_vector(to_unsigned(1000, 16));
                RespAbort    <= true;
                RespCpl      <= 3;
                doReset;
                wait until CplAbort = '1' for 2 us;
                check_value(CplAbort, '1', ERROR, "abort of the boot-up message");
                Red_Switched <= '1';
                wait until rising_edge(Clk);
                Red_Switched <= '0';
                RespAbort    <= false;
                wait until falling_edge(Clk);
                check_value(Tx_Valid, '1', ERROR, "request at the switch");
                check_value(Tx_Data, x"00", ERROR, "the boot-up message repeated at once");

            -- *** TC-NM-18: deferred boot-up message and a reset command in one cycle ***
            elsif run("test_bootdue_reset") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(2, 16));
                RespAbort  <= true;
                RespCpl    <= 3;
                doReset;
                waitFor(Ena_Sdo, '1', 50, "enables after the aborted boot-up message");
                RespAbort  <= false;
                RespCpl    <= 300;
                -- A heartbeat is taken; the switch defers the repeated boot-up message
                waitFor(Tx_Valid, '1', 5 * 16, "heartbeat");
                switched;
                C0_v := TxCnt;
                -- Reset communication in the cycle of the completion of the heartbeat
                wait until CplDone = '1' for 20 us;
                check_value(CplDone, '1', ERROR, "completion of the heartbeat");
                Rx_Valid <= '1';
                Rx_Cs    <= x"82";
                RespCpl  <= 3;
                wait until rising_edge(Clk);
                Rx_Valid <= '0';
                wait until falling_edge(Clk);
                check_value(Tx_Valid, '0', ERROR, "no boot-up request in the cycle of the reset command");
                waitFor(Reset_Comm, '1', 5, "reset communication");
                check_value(Tx_Valid, '0', ERROR, "no boot-up request before the sample");
                -- One boot-up message, then the heartbeats of Pre-operational
                waitTx(C0_v + 2, 5 * 16, "boot-up message and the next heartbeat");
                check_value(LogData(C0_v), x"00", ERROR, "boot-up message after the reset communication");
                check_value(LogData(C0_v + 1), x"7F", ERROR, "then a heartbeat, no second boot-up message");

            -- *** TC-NM-19: command and a due heartbeat in one cycle ***
            elsif run("test_command_and_heartbeat") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(1, 16));
                startNode;

                for K in 0 to 2 loop
                    wait until Tick_Ms = '1' for 1 us;
                    check_value(Tick_Ms, '1', ERROR, "tick");
                    Rx_Valid <= '1';
                    if K = 0 then
                        Rx_Cs <= x"01";
                    elsif K = 1 then
                        Rx_Cs <= x"02";
                    else
                        Rx_Cs <= x"80";
                    end if;
                    C0_v     := TxCnt;
                    wait until rising_edge(Clk);
                    Rx_Valid <= '0';
                    waitTx(C0_v + 1, 10, "heartbeat of the tick");
                    if K = 0 then
                        check_value(LogData(C0_v), x"05", ERROR, "state of the next cycle: Operational");
                    elsif K = 1 then
                        check_value(LogData(C0_v), x"04", ERROR, "state of the next cycle: Stopped");
                    else
                        check_value(LogData(C0_v), x"7F", ERROR, "state of the next cycle: Pre-operational");
                    end if;
                    clocks(4);
                end loop;

            -- *** TC-NM-20: completion time-out and reset communication during a wait ***
            elsif run("test_tx_timeout") then
                TickPer    <= 4;
                Cfg_HbTime <= std_logic_vector(to_unsigned(2, 16));
                startNode;
                -- A heartbeat without completion: time-out after 256 ticks, then the heartbeats go on. One cycle
                -- after the change of RespCpl, every later grant takes the long completion.
                RespCpl <= 3000;
                wait until rising_edge(Clk);
                C0_v    := TxCnt;
                waitTx(C0_v + 1, 20, "heartbeat taken");
                RespCpl <= 3;
                N_v     := Cyc;
                waitFor(Err_TxTimeout, '1', 256 * 4 + 20, "time-out of the heartbeat");
                check_value(Cyc - N_v >= 255 * 4 and Cyc - N_v <= 256 * 4 + 4, ERROR, "time-out after 256 ticks");
                waitFor(Tx_Valid, '1', 3 * 4 + 4, "next heartbeat requested after the time-out");
                waitTx(C0_v + 2, 3000, "next heartbeat taken after the old completion");
                -- A boot-up message without completion: time-out, the boot-up message again, enables still blocked;
                -- the bus recovers: the enables return
                wait until not RespBusy for 100 us;
                RespCpl <= 3000;
                C0_v    := TxCnt;
                doReset;
                waitTx(C0_v + 1, 20, "boot-up message taken");
                RespCpl <= 3;
                waitFor(Err_TxTimeout, '1', 256 * 4 + 20, "time-out of the boot-up message");
                wait until falling_edge(Clk);
                check_value(Tx_Valid, '1', ERROR, "boot-up message requested again");
                check_value(Tx_Data, x"00", ERROR, "boot-up message requested again");
                check_value(Ena_Sdo, '0', ERROR, "enables blocked until a boot-up message completes");
                waitFor(Ena_Sdo, '1', 3000, "enables after the completion of the repeated boot-up message");
                check_value(TxCnt, C0_v + 2, ERROR, "the boot-up message taken twice");
                -- Reset communication while a heartbeat is awaited: the boot-up request follows the sample at once
                wait until not RespBusy for 100 us;
                RespCpl <= 200;
                C0_v    := TxCnt;
                waitTx(C0_v + 1, 3 * 4 + 20, "heartbeat taken");
                RespCpl <= 3;
                nmt(130);
                waitFor(Tx_Valid, '1', 6, "boot-up request right after the reset communication");
                check_value(Tx_Data, x"00", ERROR, "boot-up request");
                check_value(RespBusy, true, ERROR, "requested while the heartbeat is still awaited");
                waitFor(Ena_Sdo, '1', 300, "enables after the boot-up message");

            -- *** TC-NM-13: minimal set ***
            elsif run("test_minimal_set") then
                check_value(MinimalSet_g, true, ERROR, "test_minimal_set runs in the configuration minimal");
                Cfg_HbTime <= std_logic_vector(to_unsigned(4, 16));
                C0_v       := TxCnt;
                doReset;
                waitState(NmtOp_c, 20, "Operational after the Initialisation");
                waitTx(C0_v + 1, 10, "heartbeat at once");
                check_value(LogData(C0_v), x"05", ERROR, "heartbeat 05h, no boot-up message");

                for Cs in 0 to 255 loop
                    nmt(Cs);
                    wait until falling_edge(Clk);
                    check_value(Err_Cs, '0', ERROR, "no Err_Cs in the minimal set");
                    check_value(Stat_State, NmtOp_c, ERROR, "NMT messages are not executed");
                end loop;

                preopReq;
                wait until falling_edge(Clk);
                check_value(Stat_State, NmtPreOp_c, ERROR, "Pre-operational at the request");
                wait until rising_edge(Clk);
                Red_Selecting <= '1';
                clocks(10);
                check_value(Stat_State, NmtPreOp_c, ERROR, "no change when the selection starts");
                Red_Selecting <= '0';
                wait until rising_edge(Clk);
                wait until falling_edge(Clk);
                check_value(Stat_State, NmtOp_c, ERROR, "Operational at the end of the bus selection");
                Red_Selecting <= '1';
                clocks(4);
                Red_Selecting <= '0';
                clocks(4);
                check_value(Stat_State, NmtOp_c, ERROR, "no change of Red_Selecting in Operational");
                -- Every command specifier in Pre-operational and in the Initialisation
                Cfg_HbTime <= std_logic_vector(to_unsigned(1000, 16));
                preopReq;

                for Cs in 0 to 255 loop
                    nmt(Cs);
                    wait until falling_edge(Clk);
                    check_value(Err_Cs, '0', ERROR, "no Err_Cs in Pre-operational");
                    check_value(Stat_State, NmtPreOp_c, ERROR, "no change in Pre-operational");
                end loop;

                setPins(0, "1111111");
                doReset;
                clocks(10);

                for Cs in 0 to 255 loop
                    nmt(Cs);
                    check_value(Stat_State, NmtInit_c, ERROR, "no change in the Initialisation");
                end loop;

                setPins(NodeId_c, not slv7(NodeId_c));
                doReset;
                waitState(NmtOp_c, 20, "Operational after the reset");
                clocks(10);
                -- An upset: reset communication, then Operational with a heartbeat at once and no boot-up message
                C0_v           := TxCnt;
                ErrInj_BitFlip <= (8 => '1', others => '0');
                ErrInj_Valid   <= '1';
                wait until rising_edge(Clk);
                ErrInj_Valid   <= '0';
                waitFor(Reset_Comm, '1', 5, "reset communication after the upset");
                waitState(NmtOp_c, 10, "Operational after the new sample");
                waitTx(C0_v + 1, 10, "heartbeat at once");
                check_value(LogData(C0_v), x"05", ERROR, "heartbeat 05h, no boot-up message");
                -- A bus switch: a heartbeat at once
                clocks(10);
                C0_v := TxCnt;
                switched;
                clocks(3);
                check_value(TxCnt, C0_v + 1, ERROR, "heartbeat at once after a switch");
                check_value(LogData(C0_v), x"05", ERROR, "heartbeat 05h after a switch");

            end if;

            clocks(10);

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
