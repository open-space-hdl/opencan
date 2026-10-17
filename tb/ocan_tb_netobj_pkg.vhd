---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- The control object of the CAN network model, shared by the model nodes and the test processes, and the
-- log of the frames that the device under test passes.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library work;
    use work.ocan_tb_net_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ocan_tb_netobj_pkg is

    shared variable Net_v    : TbNet_t;
    shared variable DutLog_v : TbFrameLog_t;

end package;
