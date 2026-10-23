---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Top level of OpenCAN: a slave node of ECSS-E-ST-50-15C on a nominal and a redundant bus. The eight blocks of the
-- architecture, the synchronised release of the reset, the millisecond tick and the fault confinement state of the
-- controller of the active bus for the object dictionary.
--
-- Documentation: hdl/ocan_core/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_core is
    generic (
        -- ocan_link
        BusAccess_g      : string                                 := "Selective";
        SyncStages_g     : positive range 2 to 4                  := 2;
        AutoRecover_g    : boolean                                := true;
        DominantLimit_g  : positive range 13 to 1023              := 32;
        -- Protocol set and objects
        MinimalSet_g     : boolean                                := false;
        NumRpdo_g        : natural range 0 to 4                   := 4;
        NumTpdo_g        : natural range 0 to 4                   := 4;
        TimePdos_g       : boolean                                := true;
        -- Clock and local time
        ClkFrequency_g   : positive range 1000000 to integer'high := 100000000;
        FineBits_g       : natural range 0 to 24                  := 24;
        -- Power-on values of the object dictionary
        DeviceType_g     : std_logic_vector(31 downto 0)          := (others => '0');
        VendorId_g       : std_logic_vector(31 downto 0)          := (others => '0');
        ProductCode_g    : std_logic_vector(31 downto 0)          := (others => '0');
        Revision_g       : std_logic_vector(31 downto 0)          := (others => '0');
        SerialNumber_g   : std_logic_vector(31 downto 0)          := (others => '0');
        ProducerHbTime_g : natural range 0 to 65535               := 1000;
        MasterNodeId_g   : natural range 0 to 127                 := 1;
        MasterHbTime_g   : natural range 0 to 65535               := 1500;
        Bdefault_g       : natural range 0 to 1                   := 0;
        Ttoggle_g        : natural range 0 to 255                 := 1;
        Ntoggle_g        : natural range 0 to 255                 := 3;
        RpdoType_g       : natural range 0 to 255                 := 254;
        TpdoType_g       : natural range 0 to 255                 := 254;
        SctCobId_g       : natural range 0 to 2047                := 0;
        SctType_g        : natural range 0 to 255                 := 254;
        LtpCobId_g       : natural range 0 to 2047                := 0;
        LtpType_g        : natural range 0 to 255                 := 254
    );
    port (
        -- Clock, reset and control
        Clk                   : in    std_logic;
        Rst                   : in    std_logic;
        Ctrl_Enable           : in    std_logic                      := '1';
        Ctrl_Recover          : in    std_logic                      := '0';
        Ctrl_Reenable         : in    std_logic_vector(1 downto 0)   := "00";
        -- Bit timing (static while Ctrl_Enable = '1')
        Cfg_Prescaler         : in    std_logic_vector(9 downto 0);
        Cfg_Tseg1             : in    std_logic_vector(4 downto 0);
        Cfg_Tseg2             : in    std_logic_vector(3 downto 0);
        Cfg_Sjw               : in    std_logic_vector(2 downto 0);
        -- NODE-ID
        Pin_NodeId            : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode        : in    std_logic_vector(6 downto 0);
        Node_Id               : out   std_logic_vector(6 downto 0);
        Node_IdValid          : out   std_logic;
        -- Transceivers (bus A in index 0, bus B in index 1)
        Can_Tx                : out   std_logic_vector(1 downto 0);
        Can_TxEn              : out   std_logic_vector(1 downto 0);
        Can_Rx                : in    std_logic_vector(1 downto 0)   := "11";
        -- PDO port of the user logic (PDO n in bit n - 1 and bits 64 n - 1 downto 64 (n - 1))
        Sync_Valid            : out   std_logic;
        Rpdo_Valid            : out   std_logic_vector(3 downto 0);
        Rpdo_Data             : out   std_logic_vector(255 downto 0);
        Tpdo_Req              : in    std_logic_vector(3 downto 0)   := (others => '0');
        Tpdo_Data             : in    std_logic_vector(255 downto 0) := (others => '0');
        Stat_TpdoBusy         : out   std_logic_vector(3 downto 0);
        Stat_PdoEnabled       : out   std_logic;
        Evt_TpdoSent          : out   std_logic_vector(3 downto 0);
        Evt_TpdoAborted       : out   std_logic_vector(3 downto 0);
        Err_RpdoLength        : out   std_logic_vector(3 downto 0);
        Err_TpdoBusy          : out   std_logic_vector(3 downto 0);
        Err_TpdoTimeout       : out   std_logic_vector(3 downto 0);
        -- Application objects
        App_ReqValid          : out   std_logic;
        App_ReqReady          : in    std_logic                      := '1';
        App_ReqWrite          : out   std_logic;
        App_ReqIndex          : out   std_logic_vector(15 downto 0);
        App_ReqSub            : out   std_logic_vector(7 downto 0);
        App_ReqData           : out   std_logic_vector(63 downto 0);
        App_ReqLen            : out   std_logic_vector(3 downto 0);
        App_RspValid          : in    std_logic                      := '1';
        App_RspData           : in    std_logic_vector(63 downto 0)  := (others => '0');
        App_RspLen            : in    std_logic_vector(3 downto 0)   := (others => '0');
        App_RspAbort          : in    std_logic_vector(31 downto 0)  := x"06020000";
        -- Local time
        Time_Coarse           : out   std_logic_vector(31 downto 0);
        Time_Fine             : out   std_logic_vector(23 downto 0);
        Time_Req              : in    std_logic                      := '0';
        Stat_TimeSet          : out   std_logic;
        Evt_TimeSet           : out   std_logic;
        Evt_TimeSync          : out   std_logic;
        Err_TimeTxBusy        : out   std_logic;
        Err_TimeRxDrop        : out   std_logic;
        Err_TimeTxTimeout     : out   std_logic;
        -- Network management
        Stat_NmtState         : out   std_logic_vector(1 downto 0);
        Evt_ResetApp          : out   std_logic;
        Evt_ResetComm         : out   std_logic;
        Err_NmtCs             : out   std_logic;
        Err_NodeId            : out   std_logic;
        Err_NmtTxTimeout      : out   std_logic;
        -- Bus redundancy
        Stat_ActiveBus        : out   std_logic;
        Stat_Selecting        : out   std_logic;
        Stat_Ctoggle          : out   std_logic_vector(7 downto 0);
        Stat_MasterHbState    : out   std_logic_vector(7 downto 0);
        Stat_MasterHbPresent  : out   std_logic_vector(1 downto 0);
        Evt_BdefaultUpdate    : out   std_logic;
        Err_MasterHbMissing   : out   std_logic;
        Err_ToggleEnd         : out   std_logic;
        Err_MasterHbDlc       : out   std_logic;
        -- Object dictionary, dispatch and SDO server
        Stat_ErrReg           : out   std_logic_vector(7 downto 0);
        Err_ParamCopy         : out   std_logic;
        Err_AppTimeout        : out   std_logic;
        Stat_CobIdMismatch    : out   std_logic_vector(11 downto 0);
        Err_Protocol          : out   std_logic;
        Err_CobId             : out   std_logic;
        Stat_SdoOpen          : out   std_logic;
        Evt_SdoAbortTx        : out   std_logic;
        Evt_SdoAbortRx        : out   std_logic;
        Err_SdoRxDrop         : out   std_logic;
        Err_SdoTxTimeout      : out   std_logic;
        Err_SdoAccTimeout     : out   std_logic;
        -- Link, per controller (controller c in slice c)
        Stat_LinkTec          : out   std_logic_vector(17 downto 0);
        Stat_LinkRec          : out   std_logic_vector(15 downto 0);
        Stat_LinkState        : out   std_logic_vector(3 downto 0);
        Stat_LinkBusIdle      : out   std_logic_vector(1 downto 0);
        Stat_LinkDomTimeout   : out   std_logic_vector(1 downto 0);
        Stat_LinkSwitching    : out   std_logic;
        Evt_LinkArbLost       : out   std_logic;
        Err_LinkBit           : out   std_logic_vector(1 downto 0);
        Err_LinkStuff         : out   std_logic_vector(1 downto 0);
        Err_LinkCrc           : out   std_logic_vector(1 downto 0);
        Err_LinkForm          : out   std_logic_vector(1 downto 0);
        Err_LinkAck           : out   std_logic_vector(1 downto 0);
        Err_LinkDomTimeout    : out   std_logic_vector(1 downto 0);
        -- Test inputs (tie to 0 in a system)
        ErrInj_OdBitFlip      : in    std_logic_vector(557 downto 0) := (others => '0');
        ErrInj_OdValid        : in    std_logic                      := '0';
        ErrInj_NmtBitFlip     : in    std_logic_vector(13 downto 0)  := (others => '0');
        ErrInj_NmtValid       : in    std_logic                      := '0';
        ErrInj_LinkTxDominant : in    std_logic_vector(1 downto 0)   := "00";
        ErrInj_LinkStopFlip   : in    std_logic_vector(1 downto 0)   := "00"
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of ocan_core is

    -- The SDO server exists in the clause 6 slave (D3), the time block unless the minimal set has no time PDOs
    -- (architecture, section 4)
    constant SdoServer_c : boolean := not MinimalSet_g;
    constant TimeBlock_c : boolean := TimePdos_g or not MinimalSet_g;

    -- Reset and tick
    signal RstSync    : std_logic;
    signal Tick       : std_logic;
    -- ocan_nmt
    signal NodeId     : std_logic_vector(6 downto 0);
    signal IdValid    : std_logic;
    signal EnaSdo     : std_logic;
    signal EnaPdo     : std_logic;
    signal EnaSync    : std_logic;
    signal NmtState   : std_logic_vector(1 downto 0);
    signal ResetApp   : std_logic;
    signal ResetComm  : std_logic;
    signal NmtValid   : std_logic;
    signal NmtCs      : std_logic_vector(7 downto 0);
    signal NmtTxValid : std_logic;
    signal NmtTxReady : std_logic;
    signal NmtTxData  : std_logic_vector(7 downto 0);
    signal NmtTxDone  : std_logic;
    signal NmtTxAbt   : std_logic;
    -- ocan_redundancy
    signal ReqBus     : std_logic;
    signal ActBus     : std_logic;
    signal Selecting  : std_logic;
    signal PreopReq   : std_logic;
    signal Switched   : std_logic;
    signal Ctoggle    : std_logic_vector(7 downto 0);
    signal UpdValid   : std_logic;
    signal UpdBdef    : std_logic;
    signal RedNmt     : std_logic_vector(1 downto 0);
    signal RedHb      : std_logic_vector(1 downto 0);
    signal RedHbDlc   : std_logic_vector(7 downto 0);
    signal RedHbState : std_logic_vector(15 downto 0);
    -- ocan_od
    signal CobId      : std_logic_vector(143 downto 0);
    signal CobIdCopy  : std_logic_vector(143 downto 0);
    signal HbTime     : std_logic_vector(15 downto 0);
    signal MasterHb   : std_logic_vector(15 downto 0);
    signal Bdefault   : std_logic;
    signal Ttoggle    : std_logic_vector(7 downto 0);
    signal Ntoggle    : std_logic_vector(7 downto 0);
    signal CtogWr     : std_logic_vector(7 downto 0);
    signal CtogWrV    : std_logic;
    signal SctType    : std_logic_vector(7 downto 0);
    signal LtpType    : std_logic_vector(7 downto 0);
    signal SetValid   : std_logic;
    signal SetScet    : std_logic_vector(55 downto 0);
    signal Scet       : std_logic_vector(55 downto 0);
    signal RpdoType   : std_logic_vector(31 downto 0);
    signal TpdoType   : std_logic_vector(31 downto 0);
    signal LinkState  : std_logic_vector(1 downto 0);
    -- Access interface between ocan_sdo and ocan_od
    signal AccValid   : std_logic;
    signal AccReady   : std_logic;
    signal AccWrite   : std_logic;
    signal AccIndex   : std_logic_vector(15 downto 0);
    signal AccSub     : std_logic_vector(7 downto 0);
    signal AccData    : std_logic_vector(63 downto 0);
    signal AccLen     : std_logic_vector(3 downto 0);
    signal RspValid   : std_logic;
    signal RspData    : std_logic_vector(63 downto 0);
    signal RspLen     : std_logic_vector(3 downto 0);
    signal RspAbort   : std_logic_vector(31 downto 0);
    -- ocan_dispatch to and from the protocol blocks
    signal SyncValid  : std_logic;
    signal SyncDlc    : std_logic_vector(3 downto 0);
    signal RpValid    : std_logic;
    signal RpNum      : std_logic_vector(1 downto 0);
    signal RpDlc      : std_logic_vector(3 downto 0);
    signal RpData     : std_logic_vector(63 downto 0);
    signal TmValid    : std_logic;
    signal TmDlc      : std_logic_vector(3 downto 0);
    signal TmData     : std_logic_vector(63 downto 0);
    signal SdValid    : std_logic;
    signal SdDlc      : std_logic_vector(3 downto 0);
    signal SdData     : std_logic_vector(63 downto 0);
    signal TpValid    : std_logic_vector(3 downto 0);
    signal TpReady    : std_logic_vector(3 downto 0);
    signal TpDlc      : std_logic_vector(15 downto 0);
    signal TpData     : std_logic_vector(255 downto 0);
    signal TpDone     : std_logic_vector(3 downto 0);
    signal TpAborted  : std_logic_vector(3 downto 0);
    signal LtValid    : std_logic;
    signal LtReady    : std_logic;
    signal LtDlc      : std_logic_vector(3 downto 0);
    signal LtData     : std_logic_vector(63 downto 0);
    signal LtDone     : std_logic;
    signal LtAborted  : std_logic;
    signal SrValid    : std_logic;
    signal SrReady    : std_logic;
    signal SrDlc      : std_logic_vector(3 downto 0);
    signal SrData     : std_logic_vector(63 downto 0);
    signal SrDone     : std_logic;
    signal SrAborted  : std_logic;
    -- ocan_link
    signal LkEnable   : std_logic;
    signal LkSwitch   : std_logic;
    signal LkActive   : std_logic;
    signal LkState    : std_logic_vector(3 downto 0);
    signal LkValid    : std_logic;
    signal LkReady    : std_logic;
    signal LkId       : std_logic_vector(28 downto 0);
    signal LkDlc      : std_logic_vector(3 downto 0);
    signal LkData     : std_logic_vector(63 downto 0);
    signal LkAbort    : std_logic;
    signal LkDone     : std_logic;
    signal LkAborted  : std_logic;
    signal LkStopped  : std_logic;
    signal LkRxValid  : std_logic_vector(1 downto 0);
    signal LkRxId     : std_logic_vector(57 downto 0);
    signal LkRxIde    : std_logic_vector(1 downto 0);
    signal LkRxRtr    : std_logic_vector(1 downto 0);
    signal LkRxDlc    : std_logic_vector(7 downto 0);
    signal LkRxData   : std_logic_vector(127 downto 0);
    -- Constant inputs as signals (no expressions as actuals)
    signal Zero       : std_logic := '0';

begin

    -----------------------------------------------------------------------------------------------
    -- Reset release and millisecond tick (CO-1, CO-2)
    -----------------------------------------------------------------------------------------------
    i_reset : entity olo.olo_base_reset_gen
        generic map (
            RstPulseCycles_g => 3,
            RstInPolarity_g  => '1',
            SyncStages_g     => SyncStages_g,
            SyncTmr_g        => true
        )
        port map (
            Clk    => Clk,
            RstOut => RstSync,
            RstIn  => Rst
        );

    i_tick : entity olo.olo_base_strobe_gen
        generic map (
            FreqClkHz_g    => real(ClkFrequency_g),
            FreqStrobeHz_g => 1.0e3
        )
        port map (
            Clk       => Clk,
            Rst       => RstSync,
            Out_Valid => Tick
        );

    -----------------------------------------------------------------------------------------------
    -- Link (CO-CN-02, CO-CN-03)
    -----------------------------------------------------------------------------------------------
    -- The controllers take part in the buses while the enable input is set and the NODE-ID is valid (CO-IF-04)
    LkEnable <= Ctrl_Enable and IdValid;

    -- Fault confinement state of the controller of the active bus (CO-CN-03): controller 0 with selective bus
    -- access, the controller of the active bus with parallel bus access
    g_state_sel : if BusAccess_g = "Selective" generate
        LinkState <= LkState(1 downto 0);
    end generate;

    g_state_par : if BusAccess_g /= "Selective" generate
        LinkState <= LkState(3 downto 2) when LkActive = '1' else LkState(1 downto 0);
    end generate;

    Stat_LinkState     <= LkState;
    Stat_LinkSwitching <= LkSwitch;

    i_link : entity work.ocan_link
        generic map (
            BusAccess_g     => BusAccess_g,
            SyncStages_g    => SyncStages_g,
            AutoRecover_g   => AutoRecover_g,
            DominantLimit_g => DominantLimit_g
        )
        port map (
            Clk               => Clk,
            Rst               => RstSync,
            Ctrl_Enable       => LkEnable,
            Ctrl_Bus          => ReqBus,
            Ctrl_Recover      => Ctrl_Recover,
            Ctrl_Reenable     => Ctrl_Reenable,
            Cfg_Prescaler     => Cfg_Prescaler,
            Cfg_Tseg1         => Cfg_Tseg1,
            Cfg_Tseg2         => Cfg_Tseg2,
            Cfg_Sjw           => Cfg_Sjw,
            Tx_Valid          => LkValid,
            Tx_Ready          => LkReady,
            Tx_Id             => LkId,
            Tx_Ide            => Zero,
            Tx_Rtr            => Zero,
            Tx_Dlc            => LkDlc,
            Tx_Data           => LkData,
            Tx_Abort          => LkAbort,
            Tx_Done           => LkDone,
            Tx_Aborted        => LkAborted,
            Tx_ArbLost        => Evt_LinkArbLost,
            Tx_Stopped        => LkStopped,
            Rx_Valid          => LkRxValid,
            Rx_Id             => LkRxId,
            Rx_Ide            => LkRxIde,
            Rx_Rtr            => LkRxRtr,
            Rx_Dlc            => LkRxDlc,
            Rx_Data           => LkRxData,
            Stat_ActiveBus    => LkActive,
            Stat_Switching    => LkSwitch,
            Stat_Tec          => Stat_LinkTec,
            Stat_Rec          => Stat_LinkRec,
            Stat_State        => LkState,
            Stat_BusIdle      => Stat_LinkBusIdle,
            Stat_DomTimeout   => Stat_LinkDomTimeout,
            Err_Bit           => Err_LinkBit,
            Err_Stuff         => Err_LinkStuff,
            Err_Crc           => Err_LinkCrc,
            Err_Form          => Err_LinkForm,
            Err_Ack           => Err_LinkAck,
            Err_DomTimeout    => Err_LinkDomTimeout,
            ErrInj_TxDominant => ErrInj_LinkTxDominant,
            ErrInj_StopFlip   => ErrInj_LinkStopFlip,
            Can_Tx            => Can_Tx,
            Can_TxEn          => Can_TxEn,
            Can_Rx            => Can_Rx
        );

    -----------------------------------------------------------------------------------------------
    -- Dispatch
    -----------------------------------------------------------------------------------------------
    i_dispatch : entity work.ocan_dispatch
        generic map (
            NumRpdo_g   => NumRpdo_g,
            NumTpdo_g   => NumTpdo_g,
            TimePdos_g  => TimePdos_g,
            SdoServer_g => SdoServer_c
        )
        port map (
            Clk                => Clk,
            Rst                => RstSync,
            LinkRx_Valid       => LkRxValid,
            LinkRx_Id          => LkRxId,
            LinkRx_Ide         => LkRxIde,
            LinkRx_Rtr         => LkRxRtr,
            LinkRx_Dlc         => LkRxDlc,
            LinkRx_Data        => LkRxData,
            LinkTx_Valid       => LkValid,
            LinkTx_Ready       => LkReady,
            LinkTx_Id          => LkId,
            LinkTx_Dlc         => LkDlc,
            LinkTx_Data        => LkData,
            LinkTx_Abort       => LkAbort,
            LinkTx_Done        => LkDone,
            LinkTx_Aborted     => LkAborted,
            LinkTx_Stopped     => LkStopped,
            Red_ActiveBus      => ActBus,
            Red_Selecting      => Selecting,
            Nmt_NodeId         => NodeId,
            Nmt_NodeIdValid    => IdValid,
            Nmt_EnaSdo         => EnaSdo,
            Nmt_EnaPdo         => EnaPdo,
            Nmt_EnaSync        => EnaSync,
            Cfg_CobId          => CobId,
            Cfg_CobIdCopy      => CobIdCopy,
            RxNmt_Valid        => NmtValid,
            RxNmt_Cs           => NmtCs,
            RxSync_Valid       => SyncValid,
            RxSync_Dlc         => SyncDlc,
            RxSync_Data        => open,
            RxRpdo_Valid       => RpValid,
            RxRpdo_Num         => RpNum,
            RxRpdo_Dlc         => RpDlc,
            RxRpdo_Data        => RpData,
            RxTime_Valid       => TmValid,
            RxTime_Dlc         => TmDlc,
            RxTime_Data        => TmData,
            RxSdo_Valid        => SdValid,
            RxSdo_Dlc          => SdDlc,
            RxSdo_Data         => SdData,
            RxRed_NmtValid     => RedNmt,
            RxRed_HbValid      => RedHb,
            RxRed_HbDlc        => RedHbDlc,
            RxRed_HbState      => RedHbState,
            TxTpdo_Valid       => TpValid,
            TxTpdo_Ready       => TpReady,
            TxTpdo_Dlc         => TpDlc,
            TxTpdo_Data        => TpData,
            TxTpdo_Done        => TpDone,
            TxTpdo_Aborted     => TpAborted,
            TxTime_Valid       => LtValid,
            TxTime_Ready       => LtReady,
            TxTime_Dlc         => LtDlc,
            TxTime_Data        => LtData,
            TxTime_Done        => LtDone,
            TxTime_Aborted     => LtAborted,
            TxSdo_Valid        => SrValid,
            TxSdo_Ready        => SrReady,
            TxSdo_Dlc          => SrDlc,
            TxSdo_Data         => SrData,
            TxSdo_Done         => SrDone,
            TxSdo_Aborted      => SrAborted,
            TxNmt_Valid        => NmtTxValid,
            TxNmt_Ready        => NmtTxReady,
            TxNmt_Data         => NmtTxData,
            TxNmt_Done         => NmtTxDone,
            TxNmt_Aborted      => NmtTxAbt,
            Err_Protocol       => Err_Protocol,
            Err_CobId          => Err_CobId,
            Stat_CobIdMismatch => Stat_CobIdMismatch
        );

    -----------------------------------------------------------------------------------------------
    -- Network management and bus redundancy
    -----------------------------------------------------------------------------------------------
    Node_Id       <= NodeId;
    Node_IdValid  <= IdValid;
    Stat_NmtState <= NmtState;
    Evt_ResetApp  <= ResetApp;
    Evt_ResetComm <= ResetComm;

    i_nmt : entity work.ocan_nmt
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => Clk,
            Rst            => RstSync,
            Pin_NodeId     => Pin_NodeId,
            Pin_NodeIdCode => Pin_NodeIdCode,
            Tick_Ms        => Tick,
            Cfg_HbTime     => HbTime,
            Rx_Valid       => NmtValid,
            Rx_Cs          => NmtCs,
            Tx_Valid       => NmtTxValid,
            Tx_Ready       => NmtTxReady,
            Tx_Data        => NmtTxData,
            Tx_Done        => NmtTxDone,
            Tx_Aborted     => NmtTxAbt,
            Node_Id        => NodeId,
            Node_IdValid   => IdValid,
            Ena_Sdo        => EnaSdo,
            Ena_Pdo        => EnaPdo,
            Ena_Sync       => EnaSync,
            Red_PreopReq   => PreopReq,
            Red_Switched   => Switched,
            Red_Selecting  => Selecting,
            Stat_State     => NmtState,
            Reset_App      => ResetApp,
            Reset_Comm     => ResetComm,
            Err_Cs         => Err_NmtCs,
            Err_NodeId     => Err_NodeId,
            Err_TxTimeout  => Err_NmtTxTimeout,
            ErrInj_BitFlip => ErrInj_NmtBitFlip,
            ErrInj_Valid   => ErrInj_NmtValid
        );

    Stat_ActiveBus     <= ActBus;
    Stat_Selecting     <= Selecting;
    Stat_Ctoggle       <= Ctoggle;
    Evt_BdefaultUpdate <= UpdValid;

    i_redundancy : entity work.ocan_redundancy
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => Clk,
            Rst            => RstSync,
            Tick_Ms        => Tick,
            Rx_NmtValid    => RedNmt,
            Rx_HbValid     => RedHb,
            Rx_HbDlc       => RedHbDlc,
            Rx_HbState     => RedHbState,
            Cfg_HbTime     => MasterHb,
            Cfg_Bdefault   => Bdefault,
            Cfg_Ttoggle    => Ttoggle,
            Cfg_Ntoggle    => Ntoggle,
            Cfg_CtoggleWr  => CtogWrV,
            Cfg_Ctoggle    => CtogWr,
            Upd_Valid      => UpdValid,
            Upd_Bdefault   => UpdBdef,
            Link_Bus       => ReqBus,
            Link_ActiveBus => LkActive,
            Link_Switching => LkSwitch,
            Nmt_State      => NmtState,
            Nmt_PreopReq   => PreopReq,
            Nmt_Switched   => Switched,
            Stat_ActiveBus => ActBus,
            Stat_Selecting => Selecting,
            Stat_Ctoggle   => Ctoggle,
            Stat_HbState   => Stat_MasterHbState,
            Stat_HbPresent => Stat_MasterHbPresent,
            Err_HbMissing  => Err_MasterHbMissing,
            Err_ToggleEnd  => Err_ToggleEnd,
            Err_HbDlc      => Err_MasterHbDlc
        );

    -----------------------------------------------------------------------------------------------
    -- Object dictionary
    -----------------------------------------------------------------------------------------------
    i_od : entity work.ocan_od
        generic map (
            MinimalSet_g     => MinimalSet_g,
            NumRpdo_g        => NumRpdo_g,
            NumTpdo_g        => NumTpdo_g,
            TimePdos_g       => TimePdos_g,
            DeviceType_g     => DeviceType_g,
            VendorId_g       => VendorId_g,
            ProductCode_g    => ProductCode_g,
            Revision_g       => Revision_g,
            SerialNumber_g   => SerialNumber_g,
            ProducerHbTime_g => ProducerHbTime_g,
            MasterNodeId_g   => MasterNodeId_g,
            MasterHbTime_g   => MasterHbTime_g,
            Bdefault_g       => Bdefault_g,
            Ttoggle_g        => Ttoggle_g,
            Ntoggle_g        => Ntoggle_g,
            RpdoType_g       => RpdoType_g,
            TpdoType_g       => TpdoType_g,
            SctCobId_g       => SctCobId_g,
            SctType_g        => SctType_g,
            LtpCobId_g       => LtpCobId_g,
            LtpType_g        => LtpType_g
        )
        port map (
            Clk              => Clk,
            Rst              => RstSync,
            Tick_Ms          => Tick,
            Acc_Valid        => AccValid,
            Acc_Ready        => AccReady,
            Acc_Write        => AccWrite,
            Acc_Index        => AccIndex,
            Acc_Sub          => AccSub,
            Acc_Data         => AccData,
            Acc_Len          => AccLen,
            Rsp_Valid        => RspValid,
            Rsp_Data         => RspData,
            Rsp_Len          => RspLen,
            Rsp_Abort        => RspAbort,
            Nmt_State        => NmtState,
            Nmt_NodeId       => NodeId,
            Nmt_ResetApp     => ResetApp,
            Nmt_ResetComm    => ResetComm,
            Cfg_CobId        => CobId,
            Cfg_CobIdCopy    => CobIdCopy,
            Cfg_HbTime       => HbTime,
            Cfg_MasterHbTime => MasterHb,
            Cfg_Bdefault     => Bdefault,
            Cfg_Ttoggle      => Ttoggle,
            Cfg_Ntoggle      => Ntoggle,
            Cfg_Ctoggle      => CtogWr,
            Cfg_CtoggleValid => CtogWrV,
            Stat_Ctoggle     => Ctoggle,
            Upd_Valid        => UpdValid,
            Upd_Bdefault     => UpdBdef,
            Cfg_SctType      => SctType,
            Cfg_LtpType      => LtpType,
            Cfg_SetValid     => SetValid,
            Cfg_SetScet      => SetScet,
            Stat_Scet        => Scet,
            Cfg_RpdoType     => RpdoType,
            Cfg_TpdoType     => TpdoType,
            Link_State       => LinkState,
            App_ReqValid     => App_ReqValid,
            App_ReqReady     => App_ReqReady,
            App_ReqWrite     => App_ReqWrite,
            App_ReqIndex     => App_ReqIndex,
            App_ReqSub       => App_ReqSub,
            App_ReqData      => App_ReqData,
            App_ReqLen       => App_ReqLen,
            App_RspValid     => App_RspValid,
            App_RspData      => App_RspData,
            App_RspLen       => App_RspLen,
            App_RspAbort     => App_RspAbort,
            Stat_ErrReg      => Stat_ErrReg,
            Err_ParamCopy    => Err_ParamCopy,
            Err_AppTimeout   => Err_AppTimeout,
            ErrInj_BitFlip   => ErrInj_OdBitFlip,
            ErrInj_Valid     => ErrInj_OdValid
        );

    -----------------------------------------------------------------------------------------------
    -- SDO server (CO-CN-04): absent with the minimal set
    -----------------------------------------------------------------------------------------------
    g_sdo : if SdoServer_c generate

        i_sdo : entity work.ocan_sdo
            port map (
                Clk            => Clk,
                Rst            => RstSync,
                Tick_Ms        => Tick,
                Rx_Valid       => SdValid,
                Rx_Dlc         => SdDlc,
                Rx_Data        => SdData,
                Tx_Valid       => SrValid,
                Tx_Ready       => SrReady,
                Tx_Dlc         => SrDlc,
                Tx_Data        => SrData,
                Tx_Done        => SrDone,
                Tx_Aborted     => SrAborted,
                Acc_Valid      => AccValid,
                Acc_Ready      => AccReady,
                Acc_Write      => AccWrite,
                Acc_Index      => AccIndex,
                Acc_Sub        => AccSub,
                Acc_Data       => AccData,
                Acc_Len        => AccLen,
                Rsp_Valid      => RspValid,
                Rsp_Data       => RspData,
                Rsp_Len        => RspLen,
                Rsp_Abort      => RspAbort,
                Nmt_EnaSdo     => EnaSdo,
                Nmt_ResetApp   => ResetApp,
                Nmt_ResetComm  => ResetComm,
                Stat_Open      => Stat_SdoOpen,
                Err_RxDrop     => Err_SdoRxDrop,
                Err_TxTimeout  => Err_SdoTxTimeout,
                Err_AccTimeout => Err_SdoAccTimeout,
                Evt_AbortTx    => Evt_SdoAbortTx,
                Evt_AbortRx    => Evt_SdoAbortRx
            );

    end generate;

    g_no_sdo : if not SdoServer_c generate
        SrValid           <= '0';
        SrDlc             <= (others => '0');
        SrData            <= (others => '0');
        AccValid          <= '0';
        AccWrite          <= '0';
        AccIndex          <= (others => '0');
        AccSub            <= (others => '0');
        AccData           <= (others => '0');
        AccLen            <= (others => '0');
        Stat_SdoOpen      <= '0';
        Err_SdoRxDrop     <= '0';
        Err_SdoTxTimeout  <= '0';
        Err_SdoAccTimeout <= '0';
        Evt_SdoAbortTx    <= '0';
        Evt_SdoAbortRx    <= '0';
    end generate;

    -----------------------------------------------------------------------------------------------
    -- PDO block
    -----------------------------------------------------------------------------------------------
    i_pdo : entity work.ocan_pdo
        generic map (
            NumRpdo_g => NumRpdo_g,
            NumTpdo_g => NumTpdo_g
        )
        port map (
            Clk             => Clk,
            Rst             => RstSync,
            Tick_Ms         => Tick,
            RxSync_Valid    => SyncValid,
            RxSync_Dlc      => SyncDlc,
            RxRpdo_Valid    => RpValid,
            RxRpdo_Num      => RpNum,
            RxRpdo_Dlc      => RpDlc,
            RxRpdo_Data     => RpData,
            TxTpdo_Valid    => TpValid,
            TxTpdo_Ready    => TpReady,
            TxTpdo_Dlc      => TpDlc,
            TxTpdo_Data     => TpData,
            TxTpdo_Done     => TpDone,
            TxTpdo_Aborted  => TpAborted,
            Cfg_RpdoType    => RpdoType,
            Cfg_TpdoType    => TpdoType,
            Nmt_EnaPdo      => EnaPdo,
            Nmt_ResetComm   => ResetComm,
            Sync_Valid      => Sync_Valid,
            Rpdo_Valid      => Rpdo_Valid,
            Rpdo_Data       => Rpdo_Data,
            Tpdo_Req        => Tpdo_Req,
            Tpdo_Data       => Tpdo_Data,
            Stat_TpdoBusy   => Stat_TpdoBusy,
            Stat_PdoEnabled => Stat_PdoEnabled,
            Evt_TpdoSent    => Evt_TpdoSent,
            Evt_TpdoAborted => Evt_TpdoAborted,
            Err_RxLength    => Err_RpdoLength,
            Err_TxBusy      => Err_TpdoBusy,
            Err_TxTimeout   => Err_TpdoTimeout
        );

    -----------------------------------------------------------------------------------------------
    -- Time block (CO-CN-04): without the time PDOs the Spacecraft Time PDO input is idle and no Local Time PDO is
    -- requested; absent in the minimal set without the time PDOs
    -----------------------------------------------------------------------------------------------
    g_time : if TimeBlock_c generate
        signal TimeRxValid : std_logic;
        signal TimeTxType  : std_logic_vector(7 downto 0);
        signal TimeReq     : std_logic;
    begin
        TimeRxValid <= TmValid when TimePdos_g else '0';
        TimeTxType  <= LtpType when TimePdos_g else x"FE";
        TimeReq     <= Time_Req when TimePdos_g else '0';

        i_time : entity work.ocan_time
            generic map (
                ClkFrequency_g => ClkFrequency_g,
                FineBits_g     => FineBits_g
            )
            port map (
                Clk           => Clk,
                Rst           => RstSync,
                Tick_Ms       => Tick,
                Rx_SyncValid  => SyncValid,
                Rx_SyncDlc    => SyncDlc,
                Rx_TimeValid  => TimeRxValid,
                Rx_TimeDlc    => TmDlc,
                Rx_TimeData   => TmData,
                Tx_Valid      => LtValid,
                Tx_Ready      => LtReady,
                Tx_Dlc        => LtDlc,
                Tx_Data       => LtData,
                Tx_Done       => LtDone,
                Tx_Aborted    => LtAborted,
                Cfg_RxType    => SctType,
                Cfg_TxType    => TimeTxType,
                Cfg_SetValid  => SetValid,
                Cfg_SetScet   => SetScet,
                Stat_Scet     => Scet,
                Nmt_ResetComm => ResetComm,
                Req_Valid     => TimeReq,
                Time_Coarse   => Time_Coarse,
                Time_Fine     => Time_Fine,
                Stat_TimeSet  => Stat_TimeSet,
                Evt_Set       => Evt_TimeSet,
                Evt_Sync      => Evt_TimeSync,
                Err_TxBusy    => Err_TimeTxBusy,
                Err_RxDrop    => Err_TimeRxDrop,
                Err_TxTimeout => Err_TimeTxTimeout
            );

    end generate;

    g_no_time : if not TimeBlock_c generate
        LtValid           <= '0';
        LtDlc             <= (others => '0');
        LtData            <= (others => '0');
        Scet              <= (others => '0');
        Time_Coarse       <= (others => '0');
        Time_Fine         <= (others => '0');
        Stat_TimeSet      <= '0';
        Evt_TimeSet       <= '0';
        Evt_TimeSync      <= '0';
        Err_TimeTxBusy    <= '0';
        Err_TimeRxDrop    <= '0';
        Err_TimeTxTimeout <= '0';
    end generate;

end architecture;
