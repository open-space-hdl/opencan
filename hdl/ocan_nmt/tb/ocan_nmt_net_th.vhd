---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_nmt: the clock (40 MHz), ocan_nmt with ocan_dispatch and ocan_link
-- (selective bus access, 1 Mbit/s, bus A), the millisecond tick from olo_base_strobe_gen and the CAN network model
-- with two model nodes on each bus. The redundancy inputs are fixed to bus A without a bus selection.
--
-- Documentation: hdl/ocan_nmt/docs/verification_plan.md

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
entity ocan_nmt_net_th is
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Pin_NodeId     : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode : in    std_logic_vector(6 downto 0);
        Cfg_HbTime     : in    std_logic_vector(15 downto 0);
        Cfg_CobId      : in    std_logic_vector(143 downto 0);
        -- Observed outputs of ocan_nmt
        Stat_State     : out   std_logic_vector(1 downto 0);
        Node_IdValid   : out   std_logic;
        Ena_Sdo        : out   std_logic;
        Ena_Pdo        : out   std_logic;
        Ena_Sync       : out   std_logic;
        Nmt_TxValid    : out   std_logic;
        Nmt_TxReady    : out   std_logic;
        Nmt_TxData     : out   std_logic_vector(7 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_nmt_net_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt    : std_logic := '0';
    signal Tick      : std_logic;
    signal NodeId    : std_logic_vector(6 downto 0);
    signal IdValid   : std_logic;
    signal EnaSdo    : std_logic;
    signal EnaPdo    : std_logic;
    signal EnaSync   : std_logic;
    signal NmtValid  : std_logic;
    signal NmtCs     : std_logic_vector(7 downto 0);
    signal TxValid   : std_logic;
    signal TxReady   : std_logic;
    signal TxData    : std_logic_vector(7 downto 0);
    signal TxDone    : std_logic;
    signal TxAborted : std_logic;
    signal LkValid   : std_logic;
    signal LkReady   : std_logic;
    signal LkId      : std_logic_vector(28 downto 0);
    signal LkDlc     : std_logic_vector(3 downto 0);
    signal LkData    : std_logic_vector(63 downto 0);
    signal LkAbort   : std_logic;
    signal LkDone    : std_logic;
    signal LkAborted : std_logic;
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
    signal Zero      : std_logic                    := '0';
    signal Presc     : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(2, 10));
    signal Tseg1     : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(15, 5));
    signal Tseg2     : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(4, 4));
    signal Sjw       : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(4, 3));

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    Node_IdValid <= IdValid;
    Ena_Sdo      <= EnaSdo;
    Ena_Pdo      <= EnaPdo;
    Ena_Sync     <= EnaSync;
    Nmt_TxValid  <= TxValid;
    Nmt_TxReady  <= TxReady;
    Nmt_TxData   <= TxData;

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

    i_nmt : entity work.ocan_nmt
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Pin_NodeId     => Pin_NodeId,
            Pin_NodeIdCode => Pin_NodeIdCode,
            Tick_Ms        => Tick,
            Cfg_HbTime     => Cfg_HbTime,
            Rx_Valid       => NmtValid,
            Rx_Cs          => NmtCs,
            Tx_Valid       => TxValid,
            Tx_Ready       => TxReady,
            Tx_Data        => TxData,
            Tx_Done        => TxDone,
            Tx_Aborted     => TxAborted,
            Node_Id        => NodeId,
            Node_IdValid   => IdValid,
            Ena_Sdo        => EnaSdo,
            Ena_Pdo        => EnaPdo,
            Ena_Sync       => EnaSync,
            Red_PreopReq   => Zero,
            Red_Switched   => Zero,
            Red_Selecting  => Zero,
            Stat_State     => Stat_State,
            Reset_App      => open,
            Reset_Comm     => open,
            Err_Cs         => open,
            Err_NodeId     => open
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
            Red_ActiveBus      => Zero,
            Red_Selecting      => Zero,
            Nmt_NodeId         => NodeId,
            Nmt_NodeIdValid    => IdValid,
            Nmt_EnaSdo         => EnaSdo,
            Nmt_EnaPdo         => EnaPdo,
            Nmt_EnaSync        => EnaSync,
            Cfg_CobId          => Cfg_CobId,
            Cfg_CobIdCopy      => Cfg_CobId,
            RxNmt_Valid        => NmtValid,
            RxNmt_Cs           => NmtCs,
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
            RxSdo_Valid        => open,
            RxSdo_Dlc          => open,
            RxSdo_Data         => open,
            RxRed_NmtValid     => open,
            RxRed_HbValid      => open,
            RxRed_HbDlc        => open,
            RxRed_HbState      => open,
            TxNmt_Valid        => TxValid,
            TxNmt_Ready        => TxReady,
            TxNmt_Data         => TxData,
            TxNmt_Done         => TxDone,
            TxNmt_Aborted      => TxAborted,
            Err_Protocol       => open,
            Err_CobId          => open,
            Stat_CobIdMismatch => open
        );

    i_link : entity work.ocan_link
        port map (
            Clk             => ClkInt,
            Rst             => Rst,
            Ctrl_Enable     => IdValid,
            Ctrl_Bus        => Zero,
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
            Rx_Valid        => RxValid,
            Rx_Id           => RxId,
            Rx_Ide          => RxIde,
            Rx_Rtr          => RxRtr,
            Rx_Dlc          => RxDlc,
            Rx_Data         => RxData,
            Stat_ActiveBus  => open,
            Stat_Switching  => open,
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
