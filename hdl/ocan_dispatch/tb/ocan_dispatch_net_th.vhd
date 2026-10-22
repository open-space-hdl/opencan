---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_dispatch: the clock (40 MHz), ocan_dispatch with ocan_link (selective
-- bus access, 1 Mbit/s) and the CAN network model with two model nodes on each bus. The ports of ocan_dispatch
-- towards the protocol blocks and its transmit stream to the link are ports of the harness.
--
-- Documentation: hdl/ocan_dispatch/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_dispatch_net_th is
    port (
        Clk             : out   std_logic;
        Rst             : in    std_logic;
        Red_ActiveBus   : in    std_logic;
        Nmt_NodeId      : in    std_logic_vector(6 downto 0);
        Nmt_NodeIdValid : in    std_logic;
        Cfg_CobId       : in    std_logic_vector(143 downto 0);
        -- Received objects
        RxNmt_Valid     : out   std_logic;
        RxSync_Valid    : out   std_logic;
        RxRpdo_Valid    : out   std_logic;
        RxTime_Valid    : out   std_logic;
        RxSdo_Valid     : out   std_logic;
        RxRed_NmtValid  : out   std_logic_vector(1 downto 0);
        RxRed_HbValid   : out   std_logic_vector(1 downto 0);
        -- Transmit requests (index 0 to 3 transmit PDOs, 4 Local Time PDO, 5 SDO reply, 6 NMT error control)
        Src_Valid       : in    std_logic_vector(6 downto 0);
        Src_Ready       : out   std_logic_vector(6 downto 0);
        Src_Done        : out   std_logic_vector(6 downto 0);
        Src_Aborted     : out   std_logic_vector(6 downto 0);
        -- Transmit stream of ocan_dispatch to ocan_link (observed)
        LinkTx_Valid    : out   std_logic;
        LinkTx_Ready    : out   std_logic;
        LinkTx_Id       : out   std_logic_vector(28 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_dispatch_net_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt    : std_logic := '0';
    signal RxValid   : std_logic_vector(1 downto 0);
    signal RxId      : std_logic_vector(57 downto 0);
    signal RxIde     : std_logic_vector(1 downto 0);
    signal RxRtr     : std_logic_vector(1 downto 0);
    signal RxDlc     : std_logic_vector(7 downto 0);
    signal RxData    : std_logic_vector(127 downto 0);
    signal TxValid   : std_logic;
    signal TxReady   : std_logic;
    signal TxId      : std_logic_vector(28 downto 0);
    signal TxDlc     : std_logic_vector(3 downto 0);
    signal TxData    : std_logic_vector(63 downto 0);
    signal TxAbort   : std_logic;
    signal TxDone    : std_logic;
    signal TxAborted : std_logic;
    signal TxStopped : std_logic;
    signal CanTx     : std_logic_vector(1 downto 0);
    signal CanTxEn   : std_logic_vector(1 downto 0);
    signal CanRx     : std_logic_vector(1 downto 0);
    signal NodeTx    : std_logic_vector(3 downto 0);
    signal Level     : std_logic_vector(1 downto 0);
    -- Constant inputs as signals (no expressions as actuals)
    signal Presc     : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(2, 10));
    signal Tseg1     : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(15, 5));
    signal Tseg2     : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(4, 4));
    signal Sjw       : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(4, 3));

