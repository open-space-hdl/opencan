---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Definitions shared by the OpenCAN modules: the encoding of the NMT state that ocan_nmt passes to
-- ocan_redundancy.
--
-- Documentation: hdl/ocan_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ocan_pkg is

    -- *** NMT state (PKG-01) ***
    subtype NmtState_t is std_logic_vector(1 downto 0);

    constant NmtInit_c    : NmtState_t := "00";
    constant NmtPreOp_c   : NmtState_t := "01";
    constant NmtOp_c      : NmtState_t := "10";
    constant NmtStopped_c : NmtState_t := "11";

end package;
