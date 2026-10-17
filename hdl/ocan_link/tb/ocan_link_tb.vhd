---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of ocan_link against the CAN network model: one run block per test case of the verification plan.
--
-- Documentation: hdl/ocan_link/docs/verification_plan.md

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
entity ocan_link_tb is
    generic (
        runner_cfg      : string;
        BusAccess_g     : string   := "Selective";
        SyncStages_g    : positive := 2;
        AutoRecover_g   : boolean  := true;
        DominantLimit_g : positive := 32
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_link_tb is

    constant Parallel_c : boolean := BusAccess_g = "Parallel";

    signal Clk               : std_logic;
    signal Rst               : std_logic                     := '1';
    signal Ctrl_Enable       : std_logic                     := '0';
    signal Ctrl_Bus          : std_logic                     := '0';
    signal Ctrl_Recover      : std_logic                     := '0';
    signal Ctrl_Reenable     : std_logic_vector(1 downto 0)  := "00";
    signal Cfg_Prescaler     : std_logic_vector(9 downto 0)  := std_logic_vector(to_unsigned(2, 10));
    signal Cfg_Tseg1         : std_logic_vector(4 downto 0)  := std_logic_vector(to_unsigned(15, 5));
    signal Cfg_Tseg2         : std_logic_vector(3 downto 0)  := std_logic_vector(to_unsigned(4, 4));
    signal Cfg_Sjw           : std_logic_vector(2 downto 0)  := std_logic_vector(to_unsigned(4, 3));
    signal Tx_Valid          : std_logic                     := '0';
    signal Tx_Ready          : std_logic;
    signal Tx_Id             : std_logic_vector(28 downto 0) := (others => '0');
    signal Tx_Ide            : std_logic                     := '0';
    signal Tx_Rtr            : std_logic                     := '0';
    signal Tx_Dlc            : std_logic_vector(3 downto 0)  := (others => '0');
    signal Tx_Data           : std_logic_vector(63 downto 0) := (others => '0');
    signal Tx_Abort          : std_logic                     := '0';
    signal Tx_Done           : std_logic;
    signal Tx_Aborted        : std_logic;
    signal Tx_ArbLost        : std_logic;
    signal Rx_Valid          : std_logic_vector(1 downto 0);
    signal Stat_ActiveBus    : std_logic;
    signal Stat_Switching    : std_logic;
    signal Stat_Tec          : std_logic_vector(17 downto 0);
    signal Stat_Rec          : std_logic_vector(15 downto 0);
    signal Stat_State        : std_logic_vector(3 downto 0);
    signal Stat_BusIdle      : std_logic_vector(1 downto 0);
    signal Stat_DomTimeout   : std_logic_vector(1 downto 0);
    signal Err_Bit           : std_logic_vector(1 downto 0);
    signal Err_Stuff         : std_logic_vector(1 downto 0);
    signal Err_Crc           : std_logic_vector(1 downto 0);
    signal Err_Form          : std_logic_vector(1 downto 0);
    signal Err_Ack           : std_logic_vector(1 downto 0);
    signal Err_DomTimeout    : std_logic_vector(1 downto 0);
    signal ErrInj_TxDominant : std_logic_vector(1 downto 0)  := "00";
    signal Can_Tx            : std_logic_vector(1 downto 0);
    signal Can_TxEn          : std_logic_vector(1 downto 0);
    signal BusLevel          : std_logic_vector(1 downto 0);
    signal ForceDom          : std_logic_vector(1 downto 0)  := "00";
    signal ForceRec          : std_logic_vector(1 downto 0)  := "00";
    signal Blind             : std_logic_vector(1 downto 0)  := "00";

    -- Event counters of the monitor
    type Count_a is array (0 to 1) of natural;

    signal CntDone    : natural := 0;
    signal CntAborted : natural := 0;
    signal CntArbLost : natural := 0;
    signal CntErr     : Count_a := (others => 0);
    signal CntDomErr  : Count_a := (others => 0);
    -- Longest dominant run on the transmit outputs, in clock cycles
    signal DomRun     : Count_a := (others => 0);
    signal DomRunMax  : Count_a := (others => 0);

begin

    i_th : entity work.ocan_link_th
        generic map (
            BusAccess_g     => BusAccess_g,
            SyncStages_g    => SyncStages_g,
            AutoRecover_g   => AutoRecover_g,
            DominantLimit_g => DominantLimit_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            Ctrl_Enable       => Ctrl_Enable,
            Ctrl_Bus          => Ctrl_Bus,
            Ctrl_Recover      => Ctrl_Recover,
            Ctrl_Reenable     => Ctrl_Reenable,
            Cfg_Prescaler     => Cfg_Prescaler,
            Cfg_Tseg1         => Cfg_Tseg1,
            Cfg_Tseg2         => Cfg_Tseg2,
            Cfg_Sjw           => Cfg_Sjw,
            Tx_Valid          => Tx_Valid,
            Tx_Ready          => Tx_Ready,
            Tx_Id             => Tx_Id,
            Tx_Ide            => Tx_Ide,
            Tx_Rtr            => Tx_Rtr,
            Tx_Dlc            => Tx_Dlc,
            Tx_Data           => Tx_Data,
            Tx_Abort          => Tx_Abort,
            Tx_Done           => Tx_Done,
            Tx_Aborted        => Tx_Aborted,
            Tx_ArbLost        => Tx_ArbLost,
            Rx_Valid          => Rx_Valid,
            Stat_ActiveBus    => Stat_ActiveBus,
            Stat_Switching    => Stat_Switching,
            Stat_Tec          => Stat_Tec,
            Stat_Rec          => Stat_Rec,
            Stat_State        => Stat_State,
            Stat_BusIdle      => Stat_BusIdle,
            Stat_DomTimeout   => Stat_DomTimeout,
            Err_Bit           => Err_Bit,
            Err_Stuff         => Err_Stuff,
            Err_Crc           => Err_Crc,
            Err_Form          => Err_Form,
            Err_Ack           => Err_Ack,
            Err_DomTimeout    => Err_DomTimeout,
            ErrInj_TxDominant => ErrInj_TxDominant,
            Can_Tx            => Can_Tx,
            Can_TxEn          => Can_TxEn,
            BusLevel          => BusLevel,
            ForceDom          => ForceDom,
            ForceRec          => ForceRec,
            Blind             => Blind
        );

    -- Every test ends within 100 ms of simulated time
    test_runner_watchdog(runner, 100 ms);

    -----------------------------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Tx_Done = '1' then
                CntDone <= CntDone + 1;
            end if;
            if Tx_Aborted = '1' then
                CntAborted <= CntAborted + 1;
            end if;
            if Tx_ArbLost = '1' then
                CntArbLost <= CntArbLost + 1;
            end if;

            for C in 0 to 1 loop
                if (Err_Bit(C) or Err_Stuff(C) or Err_Crc(C) or Err_Form(C) or Err_Ack(C)) = '1' then
                    CntErr(C) <= CntErr(C) + 1;
                end if;
                if Err_DomTimeout(C) = '1' then
                    CntDomErr(C) <= CntDomErr(C) + 1;
                end if;
            end loop;

            -- The inactive bus is never driven, in every state and under fault injection (D4)
            for B in 0 to 1 loop
                if (B = 1) /= (Stat_ActiveBus = '1') and Rst = '0' then
                    if Can_Tx(B) /= '1' or Can_TxEn(B) /= '0' then
                        alert(ERROR, "inactive bus " & integer'image(B) & " driven");
                    end if;
                end if;
                -- Longest dominant run on a driven transmit output
                if Can_Tx(B) = '0' and Can_TxEn(B) = '1' then
                    DomRun(B) <= DomRun(B) + 1;
                    if DomRun(B) + 1 > DomRunMax(B) then
                        DomRunMax(B) <= DomRun(B) + 1;
                    end if;
                else
                    DomRun(B) <= 0;
                end if;
            end loop;

        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable Bit_v    : time := 1 us;
        variable F_v      : CanFrame_t;
        variable G_v      : CanFrame_t;
        variable E_v      : TbLog_t;
        variable D_v      : TbFrameEntry_t;
        variable T0_v     : time;
        variable T1_v     : time;
        variable N0_v     : natural;
        variable N1_v     : natural;
        variable N2_v     : natural;
        variable Lat_v    : time;
        variable LatMin_v : time;
        variable LatMax_v : time;

        type FrameList_t is array (0 to 63) of CanFrame_t;

        variable List_v : FrameList_t;

        -- Bit timing of the link and of all model nodes
        procedure setTiming (
            presc  : natural;
            tseg1  : natural;
            tseg2  : natural;
            sjw    : natural;
            period : time;
            ppm0   : integer := 0;
            ppm1   : integer := 0) is
            variable Cfg_v : TbNodeCfg_t := TbNodeCfgInit_c;
        begin
            Cfg_Prescaler   <= std_logic_vector(to_unsigned(presc, 10));
            Cfg_Tseg1       <= std_logic_vector(to_unsigned(tseg1, 5));
            Cfg_Tseg2       <= std_logic_vector(to_unsigned(tseg2, 4));
            Cfg_Sjw         <= std_logic_vector(to_unsigned(sjw, 3));
            Bit_v           := period;
            Cfg_v.BitPeriod := period;

            for N in 0 to 3 loop
                if N mod 2 = 0 then
                    Cfg_v.Ppm := ppm0;
                else
                    Cfg_v.Ppm := ppm1;
                end if;
                Net_v.setCfg(N, Cfg_v);
            end loop;

        end procedure;

        procedure nodeCfg (
            idx        : natural;
            listen     : boolean := false;
            earlyStart : boolean := false;
            recDelay   : time    := 0 ns) is
            variable Cfg_v : TbNodeCfg_t;
        begin
            Cfg_v            := Net_v.getCfg(idx);
            Cfg_v.Listen     := listen;
            Cfg_v.EarlyStart := earlyStart;
            Cfg_v.RecDelay   := recDelay;
            Net_v.setCfg(idx, Cfg_v);
        end procedure;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- Sends a frame through the link (waits until it is taken)
        procedure send (
            f : CanFrame_t) is
            constant End_c : time := now + 10 ms;
        begin
            wait until rising_edge(Clk);
            Tx_Id    <= f.Id;
            Tx_Ide   <= f.Ide;
            Tx_Rtr   <= f.Rtr;
            Tx_Dlc   <= std_logic_vector(to_unsigned(f.Dlc, 4));
            Tx_Data  <= f.Data;
            Tx_Valid <= '1';

            loop
                wait until rising_edge(Clk);
                exit when Tx_Ready = '1';
                if now > End_c then
                    alert(ERROR, "send: frame not taken");
                    exit;
                end if;
            end loop;

            Tx_Valid <= '0';
        end procedure;

        -- Waits for the completion of the pending frame; returns true when it was sent
        procedure waitTx (
            sent    : out boolean;
            timeout : time := 10 ms) is
            constant End_c : time := now + timeout;
        begin

            loop
                wait until rising_edge(Clk);
                if Tx_Done = '1' then
                    sent := true;
                    exit;
                elsif Tx_Aborted = '1' then
                    sent := false;
                    exit;
                elsif now > End_c then
                    alert(ERROR, "waitTx: timeout");
                    sent := false;
                    exit;
                end if;
            end loop;

        end procedure;

        procedure sendWait (
            f : CanFrame_t) is
            variable Sent_v : boolean;
        begin
            send(f);
            waitTx(Sent_v);
            check_value(Sent_v, ERROR, "frame sent: " & canImage(f));
        end procedure;

        -- Waits until the transmit queues of all model nodes are empty and the buses have been idle 15 bits
        procedure waitNodes (timeout : time := 20 ms) is
            constant End_c : time := now + timeout;
        begin

            while Net_v.txCount(0) + Net_v.txCount(1) + Net_v.txCount(2) + Net_v.txCount(3) > 0 loop
                wait for Bit_v;
                if now > End_c then
                    alert(ERROR, "waitNodes: timeout");
                    exit;
                end if;
            end loop;

            wait for 15 * Bit_v;
        end procedure;

        -- Requests a bus and waits until the switch is done and the controller has integrated
        procedure switchTo (
            bus_s : std_logic) is
        begin
            Ctrl_Bus <= bus_s;
            clocks(2);

            while Stat_Switching = '1' or Stat_ActiveBus /= bus_s loop
                wait until rising_edge(Clk);
            end loop;

            wait for 15 * Bit_v;
        end procedure;

        -- Frames of others in the log of a node
        impure function rxCount (idx : natural) return natural is
            variable N_v : natural := 0;
            variable L_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(idx) - 1 loop
                L_v := Net_v.logGet(idx, I);
                if L_v.Kind = TbFrame and not L_v.Own then
                    N_v := N_v + 1;
                end if;
            end loop;

            return N_v;
        end function;

        impure function rxFrame (
            idx : natural;
            n   : natural) return TbLog_t is
            variable N_v : natural := 0;
            variable L_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(idx) - 1 loop
                L_v := Net_v.logGet(idx, I);
                if L_v.Kind = TbFrame and not L_v.Own then
                    if N_v = n then
                        return L_v;
                    end if;
                    N_v := N_v + 1;
                end if;
            end loop;

            alert(ERROR, "rxFrame: no frame " & integer'image(n) & " at node " & integer'image(idx));
            return L_v;
        end function;

        impure function errCount (idx : natural) return natural is
            variable N_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(idx) - 1 loop
                if Net_v.logGet(idx, I).Kind = TbError then
                    N_v := N_v + 1;
                end if;
            end loop;

            return N_v;
        end function;

        impure function seenId (
            idx : natural;
            id  : std_logic_vector(28 downto 0)) return boolean is
            variable L_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(idx) - 1 loop
                L_v := Net_v.logGet(idx, I);
                if L_v.Kind = TbFrame and L_v.Frame.Id = id then
                    return true;
                end if;
            end loop;

            return false;
        end function;

        procedure checkFrame (
            got : CanFrame_t;
            exp : CanFrame_t;
            msg : string) is
        begin
            check_value(canEqual(got, exp), ERROR, msg & ": got " & canImage(got) & ", expected " & canImage(exp));
        end procedure;

        -- Frames of every format: standard and extended, data and remote, DLC 0 to 15
        impure function sample (n : natural; base : natural) return CanFrame_t is
            constant D_c : std_logic_vector(63 downto 0) := x"0123456789ABCDEF";
        begin

            case n mod 6 is
                when 0 =>
                    return canStd(base + n, n mod 9, D_c);
                when 1 =>
                    return canExt(base * 1024 + n, n mod 9, not D_c);
                when 2 =>
                    return canStd(base + n, 9 + n mod 7, D_c);
                when 3 =>
                    return canStd(base + n, n mod 9, Rtr => '1');
                when 4 =>
                    return canExt(base * 1024 + n, 15, D_c, '1');
                when others =>
                    return canExt(base * 1024 + n, 8, x"00FF00FF00FF00FF");
            end case;

        end function;

        -- Frames in both directions on the active bus b: link to node 2b and 2b+1, node 2b to the link
        procedure exchange (
            b     : natural;
            n     : natural;
            check : boolean := true) is
            variable Rx0_v  : natural;
            variable Dut0_v : natural;
        begin
            Rx0_v  := rxCount(2 * b);
            Dut0_v := DutLog_v.count(b);

            for I in 0 to n - 1 loop
                List_v(I) := sample(I, 16#100# + 16 * b);
                sendWait(List_v(I));
            end loop;

            wait for 15 * Bit_v;

            for I in 0 to n - 1 loop
                checkFrame(rxFrame(2 * b, Rx0_v + I).Frame, List_v(I), "node " & integer'image(2 * b) & " frame " &
                           integer'image(I));
                List_v(32 + I) := sample(I, 16#200# + 16 * b);
                Net_v.txPush(2 * b, List_v(32 + I));
            end loop;

            waitNodes;
            if check then
                check_value(DutLog_v.count(b) - Dut0_v, n, ERROR, "frames passed on bus " & integer'image(b));

                for I in 0 to n - 1 loop
                    checkFrame(DutLog_v.get(b, Dut0_v + I).Frame, List_v(32 + I), "link frame " & integer'image(I));
                end loop;

            end if;
        end procedure;

        procedure reenable (c : natural) is
        begin
            wait until rising_edge(Clk);
            Ctrl_Reenable(c) <= '1';
            wait until rising_edge(Clk);
            Ctrl_Reenable(c) <= '0';
        end procedure;

        variable Sent_v : boolean;
        variable Tec_v  : std_logic_vector(17 downto 0);
        variable St_v   : std_logic_vector(3 downto 0);
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            -- *** Common start: 1 Mbit/s, bus A requested, link enabled ***
            setTiming(2, 15, 4, 4, 1 us);
            Rst <= '1';
            clocks(10);
            Rst <= '0';
            clocks(2);

            if run("test_switch_idle") then
                -- After the reset the active bus is the requested bus (LK-BS-01)
                Ctrl_Bus    <= '1';
                Ctrl_Enable <= '1';
                clocks(3);
                check_value(Stat_ActiveBus, '1', ERROR, "active bus after the reset");
                wait for 20 * Bit_v;
                check_value(Stat_BusIdle(0), '1', ERROR, "bus idle indication");
                -- Switch without a pending frame: two cycles
                Ctrl_Bus <= '0';
                wait until rising_edge(Clk) and Stat_Switching = '1';
                N0_v     := 0;

                while Stat_Switching = '1' loop
                    N0_v := N0_v + 1;
                    wait until rising_edge(Clk);
                end loop;

                check_value(N0_v, 2, ERROR, "switch duration in cycles");
                T0_v := now;
                check_value(Stat_ActiveBus, '0', ERROR, "new active bus");
                check_value(Can_TxEn, "01", ERROR, "transmit enables after the switch");
                -- The first frame after the switch starts only after the integration of 11 recessive bits
                send(canStd(16#123#, 1, x"5500000000000000"));
                wait until Can_Tx(0) = '0';
                -- T0 is taken one cycle after the controller was enabled again (the loop reads the switching flag
                -- before it is updated)
                check_value(now - T0_v >= 11 * Bit_v - 50 ns, ERROR, "integration before the first bit: " &
                            time'image(now - T0_v));
                waitTx(Sent_v);
                check_value(Sent_v, ERROR, "frame after the switch sent");
                wait for 15 * Bit_v;
                check_value(rxCount(0), 1, ERROR, "frame on bus A");
                check_value(rxCount(2), 0, ERROR, "no frame on bus B");

            else
                Ctrl_Bus    <= '0';
                Ctrl_Enable <= '1';
                wait for 20 * Bit_v;
            end if;

            if run("test_frames") then
                LatMin_v := 1 sec;
                LatMax_v := 0 ns;

                for B in 0 to 1 loop
                    if B = 1 then
                        switchTo('1');
                    end if;
                    exchange(B, 12);

                    -- Latency: link event after the receiver of the model (node 2b + 1) logged the frame
                    for I in 0 to 11 loop
                        D_v   := DutLog_v.get(B, DutLog_v.count(B) - 12 + I);
                        E_v   := rxFrame(2 * B + 1, rxCount(2 * B + 1) - 12 + I);
                        Lat_v := D_v.T - E_v.T;
                        if Lat_v < LatMin_v then
                            LatMin_v := Lat_v;
                        end if;
                        if Lat_v > LatMax_v then
                            LatMax_v := Lat_v;
                        end if;
                    end loop;

                end loop;

                log(ID_SEQUENCER, "latency after the model receiver: " & time'image(LatMin_v) & " to " &
                    time'image(LatMax_v));
                check_value(LatMax_v - LatMin_v <= 100 ns, ERROR, "constant latency on both buses (within 2 tq)");

            elsif run("test_listen_only") then

                -- Frames of node 2 on the inactive bus B are passed with index 1
                for I in 0 to 3 loop
                    List_v(I) := sample(I, 16#300#);
                    Net_v.txPush(2, List_v(I));
                end loop;

                waitNodes;
                check_value(DutLog_v.count(1), 4, ERROR, "frames of the inactive bus");

                for I in 0 to 3 loop
                    checkFrame(DutLog_v.get(1, I).Frame, List_v(I), "inactive bus frame " & integer'image(I));
                end loop;

                -- Node 3 does not acknowledge: node 2 is alone and sees acknowledge errors (no acknowledge of the link)
                nodeCfg(3, listen => true);
                Net_v.logClear(2);
                Net_v.txPush(2, canStd(16#3AA#, 2, x"1234000000000000"));
                wait for 400 * Bit_v;
                check_value(errCount(2) >= 1, ERROR, "node 2: acknowledge errors");
                check_value(Net_v.logGet(2, 0).Err = TbErrAck, ERROR, "node 2: acknowledge error");
                Net_v.txClear(2);
                wait for 200 * Bit_v;
                -- An error frame of node 3 on bus B: the link sends no error flag, its counts do not change
                nodeCfg(3);
                wait for 50 * Bit_v;
                N0_v := CntErr(1);
                Net_v.setErrFlag(3, 25, 1);
                Net_v.txPush(2, canStd(16#3AB#, 4, x"89ABCDEF00000000"));
                waitNodes;
                check_value(CntErr(1) > N0_v, ERROR, "controller 1 detected the error");
                check_value(Stat_Tec(17 downto 9), "000000000", ERROR, "controller 1: transmit count");
                check_value(Stat_Rec(15 downto 8), x"00", ERROR, "controller 1: receive count");

            elsif run("test_same_cycle") then
                F_v := canStd(16#155#, 2, x"AA55000000000000");
                Net_v.txPush(0, F_v);
                Net_v.txPush(2, F_v);
                waitNodes;
                check_value(DutLog_v.count(0), 1, ERROR, "frame on bus A");
                check_value(DutLog_v.count(1), 1, ERROR, "frame on bus B");
                check_value(DutLog_v.get(0, 0).T = DutLog_v.get(1, 0).T, ERROR, "events in the same cycle");

            elsif run("test_bit_rates") then

                for R in 0 to 3 loop
                    Ctrl_Enable <= '0';
                    clocks(2);
                    setTiming(2 * 2 ** R, 15, 4, 4, 2 ** R * 1 us);
                    clocks(2);
                    Ctrl_Enable <= '1';
                    wait for 20 * Bit_v;
                    exchange(0, 3);
                end loop;

            elsif run("test_bit_timing") then

                -- 500 kbit/s with 16 quanta (prescaler 5): sample points 62.5 %, 75 % and 87.5 %, SJW 1 to 4; node 0
                -- 0.2 % slow with delayed dominant-to-recessive edges, node 1 0.2 % fast
                for K in 0 to 4 loop
                    Ctrl_Enable <= '0';
                    clocks(2);

                    case K is
                        when 0 =>
                            setTiming(5, 9, 6, 1, 2 us, 2000, -2000);
                        when 1 =>
                            setTiming(5, 9, 6, 4, 2 us, 2000, -2000);
                        when 2 =>
                            setTiming(5, 11, 4, 4, 2 us, 2000, -2000);
                        when 3 =>
                            setTiming(5, 13, 2, 1, 2 us, 2000, -2000);
                        when others =>
                            setTiming(5, 13, 2, 2, 2 us, 2000, -2000);
                    end case;

                    nodeCfg(0, recDelay => 300 ns);
                    clocks(2);
                    Ctrl_Enable <= '1';
                    wait for 20 * Bit_v;
                    N0_v        := CntErr(0);
                    exchange(0, 6);
                    check_value(CntErr(0), N0_v, ERROR, "no error of the link, setting " & integer'image(K));
                    check_value(errCount(0) + errCount(1), 0, ERROR, "no error of the nodes");
                end loop;

            elsif run("test_switch_pending") then

                -- A frame that waits behind frames of higher priority is aborted by the switch
                for I in 0 to 9 loop
                    Net_v.txPush(0, canStd(16#010# + I, 8, x"0011223344556677"));
                end loop;

                wait for 30 * Bit_v;
                N0_v     := CntAborted;
                send(canStd(16#7EE#, 1, x"EE00000000000000"));
                wait for 300 * Bit_v;
                Ctrl_Bus <= '1';
                wait until rising_edge(Clk) and Stat_Switching = '0' and Stat_ActiveBus = '1';
                check_value(CntAborted, N0_v + 1, ERROR, "pending frame aborted");
                waitNodes;
                check_value(seenId(1, canStd(16#7EE#, 0).Id) or seenId(2, canStd(16#7EE#, 0).Id), false, ERROR,
                            "the aborted frame is never sent");
                -- A frame on the bus at the switch request completes on the old bus
                switchTo('0');
                N1_v     := CntDone;
                send(canStd(16#123#, 8, x"0123456789ABCDEF"));
                wait until Can_Tx(0) = '0';
                Ctrl_Bus <= '1';
                wait until rising_edge(Clk) and Stat_Switching = '0' and Stat_ActiveBus = '1';
                check_value(CntDone, N1_v + 1, ERROR, "frame on the bus sent on the old bus");
                wait for 20 * Bit_v;
                check_value(seenId(1, canStd(16#123#, 0).Id), true, ERROR, "frame on bus A");
                check_value(seenId(2, canStd(16#123#, 0).Id), false, ERROR, "frame not on bus B");
                -- The same with an error frame of node 1: the frame is dropped
                switchTo('0');
                N0_v     := CntAborted;
                Net_v.setErrFlag(1, 30, 1);
                send(canStd(16#124#, 8, x"0123456789ABCDEF"));
                wait until Can_Tx(0) = '0';
                Ctrl_Bus <= '1';
                wait until rising_edge(Clk) and Stat_Switching = '0' and Stat_ActiveBus = '1';
                check_value(CntAborted, N0_v + 1, ERROR, "frame dropped after the error frame");
                wait for 300 * Bit_v;
                check_value(seenId(0, canStd(16#124#, 0).Id) or seenId(2, canStd(16#124#, 0).Id), false, ERROR,
                            "the dropped frame is never sent");

            elsif run("test_switch_request_change") then
                -- Request toggled during Abort_s (a frame on the bus keeps the sequencer there)
                send(canStd(16#321#, 8, x"0123456789ABCDEF"));
                wait until Can_Tx(0) = '0';
                Ctrl_Bus <= '1';
                wait until rising_edge(Clk) and Stat_Switching = '1';
                Ctrl_Bus <= '0';
                -- First switch to bus B, then back to bus A (latest request)
                wait until rising_edge(Clk) and Stat_ActiveBus = '1';
                wait until rising_edge(Clk) and Stat_Switching = '0' and Stat_ActiveBus = '0';
                -- Request changed in Switch_s (the cycle in which the active bus changes)
                Ctrl_Bus <= '1';
                wait until rising_edge(Clk) and Stat_ActiveBus = '1';
                Ctrl_Bus <= '0';
                clocks(10);
                check_value(Stat_ActiveBus, '0', ERROR, "the active bus follows the latest request");
                check_value(Stat_Switching, '0', ERROR, "no switch pending");

            elsif run("test_disable") then

                for I in 0 to 9 loop
                    Net_v.txPush(0, canStd(16#010# + I, 8, x"0011223344556677"));
                end loop;

                wait for 30 * Bit_v;
                N0_v        := CntAborted;
                send(canStd(16#7EE#, 1, x"EE00000000000000"));
                wait for 200 * Bit_v;
                N1_v        := DutLog_v.count(0);
                check_value(Tx_Ready, '0', ERROR, "frame pending before the disable");
                Ctrl_Enable <= '0';
                -- The controller drops the frame two cycles after the disable; the counter follows one cycle later
                clocks(10);
                check_value(CntAborted, N0_v + 1, ERROR, "pending frame dropped and reported");

                for I in 0 to 199 loop
                    wait for Bit_v;
                    check_value(Can_Tx, "11", ERROR, "transmit bits recessive while disabled");
                    check_value(Can_TxEn, "00", ERROR, "transmit enables inactive while disabled");
                end loop;

                check_value(DutLog_v.count(0), N1_v, ERROR, "no frame passed while disabled");
                waitNodes;
                Ctrl_Bus    <= '1';
                Ctrl_Enable <= '1';
                clocks(3);
                check_value(Stat_ActiveBus, '1', ERROR, "active bus after the enable");
                check_value(seenId(1, canStd(16#7EE#, 0).Id), false, ERROR, "the dropped frame is never sent");

            elsif run("test_arbitration") then
                -- The link and node 0 start in the same bit after a frame of node 1
                Net_v.txPush(1, canStd(16#700#, 8, x"0123456789ABCDEF"));
                wait for 20 * Bit_v;
                Net_v.txPush(0, canStd(16#100#, 1, x"1100000000000000"));
                N0_v := CntArbLost;
                send(canStd(16#200#, 1, x"2200000000000000"));
                waitTx(Sent_v);
                check_value(Sent_v, ERROR, "link frame sent after the lost arbitration");
                check_value(CntArbLost >= N0_v + 1, ERROR, "lost arbitration reported");
                waitNodes;
                E_v  := rxFrame(1, 0);
                checkFrame(E_v.Frame, canStd(16#100#, 1, x"1100000000000000"), "winner first");
                E_v  := rxFrame(1, 1);
                checkFrame(E_v.Frame, canStd(16#200#, 1, x"2200000000000000"), "link second");
                -- The link wins against a higher identifier
                Net_v.txPush(1, canStd(16#700#, 8, x"0123456789ABCDEF"));
                wait for 20 * Bit_v;
                Net_v.txPush(0, canStd(16#300#, 1, x"3300000000000000"));
                N1_v := Net_v.count(0, TbCntArbLost);
                sendWait(canStd(16#201#, 1, x"4400000000000000"));
                waitNodes;
                check_value(Net_v.count(0, TbCntArbLost), N1_v + 1, ERROR, "node 0 lost and retransmitted");
                -- Continuous contention: 20 extended frames of each node, 20 standard frames of the link
                N0_v := rxCount(0);
                N2_v := DutLog_v.count(0);

                for I in 0 to 19 loop
                    Net_v.txPush(0, canExt(16#1000# + 2 * I, I mod 9, x"0102030405060708"));
                    Net_v.txPush(1, canExt(16#1001# + 2 * I, 8 - I mod 9, x"F1F2F3F4F5F6F7F8"));
                end loop;

                for I in 0 to 19 loop
                    List_v(I) := canStd(16#400# + I, I mod 9, x"A0A1A2A3A4A5A6A7");
                    sendWait(List_v(I));
                end loop;

                waitNodes;
                T0_v := 0 ns;
                N1_v := N0_v;
                N0_v := 0;

                for I in N1_v to rxCount(0) - 1 loop
                    E_v := rxFrame(0, I);
                    if E_v.Frame.Ide = '0' and unsigned(E_v.Frame.Id(28 downto 18)) >= 16#400# and N0_v < 20 then
                        checkFrame(E_v.Frame, List_v(N0_v), "link frame " & integer'image(N0_v) & " at node 0");
                        N0_v := N0_v + 1;
                    end if;
                end loop;

                check_value(N0_v, 20, ERROR, "every link frame once at node 0");
                check_value(DutLog_v.count(0) - N2_v, 40, ERROR, "every node frame passed by the link");

            elsif run("test_error_frames") then
                -- Node 1 destroys 32 attempts of a frame of the link: error passive at 128, bus off at 256
                F_v := canStd(16#155#, 2, x"1234000000000000");
                Net_v.setErrFlag(1, 20, 32, 16#155#);
                send(F_v);
                wait until Stat_State(1 downto 0) = "01" for 5 ms;
                check_value(Stat_State(1 downto 0), "01", ERROR, "error passive");
                check_value(unsigned(Stat_Tec(8 downto 0)) >= 128, ERROR, "transmit count of error passive");
                wait until Stat_State(1 downto 0) = "11" for 5 ms;
                check_value(Stat_State(1 downto 0), "11", ERROR, "bus off");
                check_value(CntDone, 0, ERROR, "frame still pending in bus off");
                -- Recovery after 128 x 11 recessive bits, then the frame is sent
                wait until Stat_State(1 downto 0) = "00" for 3 ms;
                check_value(Stat_State(1 downto 0), "00", ERROR, "recovered");
                waitTx(Sent_v);
                check_value(Sent_v, ERROR, "frame sent after the recovery");
                waitNodes;
                check_value(seenId(0, F_v.Id), true, ERROR, "frame at node 0");
                -- Errors during the reception of the link: receive count and error events
                N0_v := CntErr(0);
                Net_v.setErrFlag(1, 20, 5, 16#0AA#);
                Net_v.txPush(0, canStd(16#0AA#, 4, x"CAFEBABE00000000"));
                waitNodes;
                check_value(CntErr(0) >= N0_v + 5, ERROR, "error events of the receiver");
                check_value(unsigned(Stat_Rec(7 downto 0)) > 0, ERROR, "receive count");

            elsif run("test_recover_request") then
                F_v          := canStd(16#155#, 2, x"1234000000000000");
                Net_v.setErrFlag(1, 20, 32, 16#155#);
                send(F_v);
                wait until Stat_State(1 downto 0) = "11" for 10 ms;
                check_value(Stat_State(1 downto 0), "11", ERROR, "bus off");
                wait for 3 ms;
                check_value(Stat_State(1 downto 0), "11", ERROR, "still bus off without a request");
                wait until rising_edge(Clk);
                Ctrl_Recover <= '1';
                wait until rising_edge(Clk);
                Ctrl_Recover <= '0';
                wait until Stat_State(1 downto 0) = "00" for 3 ms;
                check_value(Stat_State(1 downto 0), "00", ERROR, "recovered after the request");
                waitTx(Sent_v);
                check_value(Sent_v, ERROR, "frame sent after the recovery");

            elsif run("test_counts_kept") then
                -- Five errors and one success: transmit count 5 x 8 - 1 = 39
                Net_v.setErrFlag(1, 20, 5, 16#155#);
                sendWait(canStd(16#155#, 2, x"1234000000000000"));
                wait for 20 * Bit_v;
                Tec_v       := Stat_Tec;
                St_v        := Stat_State;
                check_value(to_integer(unsigned(Tec_v(8 downto 0))), 39, ERROR, "transmit count after the errors");
                switchTo('1');
                switchTo('0');
                Ctrl_Enable <= '0';
                clocks(10);
                Ctrl_Enable <= '1';
                wait for 20 * Bit_v;
                check_value(Stat_Tec, Tec_v, ERROR, "transmit counts kept");
                check_value(Stat_State, St_v, ERROR, "states kept");

            elsif run("test_dominant_timeout") then
                -- Stuck transmit bit of the active controller (controller 0, bus A)
                wait until rising_edge(Clk);
                ErrInj_TxDominant(0) <= '1';
                T0_v                 := now;
                N0_v                 := CntAborted;
                send(canStd(16#2BC#, 1, x"BC00000000000000"));
                wait until rising_edge(Clk) and Err_DomTimeout(0) = '1' for (DominantLimit_g + 2) * Bit_v;
                T1_v                 := now;
                check_value(Err_DomTimeout(0), '1', ERROR, "dominant timeout event");
                check_value_in_range(T1_v - T0_v, DominantLimit_g * Bit_v, (DominantLimit_g + 1) * Bit_v, ERROR,
                                     "time to the timeout");
                clocks(4);
                check_value(Can_Tx(0), '1', ERROR, "transmit bit released");
                check_value(Can_TxEn(0), '0', ERROR, "transmit enable inactive");
                check_value(Stat_DomTimeout(0), '1', ERROR, "timeout state");
                check_value(CntAborted, N0_v + 1, ERROR, "pending frame aborted");
                check_value(Tx_Ready, '0', ERROR, "no frame taken while stopped");
                ErrInj_TxDominant(0) <= '0';
                wait for 100 * Bit_v;
                check_value(Stat_DomTimeout(0), '1', ERROR, "stopped until the re-enable");
                reenable(0);
                clocks(2);
                check_value(Stat_DomTimeout(0), '0', ERROR, "re-enabled");
                wait for 15 * Bit_v;
                sendWait(canStd(16#2BD#, 1, x"BD00000000000000"));
                -- Second timeout, cleared by a disable and enable
                ErrInj_TxDominant(0) <= '1';
                wait until rising_edge(Clk) and Err_DomTimeout(0) = '1' for (DominantLimit_g + 2) * Bit_v;
                ErrInj_TxDominant(0) <= '0';
                check_value(Stat_DomTimeout(0), '1', ERROR, "second timeout");
                Ctrl_Enable          <= '0';
                clocks(3);
                Ctrl_Enable          <= '1';
                clocks(2);
                check_value(Stat_DomTimeout(0), '0', ERROR, "cleared by the disable");
                wait for 15 * Bit_v;
                sendWait(canStd(16#2BE#, 1, x"BE00000000000000"));
                check_value(CntDomErr(0), 2, ERROR, "two timeout events");

            elsif run("test_dominant_inactive") then
                -- Fault injection on the listen-only controller of bus B never reaches bus B
                ErrInj_TxDominant(1) <= '1';
                wait until rising_edge(Clk) and Err_DomTimeout(1) = '1' for (DominantLimit_g + 2) * Bit_v;
                check_value(Err_DomTimeout(1), '1', ERROR, "timeout of controller 1");
                ErrInj_TxDominant(1) <= '0';
                clocks(2);
                check_value(Stat_DomTimeout, "10", ERROR, "controller 1 stopped");
                check_value(DomRunMax(1), 0, ERROR, "bus B never driven");
                -- Timeout of the active controller, then a switch to bus B with the stopped controller 1
                ErrInj_TxDominant(0) <= '1';
                wait until rising_edge(Clk) and Err_DomTimeout(0) = '1' for (DominantLimit_g + 2) * Bit_v;
                ErrInj_TxDominant(0) <= '0';
                Ctrl_Bus             <= '1';
                wait until rising_edge(Clk) and Stat_Switching = '0' and Stat_ActiveBus = '1' for 1 ms;
                check_value(Stat_ActiveBus, '1', ERROR, "switch with a stopped controller");
                clocks(2);
                check_value(Can_TxEn(1), '0', ERROR, "stopped controller takes no part");
                check_value(Tx_Ready, '0', ERROR, "no frame taken");
                reenable(1);
                wait for 15 * Bit_v;
                check_value(Can_TxEn(1), '1', ERROR, "controller 1 re-enabled");
                sendWait(canStd(16#2CC#, 1, x"CC00000000000000"));
                wait for 15 * Bit_v;
                check_value(seenId(2, canStd(16#2CC#, 0).Id), true, ERROR, "frame on bus B");

            elsif run("test_dominant_margin") then
                -- Blind mode from a transmit count of 0: the dominant bits of the link do not reach its receiver; it
                -- restarts its active error flags until it is error passive (start of frame and 16 flags of one bit).
                -- The model nodes only listen, so that no error flag of theirs reaches the receiver of the link.
                nodeCfg(0, listen => true);
                nodeCfg(1, listen => true);
                Blind(0) <= '1';
                send(canStd(16#0AD#, 2, x"ADAD000000000000"));
                wait until Stat_State(1 downto 0) = "11" for 5 ms;
                Blind(0) <= '0';
                Tx_Abort <= '1';
                clocks(2);
                Tx_Abort <= '0';
                log(ID_SEQUENCER, "longest dominant run: " & integer'image(DomRunMax(0) / 40) & " bits");
                check_value(DomRunMax(0) >= 16 * 40, ERROR, "restarted error flags: dominant run of " &
                            integer'image(DomRunMax(0) / 40) & " bits");
                check_value(CntDomErr(0) + CntDomErr(1), 0, ERROR, "no dominant timeout in blind mode");
                check_value(Stat_DomTimeout, "00", ERROR, "no controller stopped");
                nodeCfg(0);
                nodeCfg(1);
                wait until Stat_State(1 downto 0) = "00" for 5 ms;
                check_value(Stat_State(1 downto 0), "00", ERROR, "recovered from bus off");
                wait for 20 * Bit_v;
                -- Superposed error flags in receptions and transmissions of the link
                Net_v.setErrFlag(1, 20, 3, 16#0AB#);

                for I in 0 to 2 loop
                    Net_v.txPush(0, canStd(16#0AB#, 2, x"ABAB000000000000"));
                end loop;

                waitNodes;
                Net_v.setErrFlag(1, 20, 3, 16#0AC#);
                sendWait(canStd(16#0AC#, 2, x"ACAC000000000000"));
                waitNodes;
                check_value(CntDomErr(0) + CntDomErr(1), 0, ERROR, "no dominant timeout");
                check_value(Stat_DomTimeout, "00", ERROR, "no controller stopped");

            elsif run("test_back_to_back") then

                -- Frames without data, each starting in the third bit of the intermission of the previous one
                for N in 0 to 3 loop
                    nodeCfg(N, earlyStart => true);
                end loop;

                for I in 0 to 4 loop

                    for N in 0 to 1 loop
                        Net_v.txPush(N, canStd(16#040# + 2 * I + N, 0));
                        if Parallel_c then
                            Net_v.txPush(N + 2, canStd(16#060# + 2 * I + N, 0));
                        end if;
                    end loop;

                end loop;

                waitNodes;

                for B in 0 to 1 loop
                    if B = 0 or Parallel_c then
                        check_value(DutLog_v.count(B), 10, ERROR, "frames passed on bus " & integer'image(B));

                        for I in 1 to DutLog_v.count(B) - 1 loop
                            D_v  := DutLog_v.get(B, I);
                            T0_v := DutLog_v.get(B, I - 1).T;
                            check_value_in_range(D_v.T - T0_v, (canWire(D_v.Frame).Len + 2) * Bit_v - Bit_v / 4,
                                                 (canWire(D_v.Frame).Len + 2) * Bit_v + Bit_v / 4, ERROR,
                                                 "frame " & integer'image(I) & " back to back");
                        end loop;

                    end if;
                end loop;

            elsif run("test_sync_stages") then
                exchange(0, 4);

            end if;

        end loop;

        ocanTestEnd(runner);

    end process;

end architecture;
