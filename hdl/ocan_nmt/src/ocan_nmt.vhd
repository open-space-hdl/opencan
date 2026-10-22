---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- NMT slave of OpenCAN: the protected NODE-ID, the NMT state machine with the node control services and the
-- service enables, and the boot-up message and heartbeat producer (ECSS-E-ST-50-15C 6.5, 6.10, 9.4.6, 9.4.9).
--
-- Documentation: hdl/ocan_nmt/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ocan_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_nmt is
    generic (
        MinimalSet_g : boolean := false
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- NODE-ID pins and their complement (asynchronous)
        Pin_NodeId     : in    std_logic_vector(6 downto 0);
        Pin_NodeIdCode : in    std_logic_vector(6 downto 0);
        -- Millisecond tick and producer heartbeat time (1017h)
        Tick_Ms        : in    std_logic;
        Cfg_HbTime     : in    std_logic_vector(15 downto 0);
        -- NMT message from ocan_dispatch
        Rx_Valid       : in    std_logic;
        Rx_Cs          : in    std_logic_vector(7 downto 0);
        -- NMT error control frame to ocan_dispatch
        Tx_Valid       : out   std_logic;
        Tx_Ready       : in    std_logic;
        Tx_Data        : out   std_logic_vector(7 downto 0);
        Tx_Done        : in    std_logic;
        Tx_Aborted     : in    std_logic;
        -- Protected NODE-ID and service enables
        Node_Id        : out   std_logic_vector(6 downto 0);
        Node_IdValid   : out   std_logic;
        Ena_Sdo        : out   std_logic;
        Ena_Pdo        : out   std_logic;
        Ena_Sync       : out   std_logic;
        -- ocan_redundancy
        Red_PreopReq   : in    std_logic;
        Red_Switched   : in    std_logic;
        Red_Selecting  : in    std_logic;
        -- Status and events
        Stat_State     : out   std_logic_vector(1 downto 0);
        Reset_App      : out   std_logic;
        Reset_Comm     : out   std_logic;
        Err_Cs         : out   std_logic;
        Err_NodeId     : out   std_logic;
        -- Test input: inversion of bits of the NODE-ID copies (bits 6 to 0 IdCopy, 13 to 7 IdCopyN)
        ErrInj_BitFlip : in    std_logic_vector(13 downto 0) := (others => '0');
        ErrInj_Valid   : in    std_logic                     := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_nmt is

    -- Stages of the pin synchroniser and length of Init_s
    constant SyncStages_c : positive := 2;

    -- *** State machines ***
    type NmtFsm_t is (Init_s, ResetApp_s, ResetComm_s, WaitId_s, PreOp_s, Op_s, Stopped_s);
    type TxFsm_t is (TxIdle_s, TxReq_s, TxWait_s);

    -- *** Two process method ***
    type TwoProcess_r is record
        Nmt       : NmtFsm_t;
        InitCnt   : natural range 0 to SyncStages_c - 1;
        -- NODE-ID (NM-1)
        IdCopy    : std_logic_vector(6 downto 0);
        IdCopyN   : std_logic_vector(6 downto 0);
        IdSampled : std_logic;
        -- Events
        ErrCs     : std_logic;
        -- Heartbeat timer (NM-3)
        HbTime    : std_logic_vector(15 downto 0);
        HbCnt     : unsigned(15 downto 0);
        -- Requests and transmit handshake
        Tx        : TxFsm_t;
        TxData    : std_logic_vector(7 downto 0);
        TxBoot    : std_logic;
        BootDue   : std_logic;
        BootRetry : std_logic;
        -- Red_Selecting of the previous cycle (minimal set)
        Selecting : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal PinsAsync : std_logic_vector(13 downto 0);
    signal PinsSync  : std_logic_vector(13 downto 0);
    signal CopiesOk  : std_logic;
    signal OperSt    : std_logic;
    signal BootBlk   : std_logic;

    -- State of the Initialisation
    function isInit (s : NmtFsm_t) return boolean is
    begin
        return s = Init_s or s = ResetApp_s or s = ResetComm_s or s = WaitId_s;
    end function;

    -- Encoding of the NMT state for Stat_State (ocan_pkg)
    function stateCode (s : NmtFsm_t) return NmtState_t is
    begin

        case s is
            when PreOp_s =>
                return NmtPreOp_c;
            when Op_s =>
                return NmtOp_c;
            when Stopped_s =>
                return NmtStopped_c;
            when others =>
                return NmtInit_c;
        end case;

    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable SyncId_v  : std_logic_vector(6 downto 0);
        variable SyncCd_v  : std_logic_vector(6 downto 0);
        variable SampOk_v  : boolean;
        variable Cmd_v     : boolean;
        variable Cs_v      : natural range 0 to 255;
        variable Boot_v    : boolean;
        variable HbNow_v   : boolean;
        variable HbDue_v   : boolean;
        variable Restart_v : boolean;
        variable Retry_v   : boolean;
        variable P_v       : unsigned(15 downto 0);
        variable Cpl_v     : boolean;
        variable Free_v    : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.ErrCs     := '0';
        v.HbTime    := Cfg_HbTime;
        v.Selecting := Red_Selecting;
        Boot_v      := false;
        HbNow_v     := false;
        HbDue_v     := false;
        Retry_v     := false;
        Restart_v   := false;

        -- *** Test input: upset of the NODE-ID copies ***
        if ErrInj_Valid = '1' then
            v.IdCopy  := r.IdCopy xor ErrInj_BitFlip(6 downto 0);
            v.IdCopyN := r.IdCopyN xor ErrInj_BitFlip(13 downto 7);
        end if;

        -- *** Sample of the synchronised pins (NM-ID-01) ***
        SyncId_v := PinsSync(6 downto 0);
        SyncCd_v := PinsSync(13 downto 7);
        SampOk_v := SyncCd_v = not SyncId_v and SyncId_v /= "0000000";

        -- BootDue and BootRetry belong to the Initialisation that ended last
        if isInit(r.Nmt) then
            v.BootDue   := '0';
            v.BootRetry := '0';
        end if;

        -- *** NMT state machine (NM-SM-01 to NM-SM-05, NM-MS-01 to NM-MS-03) ***
        Cmd_v := Rx_Valid = '1' and not MinimalSet_g;
        Cs_v  := to_integer(unsigned(Rx_Cs));

        case r.Nmt is

            when Init_s =>
                -- Initialising: the synchronised pins are valid after SyncStages_c cycles
                if r.InitCnt = SyncStages_c - 1 then
                    v.Nmt := ResetApp_s;
                else
                    v.InitCnt := r.InitCnt + 1;
                end if;

            when ResetApp_s =>
                v.Nmt := ResetComm_s;

            when ResetComm_s | WaitId_s =>
                -- Sample in ResetComm_s, and at every tick while the sample is invalid (NM-ID-03)
                if r.Nmt = ResetComm_s or Tick_Ms = '1' then
                    if SampOk_v then
                        v.IdCopy    := SyncId_v;
                        v.IdCopyN   := SyncCd_v;
                        v.IdSampled := '1';
                        if MinimalSet_g then
                            -- Operational by local control with a heartbeat at once (NM-MS-02)
                            v.Nmt   := Op_s;
                            HbNow_v := true;
                        else
                            -- Pre-operational with the boot-up message (NM-SM-01, NM-HB-01)
                            v.Nmt  := PreOp_s;
                            Boot_v := true;
                        end if;
                    else
                        v.IdSampled := '0';
                        v.Nmt       := WaitId_s;
                    end if;
                end if;

            when PreOp_s | Op_s | Stopped_s =>
                if Cmd_v and Cs_v = 129 then
                    -- Reset node
                    v.Nmt := ResetApp_s;
                elsif (Cmd_v and Cs_v = 130) or CopiesOk = '0' then
                    -- Reset communication, or the NODE-ID copies disagree (NM-ID-04)
                    v.Nmt := ResetComm_s;
                else
                    if Cmd_v then

                        case Cs_v is
                            when 1 =>
                                v.Nmt := Op_s;
                            when 2 =>
                                v.Nmt := Stopped_s;
                            when 128 =>
                                v.Nmt := PreOp_s;
                            when others =>
                                null;
                        end case;

                    end if;
                    -- Request of ocan_redundancy after the command (NM-SM-05)
                    if Red_PreopReq = '1' and (v.Nmt = Op_s or v.Nmt = Stopped_s) then
                        v.Nmt := PreOp_s;
                    end if;
                    -- Minimal set: end of the bus selection with an active bus (NM-MS-03)
                    if MinimalSet_g and r.Nmt = PreOp_s and r.Selecting = '1' and Red_Selecting = '0' then
                        v.Nmt := Op_s;
                    end if;
                end if;
                -- Unknown command specifier (NM-SM-03)
                if Cmd_v and Cs_v /= 1 and Cs_v /= 2 and Cs_v /= 128 and Cs_v /= 129 and Cs_v /= 130 then
                    v.ErrCs := '1';
                end if;

            -- coverage off
            when others =>
                v.Nmt := ResetComm_s;
            -- coverage on

        end case;

        -- *** Heartbeat timer (NM-HB-03 to NM-HB-05) ***
        P_v := unsigned(Cfg_HbTime);
        if isInit(v.Nmt) or Boot_v then
            -- No heartbeat in the Initialisation; the boot-up message is the first heartbeat
            v.HbCnt := (others => '0');
        else
            Restart_v := HbNow_v or Cfg_HbTime /= r.HbTime or Red_Switched = '1';
            if Restart_v then
                v.HbCnt := (others => '0');
                if P_v /= 0 and (HbNow_v or Red_Switched = '1' or unsigned(r.HbTime) = 0) then
                    HbDue_v := true;
                end if;
            elsif Tick_Ms = '1' and P_v /= 0 then
                if r.HbCnt = P_v - 1 then
                    v.HbCnt := (others => '0');
                    HbDue_v := true;
                else
                    v.HbCnt := r.HbCnt + 1;
                end if;
            end if;
            -- Repeated boot-up message at a bus switch, also with P = 0 (NM-HB-07)
            if Red_Switched = '1' and v.BootRetry = '1' then
                Retry_v     := true;
                HbDue_v     := false;
                v.BootRetry := '0';
            end if;
        end if;

        -- *** Transmit handshake ***
        Cpl_v := false;

        case r.Tx is

            when TxIdle_s =>
                null;

            when TxReq_s =>
                if Tx_Ready = '1' then
                    if Tx_Done = '1' or Tx_Aborted = '1' then
                        Cpl_v := true;
                        v.Tx  := TxIdle_s;
                    else
                        v.Tx := TxWait_s;
                    end if;
                end if;

            when TxWait_s =>
                if Tx_Done = '1' or Tx_Aborted = '1' then
                    Cpl_v := true;
                    v.Tx  := TxIdle_s;
                end if;

            -- coverage off
            when others =>
                v.Tx := TxIdle_s;
            -- coverage on

        end case;

        -- An aborted boot-up message is repeated at the next bus switch (NM-HB-07)
        if Cpl_v and r.TxBoot = '1' and Tx_Aborted = '1' and not isInit(v.Nmt) and not MinimalSet_g then
            v.BootRetry := '1';
        end if;

        -- *** Requests: at most one pending (NM-HB-06) ***
        Free_v := r.Tx = TxIdle_s or Cpl_v;
        if Boot_v or Retry_v then
            if Free_v then
                v.Tx     := TxReq_s;
                v.TxData := x"00";
                v.TxBoot := '1';
            else
                v.BootDue := '1';
            end if;
        elsif v.BootDue = '1' and Free_v then
            v.Tx      := TxReq_s;
            v.TxData  := x"00";
            v.TxBoot  := '1';
            v.BootDue := '0';
        elsif HbDue_v and Free_v then
            -- Heartbeat with the state of the next cycle (NM-HB-02)
            v.Tx     := TxReq_s;
            v.TxBoot := '0';

            case v.Nmt is
                when Stopped_s =>
                    v.TxData := x"04";
                when Op_s =>
                    v.TxData := x"05";
                when others =>
                    v.TxData := x"7F";
            end case;

        end if;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    -- The compare on the registers clears the valid flag in the cycle of an upset (NM-ID-02)
    CopiesOk <= '1' when r.IdCopyN = not r.IdCopy else '0';
    OperSt   <= '1' when r.Nmt = PreOp_s or r.Nmt = Op_s or r.Nmt = Stopped_s else '0';
    BootBlk  <= '1' when r.BootDue = '1' or (r.TxBoot = '1' and r.Tx /= TxIdle_s) else '0';

    Node_Id      <= r.IdCopy;
    Node_IdValid <= r.IdSampled and CopiesOk;

    -- Service enables (NM-SM-04)
    Ena_Sdo  <= '1' when (r.Nmt = PreOp_s or r.Nmt = Op_s) and BootBlk = '0' else '0';
    Ena_Sync <= '1' when (r.Nmt = PreOp_s or r.Nmt = Op_s) and BootBlk = '0' else '0';
    Ena_Pdo  <= '1' when r.Nmt = Op_s and BootBlk = '0' else '0';

    Stat_State <= stateCode(r.Nmt);

    Reset_App  <= '1' when r.Nmt = ResetApp_s else '0';
    Reset_Comm <= '1' when r.Nmt = ResetComm_s else '0';
    Err_Cs     <= r.ErrCs;
    Err_NodeId <= OperSt and not CopiesOk;

    Tx_Valid <= '1' when r.Tx = TxReq_s else '0';
    Tx_Data  <= r.TxData;

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Nmt       <= Init_s;
                r.InitCnt   <= 0;
                r.IdCopy    <= (others => '0');
                r.IdCopyN   <= (others => '0');
                r.IdSampled <= '0';
                r.ErrCs     <= '0';
                r.HbTime    <= (others => '0');
                r.HbCnt     <= (others => '0');
                r.Tx        <= TxIdle_s;
                r.TxBoot    <= '0';
                r.BootDue   <= '0';
                r.BootRetry <= '0';
                r.Selecting <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- NODE-ID pins (NM-IF-01)
    -----------------------------------------------------------------------------------------------
    PinsAsync <= Pin_NodeIdCode & Pin_NodeId;

    i_sync : entity olo.olo_intf_sync
        generic map (
            Width_g      => 14,
            SyncStages_g => SyncStages_c,
            SyncTmr_g    => true
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            DataAsync => PinsAsync,
            DataSync  => PinsSync
        );

end architecture;
