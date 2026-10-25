---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Top level of OpenCAN for a processor system: ocan_core with the register interface ocan_mib on an AXI4-Lite
-- slave (decision D6 of the architecture).
--
-- Documentation: hdl/ocan_axi/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_axi is
    generic (
        -- ocan_core
        BusAccess_g      : string                                 := "Selective";
        SyncStages_g     : positive range 2 to 4                  := 2;
        AutoRecover_g    : boolean                                := true;
        DominantLimit_g  : positive range 13 to 1023              := 32;
        MinimalSet_g     : boolean                                := false;
        NumRpdo_g        : natural range 0 to 4                   := 4;
        NumTpdo_g        : natural range 0 to 4                   := 4;
        TimePdos_g       : boolean                                := true;
        ClkFrequency_g   : positive range 1000000 to integer'high := 100000000;
        FineBits_g       : natural range 0 to 24                  := 24;
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
        LtpType_g        : natural range 0 to 255                 := 254;
        -- ocan_mib: reset values of CONTROL.ENABLE and BIT_TIMING, error injection registers
        AutoEnable_g     : boolean                                := true;
        Prescaler_g      : positive range 1 to 1023               := 4;
        Tseg1_g          : natural range 2 to 31                  := 18;
        Tseg2_g          : natural range 2 to 15                  := 6;
        Sjw_g            : natural range 1 to 4                   := 4;
        ErrInjRegs_g     : boolean                                := false
    );
    port (
        -- Control
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- AXI4-Lite slave (9-bit byte addresses)
        S_AxiLite_ArAddr  : in    std_logic_vector(8 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(8 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        -- Interrupt
        Irq               : out   std_logic;
        -- NODE-ID pins and their complement
        Pin_NodeId        : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode    : in    std_logic_vector(6 downto 0);
        -- Transceivers of bus A (index 0) and bus B (index 1)
        Can_Tx            : out   std_logic_vector(1 downto 0);
        Can_TxEn          : out   std_logic_vector(1 downto 0);
        Can_Rx            : in    std_logic_vector(1 downto 0) := "11"
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_axi is

    -- Synchronous reset of the register interface
    signal RstSync : std_logic;

    -- Ports of ocan_core towards the register interface
    signal Ctrl_Enable           : std_logic;
    signal Ctrl_Recover          : std_logic;
    signal Ctrl_Reenable         : std_logic_vector(1 downto 0);
    signal Cfg_Prescaler         : std_logic_vector(9 downto 0);
    signal Cfg_Tseg1             : std_logic_vector(4 downto 0);
    signal Cfg_Tseg2             : std_logic_vector(3 downto 0);
    signal Cfg_Sjw               : std_logic_vector(2 downto 0);
    signal Node_Id               : std_logic_vector(6 downto 0);
    signal Node_IdValid          : std_logic;
    signal Sync_Valid            : std_logic;
    signal Rpdo_Valid            : std_logic_vector(3 downto 0);
    signal Rpdo_Data             : std_logic_vector(255 downto 0);
    signal Tpdo_Req              : std_logic_vector(3 downto 0);
    signal Tpdo_Data             : std_logic_vector(255 downto 0);
    signal Stat_TpdoBusy         : std_logic_vector(3 downto 0);
    signal Stat_PdoEnabled       : std_logic;
    signal Evt_TpdoSent          : std_logic_vector(3 downto 0);
    signal Evt_TpdoAborted       : std_logic_vector(3 downto 0);
    signal Err_RpdoLength        : std_logic_vector(3 downto 0);
    signal Err_TpdoBusy          : std_logic_vector(3 downto 0);
    signal Err_TpdoTimeout       : std_logic_vector(3 downto 0);
    signal App_ReqValid          : std_logic;
    signal App_ReqReady          : std_logic;
    signal App_ReqWrite          : std_logic;
    signal App_ReqIndex          : std_logic_vector(15 downto 0);
    signal App_ReqSub            : std_logic_vector(7 downto 0);
    signal App_ReqData           : std_logic_vector(63 downto 0);
    signal App_ReqLen            : std_logic_vector(3 downto 0);
    signal App_RspValid          : std_logic;
    signal App_RspData           : std_logic_vector(63 downto 0);
    signal App_RspLen            : std_logic_vector(3 downto 0);
    signal App_RspAbort          : std_logic_vector(31 downto 0);
    signal Time_Coarse           : std_logic_vector(31 downto 0);
    signal Time_Fine             : std_logic_vector(23 downto 0);
    signal Time_Req              : std_logic;
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
    signal ErrInj_OdBitFlip      : std_logic_vector(557 downto 0);
    signal ErrInj_OdValid        : std_logic;
    signal ErrInj_NmtBitFlip     : std_logic_vector(13 downto 0);
    signal ErrInj_NmtValid       : std_logic;
    signal ErrInj_LinkTxDominant : std_logic_vector(1 downto 0);
    signal ErrInj_LinkStopFlip   : std_logic_vector(1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Reset of the register interface: the release synchronised with triplicated synchronisers
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

    -----------------------------------------------------------------------------------------------
    -- Core
    -----------------------------------------------------------------------------------------------
    i_core : entity work.ocan_core
        generic map (
            BusAccess_g      => BusAccess_g,
            SyncStages_g     => SyncStages_g,
            AutoRecover_g    => AutoRecover_g,
            DominantLimit_g  => DominantLimit_g,
            MinimalSet_g     => MinimalSet_g,
            NumRpdo_g        => NumRpdo_g,
            NumTpdo_g        => NumTpdo_g,
            TimePdos_g       => TimePdos_g,
            ClkFrequency_g   => ClkFrequency_g,
            FineBits_g       => FineBits_g,
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
            Can_Tx                => Can_Tx,
            Can_TxEn              => Can_TxEn,
            Can_Rx                => Can_Rx,
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
            ErrInj_LinkStopFlip   => ErrInj_LinkStopFlip
        );

    -----------------------------------------------------------------------------------------------
    -- Register interface
    -----------------------------------------------------------------------------------------------
    i_mib : entity work.ocan_mib
        generic map (
            BusAccess_g      => BusAccess_g,
            MinimalSet_g     => MinimalSet_g,
            TimePdos_g       => TimePdos_g,
            AutoRecover_g    => AutoRecover_g,
            NumRpdo_g        => NumRpdo_g,
            NumTpdo_g        => NumTpdo_g,
            FineBits_g       => FineBits_g,
            SyncStages_g     => SyncStages_g,
            DominantLimit_g  => DominantLimit_g,
            ClkFrequency_g   => ClkFrequency_g,
            AutoEnable_g     => AutoEnable_g,
            Prescaler_g      => Prescaler_g,
            Tseg1_g          => Tseg1_g,
            Tseg2_g          => Tseg2_g,
            Sjw_g            => Sjw_g,
            ErrInjRegs_g     => ErrInjRegs_g
        )
        port map (
            Clk                   => Clk,
            Rst                   => RstSync,
            S_AxiLite_ArAddr      => S_AxiLite_ArAddr,
            S_AxiLite_ArValid     => S_AxiLite_ArValid,
            S_AxiLite_ArReady     => S_AxiLite_ArReady,
            S_AxiLite_AwAddr      => S_AxiLite_AwAddr,
            S_AxiLite_AwValid     => S_AxiLite_AwValid,
            S_AxiLite_AwReady     => S_AxiLite_AwReady,
            S_AxiLite_WData       => S_AxiLite_WData,
            S_AxiLite_WStrb       => S_AxiLite_WStrb,
            S_AxiLite_WValid      => S_AxiLite_WValid,
            S_AxiLite_WReady      => S_AxiLite_WReady,
            S_AxiLite_BResp       => S_AxiLite_BResp,
            S_AxiLite_BValid      => S_AxiLite_BValid,
            S_AxiLite_BReady      => S_AxiLite_BReady,
            S_AxiLite_RData       => S_AxiLite_RData,
            S_AxiLite_RResp       => S_AxiLite_RResp,
            S_AxiLite_RValid      => S_AxiLite_RValid,
            S_AxiLite_RReady      => S_AxiLite_RReady,
            Irq                   => Irq,
            Ctrl_Enable           => Ctrl_Enable,
            Ctrl_Recover          => Ctrl_Recover,
            Ctrl_Reenable         => Ctrl_Reenable,
            Cfg_Prescaler         => Cfg_Prescaler,
            Cfg_Tseg1             => Cfg_Tseg1,
            Cfg_Tseg2             => Cfg_Tseg2,
            Cfg_Sjw               => Cfg_Sjw,
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
            ErrInj_LinkStopFlip   => ErrInj_LinkStopFlip
        );

end architecture;
