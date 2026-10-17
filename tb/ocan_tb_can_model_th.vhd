---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of the self-test of the CAN network model: two model nodes (index 0 and 1) and a raw bit driver of the
-- test on one bus.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_tb_can_model_th is
    port (
        RawTx  : in    std_logic := '1';
        BusOut : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_tb_can_model_th is

    signal NodeTx : std_logic_vector(2 downto 0);
    signal CanBus : std_logic;

begin

    NodeTx(2) <= RawTx;
    BusOut    <= CanBus;

    i_bus : entity work.ocan_tb_can_bus
        generic map (
            NumNodes_g => 3
        )
        port map (
            Node_Tx => NodeTx,
            Node_Rx => CanBus
        );

    g_node : for I in 0 to 1 generate

        i_node : entity work.ocan_tb_can_node
            generic map (
                Index_g => I
            )
            port map (
                Tx => NodeTx(I),
                Rx => CanBus
            );

    end generate;

end architecture;
