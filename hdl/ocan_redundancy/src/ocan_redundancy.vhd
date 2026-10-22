---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Bus monitoring and reconfiguration of an OpenCAN slave node: the consumer of the master heartbeat and the bus
-- selection process with the toggling mechanism and the update of Bdefault (ECSS-E-ST-50-15C 8.3).
--
-- Documentation: hdl/ocan_redundancy/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_redundancy is
    generic (
        MinimalSet_g : boolean := false
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Tick_Ms        : in    std_logic;
        -- Per bus from ocan_dispatch: NMT messages and master heartbeats
        Rx_NmtValid    : in    std_logic_vector(1 downto 0);
        Rx_HbValid     : in    std_logic_vector(1 downto 0);
        Rx_HbDlc       : in    std_logic_vector(7 downto 0);
        Rx_HbState     : in    std_logic_vector(15 downto 0);
        -- Parameters (1016h sub-index 1, 2000h) and the update of Bdefault
        Cfg_HbTime     : in    std_logic_vector(15 downto 0);
        Cfg_Bdefault   : in    std_logic;
        Cfg_Ttoggle    : in    std_logic_vector(7 downto 0);
        Cfg_Ntoggle    : in    std_logic_vector(7 downto 0);
        Cfg_CtoggleWr  : in    std_logic                    := '0';
        Cfg_Ctoggle    : in    std_logic_vector(7 downto 0) := (others => '0');
        Upd_Valid      : out   std_logic;
        Upd_Bdefault   : out   std_logic;
        -- ocan_link
        Link_Bus       : out   std_logic;
        Link_ActiveBus : in    std_logic;
        Link_Switching : in    std_logic;
        -- ocan_nmt
        Nmt_State      : in    std_logic_vector(1 downto 0);
        Nmt_PreopReq   : out   std_logic;
        Nmt_Switched   : out   std_logic;
        -- Status and events
        Stat_ActiveBus : out   std_logic;
        Stat_Selecting : out   std_logic;
        Stat_Ctoggle   : out   std_logic_vector(7 downto 0);
        Stat_HbState   : out   std_logic_vector(7 downto 0);
        Stat_HbPresent : out   std_logic_vector(1 downto 0);
        Err_HbMissing  : out   std_logic;
        Err_ToggleEnd  : out   std_logic;
        Err_HbDlc      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_redundancy is

    -- *** State machine ***
    type RedFsm_t is (Idle_s, Monitor_s, Select_s, Switch_s);

    type PresMs_a is array (0 to 1) of unsigned(15 downto 0);

    -- *** Two process method ***
    type TwoProcess_r is record
        Fsm        : RedFsm_t;
        ReqBus     : std_logic;
        Ctoggle    : unsigned(7 downto 0);
        ToggleDue  : std_logic;
        Exhausted  : std_logic;
        EndAfter   : std_logic;
        -- Timer of Ttoggle consumer heartbeat times (RM-1)
        TmrMs      : unsigned(15 downto 0);
        TmrPer     : unsigned(7 downto 0);
        HbTimeReg  : std_logic_vector(15 downto 0);
        TtoggleReg : std_logic_vector(7 downto 0);
        -- Presence per bus and the last state byte
        PresMs     : PresMs_a;
        Present    : std_logic_vector(1 downto 0);
        HbState    : std_logic_vector(7 downto 0);
        -- Events
        PreopReq   : std_logic;
        Switched   : std_logic;
        UpdValid   : std_logic;
        UpdBdef    : std_logic;
        ErrMissing : std_logic;
        ErrEnd     : std_logic;
        ErrDlc     : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable HbOk_v    : std_logic_vector(1 downto 0);
        variable Msg_v     : std_logic_vector(1 downto 0);
        variable A_v       : natural range 0 to 1;
        variable I_v       : natural range 0 to 1;
        variable R_v       : natural range 0 to 1;
        variable C_v       : unsigned(15 downto 0);
        variable T_v       : unsigned(7 downto 0);
        variable ParChg_v  : boolean;
        variable HbRst_v   : boolean;
        variable Restart_v : boolean;
        variable Expire_v  : boolean;
        variable PreOp_v   : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values of the events ***
        v.PreopReq   := '0';
        v.Switched   := '0';
        v.UpdValid   := '0';
        v.ErrMissing := '0';
        v.ErrEnd     := '0';
        v.ErrDlc     := '0';
        v.HbTimeReg  := Cfg_HbTime;
        v.TtoggleReg := Cfg_Ttoggle;
        Restart_v    := false;
        Expire_v     := false;

        -- *** Master heartbeats and messages per bus (RM-HB-01) ***
        for B in 0 to 1 loop
            if Rx_HbValid(B) = '1' and Rx_HbDlc(4 * B + 3 downto 4 * B) = "0001" then
                HbOk_v(B) := '1';
            else
                HbOk_v(B) := '0';
            end if;
            if Rx_HbValid(B) = '1' and Rx_HbDlc(4 * B + 3 downto 4 * B) /= "0001" then
                v.ErrDlc := '1';
            end if;
            Msg_v(B) := HbOk_v(B) or Rx_NmtValid(B);
        end loop;

        if Link_ActiveBus = '1' then
            A_v := 1;
            I_v := 0;
        else
            A_v := 0;
            I_v := 1;
        end if;
        if r.ReqBus = '1' then
            R_v := 1;
        else
            R_v := 0;
        end if;

        if HbOk_v(A_v) = '1' then
            v.HbState := Rx_HbState(8 * A_v + 7 downto 8 * A_v);
        end if;

        C_v := unsigned(Cfg_HbTime);
        if unsigned(Cfg_Ttoggle) = 0 then
            T_v := to_unsigned(1, 8);
        else
            T_v := unsigned(Cfg_Ttoggle);
        end if;

        -- *** Presence per bus (RM-HB-05) ***
        for B in 0 to 1 loop
            if C_v = 0 then
                v.PresMs(B)  := (others => '0');
                v.Present(B) := '0';
            elsif HbOk_v(B) = '1' then
                v.PresMs(B)  := (others => '0');
                v.Present(B) := '1';
            elsif Tick_Ms = '1' and r.Present(B) = '1' then
                if r.PresMs(B) = C_v - 1 then
                    v.PresMs(B)  := (others => '0');
                    v.Present(B) := '0';
                else
                    v.PresMs(B) := r.PresMs(B) + 1;
                end if;
            end if;
        end loop;

        -- *** Timer: Ttoggle consumer heartbeat times (RM-HB-02 to RM-HB-04) ***
        ParChg_v := Cfg_HbTime /= r.HbTimeReg or Cfg_Ttoggle /= r.TtoggleReg;
        HbRst_v  := r.Fsm = Monitor_s and HbOk_v(A_v) = '1';
        if Tick_Ms = '1' and C_v /= 0 and r.Fsm /= Idle_s and not ParChg_v and not HbRst_v then
            if r.TmrMs = C_v - 1 then
                v.TmrMs := (others => '0');
                if r.TmrPer >= T_v - 1 then
                    v.TmrPer := (others => '0');
                    Expire_v := true;
                else
                    v.TmrPer := r.TmrPer + 1;
                end if;
            else
                v.TmrMs := r.TmrMs + 1;
            end if;
        end if;

        -- *** Bus selection process (RM-SL-01 to RM-SL-10, RM-MS-02) ***
        PreOp_v := Nmt_State = NmtPreOp_c;

        case r.Fsm is

            when Idle_s =>
                if not MinimalSet_g and PreOp_v then
                    -- Start-up process on Bdefault without a switch (RM-SL-01)
                    v.Fsm       := Select_s;
                    v.Ctoggle   := (others => '0');
                    v.ToggleDue := '0';
                    v.Exhausted := '0';
                    Restart_v   := true;
                elsif MinimalSet_g and Nmt_State /= NmtInit_c then
                    -- Minimal set: monitoring from the end of the Initialisation (RM-MS-02)
                    v.Fsm     := Monitor_s;
                    Restart_v := true;
                else
                    v.ReqBus := Cfg_Bdefault;
                end if;

            when Monitor_s =>
                if Expire_v then
                    -- Missing master heartbeat (RM-HB-02, RM-SL-02)
                    v.ErrMissing := '1';
                    v.PreopReq   := '1';
                    v.Ctoggle    := (others => '0');
                    v.ToggleDue  := '1';
                    v.Exhausted  := '0';
                    v.Fsm        := Select_s;
                    Restart_v    := true;
                end if;

            when Select_s =>
                if Msg_v(A_v) = '1' then
                    -- The active bus is found (RM-SL-05)
                    v.UpdValid := '1';
                    v.UpdBdef  := Link_ActiveBus;
                    v.Fsm      := Monitor_s;
                    Restart_v  := true;
                elsif Msg_v(I_v) = '1' then
                    -- Parallel bus access: message on the inactive bus (RM-SL-06)
                    v.ReqBus   := not Link_ActiveBus;
                    v.EndAfter := '1';
                    v.Fsm      := Switch_s;
                elsif r.ToggleDue = '1' and PreOp_v and r.Ctoggle < unsigned(Cfg_Ntoggle) then
                    -- Toggle (RM-SL-03, RM-SL-04, RM-SL-09)
                    v.ReqBus    := not r.ReqBus;
                    v.Ctoggle   := r.Ctoggle + 1;
                    v.ToggleDue := '0';
                    v.Exhausted := '0';
                    v.Fsm       := Switch_s;
                    Restart_v   := true;
                elsif r.ToggleDue = '1' and r.Ctoggle >= unsigned(Cfg_Ntoggle) then
                    -- End of the toggling without an active bus (RM-SL-04)
                    v.ToggleDue := '0';
                    if r.Exhausted = '0' then
                        v.ErrEnd    := '1';
                        v.Exhausted := '1';
                    end if;
                elsif Expire_v then
                    v.ToggleDue := '1';
                end if;

            when Switch_s =>
                if Link_Switching = '0' and Link_ActiveBus = r.ReqBus then
                    -- The link has ended the switch: heartbeat on the new bus (RM-SL-03, NM-HB-05)
                    v.Switched := '1';
                    if r.EndAfter = '1' then
                        v.UpdValid := '1';
                        v.UpdBdef  := r.ReqBus;
                        v.EndAfter := '0';
                        v.Fsm      := Monitor_s;
                        Restart_v  := true;
                    else
                        v.Fsm := Select_s;
                    end if;
                elsif Msg_v(R_v) = '1' then
                    v.EndAfter := '1';
                elsif Expire_v then
                    v.ToggleDue := '1';
                end if;

            -- coverage off
            when others =>
                v.Fsm     := Monitor_s;
                Restart_v := true;
            -- coverage on

        end case;

        -- *** Restart of the timer ***
        if Restart_v or ParChg_v or HbRst_v then
            v.TmrMs  := (others => '0');
            v.TmrPer := (others => '0');
        end if;

        -- *** Write of Ctoggle, also in the cycle of a toggle (RM-SL-10) ***
        if Cfg_CtoggleWr = '1' then
            v.Ctoggle := unsigned(Cfg_Ctoggle);
        end if;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    Link_Bus       <= r.ReqBus;
    Stat_ActiveBus <= Link_ActiveBus;
    Stat_Selecting <= '1' when r.Fsm = Select_s or r.Fsm = Switch_s else '0';
    Stat_Ctoggle   <= std_logic_vector(r.Ctoggle);
    Stat_HbState   <= r.HbState;
    Stat_HbPresent <= r.Present;
    Nmt_PreopReq   <= r.PreopReq;
    Nmt_Switched   <= r.Switched;
    Upd_Valid      <= r.UpdValid;
    Upd_Bdefault   <= r.UpdBdef;
    Err_HbMissing  <= r.ErrMissing;
    Err_ToggleEnd  <= r.ErrEnd;
    Err_HbDlc      <= r.ErrDlc;

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm        <= Idle_s;
                r.ReqBus     <= '0';
                r.Ctoggle    <= (others => '0');
                r.ToggleDue  <= '0';
                r.Exhausted  <= '0';
                r.EndAfter   <= '0';
                r.TmrMs      <= (others => '0');
                r.TmrPer     <= (others => '0');
                r.HbTimeReg  <= (others => '0');
                r.TtoggleReg <= (others => '0');
                r.PresMs     <= (others => (others => '0'));
                r.Present    <= (others => '0');
                r.HbState    <= (others => '0');
                r.PreopReq   <= '0';
                r.Switched   <= '0';
                r.UpdValid   <= '0';
                r.UpdBdef    <= '0';
                r.ErrMissing <= '0';
                r.ErrEnd     <= '0';
                r.ErrDlc     <= '0';
            end if;
        end if;
    end process;

end architecture;
