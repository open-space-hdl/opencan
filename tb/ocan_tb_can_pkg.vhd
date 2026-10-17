---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- CAN frame encoding of the CAN network model (Bosch CAN Specification 2.0 part B, sections 3 and 6): the frame
-- record, CRC-15, bit stuffing and the bit sequence of a complete data or remote frame on the bus. Written from the
-- specification, independent of the RTL. The bit vectors start with the start of frame at index 0; '0' is dominant.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ocan_tb_can_pkg is

    -- Longest frame on the bus: extended data frame with 8 bytes, all stuff bits, delimiters and end of frame
    constant CanMaxBits_c : positive := 160;

    -- A data or remote frame. Standard identifiers are in Id(28 downto 18); data byte 0 is Data(63 downto 56).
    type CanFrame_t is record
        Ide  : std_logic;
        Id   : std_logic_vector(28 downto 0);
        Rtr  : std_logic;
        Dlc  : natural range 0 to 15;
        Data : std_logic_vector(63 downto 0);
    end record;

    -- A bit sequence with the stuff bits marked ('1' in Stuff)
    type CanBits_t is record
        Len   : natural range 0 to CanMaxBits_c;
        Bits  : std_logic_vector(0 to CanMaxBits_c - 1);
        Stuff : std_logic_vector(0 to CanMaxBits_c - 1);
    end record;

    -- Frame constructors
    function canStd (
        Id   : natural;
        Dlc  : natural;
        Data : std_logic_vector(63 downto 0) := (others => '0');
        Rtr  : std_logic                     := '0') return CanFrame_t;

    function canExt (
        Id   : natural;
        Dlc  : natural;
        Data : std_logic_vector(63 downto 0) := (others => '0');
        Rtr  : std_logic                     := '0') return CanFrame_t;

    -- Number of data bytes on the bus: 0 for a remote frame, min(DLC, 8) otherwise
    function canDataBytes (F : CanFrame_t) return natural;

    -- Data bytes beyond the data length are 0
    function canNormalize (F : CanFrame_t) return CanFrame_t;

    -- CRC-15 over Bits(0 to Len - 1) (section 3.1.1.5)
    function canCrc15 (
        Bits : std_logic_vector;
        Len  : natural) return std_logic_vector;

    -- Destuffed bits from the start of frame to the end of the CRC sequence
    function canUnstuffed (F : CanFrame_t) return CanBits_t;

    -- Destuffed bits of the arbitration field after the start of frame: 12 (standard) or 32 (extended)
    function canArbBits (F : CanFrame_t) return natural;

    -- Bit stuffing of a destuffed bit sequence (section 6)
    function canStuff (U : CanBits_t) return CanBits_t;

    -- Complete frame on the bus from the start of frame to the last bit of the end of frame: the stuffed bits, the
    -- CRC delimiter, the acknowledge slot (Ack), the acknowledge delimiter and 7 recessive bits
    function canWire (
        F   : CanFrame_t;
        Ack : std_logic := '0') return CanBits_t;

    -- CRC-15 of a frame
    function canFrameCrc (F : CanFrame_t) return std_logic_vector;

    function canEqual (
        A : CanFrame_t;
        B : CanFrame_t) return boolean;

    function canImage (F : CanFrame_t) return string;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ocan_tb_can_pkg is

    function canStd (
        Id   : natural;
        Dlc  : natural;
        Data : std_logic_vector(63 downto 0) := (others => '0');
        Rtr  : std_logic                     := '0') return CanFrame_t is
        variable F_v : CanFrame_t;
    begin
        F_v.Ide              := '0';
        F_v.Id               := (others => '0');
        F_v.Id(28 downto 18) := std_logic_vector(to_unsigned(Id, 11));
        F_v.Rtr              := Rtr;
        F_v.Dlc              := Dlc;
        F_v.Data             := Data;
        return canNormalize(F_v);
    end function;

    function canExt (
        Id   : natural;
        Dlc  : natural;
        Data : std_logic_vector(63 downto 0) := (others => '0');
        Rtr  : std_logic                     := '0') return CanFrame_t is
        variable F_v : CanFrame_t;
    begin
        F_v.Ide  := '1';
        F_v.Id   := std_logic_vector(to_unsigned(Id, 29));
        F_v.Rtr  := Rtr;
        F_v.Dlc  := Dlc;
        F_v.Data := Data;
        return canNormalize(F_v);
    end function;

    function canDataBytes (F : CanFrame_t) return natural is
    begin
        if F.Rtr = '1' then
            return 0;
        elsif F.Dlc > 8 then
            return 8;
        else
            return F.Dlc;
        end if;
    end function;

    function canNormalize (F : CanFrame_t) return CanFrame_t is
        variable F_v : CanFrame_t := F;
    begin

        for B in canDataBytes(F) to 7 loop
            F_v.Data(63 - 8 * B downto 56 - 8 * B) := (others => '0');
        end loop;

        if F.Ide = '0' then
            F_v.Id(17 downto 0) := (others => '0');
        end if;
        return F_v;
    end function;

    function canCrc15 (
        Bits : std_logic_vector;
        Len  : natural) return std_logic_vector is
        variable Crc_v : std_logic_vector(14 downto 0) := (others => '0');
        variable Nxt_v : std_logic;
    begin

        for I in 0 to Len - 1 loop
            Nxt_v := Bits(Bits'low + I) xor Crc_v(14);
            Crc_v := Crc_v(13 downto 0) & '0';
            if Nxt_v = '1' then
                Crc_v := Crc_v xor "100010110011001";
            end if;
        end loop;

        return Crc_v;
    end function;

    -- Appends one bit to a bit sequence
    procedure canPut (
        variable U : inout CanBits_t;
        B          : std_logic) is
    begin
        U.Bits(U.Len) := B;
        U.Len         := U.Len + 1;
    end procedure;

    function canUnstuffed (F : CanFrame_t) return CanBits_t is
        variable U_v   : CanBits_t;
        variable Crc_v : std_logic_vector(14 downto 0);
        variable Dlc_v : std_logic_vector(3 downto 0);
    begin
        U_v.Len   := 0;
        U_v.Bits  := (others => '1');
        U_v.Stuff := (others => '0');
        canPut(U_v, '0');

        for I in 28 downto 18 loop
            canPut(U_v, F.Id(I));
        end loop;

        if F.Ide = '1' then
            canPut(U_v, '1');                   -- SRR
            canPut(U_v, '1');                   -- IDE

            for I in 17 downto 0 loop
                canPut(U_v, F.Id(I));
            end loop;

            canPut(U_v, F.Rtr);
            canPut(U_v, '0');                   -- r1
            canPut(U_v, '0');                   -- r0
        else
            canPut(U_v, F.Rtr);
            canPut(U_v, '0');                   -- IDE
            canPut(U_v, '0');                   -- r0
        end if;
        Dlc_v := std_logic_vector(to_unsigned(F.Dlc, 4));

        for I in 3 downto 0 loop
            canPut(U_v, Dlc_v(I));
        end loop;

        for I in 63 downto 64 - 8 * canDataBytes(F) loop
            canPut(U_v, F.Data(I));
        end loop;

        Crc_v := canCrc15(U_v.Bits, U_v.Len);

        for I in 14 downto 0 loop
            canPut(U_v, Crc_v(I));
        end loop;

        return U_v;
    end function;

    function canArbBits (F : CanFrame_t) return natural is
    begin
        if F.Ide = '1' then
            return 32;
        else
            return 12;
        end if;
    end function;

    function canStuff (U : CanBits_t) return CanBits_t is
        variable S_v    : CanBits_t;
        variable Last_v : std_logic := 'X';
        variable Run_v  : natural   := 0;
    begin
        S_v.Len   := 0;
        S_v.Bits  := (others => '1');
        S_v.Stuff := (others => '0');

        for I in 0 to U.Len - 1 loop
            S_v.Bits(S_v.Len) := U.Bits(I);
            S_v.Len           := S_v.Len + 1;
            if U.Bits(I) = Last_v then
                Run_v := Run_v + 1;
            else
                Run_v := 1;
            end if;
            Last_v := U.Bits(I);
            if Run_v = 5 then
                S_v.Bits(S_v.Len)  := not Last_v;
                S_v.Stuff(S_v.Len) := '1';
                S_v.Len            := S_v.Len + 1;
                Last_v             := not Last_v;
                Run_v              := 1;
            end if;
        end loop;

        return S_v;
    end function;

    function canWire (
        F   : CanFrame_t;
        Ack : std_logic := '0') return CanBits_t is
        variable W_v : CanBits_t;
    begin
        W_v := canStuff(canUnstuffed(F));
        -- CRC delimiter, acknowledge slot, acknowledge delimiter, end of frame
        W_v.Bits(W_v.Len to W_v.Len + 9) := '1' & Ack & "11111111";
        W_v.Len                          := W_v.Len + 10;
        return W_v;
    end function;

    function canFrameCrc (F : CanFrame_t) return std_logic_vector is
        constant U_c : CanBits_t := canUnstuffed(F);
    begin
        return U_c.Bits(U_c.Len - 15 to U_c.Len - 1);
    end function;

    function canEqual (
        A : CanFrame_t;
        B : CanFrame_t) return boolean is
        constant An_c : CanFrame_t := canNormalize(A);
        constant Bn_c : CanFrame_t := canNormalize(B);
    begin
        return An_c.Ide = Bn_c.Ide and An_c.Id = Bn_c.Id and An_c.Rtr = Bn_c.Rtr and An_c.Dlc = Bn_c.Dlc and
               An_c.Data = Bn_c.Data;
    end function;

    function canImage (F : CanFrame_t) return string is
    begin
        if F.Ide = '1' then
            return "ext id 0x" & to_hstring(F.Id) & " rtr " & to_string(F.Rtr) & " dlc " & integer'image(F.Dlc) &
                   " data 0x" & to_hstring(F.Data);
        else
            return "std id 0x" & to_hstring(F.Id(28 downto 18)) & " rtr " & to_string(F.Rtr) & " dlc " &
                   integer'image(F.Dlc) & " data 0x" & to_hstring(F.Data);
        end if;
    end function;

end package body;
