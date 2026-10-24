---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- One bus of the CAN network model: the wired-AND of the model nodes, of the device under test (through the
-- transmit enable of its transceiver) and of a fault input. ForceDom holds the bus dominant, ForceRec recessive
-- (ForceDom wins). With Blind = '1' the receive input of the device under test sees the bus without its own
-- transmit bit, so that its dominant bits do not reach its receiver. DutRec holds the receive input of the device
-- under test recessive and leaves the bus as it is: a disturbance that only the device under test sees, so that
-- the model nodes acknowledge a frame in which it detects a CRC error. '0' is dominant.
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
entity ocan_tb_can_bus is
    generic (
        NumNodes_g : positive;
        Delay_g    : time := 0 ns
    );
    port (
        -- Model nodes
        Node_Tx  : in    std_logic_vector(NumNodes_g - 1 downto 0);
        Node_Rx  : out   std_logic;
        -- Device under test
        Dut_Tx   : in    std_logic := '1';
        Dut_TxEn : in    std_logic := '1';
        Dut_Rx   : out   std_logic;
        -- Faults
        ForceDom : in    std_logic := '0';
        ForceRec : in    std_logic := '0';
        DutRec   : in    std_logic := '0';
        Blind    : in    std_logic := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_tb_can_bus is

    signal Nodes : std_logic;
    signal Level : std_logic;

begin

    p_level : process (all) is
        variable Acc_v : std_logic;
    begin
        Acc_v := '1';

        for I in Node_Tx'range loop
            if to_X01(Node_Tx(I)) = '0' then
                Acc_v := '0';
            end if;
        end loop;

        if ForceDom = '1' then
            Acc_v := '0';
        elsif ForceRec = '1' then
            Acc_v := '1';
        end if;
        Nodes <= Acc_v;
        if Dut_TxEn = '1' and to_X01(Dut_Tx) = '0' and ForceRec /= '1' then
            Level <= '0';
        else
            Level <= Acc_v;
        end if;
    end process;

    Node_Rx <= transport Level after Delay_g;
    Dut_Rx  <= transport '1' after Delay_g when DutRec = '1' else
               Nodes after Delay_g when Blind = '1' else
               Level after Delay_g;

end architecture;
