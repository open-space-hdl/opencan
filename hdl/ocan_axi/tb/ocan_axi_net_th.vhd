---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the network testbench of ocan_axi: ocan_axi with the AXI-Lite VVC master as the software, and two
-- CAN buses with two model nodes each (M1 index 2 b, M2 index 2 b + 1 on bus b).
--
-- Documentation: hdl/ocan_axi/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ocan_tb_axi_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_axi_net_th is
    generic (
        BusAccess_g  : string                   := "Selective";
        MinimalSet_g : boolean                  := false;
        TimePdos_g   : boolean                  := true;
        NumRpdo_g    : natural range 0 to 4     := 4;
        NumTpdo_g    : natural range 0 to 4     := 4;
        AutoEnable_g : boolean                  := false;
        Prescaler_g  : positive range 1 to 1023 := 4;
        ErrInjRegs_g : boolean                  := false
    );
    port (
        Clk            : out   std_logic;
        Rst            : in    std_logic;
        Irq            : out   std_logic;
        Pin_NodeId     : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode : in    std_logic_vector(6 downto 0);
        Bus_ForceDom   : in    std_logic_vector(1 downto 0);
        Bus_ForceRec   : in    std_logic_vector(1 downto 0);
        Bus_DutRec     : in    std_logic_vector(1 downto 0);
        Bus_Level      : out   std_logic_vector(1 downto 0);
        Can_TxEn       : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_axi_net_th is

    -- 50 MHz: 50 time quanta of 20 ns per bit at 1 Mbit/s with prescaler 2 (2, 18, 6, 4)
    constant ClkPeriod_c : time := 20 ns;

    signal ClkInt    : std_logic := '0';
    signal CanTx     : std_logic_vector(1 downto 0);
    signal CanTxEn   : std_logic_vector(1 downto 0);
    signal CanRx     : std_logic_vector(1 downto 0);
    signal NodeTx    : std_logic_vector(3 downto 0);
    signal Level     : std_logic_vector(1 downto 0);
    signal AxArAddr  : std_logic_vector(8 downto 0);
    signal AxArValid : std_logic;
    signal AxArReady : std_logic;
    signal AxAwAddr  : std_logic_vector(8 downto 0);
    signal AxAwValid : std_logic;
    signal AxAwReady : std_logic;
    signal AxWData   : std_logic_vector(31 downto 0);
    signal AxWStrb   : std_logic_vector(3 downto 0);
    signal AxWValid  : std_logic;
    signal AxWReady  : std_logic;
    signal AxBResp   : std_logic_vector(1 downto 0);
    signal AxBValid  : std_logic;
    signal AxBReady  : std_logic;
    signal AxRData   : std_logic_vector(31 downto 0);
    signal AxRResp   : std_logic_vector(1 downto 0);
    signal AxRValid  : std_logic;
    signal AxRReady  : std_logic;

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    Bus_Level <= Level;
    Can_TxEn  <= CanTxEn;

    i_dut : entity work.ocan_axi
        generic map (
            BusAccess_g      => BusAccess_g,
            MinimalSet_g     => MinimalSet_g,
            NumRpdo_g        => NumRpdo_g,
            NumTpdo_g        => NumTpdo_g,
            TimePdos_g       => TimePdos_g,
            ClkFrequency_g   => 50000000,
            FineBits_g       => 24,
            VendorId_g       => x"800004D8",
            ProductCode_g    => x"0000C0DE",
            ProducerHbTime_g => 5,
            MasterNodeId_g   => 1,
            MasterHbTime_g   => 10,
            Ttoggle_g        => 1,
            Ntoggle_g        => 2,
            SctCobId_g       => 16#0F0#,
            SctType_g        => 254,
            LtpCobId_g       => 16#1F5#,
            LtpType_g        => 254,
            AutoEnable_g     => AutoEnable_g,
            Prescaler_g      => Prescaler_g,
            Tseg1_g          => 18,
            Tseg2_g          => 6,
            Sjw_g            => 4,
            ErrInjRegs_g     => ErrInjRegs_g
        )
        port map (
            Clk               => ClkInt,
            Rst               => Rst,
            S_AxiLite_ArAddr  => AxArAddr,
            S_AxiLite_ArValid => AxArValid,
            S_AxiLite_ArReady => AxArReady,
            S_AxiLite_AwAddr  => AxAwAddr,
            S_AxiLite_AwValid => AxAwValid,
            S_AxiLite_AwReady => AxAwReady,
            S_AxiLite_WData   => AxWData,
            S_AxiLite_WStrb   => AxWStrb,
            S_AxiLite_WValid  => AxWValid,
            S_AxiLite_WReady  => AxWReady,
            S_AxiLite_BResp   => AxBResp,
            S_AxiLite_BValid  => AxBValid,
            S_AxiLite_BReady  => AxBReady,
            S_AxiLite_RData   => AxRData,
            S_AxiLite_RResp   => AxRResp,
            S_AxiLite_RValid  => AxRValid,
            S_AxiLite_RReady  => AxRReady,
            Irq               => Irq,
            Pin_NodeId        => Pin_NodeId,
            Pin_NodeIdCode    => Pin_NodeIdCode,
            Can_Tx            => CanTx,
            Can_TxEn          => CanTxEn,
            Can_Rx            => CanRx
        );

    i_axi : entity work.ocan_tb_axilite_master
        generic map (
            InstanceIdx_g => 0,
            AddrWidth_g   => AxiAddrBits_c
        )
        port map (
            Clk     => ClkInt,
            ArAddr  => AxArAddr,
            ArValid => AxArValid,
            ArReady => AxArReady,
            AwAddr  => AxAwAddr,
            AwValid => AxAwValid,
            AwReady => AxAwReady,
            WData   => AxWData,
            WStrb   => AxWStrb,
            WValid  => AxWValid,
            WReady  => AxWReady,
            BResp   => AxBResp,
            BValid  => AxBValid,
            BReady  => AxBReady,
            RData   => AxRData,
            RResp   => AxRResp,
            RValid  => AxRValid,
            RReady  => AxRReady
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
                ForceDom => Bus_ForceDom(B),
                ForceRec => Bus_ForceRec(B),
                DutRec   => Bus_DutRec(B)
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
