---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_nmt: ocan_nmt with ocan_dispatch and ocan_link on the CAN network model. The boot-up
-- message as the first frame and the heartbeats on the bus with NMT messages and a node guarding request of a master
-- model node (TC-NM-14), and a boot-up message that no node acknowledges (TC-NM-15).
--
-- Documentation: hdl/ocan_nmt/docs/verification_plan.md

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
entity ocan_nmt_net_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_nmt_net_tb is

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
    signal Pin_NodeId     : std_logic_vector(6 downto 0)   := std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Pin_NodeIdCode : std_logic_vector(6 downto 0)   := not std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Cfg_HbTime     : std_logic_vector(15 downto 0)  := std_logic_vector(to_unsigned(2, 16));
    signal Cfg_CobId      : std_logic_vector(143 downto 0) := table(Ids_c);
    signal Stat_State     : std_logic_vector(1 downto 0);
    signal Node_IdValid   : std_logic;
    signal Ena_Sdo        : std_logic;
    signal Ena_Pdo        : std_logic;
    signal Ena_Sync       : std_logic;
    signal Nmt_TxValid    : std_logic;
    signal Nmt_TxReady    : std_logic;
    signal Nmt_TxData     : std_logic_vector(7 downto 0);

    signal NmtReqs : natural   := 0;  -- NMT error control requests taken by ocan_dispatch
    signal TimeEna : time      := 0 ns;  -- last rise of Ena_Sdo
    signal EnaLast : std_logic := '0';

