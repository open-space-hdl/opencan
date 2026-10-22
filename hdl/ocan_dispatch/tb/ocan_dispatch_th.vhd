---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the direct testbench of ocan_dispatch: the clock (40 MHz) and the device under test; the testbench
-- drives the link events cycle by cycle and answers the transmit stream.
--
-- Documentation: hdl/ocan_dispatch/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_dispatch_th is
    generic (
        NumRpdo_g   : natural := 4;
        NumTpdo_g   : natural := 4;
        TimePdos_g  : boolean := true;
        SdoServer_g : boolean := true
    );
    port (
        Clk                : out   std_logic;
        Rst                : in    std_logic;
        LinkRx_Valid       : in    std_logic_vector(1 downto 0);
        LinkRx_Id          : in    std_logic_vector(57 downto 0);
        LinkRx_Ide         : in    std_logic_vector(1 downto 0);
        LinkRx_Rtr         : in    std_logic_vector(1 downto 0);
        LinkRx_Dlc         : in    std_logic_vector(7 downto 0);
        LinkRx_Data        : in    std_logic_vector(127 downto 0);
        LinkTx_Valid       : out   std_logic;
        LinkTx_Ready       : in    std_logic;
        LinkTx_Id          : out   std_logic_vector(28 downto 0);
        LinkTx_Dlc         : out   std_logic_vector(3 downto 0);
        LinkTx_Data        : out   std_logic_vector(63 downto 0);
        LinkTx_Abort       : out   std_logic;
        LinkTx_Done        : in    std_logic;
        LinkTx_Aborted     : in    std_logic;
        LinkTx_Stopped     : in    std_logic;
        Red_ActiveBus      : in    std_logic;
        Red_Selecting      : in    std_logic;
        Nmt_NodeId         : in    std_logic_vector(6 downto 0);
        Nmt_NodeIdValid    : in    std_logic;
        Nmt_EnaSdo         : in    std_logic;
        Nmt_EnaPdo         : in    std_logic;
        Nmt_EnaSync        : in    std_logic;
        Cfg_CobId          : in    std_logic_vector(143 downto 0);
        Cfg_CobIdCopy      : in    std_logic_vector(143 downto 0);
        RxNmt_Valid        : out   std_logic;
        RxNmt_Cs           : out   std_logic_vector(7 downto 0);
        RxSync_Valid       : out   std_logic;
        RxSync_Dlc         : out   std_logic_vector(3 downto 0);
        RxSync_Data        : out   std_logic_vector(7 downto 0);
        RxRpdo_Valid       : out   std_logic;
        RxRpdo_Num         : out   std_logic_vector(1 downto 0);
        RxRpdo_Dlc         : out   std_logic_vector(3 downto 0);
        RxRpdo_Data        : out   std_logic_vector(63 downto 0);
        RxTime_Valid       : out   std_logic;
        RxTime_Dlc         : out   std_logic_vector(3 downto 0);
        RxTime_Data        : out   std_logic_vector(63 downto 0);
        RxSdo_Valid        : out   std_logic;
        RxSdo_Dlc          : out   std_logic_vector(3 downto 0);
        RxSdo_Data         : out   std_logic_vector(63 downto 0);
        RxRed_NmtValid     : out   std_logic_vector(1 downto 0);
        RxRed_HbValid      : out   std_logic_vector(1 downto 0);
        RxRed_HbDlc        : out   std_logic_vector(7 downto 0);
        RxRed_HbState      : out   std_logic_vector(15 downto 0);
        TxTpdo_Valid       : in    std_logic_vector(3 downto 0);
        TxTpdo_Ready       : out   std_logic_vector(3 downto 0);
        TxTpdo_Dlc         : in    std_logic_vector(15 downto 0);
        TxTpdo_Data        : in    std_logic_vector(255 downto 0);
        TxTpdo_Done        : out   std_logic_vector(3 downto 0);
        TxTpdo_Aborted     : out   std_logic_vector(3 downto 0);
        TxTime_Valid       : in    std_logic;
        TxTime_Ready       : out   std_logic;
        TxTime_Dlc         : in    std_logic_vector(3 downto 0);
        TxTime_Data        : in    std_logic_vector(63 downto 0);
        TxTime_Done        : out   std_logic;
        TxTime_Aborted     : out   std_logic;
        TxSdo_Valid        : in    std_logic;
        TxSdo_Ready        : out   std_logic;
        TxSdo_Dlc          : in    std_logic_vector(3 downto 0);
        TxSdo_Data         : in    std_logic_vector(63 downto 0);
        TxSdo_Done         : out   std_logic;
        TxSdo_Aborted      : out   std_logic;
        TxNmt_Valid        : in    std_logic;
        TxNmt_Ready        : out   std_logic;
        TxNmt_Data         : in    std_logic_vector(7 downto 0);
        TxNmt_Done         : out   std_logic;
        TxNmt_Aborted      : out   std_logic;
        Err_Protocol       : out   std_logic;
        Err_CobId          : out   std_logic;
        Stat_CobIdMismatch : out   std_logic_vector(11 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_dispatch_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    i_dut : entity work.ocan_dispatch
        generic map (
            NumRpdo_g   => NumRpdo_g,
            NumTpdo_g   => NumTpdo_g,
            TimePdos_g  => TimePdos_g,
            SdoServer_g => SdoServer_g
        )
        port map (
            Clk                => ClkInt,
            Rst                => Rst,
            LinkRx_Valid       => LinkRx_Valid,
            LinkRx_Id          => LinkRx_Id,
            LinkRx_Ide         => LinkRx_Ide,
            LinkRx_Rtr         => LinkRx_Rtr,
            LinkRx_Dlc         => LinkRx_Dlc,
            LinkRx_Data        => LinkRx_Data,
            LinkTx_Valid       => LinkTx_Valid,
            LinkTx_Ready       => LinkTx_Ready,
            LinkTx_Id          => LinkTx_Id,
            LinkTx_Dlc         => LinkTx_Dlc,
            LinkTx_Data        => LinkTx_Data,
            LinkTx_Abort       => LinkTx_Abort,
            LinkTx_Done        => LinkTx_Done,
            LinkTx_Aborted     => LinkTx_Aborted,
            LinkTx_Stopped     => LinkTx_Stopped,
            Red_ActiveBus      => Red_ActiveBus,
            Red_Selecting      => Red_Selecting,
            Nmt_NodeId         => Nmt_NodeId,
            Nmt_NodeIdValid    => Nmt_NodeIdValid,
            Nmt_EnaSdo         => Nmt_EnaSdo,
            Nmt_EnaPdo         => Nmt_EnaPdo,
            Nmt_EnaSync        => Nmt_EnaSync,
            Cfg_CobId          => Cfg_CobId,
            Cfg_CobIdCopy      => Cfg_CobIdCopy,
            RxNmt_Valid        => RxNmt_Valid,
            RxNmt_Cs           => RxNmt_Cs,
            RxSync_Valid       => RxSync_Valid,
            RxSync_Dlc         => RxSync_Dlc,
            RxSync_Data        => RxSync_Data,
            RxRpdo_Valid       => RxRpdo_Valid,
            RxRpdo_Num         => RxRpdo_Num,
            RxRpdo_Dlc         => RxRpdo_Dlc,
            RxRpdo_Data        => RxRpdo_Data,
            RxTime_Valid       => RxTime_Valid,
            RxTime_Dlc         => RxTime_Dlc,
            RxTime_Data        => RxTime_Data,
            RxSdo_Valid        => RxSdo_Valid,
            RxSdo_Dlc          => RxSdo_Dlc,
            RxSdo_Data         => RxSdo_Data,
            RxRed_NmtValid     => RxRed_NmtValid,
            RxRed_HbValid      => RxRed_HbValid,
            RxRed_HbDlc        => RxRed_HbDlc,
            RxRed_HbState      => RxRed_HbState,
            TxTpdo_Valid       => TxTpdo_Valid,
            TxTpdo_Ready       => TxTpdo_Ready,
            TxTpdo_Dlc         => TxTpdo_Dlc,
            TxTpdo_Data        => TxTpdo_Data,
            TxTpdo_Done        => TxTpdo_Done,
            TxTpdo_Aborted     => TxTpdo_Aborted,
            TxTime_Valid       => TxTime_Valid,
            TxTime_Ready       => TxTime_Ready,
            TxTime_Dlc         => TxTime_Dlc,
            TxTime_Data        => TxTime_Data,
            TxTime_Done        => TxTime_Done,
            TxTime_Aborted     => TxTime_Aborted,
            TxSdo_Valid        => TxSdo_Valid,
            TxSdo_Ready        => TxSdo_Ready,
            TxSdo_Dlc          => TxSdo_Dlc,
            TxSdo_Data         => TxSdo_Data,
            TxSdo_Done         => TxSdo_Done,
            TxSdo_Aborted      => TxSdo_Aborted,
            TxNmt_Valid        => TxNmt_Valid,
            TxNmt_Ready        => TxNmt_Ready,
            TxNmt_Data         => TxNmt_Data,
            TxNmt_Done         => TxNmt_Done,
            TxNmt_Aborted      => TxNmt_Aborted,
            Err_Protocol       => Err_Protocol,
            Err_CobId          => Err_CobId,
            Stat_CobIdMismatch => Stat_CobIdMismatch
        );

end architecture;