begin

    ClkInt       <= not ClkInt after ClkPeriod_c / 2;
    Clk          <= ClkInt;
    LinkTx_Valid <= TxValid;
    LinkTx_Ready <= TxReady;
    LinkTx_Id    <= TxId;

    i_dut : entity work.ocan_dispatch
        port map (
            Clk                => ClkInt,
            Rst                => Rst,
            LinkRx_Valid       => RxValid,
            LinkRx_Id          => RxId,
            LinkRx_Ide         => RxIde,
            LinkRx_Rtr         => RxRtr,
            LinkRx_Dlc         => RxDlc,
            LinkRx_Data        => RxData,
            LinkTx_Valid       => TxValid,
            LinkTx_Ready       => TxReady,
            LinkTx_Id          => TxId,
            LinkTx_Dlc         => TxDlc,
            LinkTx_Data        => TxData,
            LinkTx_Abort       => TxAbort,
            LinkTx_Done        => TxDone,
            LinkTx_Aborted     => TxAborted,
            LinkTx_Stopped     => TxStopped,
            Red_ActiveBus      => Red_ActiveBus,
            Red_Selecting      => '0',
            Nmt_NodeId         => Nmt_NodeId,
            Nmt_NodeIdValid    => Nmt_NodeIdValid,
            Nmt_EnaSdo         => '1',
            Nmt_EnaPdo         => '1',
            Nmt_EnaSync        => '1',
            Cfg_CobId          => Cfg_CobId,
            Cfg_CobIdCopy      => Cfg_CobId,
            RxNmt_Valid        => RxNmt_Valid,
            RxNmt_Cs           => open,
            RxSync_Valid       => RxSync_Valid,
            RxSync_Dlc         => open,
            RxSync_Data        => open,
            RxRpdo_Valid       => RxRpdo_Valid,
            RxRpdo_Num         => open,
            RxRpdo_Dlc         => open,
            RxRpdo_Data        => open,
            RxTime_Valid       => RxTime_Valid,
            RxTime_Dlc         => open,
            RxTime_Data        => open,
            RxSdo_Valid        => RxSdo_Valid,
            RxSdo_Dlc          => open,
            RxSdo_Data         => open,
            RxRed_NmtValid     => RxRed_NmtValid,
            RxRed_HbValid      => RxRed_HbValid,
            RxRed_HbDlc        => open,
            RxRed_HbState      => open,
            TxTpdo_Valid       => Src_Valid(3 downto 0),
            TxTpdo_Ready       => Src_Ready(3 downto 0),
            TxTpdo_Dlc         => x"8888",
            TxTpdo_Data        => (others => '0'),
            TxTpdo_Done        => Src_Done(3 downto 0),
            TxTpdo_Aborted     => Src_Aborted(3 downto 0),
            TxTime_Valid       => Src_Valid(4),
            TxTime_Ready       => Src_Ready(4),
            TxTime_Dlc         => x"8",
            TxTime_Data        => x"0011223344556677",
            TxTime_Done        => Src_Done(4),
            TxTime_Aborted     => Src_Aborted(4),
            TxSdo_Valid        => Src_Valid(5),
            TxSdo_Ready        => Src_Ready(5),
            TxSdo_Dlc          => x"8",
            TxSdo_Data         => x"4300100000000000",
            TxSdo_Done         => Src_Done(5),
            TxSdo_Aborted      => Src_Aborted(5),
            TxNmt_Valid        => Src_Valid(6),
            TxNmt_Ready        => Src_Ready(6),
            TxNmt_Data         => x"05",
            TxNmt_Done         => Src_Done(6),
            TxNmt_Aborted      => Src_Aborted(6),
            Err_Protocol       => open,
            Err_CobId          => open,
            Stat_CobIdMismatch => open
        );

    i_link : entity work.ocan_link
        port map (
            Clk               => ClkInt,
            Rst               => Rst,
            Ctrl_Enable       => Nmt_NodeIdValid,
            Ctrl_Bus          => Red_ActiveBus,
            Cfg_Prescaler     => Presc,
            Cfg_Tseg1         => Tseg1,
            Cfg_Tseg2         => Tseg2,
            Cfg_Sjw           => Sjw,
            Tx_Valid          => TxValid,
            Tx_Ready          => TxReady,
            Tx_Id             => TxId,
            Tx_Ide            => '0',
            Tx_Rtr            => '0',
            Tx_Dlc            => TxDlc,
            Tx_Data           => TxData,
            Tx_Abort          => TxAbort,
            Tx_Done           => TxDone,
            Tx_Aborted        => TxAborted,
            Tx_ArbLost        => open,
            Tx_Stopped        => TxStopped,
            Rx_Valid          => RxValid,
            Rx_Id             => RxId,
            Rx_Ide            => RxIde,
            Rx_Rtr            => RxRtr,
            Rx_Dlc            => RxDlc,
            Rx_Data           => RxData,
            Stat_ActiveBus    => open,
            Stat_Switching    => open,
            Stat_Tec          => open,
            Stat_Rec          => open,
            Stat_State        => open,
            Stat_BusIdle      => open,
            Stat_DomTimeout   => open,
            Err_Bit           => open,
            Err_Stuff         => open,
            Err_Crc           => open,
            Err_Form          => open,
            Err_Ack           => open,
            Err_DomTimeout    => open,
            Can_Tx            => CanTx,
            Can_TxEn          => CanTxEn,
            Can_Rx            => CanRx
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
                Dut_Rx   => CanRx(B)
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
