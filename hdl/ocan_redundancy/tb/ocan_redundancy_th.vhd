---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_redundancy: the clock (40 MHz) and the device under test; the testbench
-- drives the events and the parameters cycle by cycle and models ocan_nmt and ocan_link.
--
-- Documentation: hdl/ocan_redundancy/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_redundancy_th is
    generic (
        MinimalSet_g : boolean := false
    );
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Tick_Ms        : in    std_logic;
        Rx_NmtValid    : in    std_logic_vector(1 downto 0);
        Rx_HbValid     : in    std_logic_vector(1 downto 0);
        Rx_HbDlc       : in    std_logic_vector(7 downto 0);
        Rx_HbState     : in    std_logic_vector(15 downto 0);
        Cfg_HbTime     : in    std_logic_vector(15 downto 0);
        Cfg_Bdefault   : in    std_logic;
        Cfg_Ttoggle    : in    std_logic_vector(7 downto 0);
        Cfg_Ntoggle    : in    std_logic_vector(7 downto 0);
        Cfg_CtoggleWr  : in    std_logic;
        Cfg_Ctoggle    : in    std_logic_vector(7 downto 0);
        Upd_Valid      : out   std_logic;
        Upd_Bdefault   : out   std_logic;
        Link_Bus       : out   std_logic;
        Link_ActiveBus : in    std_logic;
        Link_Switching : in    std_logic;
        Nmt_State      : in    std_logic_vector(1 downto 0);
        Nmt_PreopReq   : out   std_logic;
        Nmt_Switched   : out   std_logic;
        Stat_ActiveBus : out   std_logic;
        Stat_Selecting : out   std_logic;
        Stat_Ctoggle   : out   std_logic_vector(7 downto 0);
        Stat_HbState   : out   std_logic_vector(7 downto 0);
        Stat_HbPresent : out   std_logic_vector(1 downto 0);
        Err_HbMissing  : out   std_logic;
        Err_ToggleEnd  : out   std_logic;
        Err_HbDlc      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_redundancy_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    i_dut : entity work.ocan_redundancy
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Tick_Ms        => Tick_Ms,
            Rx_NmtValid    => Rx_NmtValid,
            Rx_HbValid     => Rx_HbValid,
            Rx_HbDlc       => Rx_HbDlc,
            Rx_HbState     => Rx_HbState,
            Cfg_HbTime     => Cfg_HbTime,
            Cfg_Bdefault   => Cfg_Bdefault,
            Cfg_Ttoggle    => Cfg_Ttoggle,
            Cfg_Ntoggle    => Cfg_Ntoggle,
            Cfg_CtoggleWr  => Cfg_CtoggleWr,
            Cfg_Ctoggle    => Cfg_Ctoggle,
            Upd_Valid      => Upd_Valid,
            Upd_Bdefault   => Upd_Bdefault,
            Link_Bus       => Link_Bus,
            Link_ActiveBus => Link_ActiveBus,
            Link_Switching => Link_Switching,
            Nmt_State      => Nmt_State,
            Nmt_PreopReq   => Nmt_PreopReq,
            Nmt_Switched   => Nmt_Switched,
            Stat_ActiveBus => Stat_ActiveBus,
            Stat_Selecting => Stat_Selecting,
            Stat_Ctoggle   => Stat_Ctoggle,
            Stat_HbState   => Stat_HbState,
            Stat_HbPresent => Stat_HbPresent,
            Err_HbMissing  => Err_HbMissing,
            Err_ToggleEnd  => Err_ToggleEnd,
            Err_HbDlc      => Err_HbDlc
        );

end architecture;
