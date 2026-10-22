---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_time: the clock with the period of ClkFrequency_g and the device under
-- test; the testbench drives the inputs cycle by cycle and answers the transmit handshake.
--
-- Documentation: hdl/ocan_time/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_time_th is
    generic (
        ClkFrequency_g : positive;
        FineBits_g     : natural
    );
    port (
        Clk           : out   std_logic;
        Rst           : in    std_logic;
        Tick_Ms       : in    std_logic;
        Rx_SyncValid  : in    std_logic;
        Rx_SyncDlc    : in    std_logic_vector(3 downto 0);
        Rx_TimeValid  : in    std_logic;
        Rx_TimeDlc    : in    std_logic_vector(3 downto 0);
        Rx_TimeData   : in    std_logic_vector(63 downto 0);
        Tx_Valid      : out   std_logic;
        Tx_Ready      : in    std_logic;
        Tx_Dlc        : out   std_logic_vector(3 downto 0);
        Tx_Data       : out   std_logic_vector(63 downto 0);
        Tx_Done       : in    std_logic;
        Tx_Aborted    : in    std_logic;
        Cfg_RxType    : in    std_logic_vector(7 downto 0);
        Cfg_TxType    : in    std_logic_vector(7 downto 0);
        Cfg_SetValid  : in    std_logic;
        Cfg_SetScet   : in    std_logic_vector(55 downto 0);
        Stat_Scet     : out   std_logic_vector(55 downto 0);
        Nmt_ResetComm : in    std_logic;
        Req_Valid     : in    std_logic;
        Time_Coarse   : out   std_logic_vector(31 downto 0);
        Time_Fine     : out   std_logic_vector(23 downto 0);
        Stat_TimeSet  : out   std_logic;
        Evt_Set       : out   std_logic;
        Evt_Sync      : out   std_logic;
        Err_TxBusy    : out   std_logic;
        Err_RxDrop    : out   std_logic;
        Err_TxTimeout : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_time_th is

    -- The period follows the generic; the reference model counts cycles, so the rounding of the period to the
    -- resolution of the simulator does not affect the checks
    constant ClkPeriod_c : time := 1 sec / ClkFrequency_g;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    i_dut : entity work.ocan_time
        generic map (
            ClkFrequency_g => ClkFrequency_g,
            FineBits_g     => FineBits_g
        )
        port map (
            Clk           => ClkInt,
            Rst           => Rst,
            Tick_Ms       => Tick_Ms,
            Rx_SyncValid  => Rx_SyncValid,
            Rx_SyncDlc    => Rx_SyncDlc,
            Rx_TimeValid  => Rx_TimeValid,
            Rx_TimeDlc    => Rx_TimeDlc,
            Rx_TimeData   => Rx_TimeData,
            Tx_Valid      => Tx_Valid,
            Tx_Ready      => Tx_Ready,
            Tx_Dlc        => Tx_Dlc,
            Tx_Data       => Tx_Data,
            Tx_Done       => Tx_Done,
            Tx_Aborted    => Tx_Aborted,
            Cfg_RxType    => Cfg_RxType,
            Cfg_TxType    => Cfg_TxType,
            Cfg_SetValid  => Cfg_SetValid,
            Cfg_SetScet   => Cfg_SetScet,
            Stat_Scet     => Stat_Scet,
            Nmt_ResetComm => Nmt_ResetComm,
            Req_Valid     => Req_Valid,
            Time_Coarse   => Time_Coarse,
            Time_Fine     => Time_Fine,
            Stat_TimeSet  => Stat_TimeSet,
            Evt_Set       => Evt_Set,
            Evt_Sync      => Evt_Sync,
            Err_TxBusy    => Err_TxBusy,
            Err_RxDrop    => Err_RxDrop,
            Err_TxTimeout => Err_TxTimeout
        );

end architecture;
