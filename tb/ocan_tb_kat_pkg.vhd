---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Known-answer frames for the CAN network model: complete frames as they appeared on real buses, from the
-- start of frame to the end of frame with the acknowledge slot dominant, and the position of every stuff bit
-- (Bits and Stuff in hexadecimal, bit 0 is the start of frame). Generated; do not edit. Sources:
--   - sigrok-test, decoder/test/can: expected decoder outputs of captures of a Microchip MCP2515DM-BM demo
--     board at 125 kbit/s (mcp2515dm-bm-125kbits_*.output, github.com/sigrokproject/sigrok-test)
--   - K. Tindell, "canframe.py", kentindell.github.io, 3 January 2020: standard identifier 014h, one data
--     byte 01h, CRC 7753h, confirmed by a logic analyser trace of an STM32F405 bxCAN controller
-- Every frame was checked against CRC-15 and the bit stuffing of the Bosch CAN 2.0 specification part B
-- before it was written.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ocan_tb_kat_pkg is

    constant KatBits_c  : positive := 160;
    constant KatCount_c : positive := 6;

    type KatFrame_t is record
        Ide   : std_logic;
        Id    : std_logic_vector(28 downto 0);
        Rtr   : std_logic;
        Dlc   : natural range 0 to 15;
        Data  : std_logic_vector(63 downto 0);
        Crc   : std_logic_vector(14 downto 0);
        Len   : natural range 0 to KatBits_c;
        Bits  : std_logic_vector(0 to KatBits_c - 1);
        Stuff : std_logic_vector(0 to KatBits_c - 1);
    end record;

    -- Frame n, 0 to KatCount_c - 1
    function katFrame (n : natural) return KatFrame_t;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ocan_tb_kat_pkg is

    function katFrame (n : natural) return KatFrame_t is
        variable K_v : KatFrame_t;
    begin

        case n is

            when 0 =>
                -- mcp2515dm-bm-125kbits_bus_load_100percent.output
                K_v.Ide   := '1';
                K_v.Id    := 29x"14611234";
                K_v.Rtr   := '0';
                K_v.Dlc   := 4;
                K_v.Data  := x"0001020300000000";
                K_v.Crc   := 15x"3FBF";
                K_v.Len   := 104;
                K_v.Bits  := x"518D123414104120A09BEDF6FF00000000000000";
                K_v.Stuff := x"0000000010104100808010080000000000000000";

            when 1 =>
                -- mcp2515dm-bm-125kbits_bus_load_100percent.output
                K_v.Ide   := '0';
                K_v.Id    := 29x"04400000";
                K_v.Rtr   := '0';
                K_v.Dlc   := 2;
                K_v.Data  := x"0011000000000000";
                K_v.Crc   := 15x"4C12";
                K_v.Len   := 64;
                K_v.Bits  := x"110420824660CAFF000000000000000000000000";
                K_v.Stuff := x"0004008200008000000000000000000000000000";

            when 2 =>
                -- mcp2515dm-bm-125kbits_bus_load_100percent.output
                K_v.Ide   := '0';
                K_v.Id    := 29x"15400000";
                K_v.Rtr   := '0';
                K_v.Dlc   := 8;
                K_v.Data  := x"AABBCCDDEEFF0A0B";
                K_v.Crc   := 15x"4FBC";
                K_v.Len   := 112;
                K_v.Bits  := x"55048AABBCCDDEEFB8506E7CF2FF000000000000";
                K_v.Stuff := x"0004000000000000400040020000000000000000";

            when 3 =>
                -- mcp2515dm-bm-125kbits_extmsg_11223344_7bytes.output
                K_v.Ide   := '1';
                K_v.Id    := 29x"11223344";
                K_v.Rtr   := '0';
                K_v.Dlc   := 7;
                K_v.Data  := x"0011223344556600";
                K_v.Crc   := 15x"0D30";
                K_v.Len   := 123;
                K_v.Bits  := x"448E3344170414488CD1155986985FE000000000";
                K_v.Stuff := x"0000000010041000000000000000000000000000";

            when 4 =>
                -- mcp2515dm-bm-125kbits_msg_222_5bytes.output
                K_v.Ide   := '0';
                K_v.Id    := 29x"08880000";
                K_v.Rtr   := '0';
                K_v.Dlc   := 5;
                K_v.Data  := x"0011223344000000";
                K_v.Crc   := 15x"66DA";
                K_v.Len   := 87;
                K_v.Bits  := x"2220D0414488CD1336D5FE000000000000000000";
                K_v.Stuff := x"0000804100000000000000000000000000000000";

            when 5 =>
                -- K. Tindell, canframe.py tool, kentindell.github.io 2020-01-03 (STM32F405 bxCAN trace)
                K_v.Ide   := '0';
                K_v.Id    := 29x"00500000";
                K_v.Rtr   := '0';
                K_v.Dlc   := 1;
                K_v.Data  := x"0100000000000000";
                K_v.Crc   := 15x"7753";
                K_v.Len   := 55;
                K_v.Bits  := x"04A08827BA9DFE00000000000000000000000000";
                K_v.Stuff := x"0400802000000000000000000000000000000000";

            when others =>
                report "ocan_tb_kat_pkg: no frame " & integer'image(n)
                    severity failure;

        end case;

        return K_v;
    end function;

end package body;
