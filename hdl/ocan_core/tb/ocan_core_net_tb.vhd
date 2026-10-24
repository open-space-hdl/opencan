---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_core: the whole node on the CAN network model. The model node M1 of the active bus is
-- the Redundancy Master and NMT master, the SYNC and time producer, the SDO client and the peer of the PDOs; M2 of
-- each bus acknowledges and sends disturbing frames. Models of the user logic at the PDO port and of the application
-- objects at the application port. Checkers in every test: no frame of the node on its inactive bus, every frame of
-- the node a data frame with an 11-bit identifier, no frame of the node while its NODE-ID is not valid.
--
-- Documentation: hdl/ocan_core/docs/verification_plan.md

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
    use work.ocan_pkg.all;
    use work.ocan_tb_pkg.all;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_core_net_tb is
    generic (
        runner_cfg   : string;
        BusAccess_g  : string               := "Selective";
        MinimalSet_g : boolean              := false;
        TimePdos_g   : boolean              := true;
        NumRpdo_g    : natural range 0 to 4 := 4;
        NumTpdo_g    : natural range 0 to 4 := 4;
        Bdefault_g   : natural range 0 to 1 := 0
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_core_net_tb is

    subtype Data_t is std_logic_vector(63 downto 0);
    subtype Scet_t is unsigned(55 downto 0);

    type Data_a is array (0 to 3) of Data_t;

    type Nat_a is array (0 to 3) of natural;

    constant Parallel_c  : boolean := BusAccess_g = "Parallel";
    constant TimeBlock_c : boolean := TimePdos_g or not MinimalSet_g;

    constant NodeId_c   : natural := 5;
    constant HbId_c     : natural := 16#705#;
    constant MasterId_c : natural := 16#701#;
    constant SdoReqId_c : natural := 16#605#;
    constant SdoRspId_c : natural := 16#585#;
    constant SyncId_c   : natural := 16#080#;
    constant SctId_c    : natural := 16#0F0#;
    constant LtpId_c    : natural := 16#1F5#;
    constant RpdoId_c   : Nat_a   := (16#205#, 16#305#, 16#405#, 16#505#);
    constant TpdoId_c   : Nat_a   := (16#185#, 16#285#, 16#385#, 16#485#);

    -- NMT command specifiers ([CiA301] 7.2.8.3.1) and heartbeat states (7.2.8.3.2)
    constant Start_c     : natural := 16#01#;
    constant Stop_c      : natural := 16#02#;
    constant EnterPo_c   : natural := 16#80#;
    constant ResetNode_c : natural := 16#81#;
    constant ResetComm_c : natural := 16#82#;
    constant HbPreop_c   : natural := 16#7F#;
    constant HbOp_c      : natural := 16#05#;
    constant HbStop_c    : natural := 16#04#;

    -- Period of the master heartbeat; the consumer heartbeat time of the node is 10 ms
    constant MasterPeriod_c : time := 4 ms;

    -- Data that depend on every bit of a and b (xorshift)
    function mix (a : natural; b : natural) return Data_t is
        variable X_v : unsigned(63 downto 0);
    begin
        X_v := to_unsigned(a mod 2 ** 30, 32) & to_unsigned((b * 40503 + 12345) mod 2 ** 30, 32);

        for I in 1 to 3 loop
            X_v := X_v xor shift_left(X_v, 13);
            X_v := X_v xor shift_right(X_v, 7);
            X_v := X_v xor shift_left(X_v, 17);
        end loop;

        return std_logic_vector(X_v);
    end function;

    function pdo (v : std_logic_vector(255 downto 0); n : natural) return Data_t is
    begin
        return v(64 * n + 63 downto 64 * n);
    end function;

    function u8 (n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 8));
    end function;

    -- SCET of a time PDO: bytes 0 to 2 the fine time, 3 to 6 the coarse time, least significant byte first
    function scetOf (d : Data_t) return Scet_t is
    begin
        return unsigned(std_logic_vector'(d(15 downto 8) & d(23 downto 16) & d(31 downto 24) & d(39 downto 32) &
                                          d(47 downto 40) & d(55 downto 48) & d(63 downto 56)));
    end function;

    function frameOf (s : Scet_t) return Data_t is
        variable V_v : std_logic_vector(55 downto 0);
    begin
        V_v := std_logic_vector(s);
        return V_v(7 downto 0) & V_v(15 downto 8) & V_v(23 downto 16) & V_v(31 downto 24) & V_v(39 downto 32) &
               V_v(47 downto 40) & V_v(55 downto 48) & x"00";
    end function;

    -- Fine time units (2^-24 s) of a duration
    function fineOf (d : time) return natural is
    begin
        return natural(real(d / 1 ns) * 0.016777216);
    end function;

    signal Clk                   : std_logic;
    signal Rst                   : std_logic                      := '1';
    signal Ctrl_Enable           : std_logic                      := '1';
    signal Ctrl_Recover          : std_logic                      := '0';
    signal Ctrl_Reenable         : std_logic_vector(1 downto 0)   := (others => '0');
    signal Cfg_Prescaler         : std_logic_vector(9 downto 0)   := std_logic_vector(to_unsigned(2, 10));
    signal Cfg_Tseg1             : std_logic_vector(4 downto 0)   := std_logic_vector(to_unsigned(15, 5));
    signal Cfg_Tseg2             : std_logic_vector(3 downto 0)   := std_logic_vector(to_unsigned(4, 4));
    signal Cfg_Sjw               : std_logic_vector(2 downto 0)   := std_logic_vector(to_unsigned(4, 3));
    signal Pin_NodeId            : std_logic_vector(6 downto 0)   := std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Pin_NodeIdCode        : std_logic_vector(6 downto 0)   := not std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Node_Id               : std_logic_vector(6 downto 0);
    signal Node_IdValid          : std_logic;
    signal Sync_Valid            : std_logic;
    signal Rpdo_Valid            : std_logic_vector(3 downto 0);
    signal Rpdo_Data             : std_logic_vector(255 downto 0);
    signal Tpdo_Req              : std_logic_vector(3 downto 0)   := (others => '0');
    signal Tpdo_Data             : std_logic_vector(255 downto 0) := (others => '0');
    signal Stat_TpdoBusy         : std_logic_vector(3 downto 0);
    signal Stat_PdoEnabled       : std_logic;
    signal Evt_TpdoSent          : std_logic_vector(3 downto 0);
    signal Evt_TpdoAborted       : std_logic_vector(3 downto 0);
    signal Err_RpdoLength        : std_logic_vector(3 downto 0);
    signal Err_TpdoBusy          : std_logic_vector(3 downto 0);
    signal Err_TpdoTimeout       : std_logic_vector(3 downto 0);
    signal App_ReqValid          : std_logic;
    signal App_ReqReady          : std_logic                      := '1';
    signal App_ReqWrite          : std_logic;
    signal App_ReqIndex          : std_logic_vector(15 downto 0);
    signal App_ReqSub            : std_logic_vector(7 downto 0);
    signal App_ReqData           : std_logic_vector(63 downto 0);
    signal App_ReqLen            : std_logic_vector(3 downto 0);
    signal App_RspValid          : std_logic                      := '0';
    signal App_RspData           : std_logic_vector(63 downto 0)  := (others => '0');
    signal App_RspLen            : std_logic_vector(3 downto 0)   := (others => '0');
    signal App_RspAbort          : std_logic_vector(31 downto 0)  := (others => '0');
    signal Time_Coarse           : std_logic_vector(31 downto 0);
    signal Time_Fine             : std_logic_vector(23 downto 0);
    signal Time_Req              : std_logic                      := '0';
    signal Stat_TimeSet          : std_logic;
    signal Evt_TimeSet           : std_logic;
    signal Evt_TimeSync          : std_logic;
    signal Err_TimeTxBusy        : std_logic;
    signal Err_TimeRxDrop        : std_logic;
    signal Err_TimeTxTimeout     : std_logic;
    signal Stat_NmtState         : std_logic_vector(1 downto 0);
    signal Evt_ResetApp          : std_logic;
    signal Evt_ResetComm         : std_logic;
    signal Err_NmtCs             : std_logic;
    signal Err_NodeId            : std_logic;
    signal Err_NmtTxTimeout      : std_logic;
    signal Stat_ActiveBus        : std_logic;
    signal Stat_Selecting        : std_logic;
    signal Stat_Ctoggle          : std_logic_vector(7 downto 0);
    signal Stat_MasterHbState    : std_logic_vector(7 downto 0);
    signal Stat_MasterHbPresent  : std_logic_vector(1 downto 0);
    signal Evt_BdefaultUpdate    : std_logic;
    signal Err_MasterHbMissing   : std_logic;
    signal Err_ToggleEnd         : std_logic;
    signal Err_MasterHbDlc       : std_logic;
    signal Stat_ErrReg           : std_logic_vector(7 downto 0);
    signal Err_ParamCopy         : std_logic;
    signal Err_AppTimeout        : std_logic;
    signal Stat_CobIdMismatch    : std_logic_vector(11 downto 0);
    signal Err_Protocol          : std_logic;
    signal Err_CobId             : std_logic;
    signal Stat_SdoOpen          : std_logic;
    signal Evt_SdoAbortTx        : std_logic;
    signal Evt_SdoAbortRx        : std_logic;
    signal Err_SdoRxDrop         : std_logic;
    signal Err_SdoTxTimeout      : std_logic;
    signal Err_SdoAccTimeout     : std_logic;
    signal Stat_LinkTec          : std_logic_vector(17 downto 0);
    signal Stat_LinkRec          : std_logic_vector(15 downto 0);
    signal Stat_LinkState        : std_logic_vector(3 downto 0);
    signal Stat_LinkBusIdle      : std_logic_vector(1 downto 0);
    signal Stat_LinkDomTimeout   : std_logic_vector(1 downto 0);
    signal Stat_LinkSwitching    : std_logic;
    signal Evt_LinkArbLost       : std_logic;
    signal Err_LinkBit           : std_logic_vector(1 downto 0);
    signal Err_LinkStuff         : std_logic_vector(1 downto 0);
    signal Err_LinkCrc           : std_logic_vector(1 downto 0);
    signal Err_LinkForm          : std_logic_vector(1 downto 0);
    signal Err_LinkAck           : std_logic_vector(1 downto 0);
    signal Err_LinkDomTimeout    : std_logic_vector(1 downto 0);
    signal ErrInj_OdBitFlip      : std_logic_vector(557 downto 0) := (others => '0');
    signal ErrInj_OdValid        : std_logic                      := '0';
    signal ErrInj_NmtBitFlip     : std_logic_vector(13 downto 0)  := (others => '0');
    signal ErrInj_NmtValid       : std_logic                      := '0';
    signal ErrInj_LinkTxDominant : std_logic_vector(1 downto 0)   := (others => '0');
    signal ErrInj_LinkStopFlip   : std_logic_vector(1 downto 0)   := (others => '0');
    signal Bus_ForceDom          : std_logic_vector(1 downto 0)   := (others => '0');
    signal Bus_ForceRec          : std_logic_vector(1 downto 0)   := (others => '0');
    signal Bus_DutRec            : std_logic_vector(1 downto 0)   := (others => '0');
    signal Bus_Level             : std_logic_vector(1 downto 0);

    -- *** Master model ***
    signal MasterOn  : boolean := true;
    signal MasterBus : natural := Bdefault_g;
    signal MasterDlc : natural := 1;

    -- *** User logic model ***
    signal UserData : Data_a                       := (others => (others => '0'));
    signal TestReq  : std_logic_vector(3 downto 0) := (others => '0');

    -- *** Application object model (2100h to 2203h, sub-indices 01h to 08h) ***
    signal AppDelay : natural                       := 0;                      -- cycles until the response
    signal AppAbort : std_logic_vector(31 downto 0) := (others => '0'); -- abort code of the next response
    signal AppCount : natural                       := 0;                      -- requests taken

    -- *** Monitors ***
    signal SwitchT   : time                      := 0 ns;                   -- time of the last change of the active bus
    signal SyncEvtT  : time                      := 0 ns;                   -- time of the last SYNC event of the time block
    signal RxCnt     : Nat_a                     := (others => 0);
    signal SentCnt   : Nat_a                     := (others => 0);
    signal ResetCnt  : natural                   := 0;                      -- reset communication events
    signal AppRstCnt : natural                   := 0;                      -- reset application events
    signal UpdCnt    : natural                   := 0;
    signal NetErrors : natural                   := 0;
    signal Seen      : std_logic_vector(0 to 51) := (others => '0');

begin

    test_runner_watchdog(runner, 600 ms);

    i_th : entity work.ocan_core_net_th
        generic map (
            BusAccess_g  => BusAccess_g,
            MinimalSet_g => MinimalSet_g,
            TimePdos_g   => TimePdos_g,
            NumRpdo_g    => NumRpdo_g,
            NumTpdo_g    => NumTpdo_g,
            Bdefault_g   => Bdefault_g
        )
        port map (
            Clk                   => Clk,
            Rst                   => Rst,
            Ctrl_Enable           => Ctrl_Enable,
            Ctrl_Recover          => Ctrl_Recover,
            Ctrl_Reenable         => Ctrl_Reenable,
            Cfg_Prescaler         => Cfg_Prescaler,
            Cfg_Tseg1             => Cfg_Tseg1,
            Cfg_Tseg2             => Cfg_Tseg2,
            Cfg_Sjw               => Cfg_Sjw,
            Pin_NodeId            => Pin_NodeId,
            Pin_NodeIdCode        => Pin_NodeIdCode,
            Node_Id               => Node_Id,
            Node_IdValid          => Node_IdValid,
            Sync_Valid            => Sync_Valid,
            Rpdo_Valid            => Rpdo_Valid,
            Rpdo_Data             => Rpdo_Data,
            Tpdo_Req              => Tpdo_Req,
            Tpdo_Data             => Tpdo_Data,
            Stat_TpdoBusy         => Stat_TpdoBusy,
            Stat_PdoEnabled       => Stat_PdoEnabled,
            Evt_TpdoSent          => Evt_TpdoSent,
            Evt_TpdoAborted       => Evt_TpdoAborted,
            Err_RpdoLength        => Err_RpdoLength,
            Err_TpdoBusy          => Err_TpdoBusy,
            Err_TpdoTimeout       => Err_TpdoTimeout,
            App_ReqValid          => App_ReqValid,
            App_ReqReady          => App_ReqReady,
            App_ReqWrite          => App_ReqWrite,
            App_ReqIndex          => App_ReqIndex,
            App_ReqSub            => App_ReqSub,
            App_ReqData           => App_ReqData,
            App_ReqLen            => App_ReqLen,
            App_RspValid          => App_RspValid,
            App_RspData           => App_RspData,
            App_RspLen            => App_RspLen,
            App_RspAbort          => App_RspAbort,
            Time_Coarse           => Time_Coarse,
            Time_Fine             => Time_Fine,
            Time_Req              => Time_Req,
            Stat_TimeSet          => Stat_TimeSet,
            Evt_TimeSet           => Evt_TimeSet,
            Evt_TimeSync          => Evt_TimeSync,
            Err_TimeTxBusy        => Err_TimeTxBusy,
            Err_TimeRxDrop        => Err_TimeRxDrop,
            Err_TimeTxTimeout     => Err_TimeTxTimeout,
            Stat_NmtState         => Stat_NmtState,
            Evt_ResetApp          => Evt_ResetApp,
            Evt_ResetComm         => Evt_ResetComm,
            Err_NmtCs             => Err_NmtCs,
            Err_NodeId            => Err_NodeId,
            Err_NmtTxTimeout      => Err_NmtTxTimeout,
            Stat_ActiveBus        => Stat_ActiveBus,
            Stat_Selecting        => Stat_Selecting,
            Stat_Ctoggle          => Stat_Ctoggle,
            Stat_MasterHbState    => Stat_MasterHbState,
            Stat_MasterHbPresent  => Stat_MasterHbPresent,
            Evt_BdefaultUpdate    => Evt_BdefaultUpdate,
            Err_MasterHbMissing   => Err_MasterHbMissing,
            Err_ToggleEnd         => Err_ToggleEnd,
            Err_MasterHbDlc       => Err_MasterHbDlc,
            Stat_ErrReg           => Stat_ErrReg,
            Err_ParamCopy         => Err_ParamCopy,
            Err_AppTimeout        => Err_AppTimeout,
            Stat_CobIdMismatch    => Stat_CobIdMismatch,
            Err_Protocol          => Err_Protocol,
            Err_CobId             => Err_CobId,
            Stat_SdoOpen          => Stat_SdoOpen,
            Evt_SdoAbortTx        => Evt_SdoAbortTx,
            Evt_SdoAbortRx        => Evt_SdoAbortRx,
            Err_SdoRxDrop         => Err_SdoRxDrop,
            Err_SdoTxTimeout      => Err_SdoTxTimeout,
            Err_SdoAccTimeout     => Err_SdoAccTimeout,
            Stat_LinkTec          => Stat_LinkTec,
            Stat_LinkRec          => Stat_LinkRec,
            Stat_LinkState        => Stat_LinkState,
            Stat_LinkBusIdle      => Stat_LinkBusIdle,
            Stat_LinkDomTimeout   => Stat_LinkDomTimeout,
            Stat_LinkSwitching    => Stat_LinkSwitching,
            Evt_LinkArbLost       => Evt_LinkArbLost,
            Err_LinkBit           => Err_LinkBit,
            Err_LinkStuff         => Err_LinkStuff,
            Err_LinkCrc           => Err_LinkCrc,
            Err_LinkForm          => Err_LinkForm,
            Err_LinkAck           => Err_LinkAck,
            Err_LinkDomTimeout    => Err_LinkDomTimeout,
            ErrInj_OdBitFlip      => ErrInj_OdBitFlip,
            ErrInj_OdValid        => ErrInj_OdValid,
            ErrInj_NmtBitFlip     => ErrInj_NmtBitFlip,
            ErrInj_NmtValid       => ErrInj_NmtValid,
            ErrInj_LinkTxDominant => ErrInj_LinkTxDominant,
            ErrInj_LinkStopFlip   => ErrInj_LinkStopFlip,
            Bus_ForceDom          => Bus_ForceDom,
            Bus_ForceRec          => Bus_ForceRec,
            Bus_DutRec            => Bus_DutRec,
            Bus_Level             => Bus_Level
        );

    -----------------------------------------------------------------------------------------------
    -- Master heartbeat of M1 on the master bus
    -----------------------------------------------------------------------------------------------
    p_master : process is
    begin
        wait for MasterPeriod_c;
        if MasterOn and Net_v.txCount(2 * MasterBus) < 2 then
            Net_v.txPush(2 * MasterBus, canStd(MasterId_c, MasterDlc, x"0500000000000000"));
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- User logic: the data of the transmit PDOs and the requests of the test
    -----------------------------------------------------------------------------------------------
    p_user : process (Clk) is
    begin
        if rising_edge(Clk) then
            Tpdo_Req <= TestReq;

            for N in 0 to 3 loop
                Tpdo_Data(64 * N + 63 downto 64 * N) <= UserData(N);
            end loop;

        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Application objects 2100h to 2203h: a write stores the value, a read returns it; the response after AppDelay
    -- cycles, with AppAbort when it is not 0
    -----------------------------------------------------------------------------------------------
    p_app : process (Clk) is
        type Mem_t is array (0 to 63) of std_logic_vector(63 downto 0);

        variable Mem_v  : Mem_t   := (others => (others => '0'));
        variable Left_v : integer := -1;
        variable A_v    : natural;
        variable Wr_v   : boolean;
        variable D_v    : std_logic_vector(63 downto 0);
    begin
        if rising_edge(Clk) then
            App_RspValid <= '0';
            if Left_v > 0 then
                Left_v := Left_v - 1;
            elsif Left_v = 0 then
                App_RspValid <= '1';
                App_RspAbort <= AppAbort;
                App_RspLen   <= x"1";
                if Wr_v then
                    Mem_v(A_v)  := D_v;
                    App_RspData <= (others => '0');
                else
                    App_RspData <= Mem_v(A_v);
                end if;
                Left_v := -1;
            end if;
            if App_ReqValid = '1' and App_ReqReady = '1' then
                AppCount <= AppCount + 1;
                A_v      := (to_integer(unsigned(App_ReqIndex(8 downto 8))) * 4 +
                             to_integer(unsigned(App_ReqIndex(1 downto 0)))) * 8 +
                            to_integer(unsigned(App_ReqSub(2 downto 0)));
                Wr_v     := App_ReqWrite = '1';
                D_v      := App_ReqData;
                Left_v   := AppDelay;
            end if;
            if Left_v >= 0 then
                App_ReqReady <= '0';
            else
                App_ReqReady <= '1';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors of the ports
    -----------------------------------------------------------------------------------------------
    p_mon : process (Clk) is
        variable Bus_v : std_logic := '0';
    begin
        if rising_edge(Clk) then
            if Stat_ActiveBus /= Bus_v then
                SwitchT <= now;
            end if;
            Bus_v := Stat_ActiveBus;
            if Evt_TimeSync = '1' then
                SyncEvtT <= now;
            end if;

            for N in 0 to 3 loop
                if Rpdo_Valid(N) = '1' then
                    RxCnt(N) <= RxCnt(N) + 1;
                end if;
                if Evt_TpdoSent(N) = '1' then
                    SentCnt(N) <= SentCnt(N) + 1;
                end if;
            end loop;

            if Evt_ResetComm = '1' then
                ResetCnt <= ResetCnt + 1;
            end if;
            if Evt_ResetApp = '1' then
                AppRstCnt <= AppRstCnt + 1;
            end if;
            if Evt_BdefaultUpdate = '1' then
                UpdCnt <= UpdCnt + 1;
            end if;
        end if;
    end process;

    -- Every port group active at least once (TC-CO-09)
    p_seen : process (Clk) is
        variable S_v : std_logic_vector(0 to 51);
    begin
        if rising_edge(Clk) and Rst = '0' then
            S_v     := Seen;
            S_v(0)  := S_v(0) or Sync_Valid;
            S_v(1)  := S_v(1) or (or Rpdo_Valid);
            S_v(2)  := S_v(2) or (or Stat_TpdoBusy);
            S_v(3)  := S_v(3) or Stat_PdoEnabled;
            S_v(4)  := S_v(4) or (or Evt_TpdoSent);
            S_v(5)  := S_v(5) or (or Evt_TpdoAborted);
            S_v(6)  := S_v(6) or (or Err_RpdoLength);
            S_v(7)  := S_v(7) or (or Err_TpdoBusy);
            S_v(8)  := S_v(8) or App_ReqValid;
            S_v(9)  := S_v(9) or (or Time_Coarse) or (or Time_Fine);
            S_v(10) := S_v(10) or Stat_TimeSet;
            S_v(11) := S_v(11) or Evt_TimeSet;
            S_v(12) := S_v(12) or Evt_TimeSync;
            S_v(13) := S_v(13) or Err_TimeTxBusy;
            S_v(14) := S_v(14) or Err_TimeRxDrop;
            S_v(15) := S_v(15) or Evt_ResetApp;
            S_v(16) := S_v(16) or Evt_ResetComm;
            S_v(17) := S_v(17) or Err_NmtCs;
            S_v(18) := S_v(18) or Err_NodeId;
            S_v(19) := S_v(19) or Stat_ActiveBus;
            S_v(20) := S_v(20) or Stat_Selecting;
            S_v(21) := S_v(21) or (or Stat_Ctoggle);
            if Stat_MasterHbState = x"05" then
                S_v(22) := '1';
            end if;
            S_v(23) := S_v(23) or (or Stat_MasterHbPresent);
            S_v(24) := S_v(24) or Evt_BdefaultUpdate;
            S_v(25) := S_v(25) or Err_MasterHbMissing;
            S_v(26) := S_v(26) or Err_ToggleEnd;
            S_v(27) := S_v(27) or Err_MasterHbDlc;
            S_v(28) := S_v(28) or Stat_ErrReg(4);
            S_v(29) := S_v(29) or Err_ParamCopy;
            S_v(30) := S_v(30) or (or Stat_CobIdMismatch);
            S_v(31) := S_v(31) or Err_Protocol;
            S_v(32) := S_v(32) or Err_CobId;
            S_v(33) := S_v(33) or Stat_SdoOpen;
            S_v(34) := S_v(34) or Evt_SdoAbortTx;
            S_v(35) := S_v(35) or Evt_SdoAbortRx;
            S_v(36) := S_v(36) or Err_SdoRxDrop;
            S_v(37) := S_v(37) or (or Stat_LinkTec);
            S_v(38) := S_v(38) or (or Stat_LinkRec);
            S_v(39) := S_v(39) or Stat_LinkState(0) or Stat_LinkState(2);
            S_v(40) := S_v(40) or not Stat_LinkBusIdle(0);
            S_v(41) := S_v(41) or (or Stat_LinkDomTimeout);
            S_v(42) := S_v(42) or Stat_LinkSwitching;
            S_v(43) := S_v(43) or Evt_LinkArbLost;
            S_v(44) := S_v(44) or (or Err_LinkBit);
            S_v(45) := S_v(45) or (or Err_LinkStuff);
            S_v(46) := S_v(46) or Err_LinkCrc(0);
            S_v(47) := S_v(47) or (or Err_LinkForm);
            S_v(48) := S_v(48) or (or Err_LinkAck);
            S_v(49) := S_v(49) or (or Err_LinkDomTimeout);
            S_v(50) := S_v(50) or Err_LinkCrc(1);
            S_v(51) := S_v(51) or Node_IdValid;
            Seen    <= S_v;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Checkers in every test: the frames of the node in the logs of M1 of both buses
    -----------------------------------------------------------------------------------------------
    p_frames : process is
        variable Done_v : Nat_a := (others => 0);
        variable E_v    : TbLog_t;
        variable Id_v   : natural;
        variable Dut_v  : boolean;
    begin
        wait for 20 us;

        for B in 0 to 1 loop

            for I in Done_v(B) to Net_v.logCount(2 * B) - 1 loop
                E_v  := Net_v.logGet(2 * B, I);
                Id_v := to_integer(unsigned(E_v.Frame.Id(28 downto 18)));
                -- The node sends 705h, 585h, the time PDO 1F5h and the transmit PDOs (181h to 4FFh); the model nodes
                -- send no frame with these identifiers except M1, whose own frames are marked
                Dut_v := E_v.Kind = TbFrame and not E_v.Own and
                         (Id_v = HbId_c or Id_v = SdoRspId_c or Id_v = LtpId_c or (Id_v >= 16#181# and Id_v <= 16#4FF#));
                if Dut_v then
                    if E_v.Frame.Ide /= '0' or E_v.Frame.Rtr /= '0' then
                        alert(ERROR, "frame of the node that is not a data frame with an 11-bit identifier");
                    end if;
                    if (Stat_ActiveBus = '1') /= (B = 1) and now - SwitchT > 500 us then
                        alert(ERROR, "frame of the node on its inactive bus " & integer'image(B) & ": " &
                              canImage(E_v.Frame));
                    end if;
                    if Node_IdValid /= '1' then
                        alert(ERROR, "frame of the node while its NODE-ID is not valid");
                    end if;
                end if;
            end loop;

            Done_v(B) := Net_v.logCount(2 * B);
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable M1_v  : natural := 2 * Bdefault_g; -- M1 of the active bus
        variable B_v   : natural := Bdefault_g;     -- active bus
        variable T_v   : time;
        variable T2_v  : time;
        variable D_v   : Data_t;
        variable R_v   : Data_t;
        variable N_v   : natural;
        variable I_v   : integer;
        variable Ok_v  : boolean;
        variable S_v   : Scet_t;
        variable X_v   : Scet_t;
        variable Cfg_v : TbNodeCfg_t;
        variable C_v   : natural;
        variable E_v   : TbLog_t;
        variable Ab_v  : std_logic_vector(31 downto 0);

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- Frames of the node with identifier id in the log of model node n after time t
        impure function countFrames (n : natural; id : natural; t : time) return natural is
            variable E_v : TbLog_t;
            variable C_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    C_v := C_v + 1;
                end if;
            end loop;

            return C_v;
        end function;

        -- Log index of the first frame of identifier id in the log of model node n after time t; -1: none
        impure function firstFrame (n : natural; id : natural; t : time) return integer is
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    return I;
                end if;
            end loop;

            return -1;
        end function;

        -- Errors that model node n logged after time t, of kind k
        impure function countErrors (n : natural; k : TbErrKind_t; t : time) return natural is
            variable E_v : TbLog_t;
            variable C_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbError and E_v.Err = k and E_v.T > t then
                    C_v := C_v + 1;
                end if;
            end loop;

            return C_v;
        end function;

        -- Waits up to tmo for a frame of identifier id after time t in the log of M1; the index or -1
        procedure waitFrame (id : natural; t : time; tmo : time; idx : out integer) is
            variable W_v : time := 0 ns;
        begin
            idx := firstFrame(M1_v, id, t);

            while idx < 0 and W_v < tmo loop
                wait for 20 us;
                W_v := W_v + 20 us;
                idx := firstFrame(M1_v, id, t);
            end loop;

        end procedure;

        procedure expectFrame (id : natural; t : time; tmo : time; msg : string) is
            variable I_v : integer;
        begin
            waitFrame(id, t, tmo, I_v);
            check_value(I_v >= 0, ERROR, msg);
        end procedure;

        procedure waitSig (signal s : std_logic; v : std_logic; tmo : time; msg : string) is
        begin
            if s /= v then
                wait until s = v for tmo;
            end if;
            check_value(s, v, ERROR, msg);
        end procedure;

        procedure waitState (s : std_logic_vector(1 downto 0); tmo : time; msg : string) is
        begin
            if Stat_NmtState /= s then
                wait until Stat_NmtState = s for tmo;
            end if;
            check_value(Stat_NmtState, s, ERROR, msg);
        end procedure;

        -- Frames of M1 of the active bus
        procedure send (id : natural; dlc : natural; d : Data_t := (others => '0'); rtr : std_logic := '0') is
        begin
            Net_v.txPush(M1_v, canStd(id, dlc, d, rtr));
        end procedure;

        procedure nmt (cs : natural; dlc : natural := 2) is
        begin
            send(0, dlc, u8(cs) & u8(NodeId_c) & x"000000000000");
        end procedure;

        procedure sync is
        begin
            T_v := now;
            send(SyncId_c, 0);
            wait until Sync_Valid = '1' for 2 ms;
            check_value(Sync_Valid, '1', ERROR, "Sync_Valid after a SYNC of M1");
        end procedure;

        procedure request (n : natural) is
        begin
            wait until rising_edge(Clk);
            TestReq(n) <= '1';
            wait until rising_edge(Clk);
            TestReq(n) <= '0';
        end procedure;

        -- An SDO request of M1 and its reply (DLC 8); ok false without a reply within 5 ms
        procedure sdoXfer (req : Data_t; rsp : out Data_t; ok : out boolean; dlc : natural := 8) is
            variable T0_v : time;
            variable I_v  : integer;
            variable E_v  : TbLog_t;
        begin
            T0_v := now;
            send(SdoReqId_c, dlc, req);
            waitFrame(SdoRspId_c, T0_v, 5 ms, I_v);
            ok   := I_v >= 0;
            rsp  := (others => '0');
            if I_v >= 0 then
                E_v := Net_v.logGet(M1_v, I_v);
                rsp := E_v.Frame.Data;
            end if;
        end procedure;

        function muxOf (cmd : natural; idx : natural; sub : natural) return std_logic_vector is
            variable I_v : std_logic_vector(15 downto 0);
        begin
            I_v := std_logic_vector(to_unsigned(idx, 16));
            return u8(cmd) & I_v(7 downto 0) & I_v(15 downto 8) & u8(sub);
        end function;

        -- Value of 1 to 7 bytes, least significant byte first in the frame
        function lsbFirst (v : std_logic_vector(63 downto 0); n : natural) return std_logic_vector is
            variable R_v : std_logic_vector(55 downto 0) := (others => '0');
        begin

            for K in 0 to 6 loop
                if K < n then
                    R_v(55 - 8 * K downto 48 - 8 * K) := v(8 * K + 7 downto 8 * K);
                end if;
            end loop;

            return R_v;
        end function;

        function valueOf (f : std_logic_vector; n : natural) return std_logic_vector is
            variable F_v : std_logic_vector(f'length - 1 downto 0) := f;
            variable V_v : std_logic_vector(63 downto 0)           := (others => '0');
        begin

            for K in 0 to 6 loop
                if K < n then
                    V_v(8 * K + 7 downto 8 * K) := F_v(f'length - 1 - 8 * K downto f'length - 8 - 8 * K);
                end if;
            end loop;

            return V_v;
        end function;

        -- SDO download of n bytes (expedited up to 4, segmented up to 7); the abort code of the reply, 0: success
        procedure sdoWrite (
            idx  : natural;
            sub  : natural;
            v    : std_logic_vector(63 downto 0);
            n    : natural;
            code : out std_logic_vector(31 downto 0);
            msg  : string) is
            variable R_v  : Data_t;
            variable Ok_v : boolean;
        begin
            code := (others => '0');
            if n <= 4 then
                sdoXfer(muxOf(16#23# + 4 * (4 - n), idx, sub) & lsbFirst(v, 4)(55 downto 24), R_v, Ok_v);
            else
                sdoXfer(muxOf(16#21#, idx, sub) & u8(n) & x"000000", R_v, Ok_v);
                if Ok_v and R_v(63 downto 56) = x"60" then
                    sdoXfer(u8(16#01# + 2 * (7 - n)) & lsbFirst(v, 7), R_v, Ok_v);
                    if Ok_v and R_v(63 downto 56) = x"20" then
                        R_v(63 downto 56) := x"60";
                    end if;
                end if;
            end if;
            check_value(Ok_v, ERROR, msg & ": SDO reply");
            if R_v(63 downto 56) = x"80" then
                code := R_v(7 downto 0) & R_v(15 downto 8) & R_v(23 downto 16) & R_v(31 downto 24);
            else
                check_value(R_v(63 downto 56), x"60", ERROR, msg & ": download response");
            end if;
        end procedure;

        procedure sdoWriteVec (
            idx : natural;
            sub : natural;
            v   : std_logic_vector(63 downto 0);
            n   : natural;
            msg : string) is
            variable C_v : std_logic_vector(31 downto 0);
        begin
            sdoWrite(idx, sub, v, n, C_v, msg);
            check_value(C_v, x"00000000", ERROR, msg & ": no abort");
        end procedure;

        procedure sdoWriteOk (idx : natural; sub : natural; v : natural; n : natural; msg : string) is
            variable C_v : std_logic_vector(31 downto 0);
        begin
            sdoWrite(idx, sub, std_logic_vector(to_unsigned(v, 64)), n, C_v, msg);
            check_value(C_v, x"00000000", ERROR, msg & ": no abort");
        end procedure;

        -- SDO upload (expedited or segmented up to 7 bytes); the value and its number of bytes, the abort code
        procedure sdoRead (
            idx  : natural;
            sub  : natural;
            v    : out std_logic_vector(63 downto 0);
            n    : out natural;
            code : out std_logic_vector(31 downto 0);
            msg  : string) is
            variable R_v  : Data_t;
            variable Ok_v : boolean;
            variable C_v  : natural;
        begin
            v    := (others => '0');
            n    := 0;
            code := (others => '0');
            sdoXfer(muxOf(16#40#, idx, sub) & x"00000000", R_v, Ok_v);
            check_value(Ok_v, ERROR, msg & ": SDO reply");
            C_v  := to_integer(unsigned(R_v(63 downto 56)));
            if C_v = 16#80# then
                code := R_v(7 downto 0) & R_v(15 downto 8) & R_v(23 downto 16) & R_v(31 downto 24);
            elsif C_v = 16#41# then
                n := to_integer(unsigned(R_v(31 downto 24)));
                sdoXfer(x"60" & x"00000000000000", R_v, Ok_v);
                check_value(Ok_v and R_v(56) = '1', ERROR, msg & ": last upload segment");
                v := valueOf(R_v(55 downto 0), n);
            else
                n := 4 - to_integer(unsigned(R_v(59 downto 58)));
                v := valueOf(R_v(31 downto 0), n);
            end if;
        end procedure;

        -- Time of the k-th (from 0) frame of identifier id after time t in the log of model node n; 0 ns: none
        impure function frameTime (n : natural; id : natural; t : time; k : natural) return time is
            variable E_v : TbLog_t;
            variable C_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    if C_v = k then
                        return E_v.T;
                    end if;
                    C_v := C_v + 1;
                end if;
            end loop;

            return 0 ns;
        end function;

        -- Time of the first own frame of identifier id after time t in the log of model node n (the end of frame as
        -- the transmitter logs it); 0 ns: none
        impure function ownFrameTime (n : natural; id : natural; t : time) return time is
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    return E_v.T;
                end if;
            end loop;

            return 0 ns;
        end function;

        -- A boot-up message of the node (DLC 1, 00h) after time t in the log of model node n
        impure function bootUpAfter (n : natural; t : time) return boolean is
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = HbId_c and E_v.Frame.Dlc = 1 and
                   E_v.Frame.Data(63 downto 56) = x"00" then
                    return true;
                end if;
            end loop;

            return false;
        end function;

        function near (a : Scet_t; b : Scet_t; tol : natural) return boolean is
        begin
            if a >= b then
                return a - b <= tol;
            end if;
            return b - a <= tol;
        end function;

        -- The NMT state in the next heartbeat that the node requested after the change of the state
        procedure checkHeartbeat (s : natural; msg : string) is
            variable I_v : integer;
            variable E_v : TbLog_t;
        begin
            waitFrame(HbId_c, now + 200 us, 12 ms, I_v);
            if I_v >= 0 then
                E_v := Net_v.logGet(M1_v, I_v);
                check_value(E_v.Frame.Data(63 downto 56), u8(s), ERROR, msg & ": state in the heartbeat");
            else
                alert(ERROR, msg & ": no heartbeat");
            end if;
        end procedure;

        -- A CRC error that only the node sees: M2 of bus b sends frame f, and the receive input of the node is held
        -- recessive during a dominant data bit between two recessive bits (no stuff error); the model nodes
        -- acknowledge the frame
        procedure dutCrcError (b : natural; f : CanFrame_t) is
            variable W_v : CanBits_t;
            variable K_v : natural := 0;
        begin
            W_v := canStuff(canUnstuffed(f));

            for I in 22 to W_v.Len - 20 loop
                if K_v = 0 and W_v.Bits(I - 2 to I + 2) = "01010" and W_v.Stuff(I) = '0' then
                    K_v := I;
                end if;
            end loop;

            check_value(K_v > 0, TB_ERROR, "dominant data bit for the CRC error");

            -- An idle bus: 20 bit times recessive
            loop
                wait until Bus_Level(b) = '0' for 20 us;
                exit when Bus_Level(b) = '1';
                wait until Bus_Level(b) = '1';
            end loop;

            Net_v.txPush(2 * b + 1, f);
            wait until Bus_Level(b) = '0' for 100 us;
            check_value(Bus_Level(b), '0', TB_ERROR, "start of the frame for the CRC error");
            wait for K_v * 1 us - 20 ns;
            Bus_DutRec(b) <= '1';
            wait for 1 us + 40 ns;
            Bus_DutRec(b) <= '0';
            wait for 1 ms;
        end procedure;

        -- TC-CO-09: every port group of the core active at least once
        procedure connections is
            variable F_v   : CanFrame_t;
            variable L_v   : natural;
            variable M2_v  : natural;
            variable Ctl_v : natural;
            variable Exp_v : std_logic_vector(0 to 51);
        begin
            -- Receive PDOs: a short one and one of 8 bytes
            send(RpdoId_c(0), 4, mix(50, 1));
            wait for 1 ms;
            send(RpdoId_c(0), 8, mix(51, 1));
            wait until Rpdo_Valid(0) = '1' for 2 ms;
            -- Transmit PDO 1 twice in a row: sent, and busy
            request(0);
            request(0);
            wait for 2 ms;
            -- Arbitration lost against M2
            send(16#100#, 8, mix(52, 1));
            wait for 40 us;
            Net_v.txPush(2 * B_v + 1, canStd(16#050#, 1, mix(53, 1)));
            request(0);
            wait for 2 ms;
            -- SYNC; the time PDOs: a short Spacecraft Time PDO, a valid one, two SYNCs back to back
            sync;
            if TimePdos_g then
                send(SctId_c, 3, mix(54, 1));
                wait for 1 ms;
                send(SctId_c, 7, frameOf(x"12345678" & x"800000"));
                wait for 1 ms;
                send(SyncId_c, 0);
                send(SyncId_c, 0);
                wait for 2 ms;
            end if;
            -- SDO: the application port with a delay and an abort, an abort sent, a short request, a client abort
            -- of an open transfer, an unknown NMT command specifier
            if not MinimalSet_g then
                sdoRead(16#2100#, 1, D_v, N_v, Ab_v, "application object");
                AppAbort <= x"06090011";
                AppDelay <= 4000;
                sdoRead(16#2101#, 2, D_v, N_v, Ab_v, "application object with an abort");
                check_value(Ab_v, x"06090011", ERROR, "abort code of the user logic");
                AppAbort <= x"00000000";
                AppDelay <= 0;
                sdoRead(16#1234#, 0, D_v, N_v, Ab_v, "object that does not exist");
                check_value(Ab_v, x"06020000", ERROR, "abort 0602 0000h");
                send(SdoReqId_c, 4, mix(55, 1));
                wait for 1 ms;
                sdoXfer(muxOf(16#40#, 16#2002#, 0) & x"00000000", R_v, Ok_v);
                check_value(R_v(63 downto 56), x"41", ERROR, "segmented upload of 2002h");
                clocks(2);
                check_value(Stat_SdoOpen, '1', ERROR, "transfer open");
                send(SdoReqId_c, 8, muxOf(16#80#, 16#2002#, 0) & x"00000008");
                wait for 1 ms;
                nmt(16#99#);
                wait for 1 ms;
            end if;
            -- An NMT frame with DLC 1, master heartbeats with DLC 2
            nmt(Start_c, 1);
            MasterDlc <= 2;
            wait for 5 ms;
            MasterDlc <= 1;
            -- Link errors: a CRC error that only the node sees and a form error in frames of M2, a stuff error in a
            -- frame of M1, a bit error in a frame of the node, no acknowledge
            M2_v      := 2 * B_v + 1;
            F_v       := canStd(16#555#, 8, x"5555555555555555");
            dutCrcError(B_v, F_v);
            L_v       := canStuff(canUnstuffed(F_v)).Len;
            Net_v.setCorrupt(M2_v, L_v, 1);
            Net_v.txPush(M2_v, F_v);
            wait for 1 ms;
            Net_v.setErrFlag(M2_v, 20, 1, 16#100#);
            send(16#100#, 8, mix(56, 1));
            wait for 1 ms;
            Net_v.setErrFlag(M2_v, 20, 1, HbId_c);
            wait for 6 ms;
            Cfg_v     := Net_v.getCfg(M1_v);
            Cfg_v.Ack := false;
            Net_v.setCfg(M1_v, Cfg_v);
            Net_v.setCfg(M2_v, Cfg_v);
            wait for 12 ms;
            Cfg_v.Ack := true;
            Net_v.setCfg(M1_v, Cfg_v);
            Net_v.setCfg(M2_v, Cfg_v);
            wait for 2 ms;
            -- With parallel bus access the controller of the inactive bus reports a CRC error too
            if Parallel_c then
                dutCrcError(1 - B_v, F_v);
            end if;
            -- The master heartbeat missing: toggling, the master on the other bus, then Ntoggle toggles without
            -- success, and the master again on the default bus
            MasterOn <= false;
            wait until Err_MasterHbMissing = '1' for 40 ms;
            N_v      := 1 - B_v;
            if (Stat_ActiveBus = '1') /= (N_v = 1) then
                wait until (Stat_ActiveBus = '1') = (N_v = 1) for 25 ms;
            end if;
            MasterBus <= N_v;
            MasterOn  <= true;
            M1_v      := 2 * N_v;
            B_v       := N_v;
            waitSig(Stat_Selecting, '0', 20 ms, "bus selection ended");
            MasterOn  <= false;
            wait until Err_ToggleEnd = '1' for 120 ms;
            MasterOn  <= true;
            waitSig(Stat_Selecting, '0', 20 ms, "bus selection ended on the default bus");
            if not MinimalSet_g then
                nmt(Start_c);
                waitState(NmtOp_c, 2 ms, "Operational");
            end if;
            -- The dominant timeout of the controller of the active bus with a pending transmit PDO: aborted
            Ctl_v := 0;
            if Parallel_c then
                Ctl_v := B_v;
            end if;
            ErrInj_LinkTxDominant(Ctl_v) <= '1';
            request(0);
            wait until Err_LinkDomTimeout(Ctl_v) = '1' for 2 ms;
            wait for 100 us;
            ErrInj_LinkTxDominant(Ctl_v) <= '0';
            wait for 1 ms;
            wait until rising_edge(Clk);
            Ctrl_Reenable(Ctl_v)         <= '1';
            wait until rising_edge(Clk);
            Ctrl_Reenable(Ctl_v)         <= '0';
            wait for 3 ms;
            -- Upsets: the valid bit of copy A of the COB-ID of transmit PDO 1 (its identifier bits are not used while
            -- the entry is relative to the NODE-ID), a copy of 1017h, a copy of the NODE-ID
            wait until rising_edge(Clk);
            ErrInj_OdBitFlip(90)  <= '1';
            ErrInj_OdValid        <= '1';
            wait until rising_edge(Clk);
            ErrInj_OdBitFlip(90)  <= '0';
            ErrInj_OdBitFlip(166) <= '1';
            wait until rising_edge(Clk);
            ErrInj_OdBitFlip(166) <= '0';
            ErrInj_OdValid        <= '0';
            wait for 1 ms;
            wait until rising_edge(Clk);
            ErrInj_NmtBitFlip(0)  <= '1';
            ErrInj_NmtValid       <= '1';
            wait until rising_edge(Clk);
            ErrInj_NmtBitFlip(0)  <= '0';
            ErrInj_NmtValid       <= '0';
            wait for 1 ms;
            -- Every port group of the configuration active at least once
            Exp_v := (others => '1');
            if MinimalSet_g then
                Exp_v(8)        := '0';
                Exp_v(17)       := '0';
                Exp_v(33 to 36) := "0000";
            end if;
            if not TimePdos_g then
                Exp_v(10) := '0';
                Exp_v(11) := '0';
                Exp_v(13) := '0';
                Exp_v(14) := '0';
            end if;
            if not TimeBlock_c then
                Exp_v(9)  := '0';
                Exp_v(12) := '0';
            end if;
            if not Parallel_c then
                Exp_v(50) := '0';
            end if;

            for K in 0 to 51 loop
                if Exp_v(K) = '1' and Seen(K) /= '1' then
                    alert(ERROR, "port group " & integer'image(K) & " never active");
                end if;
            end loop;

        end procedure;

        -- Reset and start of the node: the master heartbeat on Bdefault, the boot-up (clause 6) or Operational by
        -- local control (minimal set); with start, the clause 6 slave is started by M1
        procedure startNode (start : boolean := true) is
        begin
            MasterBus <= Bdefault_g;
            MasterOn  <= true;
            M1_v      := 2 * Bdefault_g;
            B_v       := Bdefault_g;
            Rst       <= '1';
            wait for 103 ns;
            Rst       <= '0';
            wait for 1 ms;
            if MinimalSet_g then
                waitState(NmtOp_c, 10 ms, "Operational by local control");
            else
                waitState(NmtPreOp_c, 10 ms, "Pre-operational after the boot-up");
                if start then
                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational after the start of M1");
                end if;
            end if;
        end procedure;

        constant NoData_c : Data_t := (others => '0');
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            -- *** TC-CO-01: start-up ***
            if run("test_startup") then
                -- The reset released between two clock edges
                MasterBus <= Bdefault_g;
                MasterOn  <= true;
                wait for 7 ns;
                Rst       <= '1';
                wait for 1012 ns;
                Rst       <= '0';
                T_v       := now;
                if MinimalSet_g then
                    -- Operational by local control, no boot-up message, a heartbeat at once
                    waitState(NmtOp_c, 10 ms, "Operational by local control");
                    expectFrame(HbId_c, T_v, 3 ms, "heartbeat at once");
                    I_v := firstFrame(M1_v, HbId_c, T_v);
                    if I_v >= 0 then
                        E_v := Net_v.logGet(M1_v, I_v);
                        check_value(E_v.Frame.Data(63 downto 56), u8(HbOp_c), ERROR, "first frame: a heartbeat");
                    end if;
                else
                    expectFrame(HbId_c, T_v, 10 ms, "boot-up message");
                    I_v := firstFrame(M1_v, HbId_c, T_v);
                    if I_v >= 0 then
                        E_v := Net_v.logGet(M1_v, I_v);
                        check_value(E_v.Frame.Dlc, 1, ERROR, "boot-up message: DLC 1");
                        check_value(E_v.Frame.Data(63 downto 56), x"00", ERROR, "boot-up message: 00h");
                    end if;
                    waitState(NmtPreOp_c, 2 ms, "Pre-operational after the boot-up");
                end if;
                check_value((Stat_ActiveBus = '1') = (Bdefault_g = 1), ERROR, "start on Bdefault");
                -- The heartbeat every 5 ms: one tick for all blocks (CO-CN-01)
                T_v := now;
                wait for 23 ms;
                N_v := countFrames(M1_v, HbId_c, T_v);
                check_value(N_v >= 4 and N_v <= 5, ERROR, "heartbeats every 5 ms: " & integer'image(N_v));
                check_value(frameTime(M1_v, HbId_c, T_v, 1) - frameTime(M1_v, HbId_c, T_v, 0) > 4900 us and
                            frameTime(M1_v, HbId_c, T_v, 1) - frameTime(M1_v, HbId_c, T_v, 0) < 5300 us, ERROR,
                            "heartbeat period of 5 ms");

            -- *** TC-CO-02: configuration ***
            elsif run("test_configuration") then
                startNode(start => false);
                if MinimalSet_g then
                    -- No SDO server
                    sdoXfer(muxOf(16#40#, 16#1000#, 0) & x"00000000", R_v, Ok_v);
                    check_value(not Ok_v, ERROR, "no SDO reply in the minimal set");
                else
                    -- The identity object and the device type
                    sdoRead(16#1018#, 1, D_v, N_v, Ab_v, "vendor ID");
                    check_value(D_v(31 downto 0), x"800004D8", ERROR, "vendor ID");
                    check_value(N_v, 4, ERROR, "vendor ID: 4 bytes");
                    sdoRead(16#1018#, 2, D_v, N_v, Ab_v, "product code");
                    check_value(D_v(31 downto 0), x"0000C0DE", ERROR, "product code");
                    -- Transmit PDO 1: not valid, a new identifier, valid again, transmission type 1
                    sdoRead(16#1800#, 1, D_v, N_v, Ab_v, "COB-ID of transmit PDO 1");
                    check_value(D_v(31 downto 0), x"40000185", ERROR, "COB-ID of transmit PDO 1");
                    sdoWriteVec(16#1800#, 1, x"00000000C0000185", 4, "transmit PDO 1 not valid");
                    sdoWriteVec(16#1800#, 1, x"00000000C0000195", 4, "transmit PDO 1 on 195h");
                    sdoWriteOk(16#1800#, 1, 16#40000195#, 4, "transmit PDO 1 valid");
                    sdoWriteOk(16#1800#, 2, 1, 1, "transmit PDO 1 type 1");
                    -- The producer heartbeat time, Ttoggle and the consumer heartbeat time of the master
                    sdoWriteOk(16#1017#, 0, 8, 2, "producer heartbeat time 8 ms");
                    sdoWriteOk(16#2000#, 2, 2, 1, "Ttoggle 2");
                    sdoRead(16#2000#, 2, D_v, N_v, Ab_v, "Ttoggle");
                    check_value(D_v(7 downto 0), x"02", ERROR, "Ttoggle read back");
                    sdoWriteOk(16#1016#, 1, 16#0001000C#, 4, "consumer heartbeat time 12 ms");
                    -- Ctoggle written, read back and counted by the redundancy block
                    sdoWriteOk(16#2000#, 4, 1, 1, "Ctoggle 1");
                    sdoRead(16#2000#, 4, D_v, N_v, Ab_v, "Ctoggle");
                    check_value(D_v(7 downto 0), x"01", ERROR, "Ctoggle read back");
                    check_value(Stat_Ctoggle, x"01", ERROR, "Ctoggle of the redundancy block");
                    -- An application object
                    C_v := AppCount;
                    sdoWriteOk(16#2100#, 1, 16#5A#, 1, "application object 2100h");
                    sdoRead(16#2100#, 1, D_v, N_v, Ab_v, "application object 2100h");
                    check_value(D_v(7 downto 0), x"5A", ERROR, "application object read back");
                    check_value(AppCount, C_v + 2, ERROR, "two requests of the application port");
                    -- Started: the transmit PDO on its new identifier at the SYNC
                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational");
                    UserData(0) <= mix(1, 1);
                    clocks(2);
                    sync;
                    wait for 2 ms;
                    check_value(countFrames(M1_v, 16#195#, T_v), 1, ERROR, "transmit PDO 1 on 195h at the SYNC");
                    check_value(countFrames(M1_v, 16#185#, T_v), 0, ERROR, "no frame on 185h");
                    I_v         := firstFrame(M1_v, 16#195#, T_v);
                    if I_v >= 0 then
                        E_v := Net_v.logGet(M1_v, I_v);
                        check_value(E_v.Frame.Data, mix(1, 1), ERROR, "the data of the user logic");
                    end if;
                    -- The heartbeat every 8 ms
                    T_v := now;
                    wait for 20 ms;
                    check_value(frameTime(M1_v, HbId_c, T_v, 1) - frameTime(M1_v, HbId_c, T_v, 0) > 7900 us and
                                frameTime(M1_v, HbId_c, T_v, 1) - frameTime(M1_v, HbId_c, T_v, 0) < 8300 us, ERROR,
                                "heartbeat period of 8 ms");
                    -- A transmission type written in Operational: refused
                    sdoWrite(16#1800#, 2, x"00000000000000FE", 1, Ab_v, "type in Operational");
                    check_value(Ab_v, x"08000022", ERROR, "abort 0800 0022h in Operational");
                end if;

            -- *** TC-CO-03: process data ***
            elsif run("test_process_data") then
                startNode(start => false);
                if not MinimalSet_g then
                    sdoWriteOk(16#1801#, 2, 1, 1, "transmit PDO 2 type 1");
                    sdoWriteOk(16#1802#, 2, 0, 1, "transmit PDO 3 type 0");
                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational");
                end if;
                clocks(2);
                check_value(Stat_PdoEnabled, '1', ERROR, "PDO enable in Operational");

                -- Receive PDOs to the user port
                for N in 0 to NumRpdo_g - 1 loop
                    T_v := now;
                    send(RpdoId_c(N), 8, mix(N, 2));
                    wait until Rpdo_Valid(N) = '1' for 2 ms;
                    check_value(Rpdo_Valid(N), '1', ERROR, "receive PDO " & integer'image(N + 1));
                    if N = 0 then
                        -- M1 logs its own frame at the last bit of the end of frame, after the receiver took it
                        T2_v := now;
                        wait for 2 us;
                        log(ID_SEQUENCER, "measured: last bit of the receive PDO frame (M1) to Rpdo_Valid " &
                            integer'image((T2_v - ownFrameTime(M1_v, RpdoId_c(0), T_v)) / 1 ps) & " ps");
                    end if;
                    wait until falling_edge(Clk);
                    check_value(pdo(Rpdo_Data, N), mix(N, 2), ERROR, "data of receive PDO " & integer'image(N + 1));
                end loop;

                -- Transmit PDO 1 at a request, on an idle bus
                UserData(0) <= mix(10, 3);
                wait for 100 us;
                clocks(2);
                T_v         := now;
                C_v         := SentCnt(0);
                request(0);
                T2_v        := now;
                expectFrame(TpdoId_c(0), T_v, 2 ms, "transmit PDO 1 at the request");
                wait for 100 us;
                check_value(SentCnt(0), C_v + 1, ERROR, "Evt_TpdoSent of transmit PDO 1");
                check_value(Evt_TpdoAborted, x"0", ERROR, "no Evt_TpdoAborted");
                I_v         := firstFrame(M1_v, TpdoId_c(0), T_v);
                if I_v >= 0 then
                    E_v := Net_v.logGet(M1_v, I_v);
                    check_value(E_v.Frame.Dlc, 8, ERROR, "transmit PDO 1: DLC 8");
                    check_value(E_v.Frame.Data, mix(10, 3), ERROR, "transmit PDO 1: data");
                    -- From the clock edge after which Tpdo_Req is '1' (the core samples it one cycle later); M1
                    -- logs the frame at its sample point (75 %) of the last but one bit of the end of frame
                    log(ID_SEQUENCER, "measured: Tpdo_Req to the start of the transmit PDO frame on an idle bus " &
                        integer'image((E_v.T - T2_v - (canWire(E_v.Frame).Len - 2) * 1 us - 750 ns) / 1 ps) &
                        " ps, frame of " & integer'image(canWire(E_v.Frame).Len) & " bits on the bus");
                end if;
                -- The SYNC: transmit PDO 2 (type 1) and transmit PDO 3 (type 0) after a request
                if not MinimalSet_g then
                    UserData(1) <= mix(11, 3);
                    UserData(2) <= mix(12, 3);
                    request(2);
                    clocks(2);
                    sync;
                    wait for 2 ms;
                    check_value(countFrames(M1_v, TpdoId_c(1), T_v), 1, ERROR, "transmit PDO 2 at the SYNC");
                    check_value(countFrames(M1_v, TpdoId_c(2), T_v), 1, ERROR, "transmit PDO 3 after its request");

                    -- Stopped and Pre-operational: no PDO
                    for K in 0 to 1 loop
                        if K = 0 then
                            nmt(Stop_c);
                            waitState(NmtStopped_c, 2 ms, "Stopped");
                        else
                            nmt(EnterPo_c);
                            waitState(NmtPreOp_c, 2 ms, "Pre-operational");
                        end if;
                        clocks(2);
                        check_value(Stat_PdoEnabled, '0', ERROR, "no PDO enable");
                        C_v := RxCnt(0);
                        T_v := now;
                        send(RpdoId_c(0), 8, mix(20 + K, 2));
                        request(0);
                        wait for 2 ms;
                        check_value(RxCnt(0), C_v, ERROR, "no receive PDO passed");
                        check_value(countFrames(M1_v, TpdoId_c(0), T_v), 0, ERROR, "no transmit PDO");
                    end loop;

                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational again");
                else
                    sync;
                end if;
                -- A hardware reset through Rst, after a heartbeat on an idle bus: the data at the user port 0 again
                -- (CO-IF-01)
                check_value(pdo(Rpdo_Data, 0), mix(0, 2), TB_ERROR, "data of receive PDO 1 before the reset");
                expectFrame(HbId_c, now, 10 ms, "heartbeat before the reset");
                wait until rising_edge(Clk);
                Rst <= '1';
                wait for 1 us;
                Rst <= '0';
                wait for 1 us;
                check_value(or Rpdo_Data, '0', ERROR, "the data at the user port 0 after the hardware reset");

            -- *** TC-CO-04: time ***
            elsif run("test_time") then
                startNode(start => false);
                if not MinimalSet_g then
                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational");
                end if;
                S_v := x"12345678" & x"800000";
                if not TimeBlock_c then
                    -- No time block: the local time 0
                    wait for 5 ms;
                    check_value(Time_Coarse & Time_Fine, x"00000000000000", ERROR, "local time 0 without a time block");
                    check_value(Stat_TimeSet, '0', ERROR, "time not set");
                elsif TimePdos_g then
                    -- High-resolution protocol: the SCET of M1 at the SYNC
                    sync;
                    clocks(3);
                    T2_v := SyncEvtT;
                    send(SctId_c, 7, frameOf(S_v));
                    wait until Evt_TimeSet = '1' for 2 ms;
                    check_value(Evt_TimeSet, '1', ERROR, "local time set by the Spacecraft Time PDO");
                    wait for 1 ms;
                    wait until rising_edge(Clk);
                    X_v  := unsigned(std_logic_vector'(Time_Coarse & Time_Fine));
                    Ok_v := near(X_v, S_v + fineOf(now - T2_v + 50 ns), 6);
                    check_value(Ok_v, ERROR, "local time: SCET of the SYNC plus the time since the sample");
                    -- The Local Time PDO of type 1 at the next SYNC, with the sample of that SYNC
                    sync;
                    clocks(3);
                    expectFrame(LtpId_c, T_v, 2 ms, "Local Time PDO at the SYNC");
                    I_v := firstFrame(M1_v, LtpId_c, T_v);
                    if I_v >= 0 then
                        E_v  := Net_v.logGet(M1_v, I_v);
                        check_value(E_v.Frame.Dlc, 7, ERROR, "Local Time PDO: DLC 7");
                        Ok_v := near(scetOf(E_v.Frame.Data), S_v + fineOf(SyncEvtT - T2_v), 6);
                        check_value(Ok_v, ERROR, "Local Time PDO: the local time at the SYNC");
                    end if;
                else
                    -- Without the time PDOs: the Spacecraft Time PDO without effect, no Local Time PDO
                    send(SctId_c, 7, frameOf(S_v));
                    sync;
                    wait until rising_edge(Clk);
                    Time_Req <= '1';
                    wait until rising_edge(Clk);
                    Time_Req <= '0';
                    wait for 2 ms;
                    check_value(Stat_TimeSet, '0', ERROR, "the Spacecraft Time PDO without effect");
                    check_value(countFrames(M1_v, LtpId_c, T_v), 0, ERROR, "no Local Time PDO");
                end if;
                -- Local SCET Set and Get by SDO (clause 6 slave)
                if not MinimalSet_g then
                    X_v  := x"00ABCDEF" & x"123456";
                    sdoWrite(16#2001#, 0, std_logic_vector(resize(X_v, 64)), 7, Ab_v, "Local SCET Set");
                    check_value(Ab_v, x"00000000", ERROR, "Local SCET Set accepted");
                    wait until rising_edge(Clk);
                    Ok_v := unsigned(std_logic_vector'(Time_Coarse & Time_Fine)) >= X_v and
                            unsigned(std_logic_vector'(Time_Coarse & Time_Fine)) < X_v + fineOf(500 us);
                    check_value(Ok_v, ERROR, "local time after Local SCET Set");
                    sdoRead(16#2002#, 0, D_v, N_v, Ab_v, "Local SCET Get");
                    check_value(N_v, 7, ERROR, "Local SCET Get: 7 bytes");
                    Ok_v := unsigned(D_v(55 downto 0)) >= X_v and
                            unsigned(D_v(55 downto 0)) <= unsigned(std_logic_vector'(Time_Coarse & Time_Fine));
                    check_value(Ok_v, ERROR, "Local SCET Get: the local time at the access");
                    if TimePdos_g then
                        -- The Local Time PDO on a request (type 254), with the last SYNC sample (high resolution)
                        nmt(EnterPo_c);
                        waitState(NmtPreOp_c, 2 ms, "Pre-operational");
                        sdoWriteOk(16#1804#, 2, 254, 1, "Local Time PDO type 254");
                        nmt(Start_c);
                        waitState(NmtOp_c, 2 ms, "Operational");
                        T_v      := now;
                        wait until rising_edge(Clk);
                        Time_Req <= '1';
                        wait until rising_edge(Clk);
                        Time_Req <= '0';
                        expectFrame(LtpId_c, T_v, 2 ms, "Local Time PDO at Time_Req");
                        -- The Spacecraft Time PDO keeps its own type 1 (the SCET of the SYNC)
                        S_v  := x"23456789" & x"400000";
                        sync;
                        clocks(3);
                        T2_v := SyncEvtT;
                        send(SctId_c, 7, frameOf(S_v));
                        wait until Evt_TimeSet = '1' for 2 ms;
                        check_value(Evt_TimeSet, '1', ERROR, "local time set by the Spacecraft Time PDO again");
                        wait for 1 ms;
                        wait until rising_edge(Clk);
                        X_v  := unsigned(std_logic_vector'(Time_Coarse & Time_Fine));
                        Ok_v := near(X_v, S_v + fineOf(now - T2_v + 50 ns), 6);
                        check_value(Ok_v, ERROR, "local time: the Spacecraft Time PDO still of type 1");
                    end if;
                end if;

            -- *** TC-CO-05: bus monitoring ***
            elsif run("test_bus_monitoring") then
                startNode;
                N_v := 1 - Bdefault_g;
                -- With parallel bus access: bit 4 of the error register with the controller of the start bus, the
                -- active one (CO-CN-03)
                if Parallel_c then
                    Net_v.setErrFlag(2 * B_v + 1, 30, 24, HbId_c);
                    waitSig(Stat_ErrReg(4), '1', 40 ms, "error register bit 4 with the controller of the start bus");
                    check_value(Stat_LinkState(2 * B_v + 1 downto 2 * B_v), "01", ERROR,
                                "the controller of the start bus error passive");
                    Net_v.setErrFlag(2 * B_v + 1, 30, 0, HbId_c);
                end if;
                -- The master heartbeat stops: Pre-operational, the bus selection toggles to the other bus
                MasterOn <= false;
                wait until Err_MasterHbMissing = '1' for 40 ms;
                check_value(Err_MasterHbMissing, '1', ERROR, "master heartbeat missing");
                waitState(NmtPreOp_c, 1 ms, "Pre-operational at the missing master heartbeat");
                waitSig(Stat_Selecting, '1', 1 ms, "bus selection process");
                clocks(2);
                check_value(Stat_PdoEnabled, '0', ERROR, "no PDO during the bus selection");
                if (Stat_ActiveBus = '1') /= (N_v = 1) then
                    wait until (Stat_ActiveBus = '1') = (N_v = 1) for 25 ms;
                end if;
                check_value((Stat_ActiveBus = '1') = (N_v = 1), ERROR, "toggled to the other bus");
                -- A heartbeat on the new bus at once after the switch (NM-HB-05)
                T_v := now;
                wait for 1 ms;
                check_value(countFrames(2 * N_v, HbId_c, T_v - 100 us), 1, ERROR, "heartbeat at once after the toggle");
                -- The master heartbeat on the other bus ends the bus selection; Bdefault follows
                C_v       := UpdCnt;
                MasterBus <= N_v;
                MasterOn  <= true;
                M1_v      := 2 * N_v;
                B_v       := N_v;
                waitSig(Stat_Selecting, '0', 20 ms, "bus selection ended by the master heartbeat");
                clocks(2);
                check_value(UpdCnt, C_v + 1, ERROR, "Bdefault updated");
                expectFrame(HbId_c, now, 10 ms, "heartbeat on the new bus");
                if MinimalSet_g then
                    waitState(NmtOp_c, 5 ms, "Operational by local control after the bus selection");
                else
                    sdoRead(16#2000#, 1, D_v, N_v, Ab_v, "Bdefault");
                    check_value(to_integer(unsigned(D_v(7 downto 0))), B_v, ERROR, "Bdefault is the new bus");
                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational");
                end if;
                -- Error passive controller of the active bus: bit 4 of the error register (CO-CN-03)
                Net_v.setErrFlag(2 * B_v + 1, 30, 24, HbId_c);
                waitSig(Stat_ErrReg(4), '1', 40 ms, "error register bit 4 with the state of the active controller");
                if Parallel_c then
                    check_value(Stat_LinkState(2 * B_v + 1 downto 2 * B_v), "01", ERROR,
                                "the controller of the active bus error passive");
                else
                    check_value(Stat_LinkState(1 downto 0), "01", ERROR, "the controller error passive");
                end if;
                Net_v.setErrFlag(2 * B_v + 1, 30, 0, HbId_c);
                -- An NMT message ends the bus selection (clause 6 slave): with selective bus access on the bus that
                -- the node toggled to, with parallel bus access at once from the inactive bus (8.3.3g, DS-BG-03).
                -- The node toggles at once at the missing heartbeat (RM-SL-02); the message follows the end of the
                -- switch and the integration (LK-BS-03), since a frame on the bus during the switch is cut
                if not MinimalSet_g then
                    N_v      := 1 - B_v;
                    MasterOn <= false;
                    wait until Err_MasterHbMissing = '1' for 40 ms;
                    if (Stat_ActiveBus = '1') /= (N_v = 1) then
                        wait until (Stat_ActiveBus = '1') = (N_v = 1) for 25 ms;
                    end if;
                    check_value((Stat_ActiveBus = '1') = (N_v = 1), ERROR, "toggled at the missing heartbeat");
                    waitSig(Stat_LinkSwitching, '0', 1 ms, "end of the bus switch");
                    wait for 20 us;
                    check_value(Stat_Selecting, '1', ERROR, "bus selection process");
                    if Parallel_c then
                        -- The message on the inactive bus, the bus of the master before the toggle
                        N_v := B_v;
                    end if;
                    M1_v := 2 * N_v;
                    B_v  := N_v;
                    nmt(Start_c);
                    waitSig(Stat_Selecting, '0', 5 ms, "bus selection ended by an NMT message");
                    waitState(NmtOp_c, 2 ms, "Operational by the NMT message");
                    check_value((Stat_ActiveBus = '1') = (B_v = 1), ERROR, "on the bus of the NMT message");
                end if;
                -- Ntoggle toggles without success: the end of the toggling on the default bus
                MasterOn <= false;
                wait until Err_ToggleEnd = '1' for 120 ms;
                check_value(Err_ToggleEnd, '1', ERROR, "end of the toggling after Ntoggle toggles");
                clocks(2);
                check_value((Stat_ActiveBus = '1') = (B_v = 1), ERROR, "the toggling ends on the default bus");

            -- *** TC-CO-06: NMT resets ***
            elsif run("test_nmt_resets") then
                startNode;
                if MinimalSet_g then
                    -- No node control in the minimal set
                    C_v := ResetCnt;
                    nmt(ResetComm_c);
                    nmt(ResetNode_c);
                    nmt(Stop_c);
                    wait for 3 ms;
                    check_value(ResetCnt, C_v, ERROR, "no reset communication in the minimal set");
                    check_value(Stat_NmtState, NmtOp_c, ERROR, "still Operational in the minimal set");
                else
                    sdoWriteOk(16#1017#, 0, 8, 2, "producer heartbeat time 8 ms");
                    sdoWriteOk(16#2000#, 2, 3, 1, "Ttoggle 3");
                    send(RpdoId_c(0), 8, mix(40, 4));
                    wait until Rpdo_Valid(0) = '1' for 2 ms;
                    wait until rising_edge(Clk);
                    X_v := unsigned(std_logic_vector'(Time_Coarse & Time_Fine));

                    for K in 0 to 1 loop
                        C_v := ResetCnt;
                        N_v := AppRstCnt;
                        T_v := now;
                        if K = 0 then
                            nmt(ResetComm_c);
                        else
                            nmt(ResetNode_c);
                        end if;
                        expectFrame(HbId_c, T_v, 10 ms, "boot-up message after the reset");
                        waitState(NmtPreOp_c, 2 ms, "Pre-operational after the reset");
                        check_value(ResetCnt, C_v + 1, ERROR, "Evt_ResetComm");
                        check_value(AppRstCnt, N_v + K, ERROR, "Evt_ResetApp at reset node only");
                        sdoRead(16#1017#, 0, D_v, N_v, Ab_v, "producer heartbeat time");
                        check_value(D_v(15 downto 0), x"0005", ERROR, "1017h restored to its power-on value");
                        sdoRead(16#2000#, 2, D_v, N_v, Ab_v, "Ttoggle");
                        check_value(D_v(7 downto 0), x"03", ERROR, "2000h kept");
                        check_value(pdo(Rpdo_Data, 0), mix(40, 4), ERROR, "the data at the PDO port kept");
                        check_value((Stat_ActiveBus = '1') = (Bdefault_g = 1), ERROR, "the active bus kept");
                        if TimeBlock_c then
                            check_value(unsigned(std_logic_vector'(Time_Coarse & Time_Fine)) > X_v, ERROR, "the local time kept");
                        end if;
                        nmt(Start_c);
                        waitState(NmtOp_c, 2 ms, "Operational");
                    end loop;

                    -- Stop, enter pre-operational, start: the state in the heartbeat
                    nmt(Stop_c);
                    waitState(NmtStopped_c, 2 ms, "Stopped");
                    checkHeartbeat(HbStop_c, "Stopped");
                    nmt(EnterPo_c);
                    waitState(NmtPreOp_c, 2 ms, "Pre-operational");
                    checkHeartbeat(HbPreop_c, "Pre-operational");
                    nmt(Start_c);
                    waitState(NmtOp_c, 2 ms, "Operational");
                    checkHeartbeat(HbOp_c, "Operational");
                    -- Reset communication in Stopped and reset node in Pre-operational: a boot-up message each
                    nmt(Stop_c);
                    waitState(NmtStopped_c, 2 ms, "Stopped before the reset communication");
                    C_v := ResetCnt;
                    T_v := now;
                    nmt(ResetComm_c);
                    waitState(NmtPreOp_c, 2 ms, "Pre-operational after the reset communication in Stopped");
                    wait for 1 ms;
                    check_value(bootUpAfter(M1_v, T_v), ERROR, "boot-up message after the reset in Stopped");
                    check_value(ResetCnt, C_v + 1, ERROR, "Evt_ResetComm in Stopped");
                    C_v := AppRstCnt;
                    T_v := now;
                    nmt(ResetNode_c);
                    wait until AppRstCnt = C_v + 1 for 2 ms;
                    waitState(NmtPreOp_c, 2 ms, "Pre-operational after the reset node in Pre-operational");
                    wait for 1 ms;
                    check_value(bootUpAfter(M1_v, T_v), ERROR, "boot-up message after the reset node in Pre-operational");
                    check_value(AppRstCnt, C_v + 1, ERROR, "Evt_ResetApp in Pre-operational");
                end if;

            -- *** TC-CO-07: NODE-ID and enable ***
            elsif run("test_node_id") then
                -- An invalid code: the node silent, no acknowledge
                Pin_NodeIdCode <= not std_logic_vector(to_unsigned(NodeId_c, 7)) xor "0000001";
                Cfg_v          := Net_v.getCfg(2 * Bdefault_g + 1);
                Cfg_v.Ack      := false;
                Net_v.setCfg(2 * Bdefault_g + 1, Cfg_v);
                Rst            <= '1';
                wait for 1 us;
                Rst            <= '0';
                wait for 6 ms;
                check_value(Node_IdValid, '0', ERROR, "NODE-ID not valid");
                T_v            := now;
                send(SyncId_c, 0);
                wait for 500 us;
                check_value(countErrors(M1_v, TbErrAck, T_v) > 0, ERROR, "no acknowledge of the node");
                check_value(countFrames(M1_v, HbId_c, 0 ns), 0, ERROR, "no frame of the node");
                Net_v.txClear(M1_v);
                Cfg_v.Ack      := true;
                Net_v.setCfg(2 * Bdefault_g + 1, Cfg_v);
                -- A valid code: the node starts
                Pin_NodeIdCode <= not std_logic_vector(to_unsigned(NodeId_c, 7));
                waitSig(Node_IdValid, '1', 5 ms, "NODE-ID valid");
                expectFrame(HbId_c, T_v, 10 ms, "the node starts");
                -- The enable input cleared: the node leaves the bus; new bit timing; enabled again
                Ctrl_Enable <= '0';
                wait for 100 us;
                T_v         := now;
                wait for 12 ms;
                check_value(countFrames(M1_v, HbId_c, T_v), 0, ERROR, "no frame while not enabled");
                Cfg_Tseg1   <= std_logic_vector(to_unsigned(13, 5));
                Cfg_Tseg2   <= std_logic_vector(to_unsigned(6, 4));
                wait for 1 us;
                Ctrl_Enable <= '1';
                T_v         := now;
                expectFrame(HbId_c, T_v, 10 ms, "heartbeat with the new bit timing");

            -- *** TC-CO-08: applicability ***
            elsif run("test_applicability") then
                startNode;
                C_v := RxCnt(0);
                T_v := now;
                -- Remote frames of the PDOs and the node guarding request
                send(TpdoId_c(0), 8, NoData_c, '1');
                send(RpdoId_c(0), 8, NoData_c, '1');
                send(HbId_c, 1, NoData_c, '1');
                -- Frames on the identifiers of EMCY and TIME
                send(16#085#, 8, mix(60, 1));
                send(16#100#, 6, mix(61, 1));
                wait for 3 ms;
                check_value(countFrames(M1_v, TpdoId_c(0), T_v), 0, ERROR, "no transmit PDO on a remote request");
                check_value(RxCnt(0), C_v, ERROR, "no receive PDO from a remote frame");
                check_value(countFrames(M1_v, HbId_c, T_v) <= 1, ERROR, "no answer to node guarding");
                check_value(countFrames(M1_v, SdoRspId_c, T_v), 0, ERROR, "no reply to EMCY and TIME");
                -- The block transfer: an abort; the minimal set: no SDO server
                sdoXfer(muxOf(16#C2#, 16#2100#, 1) & x"08000000", R_v, Ok_v);
                if MinimalSet_g then
                    check_value(not Ok_v, ERROR, "no SDO reply in the minimal set");
                else
                    check_value(Ok_v, ERROR, "reply to a block download");
                    check_value(R_v(63 downto 56), x"80", ERROR, "abort of the block download");
                    check_value(R_v(31 downto 0), x"01000405", ERROR, "abort code 0504 0001h");
                    sdoXfer(muxOf(16#A0#, 16#2100#, 1) & x"08000000", R_v, Ok_v);
                    check_value(R_v(63 downto 56), x"80", ERROR, "abort of the block upload");
                end if;
                -- No frame of the node in the whole test other than boot-up, heartbeats, transmit PDOs, the Local
                -- Time PDO and SDO replies; M2 sends no frame in this test, so every frame that M1 receives is one
                -- of the node
                wait for 1 ms;

                for I in 0 to Net_v.logCount(M1_v) - 1 loop
                    E_v  := Net_v.logGet(M1_v, I);
                    N_v  := to_integer(unsigned(E_v.Frame.Id(28 downto 18)));
                    Ok_v := N_v = HbId_c or N_v = SdoRspId_c or (N_v = LtpId_c and TimePdos_g);

                    for K in 0 to NumTpdo_g - 1 loop
                        Ok_v := Ok_v or N_v = TpdoId_c(K);
                    end loop;

                    if E_v.Kind = TbFrame and not E_v.Own and not Ok_v then
                        alert(ERROR, "frame of the node on identifier " & integer'image(N_v));
                    end if;
                end loop;

            -- *** TC-CO-09: connections ***
            elsif run("test_connections") then
                startNode;
                connections;

            end if;

            wait for 10 us;

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
