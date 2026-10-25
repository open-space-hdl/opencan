---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_dispatch: ocan_dispatch with ocan_link on the CAN network model. Back-to-back frames
-- of every class (TC-DS-06) and the bound of the transmit wait under full load with contention and error frames
-- (TC-DS-12).
--
-- Documentation: hdl/ocan_dispatch/docs/verification_plan.md

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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_dispatch_net_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_dispatch_net_tb is

    constant NodeId_c : natural := 5;
    constant Bit_c    : time    := 1 us;

    type Ids_t is array (0 to 11) of natural;

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

    signal Clk             : std_logic;
    signal Rst             : std_logic                      := '1';
    signal Red_ActiveBus   : std_logic                      := '0';
    signal Nmt_NodeIdValid : std_logic                      := '0';
    signal NodeId          : std_logic_vector(6 downto 0)   := std_logic_vector(to_unsigned(NodeId_c, 7));
    signal CobIds          : std_logic_vector(143 downto 0) := table(Ids_c);
    signal RxNmt_Valid     : std_logic;
    signal RxSync_Valid    : std_logic;
    signal RxRpdo_Valid    : std_logic;
    signal RxTime_Valid    : std_logic;
    signal RxSdo_Valid     : std_logic;
    signal RxRed_NmtValid  : std_logic_vector(1 downto 0);
    signal RxRed_HbValid   : std_logic_vector(1 downto 0);
    signal Src_Valid       : std_logic_vector(6 downto 0);
    signal Src_Ready       : std_logic_vector(6 downto 0);
    signal Src_Done        : std_logic_vector(6 downto 0);
    signal Src_Aborted     : std_logic_vector(6 downto 0);
    signal LinkTx_Valid    : std_logic;
    signal LinkTx_Ready    : std_logic;
    signal LinkTx_Id       : std_logic_vector(28 downto 0);

    -- Sources
    type Nat7_a is array (0 to 6) of natural;
    type Bool7_a is array (0 to 6) of boolean;

    signal ReqCnt  : Nat7_a  := (others => 0);
    signal AutoReq : Bool7_a := (others => false);
    signal CntDone : Nat7_a  := (others => 0);

    -- Received events: count and smallest distance per protocol block (NMT, PDO, time, SDO)
    type Nat4_a is array (0 to 3) of natural;
    type Time4_a is array (0 to 3) of time;

    signal BlkCount  : Nat4_a  := (others => 0);
    signal BlkLast   : Time4_a := (others => 0 ns);
    signal BlkMin    : Time4_a := (others => 1 sec);
    signal CntRpdo   : natural := 0;
    signal CntSync   : natural := 0;
    signal CntRedNmt : natural := 0;
    signal CntRedHb  : natural := 0;

    -- Background traffic of the model nodes
    signal Traffic : boolean := false;

