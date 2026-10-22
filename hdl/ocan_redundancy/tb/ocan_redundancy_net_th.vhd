---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_redundancy: the clock (40 MHz), ocan_redundancy with ocan_nmt,
-- ocan_dispatch and ocan_link (selective or parallel bus access, 1 Mbit/s), the millisecond tick from
-- olo_base_strobe_gen and the CAN network model with two model nodes and the fault inputs on each bus.
--
-- Documentation: hdl/ocan_redundancy/docs/verification_plan.md

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
entity ocan_redundancy_net_th is
    generic (
        Parallel_g : boolean := false
    );
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Cfg_HbTime     : in    std_logic_vector(15 downto 0);
        Cfg_Ttoggle    : in    std_logic_vector(7 downto 0);
        Cfg_Ntoggle    : in    std_logic_vector(7 downto 0);
        Cfg_Bdefault   : in    std_logic;
        Cfg_CobId      : in    std_logic_vector(143 downto 0);
        ForceDom       : in    std_logic_vector(1 downto 0);
        ForceRec       : in    std_logic_vector(1 downto 0);
        -- Observed
        Stat_State     : out   std_logic_vector(1 downto 0);
        Ena_Pdo        : out   std_logic;
        Stat_ActiveBus : out   std_logic;
        Stat_Selecting : out   std_logic;
        Upd_Valid      : out   std_logic;
        Upd_Bdefault   : out   std_logic;
        Err_ToggleEnd  : out   std_logic;
        Nmt_Switched   : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_redundancy_net_th is

    constant ClkPeriod_c : time := 25 ns;

    function accessMode (parallel : boolean) return string is
    begin
        if parallel then
            return "Parallel";
        else
            return "Selective";
        end if;
    end function;

    signal ClkInt     : std_logic := '0';
    signal Tick       : std_logic;
    -- ocan_nmt
    signal NodeId     : std_logic_vector(6 downto 0);
    signal IdValid    : std_logic;
    signal EnaSdo     : std_logic;
    signal EnaPdo     : std_logic;
    signal EnaSync    : std_logic;
    signal NmtState   : std_logic_vector(1 downto 0);
    signal NmtValid   : std_logic;
    signal NmtCs      : std_logic_vector(7 downto 0);
    signal TxValid    : std_logic;
    signal TxReady    : std_logic;
    signal TxData     : std_logic_vector(7 downto 0);
    signal TxDone     : std_logic;
    signal TxAborted  : std_logic;
    -- ocan_redundancy
    signal PreopReq   : std_logic;
    signal Switched   : std_logic;
    signal Selecting  : std_logic;
    signal ActBus     : std_logic;
    signal ReqBus     : std_logic;
    signal RedNmt     : std_logic_vector(1 downto 0);
    signal RedHb      : std_logic_vector(1 downto 0);
    signal RedHbDlc   : std_logic_vector(7 downto 0);
    signal RedHbState : std_logic_vector(15 downto 0);
    -- ocan_link
    signal LkActive   : std_logic;
    signal LkSwitch   : std_logic;
    signal LkValid    : std_logic;
    signal LkReady    : std_logic;
    signal LkId       : std_logic_vector(28 downto 0);
    signal LkDlc      : std_logic_vector(3 downto 0);
    signal LkData     : std_logic_vector(63 downto 0);
    signal LkAbort    : std_logic;
    signal LkDone     : std_logic;
    signal LkAborted  : std_logic;
    signal RxValid    : std_logic_vector(1 downto 0);
    signal RxId       : std_logic_vector(57 downto 0);
    signal RxIde      : std_logic_vector(1 downto 0);
    signal RxRtr      : std_logic_vector(1 downto 0);
    signal RxDlc      : std_logic_vector(7 downto 0);
    signal RxData     : std_logic_vector(127 downto 0);
    signal CanTx      : std_logic_vector(1 downto 0);
    signal CanTxEn    : std_logic_vector(1 downto 0);
    signal CanRx      : std_logic_vector(1 downto 0);
    signal NodeTx     : std_logic_vector(3 downto 0);
    signal Level      : std_logic_vector(1 downto 0);
    -- Constant inputs as signals (no expressions as actuals)
    signal Zero       : std_logic                     := '0';
    signal PinId      : std_logic_vector(6 downto 0)  := std_logic_vector(to_unsigned(5, 7));
    signal PinCode    : std_logic_vector(6 downto 0)  := not std_logic_vector(to_unsigned(5, 7));
    signal NmtHbTime  : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(2, 16));
    signal Presc      : std_logic_vector(9 downto 0)  := std_logic_vector(to_unsigned(2, 10));
    signal Tseg1      : std_logic_vector(4 downto 0)  := std_logic_vector(to_unsigned(15, 5));
    signal Tseg2      : std_logic_vector(3 downto 0)  := std_logic_vector(to_unsigned(4, 4));
    signal Sjw        : std_logic_vector(2 downto 0)  := std_logic_vector(to_unsigned(4, 3));

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    Stat_State     <= NmtState;
    Ena_Pdo        <= EnaPdo;
    Stat_ActiveBus <= ActBus;
    Stat_Selecting <= Selecting;
    Nmt_Switched   <= Switched;

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

    i_red : entity work.ocan_redundancy
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Tick_Ms        => Tick,
            Rx_NmtValid    => RedNmt,
            Rx_HbValid     => RedHb,
            Rx_HbDlc       => RedHbDlc,
            Rx_HbState     => RedHbState,
            Cfg_HbTime     => Cfg_HbTime,
            Cfg_Bdefault   => Cfg_Bdefault,
            Cfg_Ttoggle    => Cfg_Ttoggle,
            Cfg_Ntoggle    => Cfg_Ntoggle,
            Upd_Valid      => Upd_Valid,
            Upd_Bdefault   => Upd_Bdefault,
            Link_Bus       => ReqBus,
            Link_ActiveBus => LkActive,
            Link_Switching => LkSwitch,
            Nmt_State      => NmtState,
            Nmt_PreopReq   => PreopReq,
            Nmt_Switched   => Switched,
            Stat_ActiveBus => ActBus,
            Stat_Selecting => Selecting,
            Stat_Ctoggle   => open,
            Stat_HbState   => open,
            Stat_HbPresent => open,
            Err_HbMissing  => open,
            Err_ToggleEnd  => Err_ToggleEnd,
            Err_HbDlc      => open
        );

    i_nmt : entity work.ocan_nmt
        port map (
            Clk            => ClkInt,
            Rst            => Rst,
            Pin_NodeId     => PinId,
            Pin_NodeIdCode => PinCode,
            Tick_Ms        => Tick,
            Cfg_HbTime     => NmtHbTime,
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
            Red_PreopReq   => PreopReq,
            Red_Switched   => Switched,
            Red_Selecting  => Selecting,
            Stat_State     => NmtState,
            Reset_App      => open,
            Reset_Comm     => open,
            Err_Cs         => open,
            Err_NodeId     => open,
            Err_TxTimeout  => open
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
            Red_ActiveBus      => ActBus,
            Red_Selecting      => Selecting,
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
            RxRed_NmtValid     => RedNmt,
            RxRed_HbValid      => RedHb,
            RxRed_HbDlc        => RedHbDlc,
            RxRed_HbState      => RedHbState,
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
        generic map (
            BusAccess_g => accessMode(Parallel_g)
        )
        port map (
            Clk             => ClkInt,
            Rst             => Rst,
            Ctrl_Enable     => IdValid,
            Ctrl_Bus        => ReqBus,
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
            Stat_ActiveBus  => LkActive,
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
                ForceDom => ForceDom(B),
                ForceRec => ForceRec(B)
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
