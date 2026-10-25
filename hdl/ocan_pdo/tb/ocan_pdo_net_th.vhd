---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_pdo: the clock (40 MHz), ocan_pdo with ocan_nmt, ocan_od, ocan_time,
-- ocan_dispatch and ocan_link (selective bus access, 1 Mbit/s), the millisecond tick from olo_base_strobe_gen and the
-- CAN network model with two model nodes on each bus. The NODE-ID is 5, the inputs of ocan_redundancy to ocan_nmt
-- are constants and the test sets the active bus. In place of ocan_sdo the test reaches the access interface of
-- ocan_od, and it is the user logic at the port of ocan_pdo. With MinimalSet_g the node has the minimal set without
-- the time PDOs; otherwise it is a clause 6 slave with the time PDOs (Spacecraft Time PDO 0F0h, Local Time PDO 1F5h
-- with transmission type 3).
--
-- Documentation: hdl/ocan_pdo/docs/verification_plan.md

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
entity ocan_pdo_net_th is
    generic (
        MinimalSet_g : boolean := false
    );
    port (
        Clk             : out   std_logic;
        Rst             : in    std_logic;
        Bus_Sel         : in    std_logic;
        -- Access interface of ocan_od (in place of ocan_sdo)
        Acc_Valid       : in    std_logic;
        Acc_Ready       : out   std_logic;
        Acc_Write       : in    std_logic;
        Acc_Index       : in    std_logic_vector(15 downto 0);
        Acc_Sub         : in    std_logic_vector(7 downto 0);
        Acc_Data        : in    std_logic_vector(63 downto 0);
        Acc_Len         : in    std_logic_vector(3 downto 0);
        Rsp_Valid       : out   std_logic;
        Rsp_Abort       : out   std_logic_vector(31 downto 0);
        -- Port of ocan_pdo to the user logic
        Sync_Valid      : out   std_logic;
        Rpdo_Valid      : out   std_logic_vector(3 downto 0);
        Rpdo_Data       : out   std_logic_vector(255 downto 0);
        Tpdo_Req        : in    std_logic_vector(3 downto 0);
        Tpdo_Data       : in    std_logic_vector(255 downto 0);
        Stat_TpdoBusy   : out   std_logic_vector(3 downto 0);
        Stat_PdoEnabled : out   std_logic;
        Evt_TpdoSent    : out   std_logic_vector(3 downto 0);
        Evt_TpdoAborted : out   std_logic_vector(3 downto 0);
        Err_RxLength    : out   std_logic_vector(3 downto 0);
        Err_TxBusy      : out   std_logic_vector(3 downto 0);
        Err_TxTimeout   : out   std_logic_vector(3 downto 0);
        -- Observed
        Stat_State      : out   std_logic_vector(1 downto 0);
        Stat_ActiveBus  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_pdo_net_th is

    constant ClkPeriod_c : time    := 25 ns;
    constant TimePdos_c  : boolean := not MinimalSet_g;

    signal ClkInt     : std_logic := '0';
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
    -- ocan_od
    signal CobId      : std_logic_vector(143 downto 0);
    signal CobIdCopy  : std_logic_vector(143 downto 0);
    signal HbTime     : std_logic_vector(15 downto 0);
    signal SctType    : std_logic_vector(7 downto 0);
    signal LtpType    : std_logic_vector(7 downto 0);
    signal SetValid   : std_logic;
    signal SetScet    : std_logic_vector(55 downto 0);
    signal Scet       : std_logic_vector(55 downto 0);
    signal RpdoType   : std_logic_vector(31 downto 0);
    signal TpdoType   : std_logic_vector(31 downto 0);
    -- ocan_dispatch to the protocol blocks
    signal SyncValid  : std_logic;
    signal SyncDlc    : std_logic_vector(3 downto 0);
    signal RpValid    : std_logic;
    signal RpNum      : std_logic_vector(1 downto 0);
    signal RpDlc      : std_logic_vector(3 downto 0);
    signal RpData     : std_logic_vector(63 downto 0);
    signal TmValid    : std_logic;
    signal TmDlc      : std_logic_vector(3 downto 0);
    signal TmData     : std_logic_vector(63 downto 0);
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
    signal ActBus     : std_logic;
    -- ocan_link
    signal LkSwitch   : std_logic;
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
    signal CanTx      : std_logic_vector(1 downto 0);
    signal CanTxEn    : std_logic_vector(1 downto 0);
    signal CanRx      : std_logic_vector(1 downto 0);
    signal NodeTx     : std_logic_vector(3 downto 0);
    signal Level      : std_logic_vector(1 downto 0);
    -- Constant inputs as signals (no expressions as actuals)
    signal Zero       : std_logic                    := '0';
    signal One        : std_logic                    := '1';
    signal Zero2      : std_logic_vector(1 downto 0) := "00";
    signal PinId      : std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(5, 7));
    signal PinIdCode  : std_logic_vector(6 downto 0) := not std_logic_vector(to_unsigned(5, 7));
    signal Presc      : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(2, 10));
    signal Tseg1      : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(15, 5));
    signal Tseg2      : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(4, 4));
    signal Sjw        : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(4, 3));

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    Stat_State     <= NmtState;
    Stat_ActiveBus <= ActBus;

    i_tick : entity olo.olo_base_strobe_gen
        generic map (
            FreqClkHz_g    => 40.0e6,
            FreqStrobeHz_g => 1.0e3
        )
        port map (
            Clk       => ClkInt,
            Rst       => Rst,
            Out_Valid => Tick
        );

    i_pdo : entity work.ocan_pdo
        port map (
            Clk             => ClkInt,
            Rst             => Rst,
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
            Err_RxLength    => Err_RxLength,
            Err_TxBusy      => Err_TxBusy,
            Err_TxTimeout   => Err_TxTimeout
        );

    i_nmt : entity work.ocan_nmt
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Pin_NodeId     => PinId,
            Pin_NodeIdCode => PinIdCode,
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
            Red_PreopReq   => Zero,
            Red_Switched   => Zero,
            Red_Selecting  => Zero,
            Stat_State     => NmtState,
            Reset_App      => ResetApp,
            Reset_Comm     => ResetComm,
            Err_Cs         => open,
            Err_NodeId     => open,
            Err_TxTimeout  => open
        );

    i_od : entity work.ocan_od
        generic map (
            MinimalSet_g => MinimalSet_g,
            TimePdos_g   => TimePdos_c,
            SctCobId_g   => 16#0F0#,
            SctType_g    => 254,
            LtpCobId_g   => 16#1F5#,
            LtpType_g    => 3
        )
        port map (
            Clk              => ClkInt,
            Rst              => Rst,
            Tick_Ms          => Tick,
            Acc_Valid        => Acc_Valid,
            Acc_Ready        => Acc_Ready,
            Acc_Write        => Acc_Write,
            Acc_Index        => Acc_Index,
            Acc_Sub          => Acc_Sub,
            Acc_Data         => Acc_Data,
            Acc_Len          => Acc_Len,
            Rsp_Valid        => Rsp_Valid,
            Rsp_Data         => open,
            Rsp_Len          => open,
            Rsp_Abort        => Rsp_Abort,
            Nmt_State        => NmtState,
            Nmt_NodeId       => NodeId,
            Nmt_ResetApp     => ResetApp,
            Nmt_ResetComm    => ResetComm,
            Cfg_CobId        => CobId,
            Cfg_CobIdCopy    => CobIdCopy,
            Cfg_HbTime       => HbTime,
            Cfg_MasterHbTime => open,
            Cfg_Bdefault     => open,
            Cfg_Ttoggle      => open,
            Cfg_Ntoggle      => open,
            Cfg_Ctoggle      => open,
            Cfg_CtoggleValid => open,
            Cfg_SctType      => SctType,
            Cfg_LtpType      => LtpType,
            Cfg_SetValid     => SetValid,
            Cfg_SetScet      => SetScet,
            Stat_Scet        => Scet,
            Cfg_RpdoType     => RpdoType,
            Cfg_TpdoType     => TpdoType,
            App_ReqValid     => open,
            App_ReqWrite     => open,
            App_ReqIndex     => open,
            App_ReqSub       => open,
            App_ReqData      => open,
            App_ReqLen       => open,
            Stat_ErrReg      => open,
            Err_ParamCopy    => open,
            Err_AppTimeout   => open
        );

    i_time : entity work.ocan_time
        generic map (
            ClkFrequency_g => 40000000,
            FineBits_g     => 24
        )
        port map (
            Clk           => ClkInt,
            Rst           => Rst,
            Tick_Ms       => Tick,
            Rx_SyncValid  => SyncValid,
            Rx_SyncDlc    => SyncDlc,
            Rx_TimeValid  => TmValid,
            Rx_TimeDlc    => TmDlc,
            Rx_TimeData   => TmData,
            Tx_Valid      => LtValid,
            Tx_Ready      => LtReady,
            Tx_Dlc        => LtDlc,
            Tx_Data       => LtData,
            Tx_Done       => LtDone,
            Tx_Aborted    => LtAborted,
            Cfg_RxType    => SctType,
            Cfg_TxType    => LtpType,
            Cfg_SetValid  => SetValid,
            Cfg_SetScet   => SetScet,
            Stat_Scet     => Scet,
            Nmt_ResetComm => ResetComm,
            Req_Valid     => Zero,
            Time_Coarse   => open,
            Time_Fine     => open,
            Stat_TimeSet  => open,
            Evt_Set       => open,
            Evt_Sync      => open,
            Err_TxBusy    => open,
            Err_RxDrop    => open,
            Err_TxTimeout => open
        );

    i_dispatch : entity work.ocan_dispatch
        generic map (
            NumRpdo_g   => 4,
            NumTpdo_g   => 4,
            TimePdos_g  => TimePdos_c,
            SdoServer_g => not MinimalSet_g
        )
        port map (
            Clk                => ClkInt,
            Rst                => Rst,
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
            Red_Selecting      => Zero,
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
            RxSdo_Valid        => open,
            RxSdo_Dlc          => open,
            RxSdo_Data         => open,
            RxRed_NmtValid     => open,
            RxRed_HbValid      => open,
            RxRed_HbDlc        => open,
            RxRed_HbState      => open,
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
            TxNmt_Valid        => NmtTxValid,
            TxNmt_Ready        => NmtTxReady,
            TxNmt_Data         => NmtTxData,
            TxNmt_Done         => NmtTxDone,
            TxNmt_Aborted      => NmtTxAbt,
            Err_Protocol       => open,
            Err_CobId          => open,
            Stat_CobIdMismatch => open
        );

    i_link : entity work.ocan_link
        generic map (
            BusAccess_g => "Selective"
        )
        port map (
            Clk             => ClkInt,
            Rst             => Rst,
            Ctrl_Enable     => One,
            Ctrl_Bus        => Bus_Sel,
            Cfg_Prescaler   => Presc,
            Cfg_Tseg1       => Tseg1,
            Cfg_Tseg2       => Tseg2,
            Cfg_Sjw         => Sjw,
            Tx_Valid        => LkValid,
            Tx_Ready        => LkReady,
            Tx_Id           => LkId,
            Tx_Ide          => Zero,
            Tx_Rtr          => Zero,
            Tx_Dlc          => LkDlc,
            Tx_Data         => LkData,
            Tx_Abort        => LkAbort,
            Tx_Done         => LkDone,
            Tx_Aborted      => LkAborted,
            Tx_ArbLost      => open,
            Tx_Stopped      => LkStopped,
            Rx_Valid        => LkRxValid,
            Rx_Id           => LkRxId,
            Rx_Ide          => LkRxIde,
            Rx_Rtr          => LkRxRtr,
            Rx_Dlc          => LkRxDlc,
            Rx_Data         => LkRxData,
            Stat_ActiveBus  => ActBus,
            Stat_Switching  => LkSwitch,
            Stat_Tec        => open,
            Stat_Rec        => open,
            Stat_State      => open,
            Stat_BusIdle    => open,
            Stat_DomTimeout => open,
            Err_Bit         => open,
            Err_Stuff       => open,
            Err_Crc         => open,
            Err_Form        => open,
            Err_Ack         => open,
            Err_DomTimeout  => open,
            Can_Tx          => CanTx,
            Can_TxEn        => CanTxEn,
            Can_Rx          => CanRx
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
                ForceDom => Zero2(B),
                ForceRec => Zero2(B)
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
