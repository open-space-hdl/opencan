---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_redundancy: the events of both buses and the parameters are driven cycle by cycle, models
-- of ocan_nmt and ocan_link answer the requests, and a reference model written from the specification predicts every
-- output in every cycle. One run block per test case of the verification plan.
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
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_redundancy_tb is
    generic (
        runner_cfg   : string;
        MinimalSet_g : boolean := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_redundancy_tb is

    function u16 (n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 16));
    end function;

    function u8 (n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 8));
    end function;

    -- *** DUT signals ***
    signal Clk            : std_logic;
    signal Rst            : std_logic                     := '1';
    signal Tick_Ms        : std_logic                     := '0';
    signal Rx_NmtValid    : std_logic_vector(1 downto 0)  := "00";
    signal Rx_HbValid     : std_logic_vector(1 downto 0)  := "00";
    signal Rx_HbDlc       : std_logic_vector(7 downto 0)  := x"11";
    signal Rx_HbState     : std_logic_vector(15 downto 0) := x"0505";
    signal Cfg_HbTime     : std_logic_vector(15 downto 0) := u16(5);
    signal Cfg_Bdefault   : std_logic                     := '0';
    signal Cfg_Ttoggle    : std_logic_vector(7 downto 0)  := u8(2);
    signal Cfg_Ntoggle    : std_logic_vector(7 downto 0)  := u8(4);
    signal Cfg_CtoggleWr  : std_logic                     := '0';
    signal Cfg_Ctoggle    : std_logic_vector(7 downto 0)  := u8(0);
    signal Upd_Valid      : std_logic;
    signal Upd_Bdefault   : std_logic;
    signal Link_Bus       : std_logic;
    signal Link_ActiveBus : std_logic                     := '0';
    signal Link_Switching : std_logic                     := '0';
    signal Nmt_State      : std_logic_vector(1 downto 0)  := NmtInit_c;
    signal Nmt_PreopReq   : std_logic;
    signal Nmt_Switched   : std_logic;
    signal Stat_ActiveBus : std_logic;
    signal Stat_Selecting : std_logic;
    signal Stat_Ctoggle   : std_logic_vector(7 downto 0);
    signal Stat_HbState   : std_logic_vector(7 downto 0);
    signal Stat_HbPresent : std_logic_vector(1 downto 0);
    signal Err_HbMissing  : std_logic;
    signal Err_ToggleEnd  : std_logic;
    signal Err_HbDlc      : std_logic;

    -- *** Cycle counter and tick generator (period TickPer cycles) ***
    signal Cyc     : natural := 0;
    signal TickPer : natural := 4;

    -- *** Model of ocan_nmt: Initialisation during Rst and 4 cycles after it, then follows NmtTarget; enters
    -- Pre-operational NmtDly cycles after Nmt_PreopReq ***
    signal NmtTarget : std_logic_vector(1 downto 0) := NmtInit_c;
    signal NmtDly    : natural                      := 1;
    -- The NMT model does not follow Nmt_PreopReq while NmtIgnore
    signal NmtIgnore : boolean := false;

    -- *** Model of ocan_link: disabled during Rst and 4 cycles after it (the active bus is Link_Bus, LK-BS-01). A
    -- change of Link_Bus: Link_Switching = '1' from the next cycle, after SwDly cycles the other active bus, and
    -- Link_Switching = '0' one cycle later, as the abort and switch states of ocan_link ***
    signal SwDly : natural := 3;

    -- *** Monitors: counts and the cycle of the last event ***
    signal CntMiss  : natural := 0;
    signal CntEnd   : natural := 0;
    signal CntSw    : natural := 0;
    signal CntUpd   : natural := 0;
    signal CntDlc   : natural := 0;
    signal CntPreop : natural := 0;
    signal UpdBus   : std_logic;
    signal CycMiss  : natural := 0;
    signal CycEnd   : natural := 0;
    signal CycHb    : natural := 0;
    signal CycSw    : natural := 0;
    signal CycSwEnd : natural := 0;
    signal CycBus   : natural := 0;
    signal CycPreOp : natural := 0;
    signal CycReq   : natural := 0;

    -- *** Reference model ***
    signal CheckEn     : boolean := false;
    signal ExpLinkBus  : std_logic;
    signal ExpSel      : std_logic;
    signal ExpCtoggle  : std_logic_vector(7 downto 0);
    signal ExpHbState  : std_logic_vector(7 downto 0);
    signal ExpPresent  : std_logic_vector(1 downto 0);
    signal ExpPreop    : std_logic;
    signal ExpSwitched : std_logic;
    signal ExpUpdValid : std_logic;
    signal ExpUpdBdef  : std_logic;
    signal ExpMiss     : std_logic;
    signal ExpEnd      : std_logic;
    signal ExpDlc      : std_logic;