begin

    test_runner_watchdog(runner, 200 ms);

    i_th : entity work.ocan_nmt_net_th
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Pin_NodeId     => Pin_NodeId,
            Pin_NodeIdCode => Pin_NodeIdCode,
            Cfg_HbTime     => Cfg_HbTime,
            Cfg_CobId      => Cfg_CobId,
            Stat_State     => Stat_State,
            Node_IdValid   => Node_IdValid,
            Ena_Sdo        => Ena_Sdo,
            Ena_Pdo        => Ena_Pdo,
            Ena_Sync       => Ena_Sync,
            Nmt_TxValid    => Nmt_TxValid,
            Nmt_TxReady    => Nmt_TxReady,
            Nmt_TxData     => Nmt_TxData
        );

    p_mon : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Nmt_TxValid = '1' and Nmt_TxReady = '1' then
                NmtReqs <= NmtReqs + 1;
            end if;
            if Ena_Sdo = '1' and EnaLast = '0' then
                TimeEna <= now;
            end if;
            EnaLast <= Ena_Sdo;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable Cfg_v : TbNodeCfg_t;

        -- NMT message of the master model node M1 (node 0 on bus A) to the node
        procedure nmtM1 (cs : natural) is
            variable D_v : std_logic_vector(63 downto 0) := (others => '0');
        begin
            D_v(63 downto 56) := std_logic_vector(to_unsigned(cs, 8));
            D_v(55 downto 48) := std_logic_vector(to_unsigned(NodeId_c, 8));
            Net_v.txPush(0, canStd(0, 2, D_v));
        end procedure;

        -- Index of the next frame of the node in the log of M1, from index first on; -1 when none
        impure function nextDut (first : natural) return integer is
            variable E_v : TbLog_t;
        begin

            for I in first to Net_v.logCount(0) - 1 loop
                E_v := Net_v.logGet(0, I);
                if E_v.Kind = TbFrame and not E_v.Own and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = HbId_c then
                    return I;
                end if;
            end loop;

            return -1;
        end function;

        -- Checks that the frames of the node from log index first on carry byte b and are p ms apart
        procedure checkBeats (first : natural; b : std_logic_vector(7 downto 0); p : natural; msg : string) is
            variable I_v : integer;
            variable T_v : time;
            variable N_v : natural := 0;
            variable E_v : TbLog_t;
        begin
            I_v := nextDut(first);

            while I_v >= 0 loop
                E_v := Net_v.logGet(0, I_v);
                check_value(E_v.Frame.Dlc, 1, ERROR, msg & ": DLC 1");
                check_value(E_v.Frame.Data(63 downto 56), b, ERROR, msg & ": state byte");
                if N_v > 0 then
                    check_value(E_v.T - T_v > (p * 1 ms) - 150 us and E_v.T - T_v < (p * 1 ms) + 150 us, ERROR,
                                msg & ": heartbeat period " & time'image(E_v.T - T_v));
                end if;
                T_v := E_v.T;
                N_v := N_v + 1;
                I_v := nextDut(I_v + 1);
            end loop;

            check_value(N_v >= 2, ERROR, msg & ": at least two heartbeats");
        end procedure;

        variable I_v : integer;
        variable L_v : natural;
        variable E_v : TbLog_t;
        variable T_v : time;
        variable N_v : natural;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            -- *** TC-NM-14: boot-up message, heartbeats, NMT messages and node guarding on the bus ***
            if run("test_net_bootup") then
                Rst <= '1';
                wait for 250 ns;
                wait until rising_edge(Clk);
                Rst <= '0';
                wait for 7 ms;
                -- The first frame of the node is the boot-up message
                I_v := nextDut(0);
                check_value(I_v >= 0, ERROR, "a frame of the node on the bus");
                E_v := Net_v.logGet(0, I_v);
                check_value(E_v.Frame.Dlc, 1, ERROR, "boot-up message: DLC 1");
                check_value(E_v.Frame.Data(63 downto 56), x"00", ERROR, "boot-up message: 00h");
                checkBeats(I_v + 1, x"7F", 2, "Pre-operational");

                -- Start remote node, enter pre-operational, stop remote node
                for K in 0 to 2 loop
                    if K = 0 then
                        nmtM1(1);
                    elsif K = 1 then
                        nmtM1(128);
                    else
                        nmtM1(2);
                    end if;
                    wait for 1 ms;
                    L_v := Net_v.logCount(0);
                    wait for 7 ms;
                    if K = 0 then
                        check_value(Ena_Pdo, '1', ERROR, "PDO enable in Operational");
                        checkBeats(L_v, x"05", 2, "Operational");
                    elsif K = 1 then
                        check_value(Ena_Pdo, '0', ERROR, "no PDO enable in Pre-operational");
                        checkBeats(L_v, x"7F", 2, "Pre-operational again");
                    else
                        check_value(Ena_Sdo, '0', ERROR, "no SDO enable in Stopped");
                        checkBeats(L_v, x"04", 2, "Stopped");
                    end if;
                end loop;

                -- Reset communication: a boot-up message, then heartbeats of Pre-operational
                L_v := Net_v.logCount(0);
                nmtM1(130);
                wait for 6 ms;
                I_v := nextDut(L_v);
                check_value(I_v >= 0, ERROR, "a frame after the reset communication");
                E_v := Net_v.logGet(0, I_v);
                check_value(E_v.Frame.Data(63 downto 56), x"00", ERROR, "boot-up message after the reset");
                checkBeats(I_v + 1, x"7F", 2, "after the reset communication");

                -- Node guarding request right after a heartbeat: no reply, the next frame is the next heartbeat
                L_v := Net_v.logCount(0);
                wait until Nmt_TxValid = '1' and Nmt_TxReady = '1' for 5 ms;
                check_value(Nmt_TxValid = '1' and Nmt_TxReady = '1', ERROR, "heartbeat before the node guarding request");
                wait for 300 us;
                T_v := now;
                Net_v.txPush(0, canStd(HbId_c, 0, (others => '0'), '1'));
                wait for 3 ms;
                I_v := nextDut(L_v);
                N_v := 0;

                while I_v >= 0 loop
                    E_v := Net_v.logGet(0, I_v);
                    if E_v.T > T_v then
                        check_value(E_v.Frame.Rtr, '0', ERROR, "no remote frame of the node");
                        check_value(E_v.T - T_v > 1 ms, ERROR, "no reply to the node guarding request");
                        N_v := N_v + 1;
                    end if;
                    I_v := nextDut(I_v + 1);
                end loop;

                check_value(N_v >= 1, ERROR, "the next heartbeat after the node guarding request");

            -- *** TC-NM-15: boot-up message that no node acknowledges ***
            elsif run("test_net_no_ack") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(1, 16));

                for N in 0 to 1 loop
                    Cfg_v     := TbNodeCfgInit_c;
                    Cfg_v.Ack := false;
                    Net_v.setCfg(N, Cfg_v);
                end loop;

                Rst <= '1';
                wait for 250 ns;
                wait until rising_edge(Clk);
                Rst <= '0';
                wait for 10 ms;
                check_value(Stat_State, NmtPreOp_c, ERROR, "Pre-operational from the boot-up request");
                check_value(Ena_Sdo, '0', ERROR, "enables cleared while the boot-up message is pending");
                check_value(NmtReqs, 1, ERROR, "only the boot-up message requested, no heartbeat");
                N_v := 0;

                for I in 0 to Net_v.logCount(0) - 1 loop
                    if Net_v.logGet(0, I).Kind = TbError then
                        N_v := N_v + 1;
                    end if;
                end loop;

                check_value(N_v >= 10, ERROR, "the link repeats the boot-up message (" & integer'image(N_v) & ")");
                -- M2 acknowledges: the boot-up message completes, the heartbeats start
                Cfg_v := TbNodeCfgInit_c;
                Net_v.setCfg(1, Cfg_v);
                L_v   := Net_v.logCount(0);
                wait for 5 ms;
                check_value(Ena_Sdo, '1', ERROR, "enables after the boot-up message");
                I_v   := nextDut(L_v);
                check_value(I_v >= 0, ERROR, "a frame of the node after the acknowledge");
                E_v   := Net_v.logGet(0, I_v);
                check_value(E_v.Frame.Data(63 downto 56), x"00", ERROR, "the boot-up message completes");
                checkBeats(I_v + 1, x"7F", 1, "heartbeats after the boot-up message");

            -- *** TC-NM-21: reset communication while a heartbeat waits for its acknowledge ***
            elsif run("test_net_reset_wait") then
                Cfg_HbTime <= std_logic_vector(to_unsigned(1, 16));
                Rst        <= '1';
                wait for 250 ns;
                wait until rising_edge(Clk);
                Rst        <= '0';
                wait for 5 ms;
                check_value(Ena_Sdo, '1', ERROR, "boot-up message completed");

                -- No acknowledge: the next heartbeat waits at the link
                for N in 0 to 1 loop
                    Cfg_v     := TbNodeCfgInit_c;
                    Cfg_v.Ack := false;
                    Net_v.setCfg(N, Cfg_v);
                end loop;

                wait until Nmt_TxValid = '1' and Nmt_TxReady = '1' for 3 ms;
                check_value(Nmt_TxValid = '1' and Nmt_TxReady = '1', ERROR, "heartbeat taken");
                wait for 300 us;
                -- Reset communication of M1 (acknowledged by the node): the node requests the boot-up message
                nmtM1(130);
                wait for 500 us;
                check_value(Ena_Sdo, '0', ERROR, "enables blocked while the boot-up message waits");
                -- The acknowledge returns: the heartbeat completes, then the boot-up message is sent
                L_v   := Net_v.logCount(0);
                Cfg_v := TbNodeCfgInit_c;
                Net_v.setCfg(1, Cfg_v);
                wait for 3 ms;
                I_v   := nextDut(L_v);
                T_v   := 0 ns;

                while I_v >= 0 loop
                    E_v := Net_v.logGet(0, I_v);
                    if E_v.Frame.Data(63 downto 56) = x"00" and T_v = 0 ns then
                        T_v := E_v.T;
                    end if;
                    I_v := nextDut(I_v + 1);
                end loop;

                check_value(T_v > 0 ns, ERROR, "boot-up message on the bus");
                check_value(Ena_Sdo, '1', ERROR, "enables after the boot-up message");
                check_value(TimeEna > T_v, ERROR, "the enables return only after the boot-up message is on the bus");
            end if;

        end loop;

        ocanTestEnd(runner);

    end process;

end architecture;
