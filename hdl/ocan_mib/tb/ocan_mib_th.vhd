---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_mib: the clock, ocan_mib and the AXI-Lite VVC master; the AXI4-Lite
-- channel is also an output, for the reference model of the testbench.
--
-- Documentation: hdl/ocan_mib/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ocan_tb_axi_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_mib_th is
    generic (
        BusAccess_g     : string                                 := "Selective";
        MinimalSet_g    : boolean                                := false;
        TimePdos_g      : boolean                                := true;
        AutoRecover_g   : boolean                                := true;
        NumRpdo_g       : natural range 0 to 4                   := 4;
        NumTpdo_g       : natural range 0 to 4                   := 4;
        FineBits_g      : natural range 0 to 24                  := 24;
        SyncStages_g    : positive range 2 to 4                  := 2;
        DominantLimit_g : positive range 13 to 1023              := 32;
        ClkFrequency_g  : positive range 1000000 to integer'high := 100000000;
        AutoEnable_g    : boolean                                := true;
        Prescaler_g     : positive range 1 to 1023               := 4;
        Tseg1_g         : natural range 2 to 31                  := 18;
        Tseg2_g         : natural range 2 to 15                  := 6;
        Sjw_g           : natural range 1 to 4                   := 4;
        ErrInjRegs_g    : boolean                                := false
    );
    port (
        Clk                   : out   std_logic;
        Rst                   : in    std_logic;
        Irq                   : out   std_logic;
        Ctrl_Enable           : out   std_logic;
        Ctrl_Recover          : out   std_logic;
        Ctrl_Reenable         : out   std_logic_vector(1 downto 0);
        Cfg_Prescaler         : out   std_logic_vector(9 downto 0);
        Cfg_Tseg1             : out   std_logic_vector(4 downto 0);
        Cfg_Tseg2             : out   std_logic_vector(3 downto 0);
        Cfg_Sjw               : out   std_logic_vector(2 downto 0);
        Node_Id               : in    std_logic_vector(6 downto 0);
        Node_IdValid          : in    std_logic;
        Sync_Valid            : in    std_logic;
        Rpdo_Valid            : in    std_logic_vector(3 downto 0);
        Rpdo_Data             : in    std_logic_vector(255 downto 0);
        Tpdo_Req              : out   std_logic_vector(3 downto 0);
        Tpdo_Data             : out   std_logic_vector(255 downto 0);
        Stat_TpdoBusy         : in    std_logic_vector(3 downto 0);
        Stat_PdoEnabled       : in    std_logic;
        Evt_TpdoSent          : in    std_logic_vector(3 downto 0);
        Evt_TpdoAborted       : in    std_logic_vector(3 downto 0);
        Err_RpdoLength        : in    std_logic_vector(3 downto 0);
        Err_TpdoBusy          : in    std_logic_vector(3 downto 0);
        Err_TpdoTimeout       : in    std_logic_vector(3 downto 0);
        App_ReqValid          : in    std_logic;
        App_ReqReady          : out   std_logic;
        App_ReqWrite          : in    std_logic;
        App_ReqIndex          : in    std_logic_vector(15 downto 0);
        App_ReqSub            : in    std_logic_vector(7 downto 0);
        App_ReqData           : in    std_logic_vector(63 downto 0);
        App_ReqLen            : in    std_logic_vector(3 downto 0);
        App_RspValid          : out   std_logic;
        App_RspData           : out   std_logic_vector(63 downto 0);
        App_RspLen            : out   std_logic_vector(3 downto 0);
        App_RspAbort          : out   std_logic_vector(31 downto 0);
        Time_Coarse           : in    std_logic_vector(31 downto 0);
        Time_Fine             : in    std_logic_vector(23 downto 0);
        Time_Req              : out   std_logic;
        Stat_TimeSet          : in    std_logic;
        Evt_TimeSet           : in    std_logic;
        Evt_TimeSync          : in    std_logic;
        Err_TimeTxBusy        : in    std_logic;
        Err_TimeRxDrop        : in    std_logic;
        Err_TimeTxTimeout     : in    std_logic;
        Stat_NmtState         : in    std_logic_vector(1 downto 0);
        Evt_ResetApp          : in    std_logic;
        Evt_ResetComm         : in    std_logic;
        Err_NmtCs             : in    std_logic;
        Err_NodeId            : in    std_logic;
        Err_NmtTxTimeout      : in    std_logic;
        Stat_ActiveBus        : in    std_logic;
        Stat_Selecting        : in    std_logic;
        Stat_Ctoggle          : in    std_logic_vector(7 downto 0);
        Stat_MasterHbState    : in    std_logic_vector(7 downto 0);
        Stat_MasterHbPresent  : in    std_logic_vector(1 downto 0);
        Evt_BdefaultUpdate    : in    std_logic;
        Err_MasterHbMissing   : in    std_logic;
        Err_ToggleEnd         : in    std_logic;
        Err_MasterHbDlc       : in    std_logic;
        Stat_ErrReg           : in    std_logic_vector(7 downto 0);
        Err_ParamCopy         : in    std_logic;
        Err_AppTimeout        : in    std_logic;
        Stat_CobIdMismatch    : in    std_logic_vector(11 downto 0);
        Err_Protocol          : in    std_logic;
        Err_CobId             : in    std_logic;
        Stat_SdoOpen          : in    std_logic;
        Evt_SdoAbortTx        : in    std_logic;
        Evt_SdoAbortRx        : in    std_logic;
        Err_SdoRxDrop         : in    std_logic;
        Err_SdoTxTimeout      : in    std_logic;
        Err_SdoAccTimeout     : in    std_logic;
        Stat_LinkTec          : in    std_logic_vector(17 downto 0);
        Stat_LinkRec          : in    std_logic_vector(15 downto 0);
        Stat_LinkState        : in    std_logic_vector(3 downto 0);
        Stat_LinkBusIdle      : in    std_logic_vector(1 downto 0);
        Stat_LinkDomTimeout   : in    std_logic_vector(1 downto 0);
        Stat_LinkSwitching    : in    std_logic;
        Evt_LinkArbLost       : in    std_logic;
        Err_LinkBit           : in    std_logic_vector(1 downto 0);
        Err_LinkStuff         : in    std_logic_vector(1 downto 0);
        Err_LinkCrc           : in    std_logic_vector(1 downto 0);
        Err_LinkForm          : in    std_logic_vector(1 downto 0);
        Err_LinkAck           : in    std_logic_vector(1 downto 0);
        Err_LinkDomTimeout    : in    std_logic_vector(1 downto 0);
        ErrInj_OdBitFlip      : out   std_logic_vector(557 downto 0);
        ErrInj_OdValid        : out   std_logic;
        ErrInj_NmtBitFlip     : out   std_logic_vector(13 downto 0);
        ErrInj_NmtValid       : out   std_logic;
        ErrInj_LinkTxDominant : out   std_logic_vector(1 downto 0);
        ErrInj_LinkStopFlip   : out   std_logic_vector(1 downto 0);
        Axi_ArAddr            : out   std_logic_vector(8 downto 0);
        Axi_ArValid           : out   std_logic;
        Axi_ArReady           : out   std_logic;
        Axi_AwAddr            : out   std_logic_vector(8 downto 0);
        Axi_AwValid           : out   std_logic;
        Axi_AwReady           : out   std_logic;
        Axi_WData             : out   std_logic_vector(31 downto 0);
        Axi_WStrb             : out   std_logic_vector(3 downto 0);
        Axi_WValid            : out   std_logic;
        Axi_WReady            : out   std_logic;
        Axi_BResp             : out   std_logic_vector(1 downto 0);
        Axi_BValid            : out   std_logic;
        Axi_BReady            : out   std_logic;
        Axi_RData             : out   std_logic_vector(31 downto 0);
        Axi_RResp             : out   std_logic_vector(1 downto 0);
        Axi_RValid            : out   std_logic;
        Axi_RReady            : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_mib_th is

    constant ClkPeriod_c : time := 20 ns;

    signal ClkI      : std_logic := '0';
    signal AxArAddr  : std_logic_vector(8 downto 0);
    signal AxArValid : std_logic;
    signal AxArReady : std_logic;
    signal AxAwAddr  : std_logic_vector(8 downto 0);
    signal AxAwValid : std_logic;
    signal AxAwReady : std_logic;
    signal AxWData   : std_logic_vector(31 downto 0);
    signal AxWStrb   : std_logic_vector(3 downto 0);
    signal AxWValid  : std_logic;
    signal AxWReady  : std_logic;
    signal AxBResp   : std_logic_vector(1 downto 0);
    signal AxBValid  : std_logic;
    signal AxBReady  : std_logic;
    signal AxRData   : std_logic_vector(31 downto 0);
    signal AxRResp   : std_logic_vector(1 downto 0);
    signal AxRValid  : std_logic;
    signal AxRReady  : std_logic;

begin

    ClkI <= not ClkI after ClkPeriod_c / 2;
    Clk  <= ClkI;

    Axi_ArAddr  <= AxArAddr;
    Axi_ArValid <= AxArValid;
    Axi_ArReady <= AxArReady;
    Axi_AwAddr  <= AxAwAddr;
    Axi_AwValid <= AxAwValid;
    Axi_AwReady <= AxAwReady;
    Axi_WData   <= AxWData;
    Axi_WStrb   <= AxWStrb;
    Axi_WValid  <= AxWValid;
    Axi_WReady  <= AxWReady;
    Axi_BResp   <= AxBResp;
    Axi_BValid  <= AxBValid;
    Axi_BReady  <= AxBReady;
    Axi_RData   <= AxRData;
    Axi_RResp   <= AxRResp;
    Axi_RValid  <= AxRValid;
    Axi_RReady  <= AxRReady;

    i_dut : entity work.ocan_mib
        generic map (
            BusAccess_g     => BusAccess_g,
            MinimalSet_g    => MinimalSet_g,
            TimePdos_g      => TimePdos_g,
            AutoRecover_g   => AutoRecover_g,
            NumRpdo_g       => NumRpdo_g,
            NumTpdo_g       => NumTpdo_g,
            FineBits_g      => FineBits_g,
            SyncStages_g    => SyncStages_g,
            DominantLimit_g => DominantLimit_g,
            ClkFrequency_g  => ClkFrequency_g,
            AutoEnable_g    => AutoEnable_g,
            Prescaler_g     => Prescaler_g,
            Tseg1_g         => Tseg1_g,
            Tseg2_g         => Tseg2_g,
            Sjw_g           => Sjw_g,
            ErrInjRegs_g    => ErrInjRegs_g
        )
        port map (
            Clk                   => ClkI,
            Rst                   => Rst,
            S_AxiLite_ArAddr      => AxArAddr,
            S_AxiLite_ArValid     => AxArValid,
            S_AxiLite_ArReady     => AxArReady,
            S_AxiLite_AwAddr      => AxAwAddr,
            S_AxiLite_AwValid     => AxAwValid,
            S_AxiLite_AwReady     => AxAwReady,
            S_AxiLite_WData       => AxWData,
            S_AxiLite_WStrb       => AxWStrb,
            S_AxiLite_WValid      => AxWValid,
            S_AxiLite_WReady      => AxWReady,
            S_AxiLite_BResp       => AxBResp,
            S_AxiLite_BValid      => AxBValid,
            S_AxiLite_BReady      => AxBReady,
            S_AxiLite_RData       => AxRData,
            S_AxiLite_RResp       => AxRResp,
            S_AxiLite_RValid      => AxRValid,
            S_AxiLite_RReady      => AxRReady,
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

    i_axi : entity work.ocan_tb_axilite_master
        generic map (
            InstanceIdx_g => 0,
            AddrWidth_g   => AxiAddrBits_c
        )
        port map (
            Clk     => ClkI,
            ArAddr  => AxArAddr,
            ArValid => AxArValid,
            ArReady => AxArReady,
            AwAddr  => AxAwAddr,
            AwValid => AxAwValid,
            AwReady => AxAwReady,
            WData   => AxWData,
            WStrb   => AxWStrb,
            WValid  => AxWValid,
            WReady  => AxWReady,
            BResp   => AxBResp,
            BValid  => AxBValid,
            BReady  => AxBReady,
            RData   => AxRData,
            RResp   => AxRResp,
            RValid  => AxRValid,
            RReady  => AxRReady
        );

end architecture;
