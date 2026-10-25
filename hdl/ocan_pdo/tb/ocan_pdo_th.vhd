---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_pdo: the clock (40 MHz) and the device under test; the testbench drives
-- the SYNC and receive PDO events, the transmission types, the NMT inputs, the tick and the port of the user logic
-- cycle by cycle and answers the transmit handshake of every transmit PDO.
--
-- Documentation: hdl/ocan_pdo/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_pdo_th is
    generic (
        NumRpdo_g : natural range 0 to 4 := 4;
        NumTpdo_g : natural range 0 to 4 := 4
    );
    port (
        Clk             : out   std_logic;
        Rst             : in    std_logic;
        Tick_Ms         : in    std_logic;
        RxSync_Valid    : in    std_logic;
        RxSync_Dlc      : in    std_logic_vector(3 downto 0);
        RxRpdo_Valid    : in    std_logic;
        RxRpdo_Num      : in    std_logic_vector(1 downto 0);
        RxRpdo_Dlc      : in    std_logic_vector(3 downto 0);
        RxRpdo_Data     : in    std_logic_vector(63 downto 0);
        TxTpdo_Valid    : out   std_logic_vector(3 downto 0);
        TxTpdo_Ready    : in    std_logic_vector(3 downto 0);
        TxTpdo_Dlc      : out   std_logic_vector(15 downto 0);
        TxTpdo_Data     : out   std_logic_vector(255 downto 0);
        TxTpdo_Done     : in    std_logic_vector(3 downto 0);
        TxTpdo_Aborted  : in    std_logic_vector(3 downto 0);
        Cfg_RpdoType    : in    std_logic_vector(31 downto 0);
        Cfg_TpdoType    : in    std_logic_vector(31 downto 0);
        Nmt_EnaPdo      : in    std_logic;
        Nmt_ResetComm   : in    std_logic;
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
        Err_TxTimeout   : out   std_logic_vector(3 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_pdo_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    i_dut : entity work.ocan_pdo
        generic map (
            NumRpdo_g => NumRpdo_g,
            NumTpdo_g => NumTpdo_g
        )
        port map (
            Clk             => ClkInt,
            Rst             => Rst,
            Tick_Ms         => Tick_Ms,
            RxSync_Valid    => RxSync_Valid,
            RxSync_Dlc      => RxSync_Dlc,
            RxRpdo_Valid    => RxRpdo_Valid,
            RxRpdo_Num      => RxRpdo_Num,
            RxRpdo_Dlc      => RxRpdo_Dlc,
            RxRpdo_Data     => RxRpdo_Data,
            TxTpdo_Valid    => TxTpdo_Valid,
            TxTpdo_Ready    => TxTpdo_Ready,
            TxTpdo_Dlc      => TxTpdo_Dlc,
            TxTpdo_Data     => TxTpdo_Data,
            TxTpdo_Done     => TxTpdo_Done,
            TxTpdo_Aborted  => TxTpdo_Aborted,
            Cfg_RpdoType    => Cfg_RpdoType,
            Cfg_TpdoType    => Cfg_TpdoType,
            Nmt_EnaPdo      => Nmt_EnaPdo,
            Nmt_ResetComm   => Nmt_ResetComm,
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

end architecture;