begin

    test_runner_watchdog(runner, 500 ms);

    i_th : entity work.ocan_redundancy_th
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Tick_Ms        => Tick_Ms,
            Rx_NmtValid    => Rx_NmtValid,
            Rx_HbValid     => Rx_HbValid,
            Rx_HbDlc       => Rx_HbDlc,
            Rx_HbState     => Rx_HbState,
            Cfg_HbTime     => Cfg_HbTime,
            Cfg_Bdefault   => Cfg_Bdefault,
            Cfg_Ttoggle    => Cfg_Ttoggle,
            Cfg_Ntoggle    => Cfg_Ntoggle,
            Cfg_CtoggleWr  => Cfg_CtoggleWr,
            Cfg_Ctoggle    => Cfg_Ctoggle,
            Upd_Valid      => Upd_Valid,
            Upd_Bdefault   => Upd_Bdefault,
            Link_Bus       => Link_Bus,
            Link_ActiveBus => Link_ActiveBus,
            Link_Switching => Link_Switching,
            Nmt_State      => Nmt_State,
            Nmt_PreopReq   => Nmt_PreopReq,
            Nmt_Switched   => Nmt_Switched,
            Stat_ActiveBus => Stat_ActiveBus,
            Stat_Selecting => Stat_Selecting,
            Stat_Ctoggle   => Stat_Ctoggle,
            Stat_HbState   => Stat_HbState,
            Stat_HbPresent => Stat_HbPresent,
            Err_HbMissing  => Err_HbMissing,
            Err_ToggleEnd  => Err_ToggleEnd,
            Err_HbDlc      => Err_HbDlc
        );

    -----------------------------------------------------------------------------------------------
    -- Cycle counter and millisecond tick
    -----------------------------------------------------------------------------------------------
    p_tick : process (Clk) is
        variable Cnt_v : natural := 0;
    begin
        if rising_edge(Clk) then
            Cyc <= Cyc + 1;
            if TickPer > 0 and Cnt_v >= TickPer - 1 then
                Tick_Ms <= '1';
                Cnt_v   := 0;
            else
                Tick_Ms <= '0';
                Cnt_v   := Cnt_v + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Model of ocan_nmt
    -----------------------------------------------------------------------------------------------
    p_nmt : process (Clk) is
        variable Last_v : std_logic_vector(1 downto 0) := NmtInit_c;
        variable Cnt_v  : integer                      := -1;
        variable Hold_v : natural                      := 0;
    begin
        if rising_edge(Clk) then
            if Rst = '1' or Hold_v > 0 then
                Nmt_State <= NmtInit_c;
                Last_v    := NmtInit_c;
                Cnt_v     := -1;
                if Rst = '1' then
                    Hold_v := 4;
                else
                    Hold_v := Hold_v - 1;
                end if;
            elsif NmtTarget /= Last_v then
                Nmt_State <= NmtTarget;
                Last_v    := NmtTarget;
                Cnt_v     := -1;
            elsif Nmt_PreopReq = '1' and (Nmt_State = NmtOp_c or Nmt_State = NmtStopped_c) and not NmtIgnore and
                  Cnt_v < 0 then
                -- A running delay is kept, as ocan_nmt follows the first request
                Cnt_v := NmtDly;
            end if;
            if Cnt_v = 0 then
                Nmt_State <= NmtPreOp_c;
                Cnt_v     := -1;
            elsif Cnt_v > 0 then
                Cnt_v := Cnt_v - 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Model of ocan_link
    -----------------------------------------------------------------------------------------------
    p_link : process (Clk) is
        variable Ph_v  : natural range 0 to 2 := 0;  -- 0 run, 1 abort, 2 switch
        variable Cnt_v : natural              := 0;
        variable Dis_v : natural              := 0;
    begin
        if rising_edge(Clk) then
            if Rst = '1' or Dis_v > 0 then
                Link_ActiveBus <= Link_Bus;
                Link_Switching <= '0';
                Ph_v           := 0;
                if Rst = '1' then
                    Dis_v := 4;
                else
                    Dis_v := Dis_v - 1;
                end if;
            else

                case Ph_v is
                    when 0 =>
                        if Link_Bus /= Link_ActiveBus then
                            Link_Switching <= '1';
                            Cnt_v          := SwDly;
                            Ph_v           := 1;
                        end if;
                    when 1 =>
                        if Cnt_v <= 1 then
                            Link_ActiveBus <= not Link_ActiveBus;
                            Ph_v           := 2;
                        else
                            Cnt_v := Cnt_v - 1;
                        end if;
                    when others =>
                        Link_Switching <= '0';
                        Ph_v           := 0;
                end case;

            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------------------------
    p_mon : process (Clk) is
        variable Bus_v : std_logic                    := '0';
        variable Sw_v  : std_logic                    := '0';
        variable St_v  : std_logic_vector(1 downto 0) := NmtInit_c;
    begin
        if rising_edge(Clk) then
            if Err_HbMissing = '1' then
                CntMiss <= CntMiss + 1;
                CycMiss <= Cyc;
            end if;
            if Err_ToggleEnd = '1' then
                CntEnd <= CntEnd + 1;
                CycEnd <= Cyc;
            end if;
            if Nmt_Switched = '1' then
                CntSw <= CntSw + 1;
                CycSw <= Cyc;
            end if;
            if Upd_Valid = '1' then
                CntUpd <= CntUpd + 1;
                UpdBus <= Upd_Bdefault;
            end if;
            if Err_HbDlc = '1' then
                CntDlc <= CntDlc + 1;
            end if;
            if Nmt_PreopReq = '1' then
                CntPreop <= CntPreop + 1;
                CycReq   <= Cyc;
            end if;
            if Rx_HbValid /= "00" or Rx_NmtValid /= "00" then
                CycHb <= Cyc;
            end if;
            if Link_Bus /= Bus_v then
                CycBus <= Cyc;
            end if;
            if Link_Switching = '0' and Sw_v = '1' then
                CycSwEnd <= Cyc;
            end if;
            if Nmt_State = NmtPreOp_c and St_v /= NmtPreOp_c then
                CycPreOp <= Cyc;
            end if;
            Bus_v := Link_Bus;
            Sw_v  := Link_Switching;
            St_v  := Nmt_State;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Reference model, derived from the requirements of the specification (cited per rule). It keeps the state in
    -- the terms of the specification: not started, master heartbeat monitoring, bus selection process (waiting for
    -- the report of the link or not), the toggle that fell due, the end of the toggling that was reported, the end
    -- after the running switch; the timer is one count of ticks since its last restart.
    -----------------------------------------------------------------------------------------------
    p_model : process is
        type Phase_t is (NotStarted, Monitoring, Selection);
        type Nat2_a is array (0 to 1) of natural;

        -- Phase, the requested bus not yet reported by the link, the requested bus, Ctoggle, the toggle that fell
        -- due, the end of the toggling reported, the end after the running switch (RM-SL-06), ticks since the restart
        variable Phase_v   : Phase_t                       := NotStarted;
        variable WaitLk_v  : boolean                       := false;
        variable Req_v     : std_logic                     := '0';
        variable Ct_v      : natural                       := 0;
        variable Due_v     : boolean                       := false;
        variable EndRep_v  : boolean                       := false;
        variable EndSw_v   : boolean                       := false;
        variable Elap_v    : natural                       := 0;
        variable PrevC_v   : std_logic_vector(15 downto 0) := (others => '0');
        variable PrevT_v   : std_logic_vector(7 downto 0)  := (others => '0');
        variable Since_v   : Nat2_a                        := (0, 0);
        variable Pres_v    : std_logic_vector(1 downto 0)  := "00";
        variable HbSt_v    : std_logic_vector(7 downto 0)  := (others => '0');
        -- Events of the cycle: Preop, Switched, Upd, Miss, End, Dlc
        variable Ev_v      : std_logic_vector(5 downto 0) := (others => '0');
        variable UpdB_v    : std_logic                    := '0';
        variable C_v       : natural;
        variable T_v       : natural;
        variable N_v       : natural;
        variable A_v       : natural range 0 to 1;
        variable I_v       : natural range 0 to 1;
        variable R_v       : natural range 0 to 1;
        variable Hb_v      : std_logic_vector(1 downto 0);
        variable Msg_v     : std_logic_vector(1 downto 0);
        variable ParChg_v  : boolean;
        variable HbRst_v   : boolean;
        variable Expire_v  : boolean;
        variable Restart_v : boolean;
        variable PreOp_v   : boolean;
        variable OpSt_v    : boolean;
    begin
        wait until rising_edge(Clk);

        if Rst = '1' then
            Phase_v  := NotStarted;
            WaitLk_v := false;
            Req_v    := '0';
            Ct_v     := 0;
            Due_v    := false;
            EndRep_v := false;
            EndSw_v  := false;
            Elap_v   := 0;
            PrevC_v  := (others => '0');
            PrevT_v  := (others => '0');
            Since_v  := (0,
                         0);
            Pres_v   := "00";
            HbSt_v   := (others => '0');
            Ev_v     := (others => '0');
            UpdB_v   := '0';
        else
            Ev_v := (others => '0');
            -- Parameters: Ttoggle = 0 acts as 1 (RM-HB-04)
            C_v := to_integer(unsigned(Cfg_HbTime));
            T_v := to_integer(unsigned(Cfg_Ttoggle));
            N_v := to_integer(unsigned(Cfg_Ntoggle));
            if T_v = 0 then
                T_v := 1;
            end if;
            PreOp_v := Nmt_State = NmtPreOp_c;
            OpSt_v  := Nmt_State = NmtOp_c or Nmt_State = NmtStopped_c;

            -- Master heartbeats: DLC 1, any state byte; another DLC is an error event (RM-HB-01)
            for B in 0 to 1 loop
                Hb_v(B) := '0';
                if Rx_HbValid(B) = '1' then
                    if unsigned(Rx_HbDlc(4 * B + 3 downto 4 * B)) = 1 then
                        Hb_v(B) := '1';
                    else
                        Ev_v(5) := '1';
                    end if;
                end if;
                Msg_v(B) := Hb_v(B) or Rx_NmtValid(B);
            end loop;

            if Link_ActiveBus = '1' then
                A_v := 1;
            else
                A_v := 0;
            end if;
            I_v := 1 - A_v;
            if Req_v = '1' then
                R_v := 1;
            else
                R_v := 0;
            end if;

            -- State byte of the last master heartbeat on the active bus (RM-IF-07)
            if Hb_v(A_v) = '1' then
                HbSt_v := Rx_HbState(8 * A_v + 7 downto 8 * A_v);
            end if;

            -- Presence: set by a master heartbeat, cleared when none arrived for C ticks; with C = 0 cleared (RM-HB-05)
            for B in 0 to 1 loop
                if C_v = 0 then
                    Since_v(B) := 0;
                    Pres_v(B)  := '0';
                elsif Hb_v(B) = '1' then
                    Since_v(B) := 0;
                    Pres_v(B)  := '1';
                elsif Tick_Ms = '1' and Pres_v(B) = '1' then
                    Since_v(B) := Since_v(B) + 1;
                    if Since_v(B) >= C_v then
                        Since_v(B) := 0;
                        Pres_v(B)  := '0';
                    end if;
                end if;
            end loop;

            -- Timer: ticks since the last restart, expiry at T x C ticks; no expiry with C = 0 (RM-HB-02 to RM-HB-04,
            -- RM-SL-04). A restart and a tick in one cycle: the tick is not counted
            ParChg_v  := Cfg_HbTime /= PrevC_v or Cfg_Ttoggle /= PrevT_v;
            HbRst_v   := Phase_v = Monitoring and Hb_v(A_v) = '1';
            Expire_v  := false;
            Restart_v := false;
            if Phase_v /= NotStarted and C_v /= 0 and Tick_Ms = '1' and not ParChg_v and not HbRst_v then
                Elap_v := Elap_v + 1;
                if Elap_v >= T_v * C_v then
                    Elap_v   := 0;
                    Expire_v := true;
                end if;
            end if;

            case Phase_v is

                when NotStarted =>
                    if not MinimalSet_g and PreOp_v then
                        -- Start-up process on Bdefault without a switch, Ctoggle = 0 (RM-SL-01)
                        Phase_v   := Selection;
                        WaitLk_v  := false;
                        Ct_v      := 0;
                        Due_v     := false;
                        EndRep_v  := false;
                        EndSw_v   := false;
                        Restart_v := true;
                    elsif MinimalSet_g and Nmt_State /= NmtInit_c then
                        -- Minimal set: monitoring when the node leaves the Initialisation (RM-MS-02)
                        Phase_v   := Monitoring;
                        Restart_v := true;
                    elsif not MinimalSet_g and OpSt_v then
                        -- Operational or Stopped without Pre-operational: monitoring at once (RM-SL-01)
                        Phase_v   := Monitoring;
                        Restart_v := true;
                    else
                        -- Requested bus Bdefault after the hardware reset (RM-SL-01)
                        Req_v := Cfg_Bdefault;
                    end if;

                when Monitoring =>
                    if Expire_v then
                        -- Missing master heartbeat: event, Pre-operational request, process with Ctoggle = 0 and
                        -- the first toggle due (RM-HB-02, RM-SL-02)
                        Ev_v(3)   := '1';
                        Ev_v(0)   := '1';
                        Phase_v   := Selection;
                        WaitLk_v  := false;
                        Ct_v      := 0;
                        Due_v     := true;
                        EndRep_v  := false;
                        EndSw_v   := false;
                        Restart_v := true;
                    end if;

                when Selection =>
                    if WaitLk_v then
                        if Link_Switching = '0' and Link_ActiveBus = Req_v then
                            -- The link reports the new bus: switch event (RM-SL-03); end after a message (RM-SL-06)
                            Ev_v(1)  := '1';
                            WaitLk_v := false;
                            if EndSw_v then
                                Ev_v(2)   := '1';
                                UpdB_v    := Req_v;
                                EndSw_v   := false;
                                Phase_v   := Monitoring;
                                Restart_v := true;
                            end if;
                        elsif Msg_v(R_v) = '1' then
                            -- A message on the requested bus ends the process after the switch
                            EndSw_v := true;
                        elsif Expire_v then
                            Due_v := true;
                        end if;
                    elsif Msg_v(A_v) = '1' then
                        -- A message on the active bus ends the process, also over one of the inactive bus
                        -- (RM-SL-05, RM-SL-06)
                        Ev_v(2)   := '1';
                        UpdB_v    := Link_ActiveBus;
                        Phase_v   := Monitoring;
                        Restart_v := true;
                    elsif Msg_v(I_v) = '1' then
                        -- A message on the inactive bus: that bus at once, Ctoggle unchanged (RM-SL-06)
                        Req_v    := not Link_ActiveBus;
                        EndSw_v  := true;
                        WaitLk_v := true;
                    elsif Due_v and PreOp_v and C_v /= 0 and Ct_v < N_v then
                        -- Toggle: the other bus, Ctoggle + 1, timer restart; only in Pre-operational and with C /= 0
                        -- (RM-SL-03, RM-SL-04, RM-SL-09, RM-HB-03)
                        Req_v     := not Req_v;
                        Ct_v      := Ct_v + 1;
                        Due_v     := false;
                        EndRep_v  := false;
                        WaitLk_v  := true;
                        Restart_v := true;
                    elsif Due_v and Ct_v >= N_v then
                        -- Ctoggle has reached Ntoggle: no toggle, one event, the process keeps running (RM-SL-04)
                        Due_v := false;
                        if not EndRep_v then
                            Ev_v(4)  := '1';
                            EndRep_v := true;
                        end if;
                    elsif Expire_v then
                        Due_v := true;
                    end if;
                    -- A toggle that waits for Pre-operational: Pre-operational again at every expiry while the node is
                    -- Operational or Stopped (RM-SL-03)
                    if Phase_v = Selection and not WaitLk_v and Expire_v and Due_v and OpSt_v then
                        Ev_v(0) := '1';
                    end if;

            end case;

            if Restart_v or ParChg_v or HbRst_v then
                Elap_v := 0;
            end if;
            -- Write of Ctoggle, also in the cycle of a toggle (RM-SL-10)
            if Cfg_CtoggleWr = '1' then
                Ct_v := to_integer(unsigned(Cfg_Ctoggle));
            end if;
            PrevC_v := Cfg_HbTime;
            PrevT_v := Cfg_Ttoggle;
        end if;

        ExpLinkBus <= Req_v;
        if Phase_v = Selection then
            ExpSel <= '1';
        else
            ExpSel <= '0';
        end if;
        ExpCtoggle  <= std_logic_vector(to_unsigned(Ct_v mod 256, 8));
        ExpHbState  <= HbSt_v;
        ExpPresent  <= Pres_v;
        ExpPreop    <= Ev_v(0);
        ExpSwitched <= Ev_v(1);
        ExpUpdValid <= Ev_v(2);
        ExpUpdBdef  <= UpdB_v;
        ExpMiss     <= Ev_v(3);
        ExpEnd      <= Ev_v(4);
        ExpDlc      <= Ev_v(5);
    end process;

    -----------------------------------------------------------------------------------------------
    -- Checkers in every cycle
    -----------------------------------------------------------------------------------------------
    p_check : process is
        variable Bus_v : std_logic;

        procedure cmp (dut : std_logic_vector; exp : std_logic_vector; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & to_string(dut, BIN) & ", reference model " & to_string(exp, BIN));
            end if;
        end procedure;

        procedure cmp (dut : std_logic; exp : std_logic; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & std_logic'image(dut) & ", reference model " & std_logic'image(exp));
            end if;
        end procedure;

        variable Sw_v : std_logic := '0';
    begin
        wait until falling_edge(Clk);
        if CheckEn and Rst = '0' then
            cmp(Link_Bus, ExpLinkBus, "Link_Bus");
            cmp(Stat_Selecting, ExpSel, "Stat_Selecting");
            cmp(Stat_Ctoggle, ExpCtoggle, "Stat_Ctoggle");
            cmp(Stat_HbState, ExpHbState, "Stat_HbState");
            cmp(Stat_HbPresent, ExpPresent, "Stat_HbPresent");
            cmp(Nmt_PreopReq, ExpPreop, "Nmt_PreopReq");
            cmp(Nmt_Switched, ExpSwitched, "Nmt_Switched");
            cmp(Upd_Valid, ExpUpdValid, "Upd_Valid");
            if Upd_Valid = '1' then
                cmp(Upd_Bdefault, ExpUpdBdef, "Upd_Bdefault");
            end if;
            cmp(Err_HbMissing, ExpMiss, "Err_HbMissing");
            cmp(Err_ToggleEnd, ExpEnd, "Err_ToggleEnd");
            cmp(Err_HbDlc, ExpDlc, "Err_HbDlc");
            cmp(Stat_ActiveBus, Link_ActiveBus, "Stat_ActiveBus");
            -- Link_Bus never changes while the link reports a switch
            if Sw_v = '1' and Link_Bus /= Bus_v then
                alert(ERROR, "Link_Bus changed during a switch of the link");
            end if;
        end if;
        Sw_v  := Link_Switching;
        Bus_v := Link_Bus;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable N_v : natural;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        procedure doReset is
        begin
            wait until rising_edge(Clk);
            Rst <= '1';
            clocks(3);
            Rst <= '0';
        end procedure;

        -- Events of one cycle: heartbeats (DLC per bus) and NMT messages
        procedure ev (
            hbA  : std_logic;
            dlcA : natural;
            hbB  : std_logic;
            dlcB : natural;
            nmtA : std_logic;
            nmtB : std_logic;
            st   : natural := 5) is
        begin
            wait until rising_edge(Clk);
            Rx_HbValid  <= hbB & hbA;
            Rx_HbDlc    <= std_logic_vector(to_unsigned(dlcB, 4)) & std_logic_vector(to_unsigned(dlcA, 4));
            Rx_HbState  <= u8(st) & u8(st);
            Rx_NmtValid <= nmtB & nmtA;
            wait until rising_edge(Clk);
            Rx_HbValid  <= "00";
            Rx_NmtValid <= "00";
        end procedure;

        -- Master heartbeat (DLC 1) or NMT message on bus b
        procedure hb (b : natural; dlc : natural := 1; st : natural := 5) is
        begin
            if b = 0 then
                ev('1', dlc, '0', 1, '0', '0', st);
            else
                ev('0', 1, '1', dlc, '0', '0', st);
            end if;
        end procedure;

        -- Master heartbeat on bus b in the current cycle
        procedure hbNow (b : natural) is
        begin
            Rx_HbValid    <= "00";
            Rx_HbValid(b) <= '1';
            Rx_HbDlc      <= x"11";
            wait until rising_edge(Clk);
            Rx_HbValid    <= "00";
        end procedure;

        procedure nmt (b : natural) is
        begin
            if b = 0 then
                ev('0', 1, '0', 1, '1', '0');
            else
                ev('0', 1, '0', 1, '0', '1');
            end if;
        end procedure;

        impure function act return natural is
        begin
            if Link_ActiveBus = '1' then
                return 1;
            else
                return 0;
            end if;
        end function;

        procedure waitFor (signal s : std_logic; val : std_logic; timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while s /= val loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        procedure waitCnt (signal s : natural; n : natural; timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while s < n loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- Reset, start-up and the end of the start-up bus selection by an NMT message: monitoring on Bdefault
        procedure toMonitor is
        begin
            NmtTarget <= NmtInit_c;
            doReset;
            clocks(SwDly + 6);
            if MinimalSet_g then
                NmtTarget <= NmtOp_c;
                clocks(3);
            else
                NmtTarget <= NmtPreOp_c;
                clocks(1);
                nmt(act);
                NmtTarget <= NmtOp_c;
                clocks(2);
            end if;
        end procedure;

        -- Monitoring, then the missing master heartbeat: a bus selection process with its first toggle due
        procedure toSelect is
        begin
            toMonitor;
            waitCnt(CntMiss, CntMiss + 1, 300000, "missing master heartbeat");
        end procedure;

        procedure afterTick (k : natural) is
            variable N_v : natural := 0;
        begin

            loop
                wait until rising_edge(Clk);
                exit when Tick_Ms = '1';
                N_v := N_v + 1;
                if N_v > 2 * TickPer + 10 then
                    alert(ERROR, "timeout: tick");
                    exit;
                end if;
            end loop;

            clocks(k);
        end procedure;

        -- Waits until the link reports a switch (Link_Switching = '1'), at most 1 ms
        procedure waitSwitching is
        begin
            if Link_Switching /= '1' then
                wait until Link_Switching = '1' for 1 ms;
            end if;
            check_value(Link_Switching, '1', ERROR, "timeout: switch of the link");
        end procedure;

        variable C0_v   : natural;
        variable K_v    : natural;
        variable TC_v   : natural;
        variable B_v    : natural;
        variable Bd_v   : std_logic;
        variable Rnd_v  : natural;
        variable Dens_v : natural;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            CheckEn       <= false;
            TickPer       <= 4;
            NmtDly        <= 1;
            NmtIgnore     <= false;
            SwDly         <= 3;
            Cfg_HbTime    <= u16(5);
            Cfg_Ttoggle   <= u8(2);
            Cfg_Ntoggle   <= u8(4);
            Cfg_Bdefault  <= '0';
            Cfg_CtoggleWr <= '0';
            NmtTarget     <= NmtInit_c;
            doReset;
            CheckEn       <= true;

            -- *** TC-RM-01: start-up on Bdefault ***
            if run("test_startup") then

                for Bd in 0 to 1 loop
                    if Bd = 1 then
                        Cfg_Bdefault <= '1';
                    end if;
                    NmtTarget <= NmtInit_c;
                    doReset;
                    clocks(20);
                    check_value(Link_Bus = '1', Bd = 1, ERROR, "requested bus Bdefault");
                    check_value(Stat_ActiveBus = '1', Bd = 1, ERROR, "active bus Bdefault");
                    check_value(Stat_Selecting, '0', ERROR, "no process before Pre-operational");
                    C0_v      := CntSw;
                    if MinimalSet_g then
                        -- The Initialisation ends in Operational, and in the second run in Pre-operational: the
                        -- monitoring starts when the node leaves the Initialisation, in either state (RM-MS-02)
                        if Bd = 0 then
                            NmtTarget <= NmtOp_c;
                        else
                            NmtTarget <= NmtPreOp_c;
                        end if;
                        N_v := CntMiss;
                        clocks(3);
                        check_value(Stat_Selecting, '0', ERROR, "minimal set: no start-up process");
                        waitCnt(CntMiss, N_v + 1, 10 * 4 + 20, "minimal set: monitoring after the Initialisation");
                    else
                        -- A write of Ctoggle before the start has no effect on the process (RM-SL-10)
                        wait until rising_edge(Clk);
                        Cfg_Ctoggle   <= u8(3);
                        Cfg_CtoggleWr <= '1';
                        wait until rising_edge(Clk);
                        Cfg_CtoggleWr <= '0';
                        NmtTarget     <= NmtPreOp_c;
                        clocks(3);
                        check_value(Stat_Selecting, '1', ERROR, "start-up process in Pre-operational");
                        check_value(Stat_Ctoggle, u8(0), ERROR, "Ctoggle 0 at the start");
                        check_value(Link_Bus = '1', Bd = 1, ERROR, "start-up process on Bdefault");
                        check_value(CntSw, C0_v, ERROR, "no switch at the start");
                    end if;
                end loop;

            -- *** TC-RM-02: DLC of the master heartbeat ***
            elsif run("test_hb_dlc") then
                Cfg_HbTime <= u16(65535);
                toMonitor;

                for B in 0 to 1 loop

                    for Dlc in 0 to 15 loop
                        if Dlc /= 1 then
                            C0_v := CntDlc;
                            hb(B, Dlc);
                            clocks(2);
                            check_value(CntDlc, C0_v + 1, ERROR, "Err_HbDlc for DLC " & to_string(Dlc));
                            check_value(Stat_HbPresent, "00", ERROR, "no presence for a wrong DLC");
                        end if;
                    end loop;

                end loop;

                for St in 0 to 255 loop
                    hb(act, 1, St);
                    wait until falling_edge(Clk);
                    check_value(Stat_HbState, u8(St), ERROR, "state byte accepted");
                end loop;

                C0_v := CntDlc;
                ev('1', 3, '1', 0, '0', '0');
                clocks(2);
                check_value(CntDlc, C0_v + 1, ERROR, "one Err_HbDlc for both buses");

            -- *** TC-RM-03: monitoring of the master heartbeat ***
            elsif run("test_hb_monitoring") then

                for K in 0 to 4 loop

                    case K is
                        when 0 =>
                            -- C = 1 from the measured heartbeat on (below)
                            Cfg_HbTime  <= u16(5);
                            Cfg_Ttoggle <= u8(1);
                            TC_v        := 1;
                        when 1 =>
                            Cfg_HbTime  <= u16(5);
                            Cfg_Ttoggle <= u8(3);
                            TC_v        := 15;
                        when 2 =>
                            Cfg_HbTime  <= u16(2);
                            Cfg_Ttoggle <= u8(255);
                            TC_v        := 510;
                        when 3 =>
                            Cfg_HbTime  <= u16(65535);
                            Cfg_Ttoggle <= u8(1);
                            TC_v        := 65535;
                        when others =>
                            Cfg_HbTime  <= u16(5);
                            Cfg_Ttoggle <= u8(0);
                            TC_v        := 5;
                    end case;

                    toMonitor;
                    C0_v := CntMiss;
                    if TC_v > 1 then

                        for I in 1 to 3 loop
                            clocks((TC_v - 2) * 4);
                            hb(act);
                        end loop;

                        check_value(CntMiss, C0_v, ERROR, "heartbeats in time keep the monitoring");
                    end if;
                    afterTick(0);
                    if K = 0 then
                        Cfg_HbTime <= u16(1);
                    end if;
                    hbNow(act);
                    clocks(1);
                    C0_v := CntMiss;
                    waitCnt(CntMiss, C0_v + 1, TC_v * 4 + 10, "missing master heartbeat");
                    check_value(CycMiss - CycHb, TC_v * 4, ERROR, "missing after T x C ticks, K = " & to_string(K));
                end loop;

                -- Bounds: T x C = 3, tick every 16 cycles
                TickPer     <= 16;
                Cfg_HbTime  <= u16(3);
                Cfg_Ttoggle <= u8(1);
                toMonitor;
                C0_v        := CntMiss;
                afterTick(0);
                hbNow(act);
                waitCnt(CntMiss, C0_v + 1, 100, "missing heartbeat, upper bound");
                check_value(CycMiss - CycHb, 3 * 16, ERROR, "heartbeat one cycle after a tick");
                toMonitor;
                C0_v        := CntMiss;
                afterTick(14);
                hbNow(act);
                waitCnt(CntMiss, C0_v + 1, 100, "missing heartbeat, lower bound");
                check_value(CycMiss - CycHb, 2 * 16 + 2, ERROR, "heartbeat one cycle before a tick");

            -- *** TC-RM-04: consumer heartbeat time 0 ***
            elsif run("test_hb_disabled") then
                -- T = 1: a timer that ran with C = 0 would expire after 65536 ticks, within the 100000 ticks below
                Cfg_HbTime  <= u16(0);
                Cfg_Ttoggle <= u8(1);
                TickPer     <= 2;
                NmtTarget   <= NmtInit_c;
                doReset;
                clocks(10);
                NmtTarget   <= NmtPreOp_c;
                clocks(200000);
                check_value(Stat_Selecting, '1', ERROR, "the process waits for a message");
                check_value(Stat_Ctoggle, u8(0), ERROR, "no toggle with C = 0");
                hb(act);
                clocks(2);
                check_value(Stat_Selecting, '0', ERROR, "the process ends by a message");
                check_value(Stat_HbPresent, "00", ERROR, "no presence with C = 0");
                clocks(200000);
                check_value(CntMiss, 0, ERROR, "no missing heartbeat with C = 0");

            -- *** TC-RM-05: presence per bus ***
            elsif run("test_hb_presence") then
                Cfg_HbTime  <= u16(10);
                Cfg_Ttoggle <= u8(3);
                toMonitor;
                hb(act);
                wait until falling_edge(Clk);
                check_value(Stat_HbPresent(act), '1', ERROR, "presence of the active bus");
                clocks(10 * 4 + 4);
                check_value(Stat_HbPresent(act), '0', ERROR, "presence cleared after C ticks");
                -- Heartbeats on the inactive bus: presence, but no restart of the timer
                C0_v := CntMiss;
                B_v  := act;
                hb(B_v);
                clocks(1);
                N_v  := CycHb;

                for I in 1 to 4 loop
                    clocks(5 * 4);
                    hb(1 - B_v);
                    wait until falling_edge(Clk);
                    check_value(Stat_HbPresent(1 - B_v), '1', ERROR, "presence of the inactive bus");
                end loop;

                waitCnt(CntMiss, C0_v + 1, 30 * 4, "missing heartbeat despite the inactive bus");
                check_value(CycMiss - N_v >= 29 * 4 + 2 and CycMiss - N_v <= 30 * 4 + 1, ERROR,
                            "the inactive bus did not restart the timer");

            -- *** TC-RM-06: change of the parameters ***
            elsif run("test_param_change") then
                toMonitor;
                C0_v       := CntMiss;
                clocks(5 * 4);
                Cfg_HbTime <= u16(7);
                N_v        := Cyc + 1;
                waitCnt(CntMiss, C0_v + 1, 20 * 4, "missing after the change of C");
                check_value(CycMiss - N_v >= 13 * 4 + 1 and CycMiss - N_v <= 14 * 4 + 1, ERROR,
                            "missing T x C ticks after the change of C");
                -- Change of T during the process: the next toggle T x C ticks after it
                waitFor(Stat_Selecting, '1', 100, "bus selection process after the missing heartbeat");
                waitCnt(CntSw, CntSw + 1, 200, "first toggle");
                clocks(4 * 4);
                Cfg_Ttoggle <= u8(4);
                N_v         := Cyc + 1;
                C0_v        := CntSw;
                waitCnt(CntSw, C0_v + 1, 40 * 4, "toggle after the change of T");
                check_value(CycSw - N_v >= 27 * 4 and CycSw - N_v <= 28 * 4 + SwDly + 6, ERROR,
                            "toggle T x C ticks after the change of T");

            -- *** TC-RM-07: the first toggle ***
            elsif run("test_first_toggle") then

                for K in 0 to 3 loop
                    if K < 3 then

                        case K is
                            when 0 =>
                                NmtDly <= 0;
                            when 1 =>
                                NmtDly <= 1;
                            when others =>
                                NmtDly <= 50;
                        end case;

                        SwDly <= 1;
                        if K = 2 then
                            SwDly <= 400;
                        end if;
                        toSelect;
                    else
                        -- The NMT model stays in the Initialisation for 10 ticks
                        toMonitor;
                        NmtTarget <= NmtInit_c;
                        waitCnt(CntMiss, CntMiss + 1, 300, "missing heartbeat");
                        C0_v      := CntSw;
                        clocks(10 * 4);
                        check_value(Stat_Ctoggle, u8(0), ERROR, "no toggle outside Pre-operational");
                        NmtTarget <= NmtPreOp_c;
                    end if;
                    waitFor(Link_Switching, '1', 200, "toggle");
                    check_value(CycBus - CycPreOp, 1, ERROR, "toggle one cycle after Pre-operational");
                    check_value(Stat_Ctoggle, u8(1), ERROR, "Ctoggle 1 after the first toggle");
                    C0_v := CntSw;
                    waitCnt(CntSw, C0_v + 1, 500, "switch event");
                    check_value(CycSw - CycSwEnd, 1, ERROR, "Nmt_Switched one cycle after the link");
                end loop;

            -- *** TC-RM-08: toggling without a message ***
            elsif run("test_toggling") then
                TickPer     <= 8;
                Cfg_HbTime  <= u16(1);
                Cfg_Ttoggle <= u8(1);
                SwDly       <= 2;

                for K in 0 to 4 loop

                    case K is
                        when 0 =>
                            N_v  := 0;
                            Bd_v := '0';
                        when 1 =>
                            N_v  := 1;
                            Bd_v := '0';
                        when 2 =>
                            N_v  := 2;
                            Bd_v := '1';
                        when 3 =>
                            N_v  := 3;
                            Bd_v := '1';
                        when others =>
                            N_v  := 255;
                            Bd_v := '0';
                    end case;

                    Cfg_Ntoggle  <= u8(N_v);
                    Cfg_Bdefault <= Bd_v;
                    toSelect;
                    C0_v         := CntSw;
                    K_v          := CntEnd;
                    waitCnt(CntEnd, K_v + 1, (N_v + 2) * 30, "end of the toggling");
                    if N_v = 0 then
                        -- The first toggle is due at once after the missing heartbeat (RM-SL-02): with N = 0 the
                        -- toggling ends in the next cycle
                        check_value(CycEnd - CycMiss, 1, ERROR, "N = 0: Err_ToggleEnd one cycle after Err_HbMissing");
                    end if;
                    check_value(CntSw - C0_v, N_v, ERROR, "number of toggles");
                    check_value(Stat_Ctoggle, u8(N_v), ERROR, "Ctoggle after the toggling");
                    if N_v mod 2 = 0 then
                        check_value(Link_Bus, Bd_v, ERROR, "even N: on the start bus");
                    else
                        check_value(Link_Bus, not Bd_v, ERROR, "odd N: on the other bus");
                    end if;
                    clocks(50);
                    check_value(Stat_Selecting, '1', ERROR, "the process keeps running");
                    check_value(CntEnd, K_v + 1, ERROR, "one Err_ToggleEnd");
                end loop;

                -- Start-up process with N = 0: Err_ToggleEnd at the first expiry
                Cfg_Ntoggle  <= u8(0);
                Cfg_Bdefault <= '0';
                NmtTarget    <= NmtInit_c;
                doReset;
                clocks(10);
                afterTick(0);
                NmtTarget    <= NmtPreOp_c;
                C0_v         := CntEnd;
                clocks(4);
                check_value(CntEnd, C0_v, ERROR, "no Err_ToggleEnd before the first expiry");
                waitCnt(CntEnd, C0_v + 1, 30, "Err_ToggleEnd at the first expiry");

            -- *** TC-RM-09: end of the process on the active bus ***
            elsif run("test_select_end_active") then
                Cfg_Ntoggle <= u8(10);

                for K in 0 to 5 loop
                    if K / 2 = 0 then
                        NmtDly <= 20;
                    else
                        NmtDly <= 1;
                    end if;
                    toSelect;
                    C0_v := CntSw;
                    if K / 2 > 0 then
                        waitCnt(CntSw, C0_v + K / 2, 500, "toggles before the message");
                    end if;
                    clocks(2);
                    C0_v := CntUpd;
                    B_v  := act;
                    if K mod 2 = 0 then
                        nmt(B_v);
                    else
                        hb(B_v);
                    end if;
                    wait until falling_edge(Clk);
                    check_value(Stat_Selecting, '0', ERROR, "monitoring after the end");
                    wait until falling_edge(Clk);
                    check_value(CntUpd, C0_v + 1, ERROR, "Upd_Valid at the end of the process");
                    check_value(UpdBus = '1', B_v = 1, ERROR, "Bdefault updated to the active bus");
                    C0_v := CntMiss;
                    waitCnt(CntMiss, C0_v + 1, 10 * 4 + 10, "monitoring after the end");
                end loop;

            -- *** TC-RM-10: message on the inactive bus during the process ***
            elsif run("test_select_end_inactive") then
                Cfg_Ntoggle <= u8(10);
                SwDly       <= 20;

                for K in 0 to 4 loop
                    toSelect;
                    waitCnt(CntSw, CntSw + 1, 500, "first toggle completed");
                    clocks(2);
                    C0_v := CntUpd;
                    K_v  := to_integer(unsigned(Stat_Ctoggle));
                    B_v  := act;

                    case K is
                        when 0 =>
                            -- Waiting in Select_s
                            hb(1 - B_v);
                            wait until falling_edge(Clk);
                            check_value(Link_Bus = '1', B_v = 0, ERROR, "switch at once to the bus of the message");
                            check_value(Stat_Ctoggle, u8(K_v), ERROR, "Ctoggle unchanged");
                        when 1 =>
                            -- In the cycle after a toggle: a message on the requested bus
                            wait until Link_Bus /= Link_ActiveBus for 1 ms;
                            check_value(Link_Bus /= Link_ActiveBus, true, ERROR, "timeout: toggle");
                            nmt(1 - B_v);
                        when 2 =>
                            -- During a switch: a message on the requested bus
                            waitSwitching;
                            clocks(5);
                            hb(1 - B_v);
                        when 3 =>
                            -- During a switch: a message on the bus left: no effect
                            waitSwitching;
                            clocks(5);
                            hb(B_v);
                        when others =>
                            -- Messages on both buses in one cycle: the active bus wins
                            ev('1', 1, '1', 1, '0', '0');
                            clocks(1);
                            wait until falling_edge(Clk);
                            check_value(CntUpd, C0_v + 1, ERROR, "the active bus wins");
                            check_value(UpdBus = '1', B_v = 1, ERROR, "Bdefault of the active bus");
                    end case;

                    if K < 3 then
                        waitCnt(CntUpd, C0_v + 1, 200, "end of the process after the switch");
                        check_value(Stat_Selecting, '0', ERROR, "monitoring on the new bus");
                        check_value(Stat_ActiveBus, Link_Bus, ERROR, "active bus is the requested bus");
                    elsif K = 3 then
                        clocks(SwDly + 5);
                        check_value(CntUpd, C0_v, ERROR, "message on the bus left ignored");
                        check_value(Stat_Selecting, '1', ERROR, "the process continues");
                    end if;
                end loop;

            -- *** TC-RM-11: the inactive bus outside the process ***
            elsif run("test_inactive_ignored") then
                toMonitor;
                C0_v := CntMiss;
                B_v  := act;
                hb(B_v);
                clocks(1);
                N_v  := CycHb;

                for I in 0 to 5 loop
                    clocks(1);
                    if I mod 2 = 0 then
                        hb(1 - B_v);
                    else
                        nmt(1 - B_v);
                    end if;
                    check_value(Link_Bus = '1', B_v = 1, ERROR, "no change of the bus");
                end loop;

                waitCnt(CntMiss, C0_v + 1, 10 * 4 + 10, "missing heartbeat at its time");
                check_value(CycMiss - N_v <= 10 * 4 + 1, ERROR, "the inactive bus did not restart the timer");

            -- *** TC-RM-12: writes of Bdefault, Ctoggle and Ntoggle ***
            elsif run("test_writes") then
                Cfg_Ntoggle <= u8(5);
                -- Bdefault during a process: no effect on the bus and the toggling
                toSelect;
                Bd_v         := Link_ActiveBus;
                waitCnt(CntSw, CntSw + 1, 200, "first toggle");
                Cfg_Bdefault <= '1';
                waitCnt(CntSw, CntSw + 1, 200, "second toggle");
                check_value(Link_Bus, Bd_v, ERROR, "two toggles: back on the start bus");
                nmt(act);
                clocks(2);
                check_value(UpdBus, Bd_v, ERROR, "the end of the process overwrites the written Bdefault");
                -- Bdefault outside a process: no change of the bus, used after the next reset
                clocks(4);
                check_value(Link_Bus, Bd_v, ERROR, "write outside a process: no change of the bus");
                doReset;
                clocks(10);
                check_value(Link_Bus, '1', ERROR, "the written Bdefault after the reset");
                Cfg_Bdefault <= '0';
                -- Ctoggle written during a process
                toSelect;
                waitCnt(CntSw, CntSw + 1, 200, "first toggle");
                wait until rising_edge(Clk);
                Cfg_Ctoggle   <= u8(3);
                Cfg_CtoggleWr <= '1';
                wait until rising_edge(Clk);
                Cfg_CtoggleWr <= '0';
                wait until falling_edge(Clk);
                check_value(Stat_Ctoggle, u8(3), ERROR, "Ctoggle loaded");
                C0_v          := CntSw;
                waitCnt(CntEnd, CntEnd + 1, 500, "end of the toggling after the write");
                check_value(CntSw - C0_v, 2, ERROR, "toggling continued from the written value");
                -- Written to 0 after the end: the toggling resumes at the next expiry
                wait until rising_edge(Clk);
                Cfg_Ctoggle   <= u8(0);
                Cfg_CtoggleWr <= '1';
                wait until rising_edge(Clk);
                Cfg_CtoggleWr <= '0';
                C0_v          := CntSw;
                waitCnt(CntSw, C0_v + 1, 200, "toggling resumes after the write of 0");
                -- Written with N or more: the toggling ends at the next due toggle
                wait until rising_edge(Clk);
                Cfg_Ctoggle   <= u8(7);
                Cfg_CtoggleWr <= '1';
                wait until rising_edge(Clk);
                Cfg_CtoggleWr <= '0';
                C0_v          := CntEnd;
                waitCnt(CntEnd, C0_v + 1, 200, "end of the toggling after a write of 7");
                -- A write in the cycle of a toggle wins
                NmtDly        <= 5;
                toMonitor;
                NmtTarget     <= NmtOp_c;
                waitCnt(CntMiss, CntMiss + 1, 300, "missing heartbeat");
                wait until Nmt_State = NmtPreOp_c for 1 ms;
                check_value(Nmt_State, NmtPreOp_c, ERROR, "timeout: Pre-operational");
                Cfg_Ctoggle   <= u8(9);
                Cfg_CtoggleWr <= '1';
                wait until rising_edge(Clk);
                Cfg_CtoggleWr <= '0';
                wait until falling_edge(Clk);
                check_value(Stat_Ctoggle, u8(9), ERROR, "the write wins over the toggle");
                -- Ntoggle written during a process
                NmtDly      <= 1;
                Cfg_Ntoggle <= u8(5);
                toSelect;
                waitCnt(CntSw, CntSw + 1, 200, "first toggle");
                Cfg_Ntoggle <= u8(1);
                C0_v        := CntEnd;
                waitCnt(CntEnd, C0_v + 1, 200, "end at the next due toggle after the write of Ntoggle");
                check_value(Stat_Ctoggle, u8(1), ERROR, "no further toggle");

            -- *** TC-RM-13: NMT resets ***
            elsif run("test_nmt_resets") then
                toMonitor;
                Bd_v      := Link_Bus;
                NmtTarget <= NmtInit_c;
                clocks(3 * 4);
                NmtTarget <= NmtPreOp_c;
                clocks(4);
                check_value(Link_Bus, Bd_v, ERROR, "NMT reset in the monitoring: bus kept");
                check_value(Stat_Selecting, '0', ERROR, "NMT reset in the monitoring: no process");
                -- During a process: a toggle that falls due in the Initialisation waits
                toSelect;
                waitCnt(CntSw, CntSw + 1, 200, "first toggle");
                K_v := to_integer(unsigned(Stat_Ctoggle));
                -- 25 ticks of Initialisation: two expiries of the timer (T x C = 10 ticks) fall into it
                NmtTarget <= NmtInit_c;
                clocks(25 * 4);
                check_value(Stat_Ctoggle, u8(K_v), ERROR, "no toggle in the Initialisation");
                check_value(Stat_Selecting, '1', ERROR, "the process is kept");
                C0_v      := CntSw;
                NmtTarget <= NmtPreOp_c;
                waitCnt(CntSw, C0_v + 1, 100, "the waiting toggle after Pre-operational");
                -- The waiting toggle restarts the timer: the next toggle T x C ticks after it (RM-SL-03, RM-SL-04)
                N_v := CycBus;
                waitCnt(CntSw, C0_v + 2, 10 * 4 + 20, "next toggle");
                check_value(CycBus - N_v >= 9 * 4 + 2 and CycBus - N_v <= 10 * 4 + 1, ERROR,
                            "next toggle T x C ticks after the waiting toggle");

            -- *** TC-RM-14: events in every cycle ***
            elsif run("test_events_every_cycle") then
                toMonitor;

                for Seg in 1 to 60 loop
                    -- Per segment: random delays of the models, tick period, parameters and NMT state
                    TickPer     <= random(2, 8);
                    NmtDly      <= random(0, 20);
                    SwDly       <= random(1, 50);
                    Cfg_HbTime  <= u16(random(0, 4));
                    Cfg_Ttoggle <= u8(random(0, 2));
                    if random(0, 3) = 0 then
                        Cfg_Ntoggle <= u8(255);
                    else
                        Cfg_Ntoggle <= u8(random(0, 4));
                    end if;
                    Cfg_Bdefault <= std_logic'val(std_logic'pos('0') + random(0, 1));

                    case random(0, 5) is
                        when 0 =>
                            NmtTarget <= NmtInit_c;
                        when 1 =>
                            NmtTarget <= NmtOp_c;
                        when 2 =>
                            NmtTarget <= NmtStopped_c;
                        when others =>
                            NmtTarget <= NmtPreOp_c;
                    end case;

                    -- Events of both buses with a random density, from none (timer expiries) to every cycle
                    Dens_v := random(0, 3);

                    for I in 1 to 400 loop
                        wait until rising_edge(Clk);
                        Rx_HbValid  <= "00";
                        Rx_NmtValid <= "00";
                        if Dens_v > 0 and random(1, 3) <= Dens_v then
                            Rnd_v       := random(0, 63);
                            Rx_HbValid  <= std_logic_vector(to_unsigned(Rnd_v mod 4, 2));
                            Rx_NmtValid <= std_logic_vector(to_unsigned((Rnd_v / 4) mod 4, 2)) and
                                           std_logic_vector(to_unsigned(Rnd_v / 16, 2));
                            Rx_HbDlc    <= std_logic_vector(to_unsigned(random(0, 2), 4)) &
                                           std_logic_vector(to_unsigned(random(0, 2), 4));
                            Rx_HbState  <= u8(random(0, 255)) & u8(random(0, 255));
                        end if;
                        Cfg_CtoggleWr <= '0';
                        if random(0, 99) = 0 then
                            Cfg_Ctoggle   <= u8(random(0, 5));
                            Cfg_CtoggleWr <= '1';
                        end if;
                    end loop;

                end loop;

                wait until rising_edge(Clk);
                Rx_HbValid    <= "00";
                Rx_NmtValid   <= "00";
                Cfg_CtoggleWr <= '0';
                clocks(100);

            -- *** TC-RM-15: minimal set ***
            elsif run("test_minimal_set") then
                check_value(MinimalSet_g, true, ERROR, "test_minimal_set runs in the configuration minimal");
                NmtDly <= 20;

                for K in 0 to 3 loop
                    toSelect;
                    clocks(2);
                    B_v  := act;
                    C0_v := CntUpd;

                    case K is
                        when 0 =>
                            hb(B_v);
                        when 1 =>
                            nmt(B_v);
                        when 2 =>
                            hb(1 - B_v);
                        when others =>
                            nmt(1 - B_v);
                    end case;

                    waitCnt(CntUpd, C0_v + 1, 100, "end of the process");
                    if K < 2 then
                        check_value(UpdBus = '1', B_v = 1, ERROR, "the active bus found");
                    else
                        check_value(UpdBus = '1', B_v = 0, ERROR, "the other bus found");
                    end if;
                end loop;

            -- *** TC-RM-16: recovery ***
            elsif run("test_recovery") then
                Cfg_Ntoggle <= u8(2);
                -- After the end of the toggling: the master heartbeat on the bus of the node
                toSelect;
                waitCnt(CntEnd, CntEnd + 1, 500, "end of the toggling");
                C0_v := CntUpd;
                hb(act);
                waitCnt(CntUpd, C0_v + 1, 10, "end of the process by the master heartbeat");
                -- A Ctoggle write restarts the toggling; the master is found on the other bus
                toSelect;
                waitCnt(CntEnd, CntEnd + 1, 500, "end of the toggling");
                wait until rising_edge(Clk);
                Cfg_Ctoggle   <= u8(0);
                Cfg_CtoggleWr <= '1';
                wait until rising_edge(Clk);
                Cfg_CtoggleWr <= '0';
                C0_v          := CntSw;
                waitCnt(CntSw, C0_v + 1, 200, "toggle after the write");
                clocks(2);
                C0_v          := CntUpd;
                nmt(act);
                waitCnt(CntUpd, C0_v + 1, 10, "master found after the restarted toggling");

                -- Rst in Select_s and in Switch_s
                for K in 0 to 1 loop
                    toSelect;
                    if K = 1 then
                        waitSwitching;
                    end if;
                    doReset;
                    clocks(SwDly + 6);
                    check_value(Stat_Selecting, '0', ERROR, "Idle_s after the reset");
                    check_value(Link_Bus, Cfg_Bdefault, ERROR, "Bdefault after the reset");
                end loop;

                -- C from 0 to a nonzero value during the start-up process starts the toggling
                Cfg_HbTime <= u16(0);
                NmtTarget  <= NmtInit_c;
                doReset;
                clocks(10);
                NmtTarget  <= NmtPreOp_c;
                clocks(200);
                check_value(Stat_Ctoggle, u8(0), ERROR, "no toggle with C = 0");
                Cfg_HbTime <= u16(3);
                C0_v       := CntSw;
                waitCnt(CntSw, C0_v + 1, 2 * 2 * 3 * 4 + 20, "toggling after C changed from 0");

            -- *** TC-RM-20: a due toggle while the node is Operational or Stopped ***
            elsif run("test_preop_again") then

                for K in 0 to 2 loop
                    NmtDly    <= 1;
                    NmtIgnore <= false;
                    SwDly     <= 3;
                    if K = 2 then
                        SwDly <= 20;
                    end if;
                    toSelect;
                    if K = 2 then
                        -- The node enters Operational during the first switch, while the link still reports the old
                        -- bus (an NMT message of the old bus delivered during the switch)
                        waitSwitching;
                        clocks(5);
                        NmtIgnore <= true;
                        NmtTarget <= NmtStopped_c;
                        clocks(1);
                        NmtTarget <= NmtOp_c;
                    end if;
                    waitCnt(CntSw, CntSw + 1, 200, "first toggle");
                    -- The node leaves Pre-operational during the process and does not answer the requests
                    NmtIgnore <= true;
                    if K = 2 then
                        null;
                    elsif MinimalSet_g then
                        -- Minimal set: a reset communication leads through the Initialisation to Operational
                        NmtTarget <= NmtInit_c;
                        clocks(3);
                        NmtTarget <= NmtOp_c;
                    elsif K = 0 then
                        NmtTarget <= NmtStopped_c;
                    else
                        NmtTarget <= NmtStopped_c;
                        clocks(1);
                        NmtTarget <= NmtOp_c;
                    end if;
                    C0_v := CntPreop;
                    N_v  := CntSw;
                    -- Pre-operational is requested again at every expiry, T x C = 10 ticks apart (RM-SL-03)
                    waitCnt(CntPreop, C0_v + 1, 10 * 4 + 20, "Pre-operational requested again");
                    K_v := CycReq;
                    waitCnt(CntPreop, C0_v + 2, 10 * 4 + 20, "Pre-operational requested at the next expiry");
                    check_value(CycReq - K_v, 10 * 4, ERROR, "requests T x C ticks apart");
                    check_value(CntSw, N_v, ERROR, "no toggle outside Pre-operational");
                    -- The node answers the next request: the waiting toggle follows
                    NmtIgnore <= false;
                    waitCnt(CntSw, N_v + 1, 2 * 10 * 4 + 40, "the waiting toggle after Pre-operational");
                end loop;

            -- *** TC-RM-21: the Initialisation ends in Operational or Stopped (full set) ***
            elsif run("test_start_operational") then

                for K in 0 to 1 loop
                    if K = 0 then
                        NmtTarget <= NmtOp_c;
                    else
                        NmtTarget <= NmtStopped_c;
                    end if;
                    doReset;
                    clocks(10);
                    check_value(Stat_Selecting, '0', ERROR, "no start-up process outside Pre-operational");
                    C0_v := CntMiss;
                    waitCnt(CntMiss, C0_v + 1, 10 * 4 + 20, "monitoring after the Initialisation");
                    waitFor(Stat_Selecting, '1', 10, "bus selection process after the missing heartbeat");
                end loop;

            -- *** TC-RM-22: the consumer heartbeat time lowered while the presence runs ***
            elsif run("test_presence_lower_c") then
                Cfg_HbTime <= u16(10);
                toMonitor;
                B_v        := act;
                hb(B_v);
                clocks(6 * 4);
                check_value(Stat_HbPresent(B_v), '1', ERROR, "presence 6 ticks after the heartbeat");
                Cfg_HbTime <= u16(3);
                clocks(4 + 2);
                check_value(Stat_HbPresent(B_v), '0', ERROR, "presence cleared at the next tick after C = 3");

            -- *** TC-RM-23: a second process without a reset ***
            elsif run("test_second_process") then
                Cfg_Ntoggle <= u8(2);
                -- First process: two toggles and the end of the toggling
                toSelect;
                waitCnt(CntEnd, CntEnd + 1, 500, "end of the toggling of the first process");
                check_value(Stat_Ctoggle, u8(2), ERROR, "two toggles in the first process");
                C0_v := CntUpd;
                nmt(act);
                waitCnt(CntUpd, C0_v + 1, 10, "end of the first process");
                -- A write of Ctoggle outside a process has no effect on the next one (RM-SL-10)
                wait until rising_edge(Clk);
                Cfg_Ctoggle   <= u8(7);
                Cfg_CtoggleWr <= '1';
                wait until rising_edge(Clk);
                Cfg_CtoggleWr <= '0';
                -- The node in Operational, so that the first toggle waits for Pre-operational
                NmtDly    <= 20;
                NmtTarget <= NmtStopped_c;
                clocks(1);
                NmtTarget <= NmtOp_c;
                -- Second process: Ctoggle 0, the first toggle due at once, the end reported again (RM-SL-02, RM-SL-04)
                C0_v := CntMiss;
                N_v  := CntSw;
                K_v  := CntEnd;
                waitCnt(CntMiss, C0_v + 1, 10 * 4 + 20, "second missing heartbeat");
                wait until falling_edge(Clk);
                check_value(Stat_Ctoggle, u8(0), ERROR, "Ctoggle 0 at the start of the second process");
                waitCnt(CntSw, N_v + 1, 20 + 20, "first toggle of the second process after Pre-operational");
                waitCnt(CntEnd, K_v + 1, 500, "end of the toggling of the second process");
                check_value(CntSw - N_v, 2, ERROR, "two toggles in the second process");

            -- *** TC-RM-24: a due toggle and C = 0 ***
            elsif run("test_toggle_c0") then
                NmtDly <= 50;
                toSelect;
                -- C = 0 before the node enters Pre-operational: the due toggle is not made (RM-HB-03)
                Cfg_HbTime <= u16(0);
                N_v        := CntSw;
                Bd_v       := Link_Bus;
                clocks(80);
                check_value(Nmt_State, NmtPreOp_c, ERROR, "Pre-operational");
                check_value(CntSw, N_v, ERROR, "no toggle with C = 0");
                check_value(Link_Bus, Bd_v, ERROR, "the node stays on its bus");
                -- C /= 0 again: the due toggle is made
                Cfg_HbTime <= u16(5);
                waitCnt(CntSw, N_v + 1, 20, "the due toggle with C /= 0");

            end if;

            clocks(10);

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
