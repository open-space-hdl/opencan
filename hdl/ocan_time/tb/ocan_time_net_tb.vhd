---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_time: ocan_time with ocan_dispatch and ocan_link on the CAN network model, with a model
-- node as SYNC producer and time producer on each bus. The byte order on the bus, the high-resolution setting and the
-- latency of the SYNC sample on both buses (TC-TM-18).
--
-- Documentation: hdl/ocan_time/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_context;

library work;
    use work.ocan_tb_pkg.all;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_time_net_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_time_net_tb is

    constant LtpId_c : natural := 16#1F5#;
    constant StpId_c : natural := 16#0F0#;

    type Ids_t is array (0 to 11) of natural;

    -- Pre-defined connection set of NODE-ID 5; entry 1 the Spacecraft Time PDO, entry 10 the Local Time PDO
    constant Ids_c : Ids_t := (16#080#, StpId_c, 16#205#, 16#305#, 16#405#, 16#505#, 16#185#, 16#285#, 16#385#,
                               16#485#, LtpId_c, 16#701#);

    function table (ids : Ids_t) return std_logic_vector is
        variable T_v : std_logic_vector(143 downto 0);
    begin

        for E in 0 to 11 loop
            T_v(12 * E + 11)               := '1';
            T_v(12 * E + 10 downto 12 * E) := std_logic_vector(to_unsigned(ids(E), 11));
        end loop;

        return T_v;
    end function;

    -- Frame data of a 56-bit SCET (bytes 0 to 2 the fine time, 3 to 6 the coarse time, least significant byte first)
    function frameOf (s : std_logic_vector(55 downto 0)) return std_logic_vector is
    begin
        return s(7 downto 0) & s(15 downto 8) & s(23 downto 16) & s(31 downto 24) & s(39 downto 32) &
               s(47 downto 40) & s(55 downto 48) & x"00";
    end function;

    -- floor(m * 2^24 / 40 MHz) for m cycles, the advance of TM-CT-02 (exact: m * 2^24 < 2^52)
    function advance (m : natural) return unsigned is
        variable R_v : unsigned(55 downto 0);
    begin
        R_v := to_unsigned(natural(floor(real(m) * 2.0 ** 24 / 40.0e6)), 56);
        return R_v;
    end function;

    signal Clk            : std_logic;
    signal Rst            : std_logic                      := '1';
    signal Bus_Sel        : std_logic                      := '0';
    signal Cfg_RxType     : std_logic_vector(7 downto 0)   := std_logic_vector(to_unsigned(1, 8));
    signal Cfg_TxType     : std_logic_vector(7 downto 0)   := std_logic_vector(to_unsigned(1, 8));
    signal Cfg_CobId      : std_logic_vector(143 downto 0) := table(Ids_c);
    signal Stat_Scet      : std_logic_vector(55 downto 0);
    signal Evt_Set        : std_logic;
    signal Evt_Sync       : std_logic;
    signal Err_RxDrop     : std_logic;
    signal Stat_ActiveBus : std_logic;

    -- The local time of the cycle of the last SYNC sample (the cycle before Evt_Sync)
    signal Sample : std_logic_vector(55 downto 0);

begin

    test_runner_watchdog(runner, 200 ms);

    i_th : entity work.ocan_time_net_th
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Bus_Sel        => Bus_Sel,
            Cfg_RxType     => Cfg_RxType,
            Cfg_TxType     => Cfg_TxType,
            Cfg_CobId      => Cfg_CobId,
            Stat_Scet      => Stat_Scet,
            Evt_Set        => Evt_Set,
            Evt_Sync       => Evt_Sync,
            Err_RxDrop     => Err_RxDrop,
            Stat_ActiveBus => Stat_ActiveBus
        );

    p_sample : process (Clk) is
        variable Prev_v : std_logic_vector(55 downto 0) := (others => '0');
    begin
        if rising_edge(Clk) then
            if Evt_Sync = '1' then
                Sample <= Prev_v;
            end if;
            Prev_v := Stat_Scet;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        -- Time of the last frame with identifier id in the log of model node n, own or received; 0 ns: none
        impure function lastFrame (n : natural; id : natural; own : boolean) return time is
            variable E_v : TbLog_t;
            variable T_v : time := 0 ns;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and E_v.Own = own and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    T_v := E_v.T;
                end if;
            end loop;

            return T_v;
        end function;

        -- Data of the last received frame with identifier id in the log of model node n
        impure function lastData (n : natural; id : natural) return std_logic_vector is
            variable E_v : TbLog_t;
            variable D_v : std_logic_vector(63 downto 0) := (others => '0');
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    D_v := E_v.Frame.Data;
                end if;
            end loop;

            return D_v;
        end function;

        type Lat_a is array (0 to 1) of time;

        variable Lat_v   : Lat_a;
        variable TSync_v : time;
        variable TEnd_v  : time;
        variable S_v     : std_logic_vector(55 downto 0);
        variable M_v     : natural;
        variable Exp_v   : unsigned(55 downto 0);
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            -- *** TC-TM-18: the time distribution on both buses ***
            if run("test_net_time") then
                Rst <= '1';
                wait for 250 ns;
                wait until rising_edge(Clk);
                Rst <= '0';

                for B in 0 to 1 loop
                    if B = 1 then
                        Bus_Sel <= '1';
                    end if;
                    -- Integration of the controller on the bus
                    wait for 1 ms;
                    check_value(Stat_ActiveBus = '1', B = 1, ERROR, "active bus");
                    -- SYNC of the master M1 of this bus
                    Net_v.txPush(2 * B, canStd(16#080#, 0));
                    wait until Evt_Sync = '1' for 2 ms;
                    check_value(Evt_Sync, '1', ERROR, "SYNC sample");
                    TSync_v  := now;
                    wait for 1 us;
                    TEnd_v   := lastFrame(2 * B, 16#080#, true);
                    Lat_v(B) := TSync_v - TEnd_v;
                    log(ID_SEQUENCER, "bus " & to_string(B) & ": end of the SYNC frame to Evt_Sync " &
                        to_string(Lat_v(B)));
                    -- The Local Time PDO of the node (type 1) carries its sample in the byte order of TM-TX-01
                    wait for 500 us;
                    check_value(lastData(2 * B, LtpId_c), frameOf(Sample), ERROR, "Local Time PDO with the sample");
                    -- The Spacecraft Time PDO (type 1) with the time of the producer at the SYNC: the local time at
                    -- the sample is that time, advanced exactly from there (TM-RX-04)
                    S_v := std_logic_vector(to_unsigned(16#1234# + B, 32)) & x"ABCDEF";
                    Net_v.txPush(2 * B, canStd(StpId_c, 7, frameOf(S_v)));
                    wait until Evt_Set = '1' for 2 ms;
                    check_value(Evt_Set, '1', ERROR, "high-resolution setting");
                    wait for 10 us;
                    wait until falling_edge(Clk);
                    -- Cycles since the cycle of the sample: the sample lies one cycle before Evt_Sync
                    M_v   := natural((now - TSync_v) / 25 ns) + 1;
                    Exp_v := unsigned(S_v) + advance(M_v);
                    check_value(unsigned(Stat_Scet) = Exp_v, true, ERROR,
                                "local time = SCET of the producer at the sample + floor(n * 2^24 / f)");
                end loop;

                -- The same latency on both buses, within one clock cycle and one time quantum (2 cycles) of the
                -- sampling of the bits
                check_value(abs (Lat_v(0) - Lat_v(1)) <= 75 ns, true, ERROR,
                            "same latency of the SYNC sample on bus A and bus B");

            end if;

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
