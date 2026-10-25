---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_sdo: the clock (40 MHz), ocan_sdo with ocan_od, ocan_dispatch and
-- ocan_link (selective bus access, 1 Mbit/s), the millisecond tick from olo_base_strobe_gen and the CAN network model
-- with two model nodes on each bus. The NODE-ID (5), the NMT state (Pre-operational) and the service enables are
-- constants; the test sets the active bus. A register in place of ocan_time takes the writes of Local SCET Set
-- (2001h) and is the local time that ocan_od returns for Local SCET Get (2002h).
--
-- Documentation: hdl/ocan_sdo/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_sdo_net_th is
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Bus_Sel        : in    std_logic;
        -- Observed
        Stat_Open      : out   std_logic;
        Evt_AbortTx    : out   std_logic;
        Set_Valid      : out   std_logic;
        Set_Scet       : out   std_logic_vector(55 downto 0);
        Stat_ActiveBus : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_sdo_net_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt    : std_logic := '0';
    signal Tick      : std_logic;
    -- ocan_sdo, ocan_od and ocan_dispatch
    signal RxValid   : std_logic;
    signal RxDlc     : std_logic_vector(3 downto 0);
    signal RxData    : std_logic_vector(63 downto 0);
    signal TxValid   : std_logic;
    signal TxReady   : std_logic;
    signal TxDlc     : std_logic_vector(3 downto 0);
    signal TxData    : std_logic_vector(63 downto 0);
    signal TxDone    : std_logic;
    signal TxAborted : std_logic;
    signal AccValid  : std_logic;
    signal AccReady  : std_logic;
    signal AccWrite  : std_logic;
    signal AccIndex  : std_logic_vector(15 downto 0);
    signal AccSub    : std_logic_vector(7 downto 0);
    signal AccData   : std_logic_vector(63 downto 0);
    signal AccLen    : std_logic_vector(3 downto 0);
    signal RspValid  : std_logic;
    signal RspData   : std_logic_vector(63 downto 0);
    signal RspLen    : std_logic_vector(3 downto 0);
    signal RspAbort  : std_logic_vector(31 downto 0);
    signal CobId     : std_logic_vector(143 downto 0);
    signal CobIdCopy : std_logic_vector(143 downto 0);
    signal SetValid  : std_logic;
    signal SetScet   : std_logic_vector(55 downto 0);
    signal Scet      : std_logic_vector(55 downto 0) := (others => '0');
    signal ActBus    : std_logic;
    -- ocan_link
    signal LkSwitch  : std_logic;
    signal LkValid   : std_logic;
    signal LkReady   : std_logic;
    signal LkId      : std_logic_vector(28 downto 0);
    signal LkDlc     : std_logic_vector(3 downto 0);
    signal LkData    : std_logic_vector(63 downto 0);
    signal LkAbort   : std_logic;
    signal LkDone    : std_logic;
    signal LkAborted : std_logic;
    signal LkStopped : std_logic;
    signal LkRxValid : std_logic_vector(1 downto 0);
    signal LkRxId    : std_logic_vector(57 downto 0);
    signal LkRxIde   : std_logic_vector(1 downto 0);
    signal LkRxRtr   : std_logic_vector(1 downto 0);
    signal LkRxDlc   : std_logic_vector(7 downto 0);
    signal LkRxData  : std_logic_vector(127 downto 0);
    signal CanTx     : std_logic_vector(1 downto 0);
    signal CanTxEn   : std_logic_vector(1 downto 0);
    signal CanRx     : std_logic_vector(1 downto 0);
    signal NodeTx    : std_logic_vector(3 downto 0);
    signal Level     : std_logic_vector(1 downto 0);
    -- Constant inputs as signals (no expressions as actuals)
    signal Zero      : std_logic                    := '0';
    signal One       : std_logic                    := '1';
    signal Zero2     : std_logic_vector(1 downto 0) := "00";
    signal PreOp     : std_logic_vector(1 downto 0) := NmtPreOp_c;
    signal NodeId    : std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(5, 7));
    signal Presc     : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(2, 10));
    signal Tseg1     : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(15, 5));
    signal Tseg2     : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(4, 4));
    signal Sjw       : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(4, 3));

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    Stat_ActiveBus <= ActBus;
    Set_Valid      <= SetValid;
    Set_Scet       <= SetScet;

    -- In place of ocan_time: the local time is the last value written to Local SCET Set
    p_scet : process (ClkInt) is
    begin
        if rising_edge(ClkInt) then
            if SetValid = '1' then
                Scet <= SetScet;
            end if;
        end if;
    end process;

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

    i_sdo : entity work.ocan_sdo
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Tick_Ms        => Tick,
            Rx_Valid       => RxValid,
            Rx_Dlc         => RxDlc,
            Rx_Data        => RxData,
            Tx_Valid       => TxValid,
            Tx_Ready       => TxReady,
            Tx_Dlc         => TxDlc,
            Tx_Data        => TxData,
            Tx_Done        => TxDone,
            Tx_Aborted     => TxAborted,
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
            Nmt_EnaSdo     => One,
            Nmt_ResetApp   => Zero,
            Nmt_ResetComm  => Zero,
            Stat_Open      => Stat_Open,
            Err_RxDrop     => open,
            Err_TxTimeout  => open,
            Err_AccTimeout => open,
            Evt_AbortTx    => Evt_AbortTx,
            Evt_AbortRx    => open
        );

    i_od : entity work.ocan_od
        generic map (
            VendorId_g => x"800004D8"
        )
        port map (
            Clk              => ClkInt,
            Rst              => Rst,
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
            Nmt_State        => PreOp,
            Nmt_NodeId       => NodeId,
            Nmt_ResetApp     => Zero,
            Nmt_ResetComm    => Zero,
            Cfg_CobId        => CobId,
            Cfg_CobIdCopy    => CobIdCopy,
            Cfg_HbTime       => open,
            Cfg_MasterHbTime => open,
            Cfg_Bdefault     => open,
            Cfg_Ttoggle      => open,
            Cfg_Ntoggle      => open,
            Cfg_Ctoggle      => open,
            Cfg_CtoggleValid => open,
            Cfg_SctType      => open,
            Cfg_LtpType      => open,
            Cfg_SetValid     => SetValid,
            Cfg_SetScet      => SetScet,
            Stat_Scet        => Scet,
            Cfg_RpdoType     => open,
            Cfg_TpdoType     => open,
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

    i_dispatch : entity work.ocan_dispatch
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
            Nmt_NodeIdValid    => One,
            Nmt_EnaSdo         => One,
            Nmt_EnaPdo         => Zero,
            Nmt_EnaSync        => One,
            Cfg_CobId          => CobId,
            Cfg_CobIdCopy      => CobIdCopy,
            RxNmt_Valid        => open,
            RxNmt_Cs           => open,
            RxSync_Valid       => open,
            RxSync_Dlc         => open,
            RxSync_Data        => open,
            RxRpdo_Valid       => open,
            RxRpdo_Num         => open,
            RxRpdo_Dlc         => open,
            RxRpdo_Data        => open,
            RxTime_Valid       => open,
            RxTime_Dlc         => open,
            RxTime_Data        => open,
            RxSdo_Valid        => RxValid,
            RxSdo_Dlc          => RxDlc,
            RxSdo_Data         => RxData,
            RxRed_NmtValid     => open,
            RxRed_HbValid      => open,
            RxRed_HbDlc        => open,
            RxRed_HbState      => open,
            TxSdo_Valid        => TxValid,
            TxSdo_Ready        => TxReady,
            TxSdo_Dlc          => TxDlc,
            TxSdo_Data         => TxData,
            TxSdo_Done         => TxDone,
            TxSdo_Aborted      => TxAborted,
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
