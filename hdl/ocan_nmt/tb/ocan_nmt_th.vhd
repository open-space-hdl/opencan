---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_nmt: the clock (40 MHz) and the device under test; the testbench drives
-- the inputs cycle by cycle and answers the transmit handshake.
--
-- Documentation: hdl/ocan_nmt/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_nmt_th is
    generic (
        MinimalSet_g : boolean := false
    );
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Pin_NodeId     : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode : in    std_logic_vector(6 downto 0);
        Tick_Ms        : in    std_logic;
        Cfg_HbTime     : in    std_logic_vector(15 downto 0);
        Rx_Valid       : in    std_logic;
        Rx_Cs          : in    std_logic_vector(7 downto 0);
        Tx_Valid       : out   std_logic;
        Tx_Ready       : in    std_logic;
        Tx_Data        : out   std_logic_vector(7 downto 0);
        Tx_Done        : in    std_logic;
        Tx_Aborted     : in    std_logic;
        Node_Id        : out   std_logic_vector(6 downto 0);
        Node_IdValid   : out   std_logic;
        Ena_Sdo        : out   std_logic;
        Ena_Pdo        : out   std_logic;
        Ena_Sync       : out   std_logic;
        Red_PreopReq   : in    std_logic;
        Red_Switched   : in    std_logic;
        Red_Selecting  : in    std_logic;
        Stat_State     : out   std_logic_vector(1 downto 0);
        Reset_App      : out   std_logic;
        Reset_Comm     : out   std_logic;
        Err_Cs         : out   std_logic;
        Err_NodeId     : out   std_logic;
        ErrInj_BitFlip : in    std_logic_vector(13 downto 0);
        ErrInj_Valid   : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_nmt_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    i_dut : entity work.ocan_nmt
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Pin_NodeId     => Pin_NodeId,
            Pin_NodeIdCode => Pin_NodeIdCode,
            Tick_Ms        => Tick_Ms,
            Cfg_HbTime     => Cfg_HbTime,
            Rx_Valid       => Rx_Valid,
            Rx_Cs          => Rx_Cs,
            Tx_Valid       => Tx_Valid,
            Tx_Ready       => Tx_Ready,
            Tx_Data        => Tx_Data,
            Tx_Done        => Tx_Done,
            Tx_Aborted     => Tx_Aborted,
            Node_Id        => Node_Id,
            Node_IdValid   => Node_IdValid,
            Ena_Sdo        => Ena_Sdo,
            Ena_Pdo        => Ena_Pdo,
            Ena_Sync       => Ena_Sync,
            Red_PreopReq   => Red_PreopReq,
            Red_Switched   => Red_Switched,
            Red_Selecting  => Red_Selecting,
            Stat_State     => Stat_State,
            Reset_App      => Reset_App,
            Reset_Comm     => Reset_Comm,
            Err_Cs         => Err_Cs,
            Err_NodeId     => Err_NodeId,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid
        );

end architecture;
