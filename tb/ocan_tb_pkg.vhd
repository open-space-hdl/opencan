---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Common testbench functions of OpenCAN: the end of a test, which fails on unexpected UVVM alerts and on expected
-- alerts that did not occur.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ocan_tb_pkg is

    procedure ocanTestEnd (signal runner : inout runner_sync_t);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ocan_tb_pkg is

    procedure ocanTestEnd (signal runner : inout runner_sync_t) is
        variable Mismatch_v : boolean := false;
    begin
        report_alert_counters(FINAL);

        -- UVVM updates its end status (shared_uvvm_status) only when an alert occurs, so an expected alert
        -- that never came would pass unnoticed: the counters are compared here
        for L in WARNING to TB_FAILURE loop

            if L /= MANUAL_CHECK and get_alert_counter(L, REGARD) /= get_alert_counter(L, EXPECT) then
                Mismatch_v := true;
                log(ID_SEQUENCER, t_alert_level'image(L) & ": " & integer'image(get_alert_counter(L, REGARD))
                                  & " alerts, " & integer'image(get_alert_counter(L, EXPECT)) & " expected",
                    "ocanTestEnd");
            end if;

        end loop;

        -- A failure ends the simulation, whatever the stop limits of the test
        assert not Mismatch_v
            report "ocanTestEnd: the alerts of the test differ from the expected alerts (summary above)"
            severity failure;
        test_runner_cleanup(runner);
    end procedure;

end package body;
