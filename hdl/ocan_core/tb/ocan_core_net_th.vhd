---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_core: the clock (40 MHz) and ocan_core with the parameters of the
-- verification plan (NODE-ID at the pins from the testbench, 1 Mbit/s from the bit timing ports, master NODE-ID 1
-- with a consumer heartbeat time of 10 ms, a producer heartbeat time of 5 ms, Ttoggle 1, Ntoggle 2, the time PDOs
-- 0F0h and 1F5h with transmission type 1) on the CAN network model with two model nodes on each bus. Every port of
-- the core except the clock and the transceivers passes through to the testbench, together with the force inputs
-- of both buses, the receive disturbance of the core (Bus_DutRec) and the level of both buses (Bus_Level).
--
-- Documentation: hdl/ocan_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_core_net_th is
    generic (
        BusAccess_g  : string               := "Selective";
        MinimalSet_g : boolean              := false;
        TimePdos_g   : boolean              := true;
        NumRpdo_g    : natural range 0 to 4 := 4;
        NumTpdo_g    : natural range 0 to 4 := 4;
        Bdefault_g   : natural range 0 to 1 := 0
    );
    port (
        Clk                   : out   std_logic;
        Rst                   : in    std_logic;
        Ctrl_Enable           : in    std_logic;
        Ctrl_Recover          : in    std_logic;
        Ctrl_Reenable         : in    std_logic_vector(1 downto 0);
        Cfg_Prescaler         : in    std_logic_vector(9 downto 0);
        Cfg_Tseg1             : in    std_logic_vector(4 downto 0);
        Cfg_Tseg2             : in    std_logic_vector(3 downto 0);
        Cfg_Sjw               : in    std_logic_vector(2 downto 0);
        Pin_NodeId            : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode        : in    std_logic_vector(6 downto 0);
        Node_Id               : out   std_logic_vector(6 downto 0);
        Node_IdValid          : out   std_logic;
        Sync_Valid            : out   std_logic;
        Rpdo_Valid            : out   std_logic_vector(3 downto 0);
        Rpdo_Data             : out   std_logic_vector(255 downto 0);
        Tpdo_Req              : in    std_logic_vector(3 downto 0);
        Tpdo_Data             : in    std_logic_vector(255 downto 0);
        Stat_TpdoBusy         : out   std_logic_vector(3 downto 0);
        Stat_PdoEnabled       : out   std_logic;
        Evt_TpdoSent          : out   std_logic_vector(3 downto 0);
        Evt_TpdoAborted       : out   std_logic_vector(3 downto 0);
        Err_RpdoLength        : out   std_logic_vector(3 downto 0);
        Err_TpdoBusy          : out   std_logic_vector(3 downto 0);
        Err_TpdoTimeout       : out   std_logic_vector(3 downto 0);
        App_ReqValid          : out   std_logic;
        App_ReqReady          : in    std_logic;
        App_ReqWrite          : out   std_logic;
        App_ReqIndex          : out   std_logic_vector(15 downto 0);
        App_ReqSub            : out   std_logic_vector(7 downto 0);
        App_ReqData           : out   std_logic_vector(63 downto 0);
        App_ReqLen            : out   std_logic_vector(3 downto 0);
        App_RspValid          : in    std_logic;
        App_RspData           : in    std_logic_vector(63 downto 0);
        App_RspLen            : in    std_logic_vector(3 downto 0);
        App_RspAbort          : in    std_logic_vector(31 downto 0);
        Time_Coarse           : out   std_logic_vector(31 downto 0);
        Time_Fine             : out   std_logic_vector(23 downto 0);
        Time_Req              : in    std_logic;
        Stat_TimeSet          : out   std_logic;
        Evt_TimeSet           : out   std_logic;
        Evt_TimeSync          : out   std_logic;
        Err_TimeTxBusy        : out   std_logic;
        Err_TimeRxDrop        : out   std_logic;
        Err_TimeTxTimeout     : out   std_logic;
        Stat_NmtState         : out   std_logic_vector(1 downto 0);
        Evt_ResetApp          : out   std_logic;
        Evt_ResetComm         : out   std_logic;
        Err_NmtCs             : out   std_logic;
        Err_NodeId            : out   std_logic;
        Err_NmtTxTimeout      : out   std_logic;
        Stat_ActiveBus        : out   std_logic;
        Stat_Selecting        : out   std_logic;
        Stat_Ctoggle          : out   std_logic_vector(7 downto 0);
        Stat_MasterHbState    : out   std_logic_vector(7 downto 0);
        Stat_MasterHbPresent  : out   std_logic_vector(1 downto 0);
        Evt_BdefaultUpdate    : out   std_logic;
        Err_MasterHbMissing   : out   std_logic;
        Err_ToggleEnd         : out   std_logic;
        Err_MasterHbDlc       : out   std_logic;
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
        ErrInj_OdBitFlip      : in    std_logic_vector(557 downto 0);
        ErrInj_OdValid        : in    std_logic;
        ErrInj_NmtBitFlip     : in    std_logic_vector(13 downto 0);
        ErrInj_NmtValid       : in    std_logic;
        ErrInj_LinkTxDominant : in    std_logic_vector(1 downto 0);
        ErrInj_LinkStopFlip   : in    std_logic_vector(1 downto 0);
        Bus_ForceDom          : in    std_logic_vector(1 downto 0);
        Bus_ForceRec          : in    std_logic_vector(1 downto 0);
        Bus_DutRec            : in    std_logic_vector(1 downto 0);
        Bus_Level             : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_core_net_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt  : std_logic := '0';
    signal CanTx   : std_logic_vector(1 downto 0);
    signal CanTxEn : std_logic_vector(1 downto 0);
    signal CanRx   : std_logic_vector(1 downto 0);
    signal NodeTx  : std_logic_vector(3 downto 0);
    signal Level   : std_logic_vector(1 downto 0);

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    Bus_Level <= Level;

    i_core : entity work.ocan_core
        generic map (
            BusAccess_g      => BusAccess_g,
            MinimalSet_g     => MinimalSet_g,
            NumRpdo_g        => NumRpdo_g,
            NumTpdo_g        => NumTpdo_g,
            TimePdos_g       => TimePdos_g,
            ClkFrequency_g   => 40000000,
            FineBits_g       => 24,
            VendorId_g       => x"800004D8",
            ProductCode_g    => x"0000C0DE",
            ProducerHbTime_g => 5,
            MasterNodeId_g   => 1,
            MasterHbTime_g   => 10,
            Bdefault_g       => Bdefault_g,
            Ttoggle_g        => 1,
            Ntoggle_g        => 2,
            SctCobId_g       => 16#0F0#,
            SctType_g        => 1,
            LtpCobId_g       => 16#1F5#,
            LtpType_g        => 1
        )
        port map (
            Clk                   => ClkInt,
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
            Can_Tx                => CanTx,
            Can_TxEn              => CanTxEn,
            Can_Rx                => CanRx
        );

    g_bus : for B in 0 to 1 generate

        i_bus : entity work.ocan_tb_can_bus
            generic map (
                NumNodes_g => 2
            )
            port map (
                Node_Tx  => NodeTx(2 * B + 1 downto 2 * B),
                Node_Rx  => Level(B),
                Dut_Tx   => CanTx(B),
                Dut_TxEn => CanTxEn(B),
                Dut_Rx   => CanRx(B),
                ForceDom => Bus_ForceDom(B),
                ForceRec => Bus_ForceRec(B),
                DutRec   => Bus_DutRec(B)
            );

        g_node : for N in 0 to 1 generate

            i_node : entity work.ocan_tb_can_node
                generic map (
                    Index_g => 2 * B + N
                )
                port map (
                    Tx => NodeTx(2 * B + N),
                    Rx => Level(B)
                );

        end generate;

    end generate;

end architecture;
