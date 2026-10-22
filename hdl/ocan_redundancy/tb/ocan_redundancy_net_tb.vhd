---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_redundancy: the slave node of ocan_redundancy, ocan_nmt, ocan_dispatch and ocan_link on
-- the CAN network model, with a Redundancy Master model that produces its heartbeat on a chosen bus and sends NMT
-- messages, and faults that break a bus. The bus switch of the master (TC-RM-17), the master on the other bus during a
-- bus selection with parallel bus access (TC-RM-18) and broken and stuck buses (TC-RM-19).
--
-- Documentation: hdl/ocan_redundancy/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_context;

library work;
    use work.ocan_tb_pkg.all;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_redundancy_net_tb is
    generic (
        runner_cfg : string;
        Parallel_g : boolean := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_redundancy_net_tb is

    constant NodeId_c : natural := 5;
    constant HbId_c   : natural := 16#700# + NodeId_c;

    type Ids_t is array (0 to 11) of natural;

    -- Pre-defined connection set of NODE-ID 5, master heartbeat of NODE-ID 1
    constant Ids_c : Ids_t := (16#080#, 16#0F0#, 16#205#, 16#305#, 16#405#, 16#505#, 16#185#, 16#285#, 16#385#,
                               16#485#, 16#1F5#, 16#701#);

    function table (ids : Ids_t) return std_logic_vector is
        variable T_v : std_logic_vector(143 downto 0);
    begin

        for E in 0 to 11 loop
            T_v(12 * E + 11)               := '1';
            T_v(12 * E + 10 downto 12 * E) := std_logic_vector(to_unsigned(ids(E), 11));
        end loop;

        return T_v;
    end function;

    signal Clk            : std_logic;
    signal Rst            : std_logic                      := '1';
    signal Cfg_HbTime     : std_logic_vector(15 downto 0)  := std_logic_vector(to_unsigned(3, 16));
    signal Cfg_Ttoggle    : std_logic_vector(7 downto 0)   := std_logic_vector(to_unsigned(2, 8));
    signal Cfg_Ntoggle    : std_logic_vector(7 downto 0)   := std_logic_vector(to_unsigned(4, 8));
    signal Cfg_Bdefault   : std_logic                      := '0';
    signal Cfg_CobId      : std_logic_vector(143 downto 0) := table(Ids_c);
    signal ForceDom       : std_logic_vector(1 downto 0)   := "00";
    signal ForceRec       : std_logic_vector(1 downto 0)   := "00";
    signal Stat_State     : std_logic_vector(1 downto 0);
    signal Ena_Pdo        : std_logic;
    signal Stat_ActiveBus : std_logic;
    signal Stat_Selecting : std_logic;
    signal Upd_Valid      : std_logic;
    signal Upd_Bdefault   : std_logic;
    signal Err_ToggleEnd  : std_logic;
    signal Nmt_Switched   : std_logic;

    -- Redundancy Master model: heartbeat (state Operational) every HbPeriod on bus MasterBus while MasterOn
    signal MasterOn  : boolean := false;
    signal MasterBus : natural := 0;

    constant HbPeriod_c : time := 1 ms;

    -- Monitors
    signal CntUpd : natural := 0;
    signal UpdBus : std_logic;
    signal CntEnd : natural := 0;
    signal CntSw  : natural := 0;
    signal TimeSw : time    := 0 ns;

begin

    test_runner_watchdog(runner, 400 ms);

    i_th : entity work.ocan_redundancy_net_th
        generic map (
            Parallel_g => Parallel_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Cfg_HbTime     => Cfg_HbTime,
            Cfg_Ttoggle    => Cfg_Ttoggle,
            Cfg_Ntoggle    => Cfg_Ntoggle,
            Cfg_Bdefault   => Cfg_Bdefault,
            Cfg_CobId      => Cfg_CobId,
            ForceDom       => ForceDom,
            ForceRec       => ForceRec,
            Stat_State     => Stat_State,
            Ena_Pdo        => Ena_Pdo,
            Stat_ActiveBus => Stat_ActiveBus,
            Stat_Selecting => Stat_Selecting,
            Upd_Valid      => Upd_Valid,
            Upd_Bdefault   => Upd_Bdefault,
            Err_ToggleEnd  => Err_ToggleEnd,
            Nmt_Switched   => Nmt_Switched
        );

    p_master : process is
    begin
        wait for HbPeriod_c;
        if MasterOn and Net_v.txCount(2 * MasterBus) < 2 then
            Net_v.txPush(2 * MasterBus, canStd(16#701#, 1, x"0500000000000000"));
        end if;
    end process;

    p_mon : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Upd_Valid = '1' then
                CntUpd <= CntUpd + 1;
                UpdBus <= Upd_Bdefault;
            end if;
            if Err_ToggleEnd = '1' then
                CntEnd <= CntEnd + 1;
            end if;
            if Nmt_Switched = '1' then
                CntSw  <= CntSw + 1;
                TimeSw <= now;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable N_v : natural;

        -- NMT message of the master on bus b (node 0 on bus A, node 2 on bus B)
        procedure nmtMaster (b : natural; cs : natural) is
            variable D_v : std_logic_vector(63 downto 0) := (others => '0');
        begin
            D_v(63 downto 56) := std_logic_vector(to_unsigned(cs, 8));
            D_v(55 downto 48) := std_logic_vector(to_unsigned(NodeId_c, 8));
            Net_v.txPush(2 * b, canStd(0, 2, D_v));
        end procedure;

        -- Time of the first frame of the node in the log of the master node on bus b after time t0; 0 ns: none
        impure function firstDut (b : natural; t0 : time) return time is
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(2 * b) - 1 loop
                E_v := Net_v.logGet(2 * b, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t0 and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = HbId_c then
                    return E_v.T;
                end if;
            end loop;

            return 0 ns;
        end function;

        procedure startNode is
        begin
            Rst <= '1';
            wait for 250 ns;
            wait until rising_edge(Clk);
            Rst <= '0';
        end procedure;

        procedure waitSig (signal s : std_logic; val : std_logic; timeout : time; msg : string) is
            constant End_c : time := now + timeout;
        begin

            while s /= val and now < End_c loop
                wait for 10 us;
            end loop;

            if s /= val then
                alert(ERROR, "timeout: " & msg);
            end if;
        end procedure;

        variable T_v : time;
        variable C_v : natural;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            -- *** TC-RM-17: the master moves its heartbeat to the other bus ***
            if run("test_net_switch") then
                MasterBus <= 0;
                MasterOn  <= true;
                startNode;
                -- The master heartbeat ends the start-up bus selection on bus A; start remote node
                waitSig(Stat_Selecting, '1', 2 ms, "start-up bus selection");
                waitSig(Stat_Selecting, '0', 10 ms, "start-up bus selection ended by the master heartbeat");
                nmtMaster(0, 1);
                wait for 3 ms;
                check_value(Stat_State, NmtOp_c, ERROR, "Operational after start remote node");
                check_value(Stat_ActiveBus, '0', ERROR, "bus A active");
                -- The master moves to bus B (clause 8.3.3b)
                MasterBus <= 1;
                C_v       := CntSw;
                waitSig(Stat_Selecting, '1', 12 ms, "missing master heartbeat");
                wait for 100 us;
                check_value(Ena_Pdo, '0', ERROR, "Pre-operational during the bus selection");
                waitSig(Stat_Selecting, '0', 20 ms, "bus B found");
                check_value(Stat_ActiveBus, '1', ERROR, "bus B active");
                check_value(UpdBus, '1', ERROR, "Bdefault updated to bus B");
                T_v       := firstDut(1, TimeSw - 1 us);
                check_value(T_v > 0 ns and T_v - TimeSw < 500 us, ERROR,
                            "heartbeat of the node on bus B at once after the switch");
                nmtMaster(1, 1);
                wait for 3 ms;
                check_value(Stat_State, NmtOp_c, ERROR, "Operational after start remote node on bus B");

            -- *** TC-RM-18: the master appears on the other bus during a bus selection (parallel bus access) ***
            elsif run("test_net_master_other_bus") then
                check_value(Parallel_g, true, ERROR, "test_net_master_other_bus runs with parallel bus access");

                for K in 0 to 1 loop
                    MasterOn <= false;
                    startNode;
                    wait for 3 ms;
                    check_value(Stat_Selecting, '1', ERROR, "start-up bus selection on bus A");
                    C_v      := CntUpd;
                    T_v      := now;
                    if K = 0 then
                        MasterBus <= 1;
                        MasterOn  <= true;
                    else
                        nmtMaster(1, 1);
                    end if;
                    waitSig(Stat_Selecting, '0', 2 ms, "bus selection ended by the master on bus B");
                    check_value(now - T_v < 2 ms, ERROR, "switch at once, before the first toggle");
                    check_value(Stat_ActiveBus, '1', ERROR, "bus B active");
                    check_value(UpdBus, '1', ERROR, "Bdefault updated to bus B");
                    wait for 1 ms;
                    T_v := firstDut(1, TimeSw - 1 us);
                    check_value(T_v > 0 ns and T_v - TimeSw < 500 us, ERROR, "heartbeat of the node on bus B");
                    if K = 1 then
                        check_value(Stat_State, NmtOp_c, ERROR, "the NMT message is processed on bus B");
                    end if;
                    MasterOn <= false;
                    wait for 2 ms;
                end loop;

            -- *** TC-RM-19: broken and stuck buses ***
            elsif run("test_net_bus_faults") then
                Cfg_Ntoggle <= std_logic_vector(to_unsigned(3, 8));

                -- Bus A stuck dominant, then bus A broken, with the master on bus B
                for K in 0 to 1 loop
                    if K = 0 then
                        ForceDom <= "01";
                        ForceRec <= "00";
                    else
                        ForceDom <= "00";
                        ForceRec <= "01";
                    end if;
                    MasterBus <= 1;
                    MasterOn  <= true;
                    startNode;
                    waitSig(Stat_ActiveBus, '1', 20 ms, "bus B found");
                    waitSig(Stat_Selecting, '0', 5 ms, "bus selection ended on bus B");
                    check_value(UpdBus, '1', ERROR, "Bdefault updated to bus B");
                    MasterOn  <= false;
                    ForceDom  <= "00";
                    ForceRec  <= "00";
                    wait for 2 ms;
                end loop;

                -- Both buses broken: Ntoggle toggles, then Err_ToggleEnd; bus B repaired with the master on it
                ForceRec  <= "11";
                MasterBus <= 1;
                MasterOn  <= true;
                C_v       := CntEnd;
                startNode;
                waitSig(Stat_Selecting, '1', 5 ms, "start-up bus selection");
                N_v       := 0;

                while CntEnd = C_v and N_v < 400 loop
                    wait for 100 us;
                    N_v := N_v + 1;
                end loop;

                check_value(CntEnd, C_v + 1, ERROR, "Err_ToggleEnd after Ntoggle toggles");
                check_value(Stat_ActiveBus, '1', ERROR, "after three toggles on bus B");
                ForceRec <= "01";
                waitSig(Stat_Selecting, '0', 5 ms, "the master heartbeat on the repaired bus B ends the process");
                check_value(UpdBus, '1', ERROR, "Bdefault updated to bus B");

            end if;

        end loop;

        ocanTestEnd(runner);

    end process;

end architecture;