begin

    test_runner_watchdog(runner, 100 ms);

    i_th : entity work.ocan_dispatch_net_th
        port map (
            Clk             => Clk,
            Rst             => Rst,
            Red_ActiveBus   => Red_ActiveBus,
            Nmt_NodeId      => NodeId,
            Nmt_NodeIdValid => Nmt_NodeIdValid,
            Cfg_CobId       => CobIds,
            RxNmt_Valid     => RxNmt_Valid,
            RxSync_Valid    => RxSync_Valid,
            RxRpdo_Valid    => RxRpdo_Valid,
            RxTime_Valid    => RxTime_Valid,
            RxSdo_Valid     => RxSdo_Valid,
            RxRed_NmtValid  => RxRed_NmtValid,
            RxRed_HbValid   => RxRed_HbValid,
            Src_Valid       => Src_Valid,
            Src_Ready       => Src_Ready,
            Src_Done        => Src_Done,
            Src_Aborted     => Src_Aborted,
            LinkTx_Valid    => LinkTx_Valid,
            LinkTx_Ready    => LinkTx_Ready,
            LinkTx_Id       => LinkTx_Id
        );

    -- *** Sources: requests logged in channel 3 (identifier = source, time = start of the request) ***
    g_src : for S in 0 to 6 generate

        p_src : process is
            variable Issued_v : natural := 0;
        begin
            Src_Valid(S) <= '0';

            loop
                wait until rising_edge(Clk);
                if AutoReq(S) or Issued_v < ReqCnt(S) then
                    DutLog_v.push(3, canStd(S, 0));
                    Src_Valid(S) <= '1';

                    loop
                        wait until rising_edge(Clk);
                        exit when Src_Ready(S) = '1';
                    end loop;

                    Src_Valid(S) <= '0';
                    if not AutoReq(S) then
                        Issued_v := Issued_v + 1;
                    end if;
                end if;
            end loop;

        end process;

    end generate;

    -- *** Monitors: frames passed to the link (channel 2), completions, received events ***
    p_mon : process (Clk) is
        variable Ev_v : std_logic_vector(3 downto 0);
    begin
        if rising_edge(Clk) then
            if LinkTx_Valid = '1' and LinkTx_Ready = '1' then
                DutLog_v.push(2, (Ide => '0', Id => LinkTx_Id, Rtr => '0', Dlc => 0, Data => (others => '0')));
            end if;

            for S in 0 to 6 loop
                if Src_Done(S) = '1' then
                    CntDone(S) <= CntDone(S) + 1;
                end if;
            end loop;

            Ev_v := (RxSdo_Valid,
                     RxSync_Valid or RxTime_Valid,
                     RxSync_Valid or RxRpdo_Valid,
                     RxNmt_Valid);

            for B in 0 to 3 loop
                if Ev_v(B) = '1' then
                    if BlkCount(B) > 0 and now - BlkLast(B) < BlkMin(B) then
                        BlkMin(B) <= now - BlkLast(B);
                    end if;
                    BlkLast(B)  <= now;
                    BlkCount(B) <= BlkCount(B) + 1;
                end if;
            end loop;

            if RxRpdo_Valid = '1' then
                CntRpdo <= CntRpdo + 1;
            end if;
            if RxSync_Valid = '1' then
                CntSync <= CntSync + 1;
            end if;
            if RxRed_NmtValid(0) = '1' then
                CntRedNmt <= CntRedNmt + 1;
            end if;
            if RxRed_HbValid(0) = '1' then
                CntRedHb <= CntRedHb + 1;
            end if;
        end if;
    end process;

    -- *** Background traffic: node 0 frames of higher, node 1 frames of lower priority than the link ***
    p_traffic : process is
        variable N_v : natural := 0;
    begin
        wait until Traffic;

        while Traffic loop
            Net_v.txPush(0, canStd(16#010# + N_v mod 16, 8, x"0011223344556677"));
            wait for 150 us;
            Net_v.txPush(1, canStd(16#6F0# + N_v mod 8, 4, x"8899AABB00000000"));
            wait for 150 us;
            N_v := N_v + 1;
        end loop;

        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        impure function sourceOf (id : std_logic_vector(28 downto 0)) return natural is
            constant I_c : natural := to_integer(unsigned(id(28 downto 18)));
        begin

            for N in 0 to 3 loop
                if I_c = Ids_c(6 + N) then
                    return N;
                end if;
            end loop;

            if I_c = Ids_c(10) then
                return 4;
            elsif I_c = 16#580# + NodeId_c then
                return 5;
            else
                return 6;
            end if;
        end function;

        procedure waitNodes (timeout : time := 50 ms) is
            constant End_c : time := now + timeout;
        begin

            while Net_v.txCount(0) + Net_v.txCount(1) > 0 and now < End_c loop
                wait for Bit_c;
            end loop;

            wait for 20 * Bit_c;
        end procedure;

        function nmtFrame return CanFrame_t is
            variable R_v : CanFrame_t;
        begin
            R_v := canStd(0, 2, x"0105000000000000");
            return R_v;
        end function;

        variable Cfg_v  : TbNodeCfg_t;
        variable E_v    : TbFrameEntry_t;
        variable N_v    : natural;
        variable K_v    : natural;
        variable ReqT_v : time;
        variable Max_v  : time := 0 ns;
        variable Seen_v : Nat7_a;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            Rst             <= '1';
            wait for 250 ns;
            wait until rising_edge(Clk);
            Rst             <= '0';
            Nmt_NodeIdValid <= '1';
            wait for 20 * Bit_c;

            -- *** Back-to-back frames of every class ***
            if run("test_rx_spacing") then

                for N in 0 to 1 loop
                    Cfg_v            := TbNodeCfgInit_c;
                    Cfg_v.EarlyStart := true;
                    Net_v.setCfg(N, Cfg_v);
                end loop;

                for I in 0 to 4 loop
                    Net_v.txPush(0, canStd(16#080#, 0));
                    Net_v.txPush(0, canStd(16#205#, 0));
                    Net_v.txPush(0, canStd(16#605#, 0));
                    Net_v.txPush(0, canStd(16#0F0#, 0));
                    Net_v.txPush(1, canStd(16#701#, 1, x"0500000000000000"));
                    Net_v.txPush(1, nmtFrame);
                    Net_v.txPush(1, canStd(16#305#, 0));
                end loop;

                waitNodes;
                check_value(BlkCount(0), 5, ERROR, "NMT messages");
                check_value(CntSync, 5, ERROR, "SYNC");
                check_value(CntRpdo, 10, ERROR, "receive PDOs");
                check_value(BlkCount(2), 10, ERROR, "events to the time block (SYNC and Spacecraft Time PDO)");
                check_value(BlkCount(3), 5, ERROR, "SDO requests");
                check_value(CntRedNmt, 5, ERROR, "NMT messages to the redundancy");
                check_value(CntRedHb, 5, ERROR, "master heartbeats to the redundancy");

                for B in 0 to 3 loop
                    log(ID_SEQUENCER, "block " & integer'image(B) & ": smallest distance " & time'image(BlkMin(B)));
                    check_value(BlkMin(B) >= 46 * Bit_c, ERROR, "events of block " & integer'image(B) &
                                " at least 46 bit times apart");
                end loop;

            -- *** Transmit wait under full load with contention and error frames ***
            elsif run("test_heartbeat_load") then
                Net_v.setErrFlag(1, 25, 5);
                Traffic <= true;

                for S in 0 to 5 loop
                    AutoReq(S) <= true;
                end loop;

                -- NMT error control every 1 ms (the shortest heartbeat period)
                for K in 1 to 10 loop
                    ReqCnt(6) <= ReqCnt(6) + 1;
                    wait for 1 ms;
                end loop;

                for S in 0 to 5 loop
                    AutoReq(S) <= false;
                end loop;

                Traffic <= false;
                wait for 2 ms;
                waitNodes;
                check_value(CntDone(6), 10, ERROR, "every heartbeat sent");
                check_value(Net_v.count(1, TbCntErrors) >= 5, ERROR, "error frames on the bus");
                -- Bound: between the start of a request and its frame, at most one frame of each other source
                Seen_v := (others => 0);

                for I in 0 to DutLog_v.count(2) - 1 loop
                    E_v := DutLog_v.get(2, I);
                    N_v := sourceOf(E_v.Frame.Id);
                    K_v := 0;

                    for J in 0 to DutLog_v.count(3) - 1 loop
                        if to_integer(unsigned(DutLog_v.get(3, J).Frame.Id(28 downto 18))) = N_v then
                            if K_v = Seen_v(N_v) then
                                ReqT_v := DutLog_v.get(3, J).T;
                                exit;
                            end if;
                            K_v := K_v + 1;
                        end if;
                    end loop;

                    Seen_v(N_v) := Seen_v(N_v) + 1;
                    if N_v = 6 and E_v.T - ReqT_v > Max_v then
                        Max_v := E_v.T - ReqT_v;
                    end if;

                    for S in 0 to 6 loop
                        if S /= N_v then
                            K_v := 0;

                            for M in 0 to I - 1 loop
                                if DutLog_v.get(2, M).T > ReqT_v and sourceOf(DutLog_v.get(2, M).Frame.Id) = S then
                                    K_v := K_v + 1;
                                end if;
                            end loop;

                            if K_v > 1 then
                                alert(ERROR, "frame " & integer'image(I) & " of source " & integer'image(N_v) &
                                      " waited for " & integer'image(K_v) & " frames of source " & integer'image(S));
                            end if;
                        end if;
                    end loop;

                end loop;

                log(ID_SEQUENCER, integer'image(DutLog_v.count(2)) & " frames checked; longest wait of the heartbeat " &
                    "for the link: " & time'image(Max_v));

            end if;

        end loop;

        ocanTestEnd(runner);

    end process;

end architecture;
