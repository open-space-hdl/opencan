---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of ocan_pkg: the constants are compared with the values of the specification, written here as literals.
--
-- Documentation: hdl/ocan_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_context;

library work;
    use work.ocan_tb_pkg.all;
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_pkg_tb is

begin

    p_control : process is
    begin
        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            -- *** TC-PKG-01: NMT state encoding of the specification (PKG-01) ***
            if run("test_nmt_state_encoding") then
                check_value(NmtState_t'length, 2, ERROR, "width of the NMT state");
                check_value(NmtInit_c, "00", ERROR, "Initialisation");
                check_value(NmtPreOp_c, "01", ERROR, "Pre-operational");
                check_value(NmtOp_c, "10", ERROR, "Operational");
                check_value(NmtStopped_c, "11", ERROR, "Stopped");
            end if;

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
