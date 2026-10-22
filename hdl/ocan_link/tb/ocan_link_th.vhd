---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of ocan_link: the clock (40 MHz), the device under test and the CAN network model with bus A (model nodes
-- 0 and 1) and bus B (model nodes 2 and 3). Every received frame of the device is logged in DutLog_v with its bus.
--
-- Documentation: hdl/ocan_link/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_link_th is
    generic (
        BusAccess_g     : string   := "Selective";
        SyncStages_g    : positive := 2;
        AutoRecover_g   : boolean  := true;
        DominantLimit_g : positive := 32
    );
    port (
        Clk               : out   std_logic;
        Rst               : in    std_logic;
        Ctrl_Enable       : in    std_logic;
        Ctrl_Bus          : in    std_logic;
        Ctrl_Recover      : in    std_logic;
        Ctrl_Reenable     : in    std_logic_vector(1 downto 0);
        Cfg_Prescaler     : in    std_logic_vector(9 downto 0);
        Cfg_Tseg1         : in    std_logic_vector(4 downto 0);
        Cfg_Tseg2         : in    std_logic_vector(3 downto 0);
        Cfg_Sjw           : in    std_logic_vector(2 downto 0);
        Tx_Valid          : in    std_logic;
        Tx_Ready          : out   std_logic;
        Tx_Id             : in    std_logic_vector(28 downto 0);
        Tx_Ide            : in    std_logic;
        Tx_Rtr            : in    std_logic;
        Tx_Dlc            : in    std_logic_vector(3 downto 0);
        Tx_Data           : in    std_logic_vector(63 downto 0);
        Tx_Abort          : in    std_logic;
        Tx_Done           : out   std_logic;
        Tx_Aborted        : out   std_logic;
        Tx_ArbLost        : out   std_logic;
        Tx_Stopped        : out   std_logic;
        Rx_Valid          : out   std_logic_vector(1 downto 0);
        Stat_ActiveBus    : out   std_logic;
        Stat_Switching    : out   std_logic;
        Stat_Tec          : out   std_logic_vector(17 downto 0);
        Stat_Rec          : out   std_logic_vector(15 downto 0);
        Stat_State        : out   std_logic_vector(3 downto 0);
        Stat_BusIdle      : out   std_logic_vector(1 downto 0);
        Stat_DomTimeout   : out   std_logic_vector(1 downto 0);
        Err_Bit           : out   std_logic_vector(1 downto 0);
        Err_Stuff         : out   std_logic_vector(1 downto 0);
        Err_Crc           : out   std_logic_vector(1 downto 0);
        Err_Form          : out   std_logic_vector(1 downto 0);
        Err_Ack           : out   std_logic_vector(1 downto 0);
        Err_DomTimeout    : out   std_logic_vector(1 downto 0);
        ErrInj_TxDominant : in    std_logic_vector(1 downto 0);
        ErrInj_StopFlip   : in    std_logic_vector(1 downto 0);
        -- Bus side, observed by the test
        Can_Tx            : out   std_logic_vector(1 downto 0);
        Can_TxEn          : out   std_logic_vector(1 downto 0);
        BusLevel          : out   std_logic_vector(1 downto 0);
        -- Faults per bus
        ForceDom          : in    std_logic_vector(1 downto 0);
        ForceRec          : in    std_logic_vector(1 downto 0);
        Blind             : in    std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_link_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt   : std_logic := '0';
    signal CanTxInt : std_logic_vector(1 downto 0);
    signal CanTxEn  : std_logic_vector(1 downto 0);
    signal CanRx    : std_logic_vector(1 downto 0);
    signal NodeTx   : std_logic_vector(3 downto 0);
    signal Level    : std_logic_vector(1 downto 0);
    signal RxValid  : std_logic_vector(1 downto 0);
    signal RxId     : std_logic_vector(57 downto 0);
    signal RxIde    : std_logic_vector(1 downto 0);
    signal RxRtr    : std_logic_vector(1 downto 0);
    signal RxDlc    : std_logic_vector(7 downto 0);
    signal RxData   : std_logic_vector(127 downto 0);

begin

    ClkInt   <= not ClkInt after ClkPeriod_c / 2;
    Clk      <= ClkInt;
    Can_Tx   <= CanTxInt;
    Can_TxEn <= CanTxEn;
    BusLevel <= Level;
    Rx_Valid <= RxValid;

    i_dut : entity work.ocan_link
        generic map (
            BusAccess_g     => BusAccess_g,
            SyncStages_g    => SyncStages_g,
            AutoRecover_g   => AutoRecover_g,
            DominantLimit_g => DominantLimit_g
        )
        port map (
            Clk               => ClkInt,
            Rst               => Rst,
            Ctrl_Enable       => Ctrl_Enable,
            Ctrl_Bus          => Ctrl_Bus,
            Ctrl_Recover      => Ctrl_Recover,
            Ctrl_Reenable     => Ctrl_Reenable,
            Cfg_Prescaler     => Cfg_Prescaler,
            Cfg_Tseg1         => Cfg_Tseg1,
            Cfg_Tseg2         => Cfg_Tseg2,
            Cfg_Sjw           => Cfg_Sjw,
            Tx_Valid          => Tx_Valid,
            Tx_Ready          => Tx_Ready,
            Tx_Id             => Tx_Id,
            Tx_Ide            => Tx_Ide,
            Tx_Rtr            => Tx_Rtr,
            Tx_Dlc            => Tx_Dlc,
            Tx_Data           => Tx_Data,
            Tx_Abort          => Tx_Abort,
            Tx_Done           => Tx_Done,
            Tx_Aborted        => Tx_Aborted,
            Tx_ArbLost        => Tx_ArbLost,
            Tx_Stopped        => Tx_Stopped,
            Rx_Valid          => RxValid,
            Rx_Id             => RxId,
            Rx_Ide            => RxIde,
            Rx_Rtr            => RxRtr,
            Rx_Dlc            => RxDlc,
            Rx_Data           => RxData,
            Stat_ActiveBus    => Stat_ActiveBus,
            Stat_Switching    => Stat_Switching,
            Stat_Tec          => Stat_Tec,
            Stat_Rec          => Stat_Rec,
            Stat_State        => Stat_State,
            Stat_BusIdle      => Stat_BusIdle,
            Stat_DomTimeout   => Stat_DomTimeout,
            Err_Bit           => Err_Bit,
            Err_Stuff         => Err_Stuff,
            Err_Crc           => Err_Crc,
            Err_Form          => Err_Form,
            Err_Ack           => Err_Ack,
            Err_DomTimeout    => Err_DomTimeout,
            ErrInj_TxDominant => ErrInj_TxDominant,
            ErrInj_StopFlip   => ErrInj_StopFlip,
            Can_Tx            => CanTxInt,
            Can_TxEn          => CanTxEn,
            Can_Rx            => CanRx
        );

    -- *** Network model: bus A (nodes 0, 1) and bus B (nodes 2, 3) ***
    g_bus : for B in 0 to 1 generate

        i_bus : entity work.ocan_tb_can_bus
            generic map (
                NumNodes_g => 2
            )
            port map (
                Node_Tx  => NodeTx(2 * B + 1 downto 2 * B),
                Node_Rx  => Level(B),
                Dut_Tx   => CanTxInt(B),
                Dut_TxEn => CanTxEn(B),
                Dut_Rx   => CanRx(B),
                ForceDom => ForceDom(B),
                ForceRec => ForceRec(B),
                Blind    => Blind(B)
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

    -- *** Log of the received frames of the device ***
    p_rxlog : process (ClkInt) is
        variable F_v : CanFrame_t;
    begin
        if rising_edge(ClkInt) then

            for B in 0 to 1 loop
                if RxValid(B) = '1' then
                    F_v.Id   := RxId(29 * B + 28 downto 29 * B);
                    F_v.Ide  := RxIde(B);
                    F_v.Rtr  := RxRtr(B);
                    F_v.Dlc  := to_integer(unsigned(RxDlc(4 * B + 3 downto 4 * B)));
                    F_v.Data := RxData(64 * B + 63 downto 64 * B);
                    DutLog_v.push(B, F_v);
                end if;
            end loop;

        end if;
    end process;

end architecture;
