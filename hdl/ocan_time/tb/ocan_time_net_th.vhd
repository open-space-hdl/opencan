---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_time: the clock (40 MHz), ocan_time with ocan_dispatch and ocan_link
-- (selective bus access, 1 Mbit/s), the millisecond tick from olo_base_strobe_gen and the CAN network model with two
-- model nodes on each bus. The NODE-ID and the service enables are constants; the test sets the active bus.
--
-- Documentation: hdl/ocan_time/docs/verification_plan.md

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
entity ocan_time_net_th is
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Bus_Sel        : in    std_logic;
        Cfg_RxType     : in    std_logic_vector(7 downto 0);
        Cfg_TxType     : in    std_logic_vector(7 downto 0);
        Cfg_CobId      : in    std_logic_vector(143 downto 0);
        -- Observed
        Stat_Scet      : out   std_logic_vector(55 downto 0);
        Evt_Set        : out   std_logic;
        Evt_Sync       : out   std_logic;
        Err_RxDrop     : out   std_logic;
        Stat_ActiveBus : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_time_net_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt    : std_logic := '0';
    signal Tick      : std_logic;
    -- ocan_time and ocan_dispatch
    signal SyncValid : std_logic;
    signal SyncDlc   : std_logic_vector(3 downto 0);
    signal TimeValid : std_logic;
    signal TimeDlc   : std_logic_vector(3 downto 0);
    signal TimeData  : std_logic_vector(63 downto 0);
    signal TxValid   : std_logic;
    signal TxReady   : std_logic;
    signal TxDlc     : std_logic_vector(3 downto 0);
    signal TxData    : std_logic_vector(63 downto 0);
    signal TxDone    : std_logic;
    signal TxAborted : std_logic;
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
    signal RxValid   : std_logic_vector(1 downto 0);
    signal RxId      : std_logic_vector(57 downto 0);
    signal RxIde     : std_logic_vector(1 downto 0);
    signal RxRtr     : std_logic_vector(1 downto 0);
    signal RxDlc     : std_logic_vector(7 downto 0);
    signal RxData    : std_logic_vector(127 downto 0);
    signal CanTx     : std_logic_vector(1 downto 0);
    signal CanTxEn   : std_logic_vector(1 downto 0);
    signal CanRx     : std_logic_vector(1 downto 0);
    signal NodeTx    : std_logic_vector(3 downto 0);
    signal Level     : std_logic_vector(1 downto 0);
    -- Constant inputs as signals (no expressions as actuals)
    signal Zero      : std_logic                     := '0';
    signal One       : std_logic                     := '1';
    signal Zero2     : std_logic_vector(1 downto 0)  := "00";
    signal NodeId    : std_logic_vector(6 downto 0)  := std_logic_vector(to_unsigned(5, 7));
    signal Presc     : std_logic_vector(9 downto 0)  := std_logic_vector(to_unsigned(2, 10));
    signal Tseg1     : std_logic_vector(4 downto 0)  := std_logic_vector(to_unsigned(15, 5));
    signal Tseg2     : std_logic_vector(3 downto 0)  := std_logic_vector(to_unsigned(4, 4));
    signal Sjw       : std_logic_vector(2 downto 0)  := std_logic_vector(to_unsigned(4, 3));
    signal NoScet    : std_logic_vector(55 downto 0) := (others => '0');

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

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
            Rx_TimeValid  => TimeValid,
            Rx_TimeDlc    => TimeDlc,
            Rx_TimeData   => TimeData,
            Tx_Valid      => TxValid,
            Tx_Ready      => TxReady,
            Tx_Dlc        => TxDlc,
            Tx_Data       => TxData,
            Tx_Done       => TxDone,
            Tx_Aborted    => TxAborted,
            Cfg_RxType    => Cfg_RxType,
            Cfg_TxType    => Cfg_TxType,
            Cfg_SetValid  => Zero,
            Cfg_SetScet   => NoScet,
            Stat_Scet     => Stat_Scet,
            Nmt_ResetComm => Zero,
            Req_Valid     => Zero,
            Time_Coarse   => open,
            Time_Fine     => open,
            Stat_TimeSet  => open,
            Evt_Set       => Evt_Set,
            Evt_Sync      => Evt_Sync,
            Err_TxBusy    => open,
            Err_RxDrop    => Err_RxDrop,
            Err_TxTimeout => open
        );

    i_dispatch : entity work.ocan_dispatch
        port map (
            Clk                => ClkInt,
            Rst                => Rst,
            LinkRx_Valid       => RxValid,
            LinkRx_Id          => RxId,
            LinkRx_Ide         => RxIde,
            LinkRx_Rtr         => RxRtr,
            LinkRx_Dlc         => RxDlc,
            LinkRx_Data        => RxData,
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
            Nmt_EnaSdo         => Zero,
            Nmt_EnaPdo         => One,
            Nmt_EnaSync        => One,
            Cfg_CobId          => Cfg_CobId,
            Cfg_CobIdCopy      => Cfg_CobId,
            RxNmt_Valid        => open,
            RxNmt_Cs           => open,
            RxSync_Valid       => SyncValid,
            RxSync_Dlc         => SyncDlc,
            RxSync_Data        => open,
            RxRpdo_Valid       => open,
            RxRpdo_Num         => open,
            RxRpdo_Dlc         => open,
            RxRpdo_Data        => open,
            RxTime_Valid       => TimeValid,
            RxTime_Dlc         => TimeDlc,
            RxTime_Data        => TimeData,
            RxSdo_Valid        => open,
            RxSdo_Dlc          => open,
            RxSdo_Data         => open,
            RxRed_NmtValid     => open,
            RxRed_HbValid      => open,
            RxRed_HbDlc        => open,
            RxRed_HbState      => open,
            TxTime_Valid       => TxValid,
            TxTime_Ready       => TxReady,
            TxTime_Dlc         => TxDlc,
            TxTime_Data        => TxData,
            TxTime_Done        => TxDone,
            TxTime_Aborted     => TxAborted,
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
            Rx_Valid        => RxValid,
            Rx_Id           => RxId,
            Rx_Ide          => RxIde,
            Rx_Rtr          => RxRtr,
            Rx_Dlc          => RxDlc,
            Rx_Data         => RxData,
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
