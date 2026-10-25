---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Time consumer of OpenCAN: the local spacecraft elapsed time, its sample at every SYNC, the setting from the
-- Spacecraft Time PDO (basic or high-resolution protocol) and the Local Time PDO (ECSS-E-ST-50-15C clause 7).
--
-- Documentation: hdl/ocan_time/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_time is
    generic (
        ClkFrequency_g : positive range 1000000 to integer'high := 100000000;
        FineBits_g     : natural range 0 to 24                  := 24
    );
    port (
        -- Control
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        Tick_Ms       : in    std_logic;
        -- SYNC and Spacecraft Time PDO from ocan_dispatch
        Rx_SyncValid  : in    std_logic;
        Rx_SyncDlc    : in    std_logic_vector(3 downto 0);
        Rx_TimeValid  : in    std_logic;
        Rx_TimeDlc    : in    std_logic_vector(3 downto 0);
        Rx_TimeData   : in    std_logic_vector(63 downto 0);
        -- Local Time PDO to ocan_dispatch
        Tx_Valid      : out   std_logic;
        Tx_Ready      : in    std_logic;
        Tx_Dlc        : out   std_logic_vector(3 downto 0);
        Tx_Data       : out   std_logic_vector(63 downto 0);
        Tx_Done       : in    std_logic;
        Tx_Aborted    : in    std_logic;
        -- ocan_od: transmission types, Local SCET Set and Get
        Cfg_RxType    : in    std_logic_vector(7 downto 0);
        Cfg_TxType    : in    std_logic_vector(7 downto 0);
        Cfg_SetValid  : in    std_logic                     := '0';
        Cfg_SetScet   : in    std_logic_vector(55 downto 0) := (others => '0');
        Stat_Scet     : out   std_logic_vector(55 downto 0);
        -- ocan_nmt and the user logic
        Nmt_ResetComm : in    std_logic;
        Req_Valid     : in    std_logic                     := '0';
        -- Local time, status and events
        Time_Coarse   : out   std_logic_vector(31 downto 0);
        Time_Fine     : out   std_logic_vector(23 downto 0);
        Stat_TimeSet  : out   std_logic;
        Evt_Set       : out   std_logic;
        Evt_Sync      : out   std_logic;
        Err_TxBusy    : out   std_logic;
        Err_RxDrop    : out   std_logic;
        Err_TxTimeout : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_time is

    -- Bits for the values 0 to n - 1
    function bitsFor (n : positive) return positive is
        variable V_v : natural := n - 1;
        variable B_v : natural := 0;
    begin

        while V_v > 0 loop
            V_v := V_v / 2;
            B_v := B_v + 1;
        end loop;

        if B_v = 0 then
            return 1;
        end if;
        return B_v;
    end function;

    -- *** Counter constants (architecture, section 2) ***
    constant F_c     : natural  := FineBits_g;
    constant Freq_c  : positive := ClkFrequency_g;
    constant TimeW_c : positive := 32 + F_c;
    constant AccW_c  : positive := bitsFor(Freq_c);
    constant Q_c     : natural  := 2 ** F_c / Freq_c;
    constant R_c     : natural  := 2 ** F_c mod Freq_c;
    -- Advance of two cycles from Acc = 0: the start of the elapsed counter, one cycle ahead (section 3)
    constant Q2_c    : natural := (2 * 2 ** F_c) / Freq_c;
    constant R2_c    : natural := (2 * 2 ** F_c) mod Freq_c;

    -- Ticks without the completion of a taken Local Time PDO until the time-out (TM-TX-07)
    constant TxTimeout_c : positive := 256;

    subtype Time_t is unsigned(TimeW_c - 1 downto 0);
    subtype Acc_t is unsigned(AccW_c - 1 downto 0);

    -- *** Transmit handshake ***
    type TxFsm_t is (TxIdle_s, TxReq_s, TxWait_s);

    -- *** Two process method ***
    type TwoProcess_r is record
        -- Local SCET (TM-1)
        Time        : Time_t;
        Acc         : Acc_t;
        TimeSet     : std_logic;
        -- SYNC sample and elapsed counter (TM-2)
        Sample      : Time_t;
        SampleValid : std_logic;
        Elap        : Time_t;
        ElapAcc     : Acc_t;
        -- High-resolution setting in the cycle after the PDO (TM-3)
        HrLoad      : std_logic;
        Scet        : Time_t;
        -- Triggers and transmit handshake (TM-4)
        SyncCnt     : unsigned(7 downto 0);
        ReqPend     : std_logic;
        TxTypeReg   : std_logic_vector(7 downto 0);
        Tx          : TxFsm_t;
        TxTmo       : unsigned(7 downto 0);
        TxData      : std_logic_vector(63 downto 0);
        -- Events
        EvtSet      : std_logic;
        EvtSync     : std_logic;
        ErrBusy     : std_logic;
        ErrDrop     : std_logic;
        ErrTmo      : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- One cycle of the counter: f * Time + Acc grows by 2^F (TM-CT-02); the compare with >= also brings an Acc above
    -- f - 1 back below f
    type Count_r is record
        Time : Time_t;
        Acc  : Acc_t;
    end record;

    function advance (t : Time_t; a : Acc_t) return Count_r is
        variable Sum_v : unsigned(AccW_c downto 0);
        variable C_v   : Count_r;
    begin
        Sum_v := ('0' & a) + R_c;
        if Sum_v >= Freq_c then
            C_v.Acc  := resize(Sum_v - Freq_c, AccW_c);
            C_v.Time := t + (Q_c + 1);
        else
            C_v.Acc  := resize(Sum_v, AccW_c);
            C_v.Time := t + Q_c;
        end if;
        return C_v;
    end function;

    -- SCET of a frame (bytes 0 to 2 the fine time, 3 to 6 the coarse time, least significant byte first; byte 0 in
    -- bits 63 to 56), the fine time cut to its upper F bits (TM-RX-01)
    function decode (d : std_logic_vector(63 downto 0)) return Time_t is
        variable Fine_v   : std_logic_vector(23 downto 0);
        variable Coarse_v : std_logic_vector(31 downto 0);
        variable T_v      : Time_t;
    begin
        Fine_v                      := d(47 downto 40) & d(55 downto 48) & d(63 downto 56);
        Coarse_v                    := d(15 downto 8) & d(23 downto 16) & d(31 downto 24) & d(39 downto 32);
        T_v(TimeW_c - 1 downto F_c) := unsigned(Coarse_v);
        T_v(F_c - 1 downto 0)       := unsigned(Fine_v(23 downto 24 - F_c));
        return T_v;
    end function;

    -- The 56-bit value of a local time: coarse time in bits 55 to 24, fine time aligned to bit 23, below F at 0
    function scet56 (t : Time_t) return std_logic_vector is
        variable S_v : std_logic_vector(55 downto 0) := (others => '0');
    begin
        S_v(55 downto 24)       := std_logic_vector(t(TimeW_c - 1 downto F_c));
        S_v(23 downto 24 - F_c) := std_logic_vector(t(F_c - 1 downto 0));
        return S_v;
    end function;

    -- Local time from a 56-bit value (Local SCET Set)
    function fromScet56 (s : std_logic_vector(55 downto 0)) return Time_t is
        variable T_v : Time_t;
    begin
        T_v(TimeW_c - 1 downto F_c) := unsigned(s(55 downto 24));
        T_v(F_c - 1 downto 0)       := unsigned(s(23 downto 24 - F_c));
        return T_v;
    end function;

    -- Data of the Local Time PDO in the byte order of TM-TX-01, byte 7 at 0
    function frame (t : Time_t) return std_logic_vector is
        variable S_v : std_logic_vector(55 downto 0);
    begin
        S_v := scet56(t);
        return S_v(7 downto 0) & S_v(15 downto 8) & S_v(23 downto 16) & S_v(31 downto 24) & S_v(39 downto 32) &
               S_v(47 downto 40) & S_v(55 downto 48) & x"00";
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Cnt_v     : Count_r;
        variable SyncOk_v  : boolean;
        variable RxType_v  : natural range 0 to 255;
        variable TxType_v  : natural range 0 to 255;
        variable HighRes_v : boolean;
        variable Scet_v    : Time_t;
        variable CommRst_v : boolean;
        variable Due_v     : boolean;
        variable DueT_v    : Time_t;
        variable Cpl_v     : boolean;
        variable Free_v    : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.EvtSet    := '0';
        v.EvtSync   := '0';
        v.ErrBusy   := '0';
        v.ErrDrop   := '0';
        v.ErrTmo    := '0';
        v.HrLoad    := '0';
        v.TxTypeReg := Cfg_TxType;
        RxType_v    := to_integer(unsigned(Cfg_RxType));
        TxType_v    := to_integer(unsigned(Cfg_TxType));
        HighRes_v   := RxType_v <= 240;
        Due_v       := false;
        DueT_v      := r.Time;
        Cpl_v       := false;

        -- *** Local SCET counter (TM-CT-02, TM-CT-03) ***
        Cnt_v  := advance(r.Time, r.Acc);
        v.Time := Cnt_v.Time;
        v.Acc  := Cnt_v.Acc;

        -- *** SYNC sample and elapsed counter, one cycle ahead (TM-SY-01, TM-SY-02) ***
        Cnt_v     := advance(r.Elap, r.ElapAcc);
        v.Elap    := Cnt_v.Time;
        v.ElapAcc := Cnt_v.Acc;
        SyncOk_v  := Rx_SyncValid = '1' and unsigned(Rx_SyncDlc) <= 1;
        if SyncOk_v then
            v.Sample      := r.Time;
            v.SampleValid := '1';
            v.Elap        := to_unsigned(Q2_c, TimeW_c);
            v.ElapAcc     := to_unsigned(R2_c, AccW_c);
            v.EvtSync     := '1';
        end if;

        -- *** Settings in the order of their precedence (architecture, section 4) ***
        -- High-resolution load of the PDO of the previous cycle: one addition of two registers (TM-RX-04)
        if r.HrLoad = '1' then
            v.Time    := r.Scet + r.Elap;
            v.Acc     := r.ElapAcc;
            v.TimeSet := '1';
            v.EvtSet  := '1';
        end if;
        -- Spacecraft Time PDO of this cycle; a SYNC of this cycle is the one it relates to
        if Rx_TimeValid = '1' then
            Scet_v := decode(Rx_TimeData);
            if unsigned(Rx_TimeDlc) < 7 then
                v.ErrDrop := '1';                 -- TM-RX-02
            elsif RxType_v >= 241 and RxType_v <= 253 then
                v.ErrDrop := '1';                 -- TM-RX-06
            elsif RxType_v >= 254 then
                -- Basic protocol (TM-RX-03)
                v.Time    := Scet_v;
                v.Acc     := (others => '0');
                v.TimeSet := '1';
                v.EvtSet  := '1';
            elsif v.SampleValid = '0' then
                v.ErrDrop := '1';                 -- TM-RX-05
            else
                v.Scet   := Scet_v;
                v.HrLoad := '1';
            end if;
        end if;
        -- Write of Local SCET Set: wins, also over a high-resolution setting in progress (TM-CT-05)
        if Cfg_SetValid = '1' then
            v.Time    := fromScet56(Cfg_SetScet);
            v.Acc     := (others => '0');
            v.TimeSet := '1';
            v.EvtSet  := '1';
            v.HrLoad  := '0';
        end if;

        -- *** Triggers of the Local Time PDO (TM-TX-02 to TM-TX-05) ***
        -- A reset communication or a change of the type restarts the count; a SYNC of that cycle is not counted
        CommRst_v := Nmt_ResetComm = '1' or Cfg_TxType /= r.TxTypeReg;
        if CommRst_v then
            v.SyncCnt := (others => '0');
            v.ReqPend := '0';
        elsif TxType_v >= 1 and TxType_v <= 240 then
            v.ReqPend := '0';
            if SyncOk_v then
                if r.SyncCnt >= TxType_v - 1 then
                    Due_v     := true;
                    DueT_v    := r.Time;
                    v.SyncCnt := (others => '0');
                else
                    v.SyncCnt := r.SyncCnt + 1;
                end if;
            end if;
        elsif TxType_v = 0 then
            v.SyncCnt := (others => '0');
            if SyncOk_v and r.ReqPend = '1' then
                Due_v     := true;
                DueT_v    := r.Time;
                v.ReqPend := '0';
            end if;
            -- A request in the cycle of a SYNC applies to the next SYNC
            if Req_Valid = '1' then
                v.ReqPend := '1';
            end if;
        else
            v.SyncCnt := (others => '0');
            v.ReqPend := '0';
            if TxType_v >= 254 and Req_Valid = '1' then
                Due_v := true;
                if HighRes_v and v.SampleValid = '1' then
                    DueT_v := v.Sample;
                else
                    DueT_v := r.Time;
                end if;
            end if;
        end if;

        -- *** Transmit handshake (TM-IF-02, TM-TX-07) ***
        case r.Tx is

            when TxIdle_s =>
                null;

            when TxReq_s =>
                if Tx_Ready = '1' then
                    if Tx_Done = '1' or Tx_Aborted = '1' then
                        -- Reject path of ocan_dispatch
                        Cpl_v := true;
                        v.Tx  := TxIdle_s;
                    else
                        v.Tx    := TxWait_s;
                        v.TxTmo := (others => '0');
                    end if;
                end if;

            when TxWait_s =>
                if Tx_Done = '1' or Tx_Aborted = '1' then
                    Cpl_v := true;
                    v.Tx  := TxIdle_s;
                elsif Tick_Ms = '1' then
                    if r.TxTmo >= TxTimeout_c - 1 then
                        -- No completion: the wait ends, the frame is not repeated (TM-TX-07)
                        v.ErrTmo := '1';
                        Cpl_v    := true;
                        v.Tx     := TxIdle_s;
                    else
                        v.TxTmo := r.TxTmo + 1;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.Tx := TxIdle_s;
            -- coverage on

        end case;

        -- *** Request: at most one pending (TM-TX-06) ***
        Free_v := r.Tx = TxIdle_s or Cpl_v;
        if Due_v then
            if Free_v then
                v.Tx     := TxReq_s;
                v.TxData := frame(DueT_v);
            else
                v.ErrBusy := '1';
            end if;
        end if;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    Time_Coarse   <= scet56(r.Time)(55 downto 24);
    Time_Fine     <= scet56(r.Time)(23 downto 0);
    Stat_Scet     <= scet56(r.Time);
    Stat_TimeSet  <= r.TimeSet;
    Tx_Valid      <= '1' when r.Tx = TxReq_s else '0';
    Tx_Dlc        <= "0111";
    Tx_Data       <= r.TxData;
    Evt_Set       <= r.EvtSet;
    Evt_Sync      <= r.EvtSync;
    Err_TxBusy    <= r.ErrBusy;
    Err_RxDrop    <= r.ErrDrop;
    Err_TxTimeout <= r.ErrTmo;

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Time        <= (others => '0');
                r.Acc         <= (others => '0');
                r.TimeSet     <= '0';
                r.Sample      <= (others => '0');
                r.SampleValid <= '0';
                r.Elap        <= (others => '0');
                r.ElapAcc     <= (others => '0');
                r.HrLoad      <= '0';
                r.SyncCnt     <= (others => '0');
                r.ReqPend     <= '0';
                r.TxTypeReg   <= Cfg_TxType;
                r.Tx          <= TxIdle_s;
                r.TxTmo       <= (others => '0');
                r.EvtSet      <= '0';
                r.EvtSync     <= '0';
                r.ErrBusy     <= '0';
                r.ErrDrop     <= '0';
                r.ErrTmo      <= '0';
            end if;
        end if;
    end process;

end architecture;
