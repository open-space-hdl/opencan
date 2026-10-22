---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_sdo: the clock (40 MHz) and the device under test; the testbench drives
-- the requests, the NMT inputs and the tick cycle by cycle and answers the transmit handshake and the access
-- interface.
--
-- Documentation: hdl/ocan_sdo/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_sdo_th is
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Tick_Ms        : in    std_logic;
        Rx_Valid       : in    std_logic;
        Rx_Dlc         : in    std_logic_vector(3 downto 0);
        Rx_Data        : in    std_logic_vector(63 downto 0);
        Tx_Valid       : out   std_logic;
        Tx_Ready       : in    std_logic;
        Tx_Dlc         : out   std_logic_vector(3 downto 0);
        Tx_Data        : out   std_logic_vector(63 downto 0);
        Tx_Done        : in    std_logic;
        Tx_Aborted     : in    std_logic;
        Acc_Valid      : out   std_logic;
        Acc_Ready      : in    std_logic;
        Acc_Write      : out   std_logic;
        Acc_Index      : out   std_logic_vector(15 downto 0);
        Acc_Sub        : out   std_logic_vector(7 downto 0);
        Acc_Data       : out   std_logic_vector(63 downto 0);
        Acc_Len        : out   std_logic_vector(3 downto 0);
        Rsp_Valid      : in    std_logic;
        Rsp_Data       : in    std_logic_vector(63 downto 0);
        Rsp_Len        : in    std_logic_vector(3 downto 0);
        Rsp_Abort      : in    std_logic_vector(31 downto 0);
        Nmt_EnaSdo     : in    std_logic;
        Nmt_ResetApp   : in    std_logic;
        Nmt_ResetComm  : in    std_logic;
        Stat_Open      : out   std_logic;
        Err_RxDrop     : out   std_logic;
        Err_TxTimeout  : out   std_logic;
        Err_AccTimeout : out   std_logic;
        Evt_AbortTx    : out   std_logic;
        Evt_AbortRx    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_sdo_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    i_dut : entity work.ocan_sdo
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Tick_Ms        => Tick_Ms,
            Rx_Valid       => Rx_Valid,
            Rx_Dlc         => Rx_Dlc,
            Rx_Data        => Rx_Data,
            Tx_Valid       => Tx_Valid,
            Tx_Ready       => Tx_Ready,
            Tx_Dlc         => Tx_Dlc,
            Tx_Data        => Tx_Data,
            Tx_Done        => Tx_Done,
            Tx_Aborted     => Tx_Aborted,
            Acc_Valid      => Acc_Valid,
            Acc_Ready      => Acc_Ready,
            Acc_Write      => Acc_Write,
            Acc_Index      => Acc_Index,
            Acc_Sub        => Acc_Sub,
            Acc_Data       => Acc_Data,
            Acc_Len        => Acc_Len,
            Rsp_Valid      => Rsp_Valid,
            Rsp_Data       => Rsp_Data,
            Rsp_Len        => Rsp_Len,
            Rsp_Abort      => Rsp_Abort,
            Nmt_EnaSdo     => Nmt_EnaSdo,
            Nmt_ResetApp   => Nmt_ResetApp,
            Nmt_ResetComm  => Nmt_ResetComm,
            Stat_Open      => Stat_Open,
            Err_RxDrop     => Err_RxDrop,
            Err_TxTimeout  => Err_TxTimeout,
            Err_AccTimeout => Err_AccTimeout,
            Evt_AbortTx    => Evt_AbortTx,
            Evt_AbortRx    => Evt_AbortRx
        );

end architecture;
