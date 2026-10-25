---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_pdo: the SYNC and receive PDO events, the transmission types, the NMT inputs, the tick and
-- the port of the user logic are driven cycle by cycle; a responder per transmit PDO answers the transmit handshake
-- like ocan_dispatch (delays, the reject path, completions as sent and as aborted, no completion, completions while
-- no request waits, or a handshake driven by the test); the data of the user logic change in every cycle; and a
-- reference model written from [CiA301] section 7.2.2 and the specification predicts every output in every cycle.
-- One run block per test case of the verification plan.
--
-- Documentation: hdl/ocan_pdo/docs/verification_plan.md

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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_pdo_tb is
    generic (
        runner_cfg : string;
        NumRpdo_g  : natural range 0 to 4 := 4;
        NumTpdo_g  : natural range 0 to 4 := 4
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_pdo_tb is

    subtype Byte_t is std_logic_vector(7 downto 0);
    subtype Data_t is std_logic_vector(63 downto 0);
    subtype Vec4_t is std_logic_vector(3 downto 0);
    subtype Vec256_t is std_logic_vector(255 downto 0);

    type Bytes_t is array (0 to 7) of Byte_t;

    type Data_a is array (0 to 3) of Data_t;

    type Nat_a is array (0 to 3) of natural;

    type Bool_a is array (0 to 3) of boolean;

    -- The last 64 requests taken of every PDO
    type Log_a is array (0 to 3, 0 to 63) of Data_t;

    constant Zero64_c : Data_t := (others => '0');

    function u4 (n : natural) return std_logic_vector is
        variable R_v : std_logic_vector(3 downto 0);
    begin
        R_v := std_logic_vector(to_unsigned(n, 4));
        return R_v;
    end function;

    function u8 (n : natural) return std_logic_vector is
        variable R_v : std_logic_vector(7 downto 0);
    begin
        R_v := std_logic_vector(to_unsigned(n, 8));
        return R_v;
    end function;

    -- The 64 bits of PDO n (0 to 3) in a vector of the ports
    function pdo (v : Vec256_t; n : natural) return Data_t is
    begin
        return v(64 * n + 63 downto 64 * n);
    end function;

    -- Transmission type of PDO n in Cfg_RpdoType or Cfg_TpdoType
    function typeOf (v : std_logic_vector(31 downto 0); n : natural) return natural is
    begin
        return to_integer(unsigned(v(8 * n + 7 downto 8 * n)));
    end function;

    -- Frame of 8 bytes as ocan_dispatch passes it: byte 0, the first on the bus, in bits 63 to 56
    function toFrame (b : Bytes_t) return Data_t is
        variable F_v : Data_t;
    begin

        for K in 0 to 7 loop
            F_v(63 - 8 * K downto 56 - 8 * K) := b(K);
        end loop;

        return F_v;
    end function;

    -- Sub-index k (1 to 8) of the mapping object of a PDO: data byte k - 1 of the frame (PD-RX-01, PD-TX-01)
    function subIndex (d : Data_t; k : positive) return Byte_t is
    begin
        return d(71 - 8 * k downto 64 - 8 * k);
    end function;

    -- Data that depend on every bit of a and b (xorshift)
    function mix (a : natural; b : natural) return Data_t is
        variable X_v : unsigned(63 downto 0);
    begin
        X_v := to_unsigned(a mod 2 ** 30, 32) & to_unsigned((b * 40503 + 12345) mod 2 ** 30, 32);

        for I in 1 to 3 loop
            X_v := X_v xor shift_left(X_v, 13);
            X_v := X_v xor shift_right(X_v, 7);
            X_v := X_v xor shift_left(X_v, 17);
        end loop;

        return std_logic_vector(X_v);
    end function;

    -- *** DUT signals ***
    signal Clk             : std_logic;
    signal Rst             : std_logic                     := '1';
    signal Tick_Ms         : std_logic                     := '0';
    signal RxSync_Valid    : std_logic                     := '0';
    signal RxSync_Dlc      : std_logic_vector(3 downto 0)  := x"0";
    signal RxRpdo_Valid    : std_logic                     := '0';
    signal RxRpdo_Num      : std_logic_vector(1 downto 0)  := "00";
    signal RxRpdo_Dlc      : std_logic_vector(3 downto 0)  := x"8";
    signal RxRpdo_Data     : Data_t                        := (others => '0');
    signal TxTpdo_Valid    : Vec4_t;
    signal TxTpdo_Ready    : Vec4_t;
    signal TxTpdo_Dlc      : std_logic_vector(15 downto 0);
    signal TxTpdo_Data     : Vec256_t;
    signal TxTpdo_Done     : Vec4_t;
    signal TxTpdo_Aborted  : Vec4_t;
    signal Cfg_RpdoType    : std_logic_vector(31 downto 0) := x"FEFEFEFE";
    signal Cfg_TpdoType    : std_logic_vector(31 downto 0) := x"FEFEFEFE";
    signal Nmt_EnaPdo      : std_logic                     := '1';
    signal Nmt_ResetComm   : std_logic                     := '0';
    signal Sync_Valid      : std_logic;
    signal Rpdo_Valid      : Vec4_t;
    signal Rpdo_Data       : Vec256_t;
    signal Tpdo_Req        : Vec4_t                        := (others => '0');
    signal Tpdo_Data       : Vec256_t;
    signal Stat_TpdoBusy   : Vec4_t;
    signal Stat_PdoEnabled : std_logic;
    signal Evt_TpdoSent    : Vec4_t;
    signal Evt_TpdoAborted : Vec4_t;
    signal Err_RxLength    : Vec4_t;
    signal Err_TxBusy      : Vec4_t;
    signal Err_TxTimeout   : Vec4_t;

    -- *** Cycle counter and tick generator (period TickPer cycles) ***
    signal Cyc     : natural  := 0;
    signal TickPer : positive := 16;

    -- *** Responder per transmit PDO (behaviour of ocan_dispatch at its source port) ***
    signal RespHold  : Bool_a  := (others => false); -- never take a request
    signal RespRdy   : Nat_a   := (others => 0);     -- cycles of TxTpdo_Valid before TxTpdo_Ready
    signal RespCpl   : Nat_a   := (others => 3);     -- cycles from the take to the completion, 0: no completion
    signal RespAbort : Bool_a  := (others => false); -- complete with TxTpdo_Aborted
    signal RespRej   : Bool_a  := (others => false); -- reject path: TxTpdo_Ready and TxTpdo_Aborted together
    signal Manual    : Bool_a  := (others => false); -- the handshake inputs driven by the test
    signal ManRdy    : Vec4_t  := (others => '0');
    signal ManDone   : Vec4_t  := (others => '0');
    signal ManAbt    : Vec4_t  := (others => '0');
    signal StrayDone : Vec4_t  := (others => '0');   -- completions driven by the test
    signal StrayAbt  : Vec4_t  := (others => '0');
    signal VCnt      : Nat_a   := (others => 0);
    signal Grant     : Vec4_t;
    signal RejNow    : Vec4_t;
    signal CplDone   : Vec4_t  := (others => '0');
    signal CplAbort  : Vec4_t  := (others => '0');
    signal RespBusy  : Bool_a  := (others => false);
    signal RespIdle  : boolean := true;

    -- *** Monitors ***
    signal SyncCyc    : natural  := 0; -- cycle of the last SYNC event at the input
    signal SyncData   : Vec256_t := (others => '0'); -- Tpdo_Data in the cycle of the last SYNC event
    signal ReqData    : Vec256_t := (others => '0'); -- Tpdo_Data of PDO n in the cycle of its last request
    signal SyncOutCnt : natural  := 0;
    signal RxCnt      : Nat_a    := (others => 0);
    signal RxCyc      : Nat_a    := (others => 0);
    signal TxCnt      : Nat_a    := (others => 0); -- requests taken or rejected
    signal TxLog      : Log_a;
    signal TxCyc      : Nat_a    := (others => 0); -- first cycle of the last request offered
    signal CntSent    : Nat_a    := (others => 0);
    signal CntAbort   : Nat_a    := (others => 0);
    signal CntLen     : Nat_a    := (others => 0);
    signal CntBusy    : Nat_a    := (others => 0);
    signal CntTmo     : Nat_a    := (others => 0);
    signal TmoTicks   : Nat_a    := (others => 0); -- ticks from the take to the time-out

    -- *** Reference model ***
    signal CheckEn      : boolean                       := false;
    signal ModelIdle    : boolean                       := true;
    signal ExpSync      : std_logic                     := '0';
    signal ExpRpdoValid : Vec4_t                        := (others => '0');
    signal ExpRpdoData  : Vec256_t                      := (others => '0');
    signal ExpTxValid   : Vec4_t                        := (others => '0');
    signal ExpTxData    : Vec256_t                      := (others => '0');
    signal ExpBusy      : Vec4_t                        := (others => '0');
    signal ExpEv        : std_logic_vector(19 downto 0) := (others => '0');

begin

    -- Simulated time: the longest test takes about 2 ms
    test_runner_watchdog(runner, 50 ms);

    i_th : entity work.ocan_pdo_th
        generic map (
            NumRpdo_g => NumRpdo_g,
            NumTpdo_g => NumTpdo_g
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            Tick_Ms         => Tick_Ms,
            RxSync_Valid    => RxSync_Valid,
            RxSync_Dlc      => RxSync_Dlc,
            RxRpdo_Valid    => RxRpdo_Valid,
            RxRpdo_Num      => RxRpdo_Num,
            RxRpdo_Dlc      => RxRpdo_Dlc,
            RxRpdo_Data     => RxRpdo_Data,
            TxTpdo_Valid    => TxTpdo_Valid,
            TxTpdo_Ready    => TxTpdo_Ready,
            TxTpdo_Dlc      => TxTpdo_Dlc,
            TxTpdo_Data     => TxTpdo_Data,
            TxTpdo_Done     => TxTpdo_Done,
            TxTpdo_Aborted  => TxTpdo_Aborted,
            Cfg_RpdoType    => Cfg_RpdoType,
            Cfg_TpdoType    => Cfg_TpdoType,
            Nmt_EnaPdo      => Nmt_EnaPdo,
            Nmt_ResetComm   => Nmt_ResetComm,
            Sync_Valid      => Sync_Valid,
            Rpdo_Valid      => Rpdo_Valid,
            Rpdo_Data       => Rpdo_Data,
            Tpdo_Req        => Tpdo_Req,
            Tpdo_Data       => Tpdo_Data,
            Stat_TpdoBusy   => Stat_TpdoBusy,
            Stat_PdoEnabled => Stat_PdoEnabled,
            Evt_TpdoSent    => Evt_TpdoSent,
            Evt_TpdoAborted => Evt_TpdoAborted,
            Err_RxLength    => Err_RxLength,
            Err_TxBusy      => Err_TxBusy,
            Err_TxTimeout   => Err_TxTimeout
        );

    -----------------------------------------------------------------------------------------------
    -- Cycle counter and millisecond tick
    -----------------------------------------------------------------------------------------------
    p_tick : process (Clk) is
        variable Cnt_v : natural := 0;
    begin
        if rising_edge(Clk) then
            Cyc <= Cyc + 1;
            if Cnt_v >= TickPer - 1 then
                Tick_Ms <= '1';
                Cnt_v   := 0;
            else
                Tick_Ms <= '0';
                Cnt_v   := Cnt_v + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Model of the user logic: the data of every transmit PDO change in every cycle
    -----------------------------------------------------------------------------------------------
    p_user : process (all) is
    begin

        for N in 0 to 3 loop
            Tpdo_Data(64 * N + 63 downto 64 * N) <= mix(Cyc, N + 1);
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Responders (one request at a time per PDO, no grant in the cycle of a completion, DS-TX-03)
    -----------------------------------------------------------------------------------------------
    p_resp_out : process (all) is
        variable Free_v : boolean;
        variable G_v    : std_logic;
        variable J_v    : std_logic;
    begin

        for N in 0 to 3 loop
            Free_v := TxTpdo_Valid(N) = '1' and not Manual(N) and not RespHold(N) and not RespBusy(N) and
                      VCnt(N) >= RespRdy(N) and CplDone(N) = '0' and CplAbort(N) = '0' and StrayDone(N) = '0' and
                      StrayAbt(N) = '0';
            G_v    := '0';
            J_v    := '0';
            if Free_v and not RespRej(N) then
                G_v := '1';
            end if;
            if Free_v and RespRej(N) then
                J_v := '1';
            end if;
            Grant(N)  <= G_v;
            RejNow(N) <= J_v;
            if Manual(N) then
                TxTpdo_Ready(N)   <= ManRdy(N);
                TxTpdo_Done(N)    <= ManDone(N) or StrayDone(N);
                TxTpdo_Aborted(N) <= ManAbt(N) or StrayAbt(N);
            else
                TxTpdo_Ready(N)   <= G_v or J_v;
                TxTpdo_Done(N)    <= CplDone(N) or StrayDone(N);
                TxTpdo_Aborted(N) <= CplAbort(N) or J_v or StrayAbt(N);
            end if;
        end loop;

    end process;

    p_resp : process (Clk) is
        variable Left_v : integer_vector(0 to 3) := (others => -1);
        variable Abt_v  : Bool_a                 := (others => false);
        variable Idle_v : boolean;
    begin
        if rising_edge(Clk) then
            Idle_v := true;

            for N in 0 to 3 loop
                CplDone(N)  <= '0';
                CplAbort(N) <= '0';
                if Left_v(N) > 0 then
                    Left_v(N) := Left_v(N) - 1;
                end if;
                if Left_v(N) = 0 then
                    if Abt_v(N) then
                        CplAbort(N) <= '1';
                    else
                        CplDone(N) <= '1';
                    end if;
                    Left_v(N) := -1;
                end if;
                if Grant(N) = '1' and RespCpl(N) > 0 then
                    Left_v(N) := RespCpl(N) - 1;
                    Abt_v(N)  := RespAbort(N);
                    if Left_v(N) = 0 then
                        if Abt_v(N) then
                            CplAbort(N) <= '1';
                        else
                            CplDone(N) <= '1';
                        end if;
                        Left_v(N) := -1;
                    end if;
                end if;
                if TxTpdo_Valid(N) = '1' and TxTpdo_Ready(N) = '0' then
                    VCnt(N) <= VCnt(N) + 1;
                else
                    VCnt(N) <= 0;
                end if;
                -- The reset of the dispatch with the reset of the node
                if Rst = '1' then
                    Left_v(N)   := -1;
                    CplDone(N)  <= '0';
                    CplAbort(N) <= '0';
                end if;
                RespBusy(N) <= Left_v(N) >= 0;
                if Left_v(N) >= 0 then
                    Idle_v := false;
                end if;
            end loop;

            RespIdle <= Idle_v;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------------------------
    p_mon : process (Clk) is
        variable Tk_v    : Nat_a  := (others => 0);
        variable PrevV_v : Vec4_t := (others => '0');
        variable PrevR_v : Vec4_t := (others => '0');
    begin
        if rising_edge(Clk) then
            if RxSync_Valid = '1' then
                SyncCyc  <= Cyc;
                SyncData <= Tpdo_Data;
            end if;
            if Sync_Valid = '1' then
                SyncOutCnt <= SyncOutCnt + 1;
            end if;

            for N in 0 to 3 loop
                if Tpdo_Req(N) = '1' then
                    ReqData(64 * N + 63 downto 64 * N) <= pdo(Tpdo_Data, N);
                end if;
                if Rpdo_Valid(N) = '1' then
                    RxCnt(N) <= RxCnt(N) + 1;
                    RxCyc(N) <= Cyc;
                end if;
                if TxTpdo_Valid(N) = '1' and (PrevV_v(N) = '0' or PrevR_v(N) = '1') then
                    TxCyc(N) <= Cyc;
                end if;
                if TxTpdo_Valid(N) = '1' and TxTpdo_Ready(N) = '1' then
                    TxLog(N, TxCnt(N) mod 64) <= pdo(TxTpdo_Data, N);
                    TxCnt(N)                  <= TxCnt(N) + 1;
                end if;
                if Evt_TpdoSent(N) = '1' then
                    CntSent(N) <= CntSent(N) + 1;
                end if;
                if Evt_TpdoAborted(N) = '1' then
                    CntAbort(N) <= CntAbort(N) + 1;
                end if;
                if Err_RxLength(N) = '1' then
                    CntLen(N) <= CntLen(N) + 1;
                end if;
                if Err_TxBusy(N) = '1' then
                    CntBusy(N) <= CntBusy(N) + 1;
                end if;
                if Err_TxTimeout(N) = '1' then
                    CntTmo(N)   <= CntTmo(N) + 1;
                    TmoTicks(N) <= Tk_v(N);
                end if;
                -- Ticks from the take
                if TxTpdo_Valid(N) = '1' and TxTpdo_Ready(N) = '1' and TxTpdo_Aborted(N) = '0' then
                    Tk_v(N) := 0;
                elsif Tick_Ms = '1' then
                    Tk_v(N) := Tk_v(N) + 1;
                end if;
            end loop;

            PrevV_v := TxTpdo_Valid;
            PrevR_v := TxTpdo_Ready;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Reference model of the PDO block, written from [CiA301] 7.2.2 and the specification, with the timing of the
    -- architecture (section 7): every output follows the inputs of a cycle by one cycle. The inputs of a cycle give
    -- the expectations of the next one.
    -----------------------------------------------------------------------------------------------
    p_model : process is
        type Phase_t is (PFree, POffer, PTaken);

        type Phase_a is array (0 to 3) of Phase_t;

        variable Out_v     : Data_a  := (others => (others => '0')); -- data at the port of the receive PDOs
        variable Held_v    : Bool_a  := (others => false);           -- data held for the next SYNC
        variable HeldD_v   : Data_a  := (others => (others => '0'));
        variable Cnt_v     : Nat_a   := (others => 0);               -- SYNCs counted since the start of the count
        variable Wait_v    : Bool_a  := (others => false);           -- a request of type 0 waits for the SYNC
        variable Prev_v    : Nat_a   := (others => 254);             -- type of the previous cycle
        variable Ph_v      : Phase_a := (others => PFree);
        variable Tk_v      : Nat_a   := (others => 0);
        variable Dat_v     : Data_a  := (others => (others => '0'));
        variable Sync_v    : boolean;
        variable Ena_v     : boolean;
        variable Rc_v      : boolean;
        variable Restart_v : boolean;
        variable Due_v     : boolean;
        variable T_v       : natural;
        variable N_v       : natural;
        variable SyncE_v   : std_logic;
        variable RxE_v     : Vec4_t;
        variable LenE_v    : Vec4_t;
        variable SentE_v   : Vec4_t;
        variable AbtE_v    : Vec4_t;
        variable BusyE_v   : Vec4_t;
        variable TmoE_v    : Vec4_t;
        variable Rd_v      : Vec256_t;
        variable Td_v      : Vec256_t;
        variable Tv_v      : Vec4_t;
        variable Bz_v      : Vec4_t;
        variable Idle_v    : boolean;
    begin
        wait until rising_edge(Clk);
        SyncE_v := '0';
        RxE_v   := (others => '0');
        LenE_v  := (others => '0');
        SentE_v := (others => '0');
        AbtE_v  := (others => '0');
        BusyE_v := (others => '0');
        TmoE_v  := (others => '0');
        if Rst = '1' then
            -- No request pending, no count, no data held, the data at the port 0 (PD-RS-04)
            Out_v  := (others => (others => '0'));
            Held_v := (others => false);
            Cnt_v  := (others => 0);
            Wait_v := (others => false);
            Ph_v   := (others => PFree);

            for N in 0 to 3 loop
                Prev_v(N) := typeOf(Cfg_TpdoType, N);
            end loop;

        else
            Sync_v := RxSync_Valid = '1' and to_integer(unsigned(RxSync_Dlc)) <= 1; -- PD-SY-01
            Ena_v  := Nmt_EnaPdo = '1';
            Rc_v   := Nmt_ResetComm = '1';
            if Sync_v then
                SyncE_v := '1';                                                     -- PD-SY-02
            end if;

            -- *** Receive PDOs ***
            for N in 0 to NumRpdo_g - 1 loop
                if not Ena_v or Rc_v then
                    -- Discarded outside Operational and at a reset communication (PD-RS-02, PD-RS-03)
                    Held_v(N) := false;
                elsif Sync_v and Held_v(N) then
                    -- Passed at the next SYNC (PD-RX-04)
                    Out_v(N)  := HeldD_v(N);
                    RxE_v(N)  := '1';
                    Held_v(N) := false;
                end if;
            end loop;

            N_v := to_integer(unsigned(RxRpdo_Num));
            if RxRpdo_Valid = '1' and N_v < NumRpdo_g and Ena_v and not Rc_v then
                T_v := typeOf(Cfg_RpdoType, N_v);
                if to_integer(unsigned(RxRpdo_Dlc)) < 8 then
                    LenE_v(N_v) := '1';                                             -- PD-RX-02
                elsif T_v = 254 or T_v = 255 then
                    Out_v(N_v) := RxRpdo_Data;                                      -- PD-RX-03
                    RxE_v(N_v) := '1';
                elsif T_v <= 240 then
                    -- Held for the next SYNC, also in the cycle of a SYNC (PD-RX-04, PD-RX-06)
                    HeldD_v(N_v) := RxRpdo_Data;
                    Held_v(N_v)  := true;
                end if;                                                             -- PD-RX-05
            end if;

            -- *** Transmit PDOs ***
            for N in 0 to NumTpdo_g - 1 loop
                T_v       := typeOf(Cfg_TpdoType, N);
                Restart_v := Rc_v or T_v /= Prev_v(N);
                Prev_v(N) := T_v;
                Due_v     := false;
                -- A reset communication and a change of the type clear the state of the previous cycles (PD-TX-02,
                -- PD-TX-03, PD-RS-03)
                if Restart_v then
                    Cnt_v(N)  := 0;
                    Wait_v(N) := false;
                end if;
                if T_v >= 1 and T_v <= 240 then
                    -- Every T-th SYNC that counts (PD-TX-02); a request has no effect
                    if Sync_v and not Restart_v then
                        Cnt_v(N) := Cnt_v(N) + 1;
                        if Cnt_v(N) >= T_v then
                            Due_v    := true;
                            Cnt_v(N) := 0;
                        end if;
                    end if;
                    Wait_v(N) := false;
                elsif T_v = 0 then
                    -- The first SYNC after a request (PD-TX-03)
                    if Sync_v and not Restart_v and Wait_v(N) then
                        Due_v     := true;
                        Wait_v(N) := false;
                    end if;
                    if Tpdo_Req(N) = '1' and Ena_v then
                        Wait_v(N) := true;
                    end if;
                elsif T_v >= 254 then
                    Due_v     := Tpdo_Req(N) = '1';                                 -- PD-TX-04
                    Wait_v(N) := false;
                else
                    Wait_v(N) := false;                                             -- PD-TX-05
                end if;
                if not Ena_v then
                    Wait_v(N) := false;                                             -- PD-RS-02
                end if;

                -- Handshake: pending from the request to the completion or the time-out (PD-TX-07 to PD-TX-09)
                case Ph_v(N) is

                    when POffer =>
                        if TxTpdo_Ready(N) = '1' then
                            if TxTpdo_Aborted(N) = '1' then
                                AbtE_v(N) := '1';
                                Ph_v(N)   := PFree;
                            else
                                Ph_v(N) := PTaken;
                                Tk_v(N) := 0;
                            end if;
                        end if;

                    when PTaken =>
                        if TxTpdo_Done(N) = '1' then
                            SentE_v(N) := '1';
                            Ph_v(N)    := PFree;
                        elsif TxTpdo_Aborted(N) = '1' then
                            AbtE_v(N) := '1';
                            Ph_v(N)   := PFree;
                        elsif Tick_Ms = '1' then
                            Tk_v(N) := Tk_v(N) + 1;
                            if Tk_v(N) = 256 then
                                TmoE_v(N) := '1';
                                Ph_v(N)   := PFree;
                            end if;
                        end if;

                    when PFree =>
                        null;

                end case;

                -- Requested while the PDO enable is set, when no request is pending (PD-RS-01, PD-TX-07)
                if Due_v and Ena_v then
                    if Ph_v(N) = PFree then
                        Ph_v(N)  := POffer;
                        Dat_v(N) := pdo(Tpdo_Data, N);
                    else
                        BusyE_v(N) := '1';
                    end if;
                end if;
            end loop;

        end if;

        -- *** Expectations; the outputs of absent PDOs are 0 ***
        Rd_v   := (others => '0');
        Td_v   := (others => '0');
        Tv_v   := (others => '0');
        Bz_v   := (others => '0');
        Idle_v := true;

        for N in 0 to 3 loop
            if N < NumRpdo_g then
                Rd_v(64 * N + 63 downto 64 * N) := Out_v(N);
            end if;
            if N < NumTpdo_g then
                Td_v(64 * N + 63 downto 64 * N) := Dat_v(N);
                if Ph_v(N) = POffer then
                    Tv_v(N) := '1';
                end if;
                if Ph_v(N) /= PFree then
                    Bz_v(N) := '1';
                    Idle_v  := false;
                end if;
            end if;
        end loop;

        ModelIdle    <= Idle_v;
        ExpSync      <= SyncE_v;
        ExpRpdoValid <= RxE_v;
        ExpRpdoData  <= Rd_v;
        ExpTxValid   <= Tv_v;
        ExpTxData    <= Td_v;
        ExpBusy      <= Bz_v;
        ExpEv        <= SentE_v & AbtE_v & LenE_v & BusyE_v & TmoE_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Checkers in every cycle
    -----------------------------------------------------------------------------------------------
    p_check : process is
        variable Dlc_v : std_logic_vector(3 downto 0);
        variable Mis_v : natural := 0;

        -- The first 20 mismatches of a test as alerts, the others only counted: one alert fails the test, and a
        -- mismatch that lasts does not flood the log
        procedure mismatch (msg : string) is
        begin
            Mis_v := Mis_v + 1;
            if Mis_v <= 20 then
                alert(ERROR, msg);
            elsif Mis_v = 21 then
                log(ID_SEQUENCER, "further mismatches of the reference model in this test are not reported");
            end if;
        end procedure;

        procedure cmp (dut : std_logic_vector; exp : std_logic_vector; name : string) is
        begin
            if dut /= exp then
                mismatch(name & " = " & to_hstring(dut) & ", reference model " & to_hstring(exp));
            end if;
        end procedure;

        procedure cmp (dut : std_logic; exp : std_logic; name : string) is
        begin
            if dut /= exp then
                mismatch(name & " = " & std_logic'image(dut) & ", reference model " & std_logic'image(exp));
            end if;
        end procedure;

        constant Dlc8_c : std_logic_vector(3 downto 0) := "1000";
    begin
        wait until falling_edge(Clk);
        if not CheckEn then
            Mis_v := 0;
        end if;
        if CheckEn and Rst = '0' then
            cmp(Sync_Valid, ExpSync, "Sync_Valid");
            cmp(Rpdo_Valid, ExpRpdoValid, "Rpdo_Valid");
            cmp(Rpdo_Data, ExpRpdoData, "Rpdo_Data");
            cmp(TxTpdo_Valid, ExpTxValid, "TxTpdo_Valid");

            for N in 0 to 3 loop
                if N >= NumTpdo_g or TxTpdo_Valid(N) = '1' then
                    cmp(pdo(TxTpdo_Data, N), pdo(ExpTxData, N), "TxTpdo_Data of PDO " & integer'image(N + 1));
                end if;
                if N < NumTpdo_g then
                    Dlc_v := Dlc8_c;
                else
                    Dlc_v := "0000";
                end if;
                cmp(TxTpdo_Dlc(4 * N + 3 downto 4 * N), Dlc_v, "TxTpdo_Dlc of PDO " & integer'image(N + 1));
            end loop;

            cmp(Stat_TpdoBusy, ExpBusy, "Stat_TpdoBusy");
            cmp(Stat_PdoEnabled, Nmt_EnaPdo, "Stat_PdoEnabled (Nmt_EnaPdo of the cycle)");
            cmp(Evt_TpdoSent & Evt_TpdoAborted & Err_RxLength & Err_TxBusy & Err_TxTimeout, ExpEv,
                "Evt_TpdoSent & Evt_TpdoAborted & Err_RxLength & Err_TxBusy & Err_TxTimeout");
        end if;
    end process;

    -- The transmit handshake: a request stays with its data until TxTpdo_Ready, and no second request of a PDO
    -- before the completion or the time-out of the first one (PD-TX-07)
    p_handshake : process (Clk) is
        variable Offer_v : Vec4_t  := (others => '0');
        variable Taken_v : Bool_a  := (others => false);
        variable Viol_v  : natural := 0;

        -- The first 20 violations of a test as alerts, the others only counted
        procedure violation (msg : string) is
        begin
            Viol_v := Viol_v + 1;
            if Viol_v <= 20 then
                alert(ERROR, msg);
            end if;
        end procedure;

        variable Data_v : Vec256_t := (others => '0');
    begin
        if rising_edge(Clk) then
            if not CheckEn then
                Viol_v := 0;
            end if;

            for N in 0 to 3 loop
                if Rst = '1' or not CheckEn then
                    Offer_v(N) := '0';
                    Taken_v(N) := false;
                else
                    if Offer_v(N) = '1' and (TxTpdo_Valid(N) = '0' or pdo(TxTpdo_Data, N) /= pdo(Data_v, N)) then
                        violation("request of PDO " & integer'image(N + 1) & " changed before TxTpdo_Ready");
                    end if;
                    if Taken_v(N) and TxTpdo_Valid(N) = '1' and Err_TxTimeout(N) = '0' then
                        violation("second request of PDO " & integer'image(N + 1) & " before the completion");
                    end if;
                    if TxTpdo_Done(N) = '1' or TxTpdo_Aborted(N) = '1' or Err_TxTimeout(N) = '1' then
                        Taken_v(N) := false;
                    end if;
                    if TxTpdo_Valid(N) = '1' and TxTpdo_Ready(N) = '1' and TxTpdo_Aborted(N) = '0' then
                        Taken_v(N) := true;
                    end if;
                    Offer_v(N) := TxTpdo_Valid(N) and not TxTpdo_Ready(N);
                end if;
            end loop;

            Data_v := TxTpdo_Data;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable B_v    : Nat_a;
        variable B2_v   : Nat_a;
        variable B3_v   : Nat_a;
        variable C_v    : natural;
        variable L_v    : natural;
        variable N_v    : natural;
        variable T_v    : natural;
        variable R_v    : natural;
        variable D_v    : Data_t;
        variable Ds_v   : Data_a;
        variable P_v    : Vec256_t;
        variable By_v   : Bytes_t;
        variable Tt_v   : Nat_a;
        variable Syn_v  : boolean;
        variable Sdlc_v : natural;
        variable Rp_v   : integer;
        variable Rdlc_v : natural;
        variable Req_v  : Vec4_t;
        variable Rc_v   : boolean;
        variable SwR_v  : natural;
        variable SwT_v  : natural;
        variable CovR_v : std_logic_vector(0 to 255);
        variable CovT_v : std_logic_vector(0 to 255);
        variable K_v    : natural;
        variable Mode_v : Nat_a := (others => 0);

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

        procedure setRxType (n : natural; t : natural) is
        begin
            Cfg_RpdoType(8 * n + 7 downto 8 * n) <= u8(t);
        end procedure;

        procedure setTxType (n : natural; t : natural) is
        begin
            Cfg_TpdoType(8 * n + 7 downto 8 * n) <= u8(t);
        end procedure;

        procedure setRxTypes (t : natural) is
        begin
            Cfg_RpdoType <= u8(t) & u8(t) & u8(t) & u8(t);
        end procedure;

        procedure setTxTypes (t : natural) is
        begin
            Cfg_TpdoType <= u8(t) & u8(t) & u8(t) & u8(t);
        end procedure;

        -- The events of one cycle, starting in the current cycle (called after a rising edge)
        procedure step (
            syn   : boolean := false;
            sdlc  : natural := 0;
            rp    : integer := -1;
            rdata : Data_t  := Zero64_c;
            rdlc  : natural := 8;
            req   : Vec4_t  := "0000";
            rc    : boolean := false) is
        begin
            if syn then
                RxSync_Valid <= '1';
                RxSync_Dlc   <= u4(sdlc);
            end if;
            if rp >= 0 then
                RxRpdo_Valid <= '1';
                RxRpdo_Num   <= std_logic_vector(to_unsigned(rp, 2));
                RxRpdo_Dlc   <= u4(rdlc);
                RxRpdo_Data  <= rdata;
            end if;
            Tpdo_Req <= req;
            if rc then
                Nmt_ResetComm <= '1';
            end if;
            wait until rising_edge(Clk);
            RxSync_Valid  <= '0';
            RxRpdo_Valid  <= '0';
            Tpdo_Req      <= "0000";
            Nmt_ResetComm <= '0';
        end procedure;

        procedure syncEv (dlc : natural := 0) is
        begin
            step(syn => true, sdlc => dlc);
        end procedure;

        procedure rpdo (n : natural; d : Data_t; dlc : natural := 8) is
        begin
            step(rp => n, rdata => d, rdlc => dlc);
        end procedure;

        procedure waitCnt (signal s : Nat_a; n : natural; v : natural; timeout : natural; msg : string) is
            variable N_v : natural := 0;
        begin

            while s(n) < v loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > timeout then
                    alert(ERROR, "timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- Until the PDO block and the responders are idle
        procedure settle is
            variable N_v : natural := 0;
        begin
            clocks(2);

            while not ModelIdle or not RespIdle or TxTpdo_Valid /= "0000" loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > 20000 then
                    alert(ERROR, "timeout: the PDO block does not become idle");
                    exit;
                end if;
            end loop;

            clocks(2);
        end procedure;

        -- A completion while no request waits for it, or in place of the responder
        procedure stray (n : natural; abt : boolean) is
        begin
            if abt then
                StrayAbt(n) <= '1';
            else
                StrayDone(n) <= '1';
            end if;
            wait until rising_edge(Clk);
            StrayAbt(n)  <= '0';
            StrayDone(n) <= '0';
        end procedure;

        -- k SYNCs gap cycles apart with the types tt: each transmit PDO of a type from 1 to 240 is requested one cycle
        -- after every tt-th SYNC with the data of the cycle of that SYNC; with reqs a request of the user logic before
        -- every third SYNC, without effect
        procedure cyclic (tt : Nat_a; k : natural; msg : string; reqs : boolean := true; gap : natural := 8) is
            variable B_v   : Nat_a;
            variable Due_v : boolean;
        begin

            for N in 0 to 3 loop
                B_v(N) := TxCnt(N);
            end loop;

            for I in 1 to k loop
                if reqs and I mod 3 = 0 then
                    step(req => "1111");
                    clocks(2);
                end if;
                syncEv;
                wait until falling_edge(Clk);

                for N in 0 to 3 loop
                    Due_v := tt(N) >= 1 and tt(N) <= 240 and I mod tt(N) = 0;
                    if Due_v then
                        check_value(TxTpdo_Valid(N), '1', ERROR, msg & ": PDO " & integer'image(N + 1) &
                                    " requested one cycle after SYNC " & integer'image(I));
                        check_value(pdo(TxTpdo_Data, N), pdo(SyncData, N), ERROR,
                                    msg & ": the data of the cycle of the SYNC");
                    else
                        check_value(TxTpdo_Valid(N), '0', ERROR, msg & ": PDO " & integer'image(N + 1) &
                                    " not requested at SYNC " & integer'image(I));
                    end if;
                end loop;

                clocks(gap);

                for N in 0 to 3 loop
                    if tt(N) >= 1 and tt(N) <= 240 then
                        check_value(TxCnt(N), B_v(N) + I / tt(N), ERROR, msg & ": requests of PDO " &
                                    integer'image(N + 1));
                    else
                        check_value(TxCnt(N), B_v(N), ERROR, msg & ": no request of PDO " & integer'image(N + 1));
                    end if;
                end loop;

            end loop;

        end procedure;

        -- PDO n offered (manual handshake): its completion of kind k (0 sent, 1 aborted after the take, 2 the reject
        -- path) and a new trigger in the same cycle (a SYNC or a request): requested again with the new data
        procedure cplAndTrigger (n : natural; k : natural; bySync : boolean; msg : string) is
        begin
            wait until falling_edge(Clk);
            check_value(TxTpdo_Valid(n), '1', ERROR, msg & ": offered");
            wait until rising_edge(Clk);
            if k /= 2 then
                ManRdy(n) <= '1';
                clocks(1);
                ManRdy(n) <= '0';
                clocks(3);
            end if;
            if k = 0 then
                ManDone(n) <= '1';
            elsif k = 1 then
                ManAbt(n) <= '1';
            else
                ManRdy(n) <= '1';
                ManAbt(n) <= '1';
            end if;
            if bySync then
                RxSync_Valid <= '1';
                RxSync_Dlc   <= x"0";
            else
                Tpdo_Req(n) <= '1';
            end if;
            clocks(1);
            ManRdy(n)    <= '0';
            ManDone(n)   <= '0';
            ManAbt(n)    <= '0';
            RxSync_Valid <= '0';
            Tpdo_Req(n)  <= '0';
            wait until falling_edge(Clk);
            check_value(TxTpdo_Valid(n), '1', ERROR, msg & ": requested in the cycle of the completion");
            if bySync then
                check_value(pdo(TxTpdo_Data, n), pdo(SyncData, n), ERROR, msg & ": the data of the SYNC cycle");
            else
                check_value(pdo(TxTpdo_Data, n), pdo(ReqData, n), ERROR, msg & ": the data of the request cycle");
            end if;
            check_value(Err_TxBusy(n), '0', ERROR, msg & ": no Err_TxBusy");
            if k = 0 then
                check_value(Evt_TpdoSent(n), '1', ERROR, msg & ": Evt_TpdoSent");
            else
                check_value(Evt_TpdoAborted(n), '1', ERROR, msg & ": Evt_TpdoAborted");
            end if;
            wait until rising_edge(Clk);
        end procedure;

        -- A transmission type for the random test, weighted to the classes of the specification
        impure function randType return natural is
            variable R_v : natural;
        begin
            R_v := random(1, 10);
            if R_v <= 3 then
                return random(0, 3);
            elsif R_v <= 5 then
                return random(254, 255);
            elsif R_v <= 6 then
                return random(241, 253);
            elsif R_v <= 7 then
                return random(239, 240);
            else
                return random(0, 255);
            end if;
        end function;

        constant RdyDelays_c : Nat_a                      := (0, 1, 7, 50);
        constant AllCov_c    : std_logic_vector(0 to 255) := (others => '1');
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            -- Defaults of every test
            CheckEn       <= false;
            TickPer       <= 16;
            RespHold      <= (others => false);
            RespRdy       <= (others => 0);
            RespCpl       <= (others => 3);
            RespAbort     <= (others => false);
            RespRej       <= (others => false);
            Manual        <= (others => false);
            ManRdy        <= (others => '0');
            ManDone       <= (others => '0');
            ManAbt        <= (others => '0');
            StrayDone     <= (others => '0');
            StrayAbt      <= (others => '0');
            RxSync_Valid  <= '0';
            RxRpdo_Valid  <= '0';
            Tpdo_Req      <= (others => '0');
            Nmt_EnaPdo    <= '1';
            Nmt_ResetComm <= '0';
            setRxTypes(254);
            setTxTypes(254);
            doReset;
            clocks(2);
            CheckEn       <= true;
            clocks(1);

            -- *** TC-PD-01: event-driven receive PDOs ***
            if run("test_rpdo_event") then

                for TI in 0 to 1 loop
                    setRxTypes(254 + TI);
                    clocks(2);

                    for N in 0 to 3 loop

                        -- Data byte k - 1 at sub-index k, with bytes that differ in every bit
                        for K in 0 to 7 loop
                            By_v(K) := mix(100 * TI + 10 * N + K, K)(15 downto 8);
                        end loop;

                        D_v := toFrame(By_v);
                        P_v := Rpdo_Data;
                        C_v := RxCnt(N);
                        rpdo(N, D_v);
                        wait until falling_edge(Clk);
                        check_value(Rpdo_Valid(N), '1', ERROR, "Rpdo_Valid one cycle after the event");

                        for K in 1 to 8 loop
                            check_value(subIndex(pdo(Rpdo_Data, N), K), By_v(K - 1), ERROR,
                                        "PDO " & integer'image(N + 1) & ", sub-index " & integer'image(K));
                        end loop;

                        for M in 0 to 3 loop
                            if M /= N then
                                check_value(pdo(Rpdo_Data, M), pdo(P_v, M), ERROR, "other receive PDOs unchanged");
                            end if;
                        end loop;

                        clocks(20);
                        check_value(pdo(Rpdo_Data, N), D_v, ERROR, "the data held until the next PDO");
                        check_value(RxCnt(N), C_v + 1, ERROR, "one Rpdo_Valid");
                    end loop;

                end loop;

            -- *** TC-PD-02: length of the receive PDOs ***
            elsif run("test_rpdo_length") then
                setRxType(0, 254);
                setRxType(1, 1);
                setRxType(2, 0);
                setRxType(3, 255);
                clocks(2);

                for DLC in 0 to 15 loop
                    N_v := DLC mod 4;
                    D_v := mix(2000 + DLC, N_v + 1);
                    P_v := Rpdo_Data;
                    C_v := RxCnt(N_v);
                    L_v := CntLen(N_v);
                    rpdo(N_v, D_v, DLC);
                    clocks(3);
                    if DLC < 8 then
                        check_value(CntLen(N_v), L_v + 1, ERROR, "Err_RxLength at DLC " & integer'image(DLC));
                        check_value(RxCnt(N_v), C_v, ERROR, "not processed at DLC " & integer'image(DLC));
                        check_value(pdo(Rpdo_Data, N_v), pdo(P_v, N_v), ERROR, "data unchanged");
                        syncEv;
                        clocks(3);
                        check_value(RxCnt(N_v), C_v, ERROR, "not held at DLC " & integer'image(DLC));
                    else
                        check_value(CntLen(N_v), L_v, ERROR, "no Err_RxLength at DLC " & integer'image(DLC));
                        if N_v = 1 or N_v = 2 then
                            check_value(RxCnt(N_v), C_v, ERROR, "held");
                            syncEv;
                            clocks(3);
                        end if;
                        check_value(RxCnt(N_v), C_v + 1, ERROR, "processed at DLC " & integer'image(DLC));
                        check_value(pdo(Rpdo_Data, N_v), D_v, ERROR, "8 bytes at DLC " & integer'image(DLC));
                    end if;
                end loop;

                -- A short PDO leaves the held data unchanged
                D_v := mix(2100, 2);
                rpdo(1, D_v);
                clocks(2);
                rpdo(1, mix(2101, 2), 5);
                clocks(2);
                C_v := RxCnt(1);
                syncEv;
                clocks(3);
                check_value(RxCnt(1), C_v + 1, ERROR, "held data passed after a short PDO");
                check_value(pdo(Rpdo_Data, 1), D_v, ERROR, "held data unchanged by a short PDO");
                -- The length check applies with every transmission type
                setRxType(3, 245);
                clocks(1);
                L_v := CntLen(3);
                rpdo(3, D_v, 7);
                clocks(3);
                check_value(CntLen(3), L_v + 1, ERROR, "Err_RxLength with a reserved type");

            -- *** TC-PD-03: synchronous receive PDOs ***
            elsif run("test_rpdo_sync") then
                setRxType(0, 0);
                setRxType(1, 1);
                setRxType(2, 240);
                setRxType(3, 0);
                clocks(2);

                -- Held, passed one cycle after the next SYNC with DLC 0 and 1, all in the same cycle
                for SD in 0 to 1 loop
                    B_v := RxCnt;

                    for N in 0 to 3 loop
                        Ds_v(N) := mix(3000 + 10 * SD + N, N);
                        rpdo(N, Ds_v(N));
                    end loop;

                    clocks(10);
                    check_value(RxCnt = B_v, ERROR, "no pass at the reception");
                    syncEv(SD);
                    wait until falling_edge(Clk);
                    check_value(Rpdo_Valid, "1111", ERROR, "all held PDOs passed one cycle after the SYNC");

                    for N in 0 to 3 loop
                        check_value(pdo(Rpdo_Data, N), Ds_v(N), ERROR, "held data of PDO " & integer'image(N + 1));
                    end loop;

                    clocks(3);
                end loop;

                -- Several PDOs between two SYNCs: the last one
                C_v := RxCnt(0);
                rpdo(0, mix(3100, 1));
                clocks(3);
                rpdo(0, mix(3101, 1));
                clocks(3);
                rpdo(0, mix(3102, 1));
                syncEv;
                clocks(3);
                check_value(RxCnt(0), C_v + 1, ERROR, "one pass for several PDOs");
                check_value(pdo(Rpdo_Data, 0), mix(3102, 1), ERROR, "the last value");
                -- A type changed to 254 between the reception and the SYNC: passed at the SYNC
                C_v := RxCnt(1);
                rpdo(1, mix(3200, 2));
                clocks(2);
                setRxType(1, 254);
                clocks(5);
                check_value(RxCnt(1), C_v, ERROR, "not passed at the change of the type");
                syncEv;
                clocks(3);
                check_value(RxCnt(1), C_v + 1, ERROR, "held data passed at the SYNC after a change of the type");
                check_value(pdo(Rpdo_Data, 1), mix(3200, 2), ERROR, "held data after a change of the type");
                setRxType(1, 1);
                -- A SYNC with DLC 2 to 15 passes nothing
                C_v := RxCnt(2);
                rpdo(2, mix(3300, 3));

                for SD in 2 to 15 loop
                    syncEv(SD);
                    clocks(3);
                end loop;

                check_value(RxCnt(2), C_v, ERROR, "no pass at a SYNC with DLC 2 to 15");
                syncEv(1);
                clocks(3);
                check_value(RxCnt(2), C_v + 1, ERROR, "passed at the next SYNC that counts");
                -- A SYNC without held data passes nothing
                B_v := RxCnt;
                syncEv;
                clocks(3);
                check_value(RxCnt = B_v, ERROR, "no pass without held data");
                -- A synchronous PDO in the cycle of a SYNC: held for the next SYNC (PD-RX-06)
                rpdo(3, mix(3400, 4));
                clocks(2);
                C_v := RxCnt(3);
                step(syn => true, rp => 3, rdata => mix(3401, 4));
                clocks(3);
                check_value(RxCnt(3), C_v + 1, ERROR, "the held data passed at the SYNC");
                check_value(pdo(Rpdo_Data, 3), mix(3400, 4), ERROR, "the data held before the SYNC");
                syncEv;
                clocks(3);
                check_value(RxCnt(3), C_v + 2, ERROR, "the PDO of the SYNC cycle passed at the next SYNC");
                check_value(pdo(Rpdo_Data, 3), mix(3401, 4), ERROR, "the data of the PDO of the SYNC cycle");
                -- An event-driven PDO in the cycle of a SYNC that passes held data of the same PDO: its data
                -- replace the held data (PD-RX-06)
                rpdo(3, mix(3500, 4));
                clocks(2);
                setRxType(3, 254);
                C_v := RxCnt(3);
                step(syn => true, rp => 3, rdata => mix(3501, 4));
                clocks(3);
                check_value(RxCnt(3), C_v + 1, ERROR, "one pass in the SYNC cycle");
                check_value(pdo(Rpdo_Data, 3), mix(3501, 4), ERROR, "the data of the event-driven PDO");
                syncEv;
                clocks(3);
                check_value(RxCnt(3), C_v + 1, ERROR, "nothing held after the SYNC");

            -- *** TC-PD-04: reserved transmission types of the receive PDOs ***
            elsif run("test_rpdo_reserved") then

                for T in 241 to 253 loop
                    N_v := T mod 4;
                    setRxType(N_v, T);
                    clocks(1);
                    C_v := RxCnt(N_v);
                    L_v := CntLen(N_v);
                    rpdo(N_v, mix(T, N_v));
                    clocks(3);
                    syncEv;
                    clocks(3);
                    check_value(RxCnt(N_v), C_v, ERROR, "not processed with type " & integer'image(T));
                    check_value(CntLen(N_v), L_v, ERROR, "no event with type " & integer'image(T));
                    setRxType(N_v, 254);
                end loop;

            -- *** TC-PD-05: SYNC ***
            elsif run("test_sync") then

                for EN in 0 to 1 loop
                    if EN = 1 then
                        Nmt_EnaPdo <= '0';
                    end if;

                    for SD in 0 to 15 loop
                        C_v := SyncOutCnt;
                        syncEv(SD);
                        wait until falling_edge(Clk);
                        check_value((Sync_Valid = '1') = (SD <= 1), ERROR,
                                    "Sync_Valid one cycle after a SYNC with DLC " & integer'image(SD));
                        clocks(3);
                        check_value(SyncOutCnt, C_v + boolean'pos(SD <= 1), ERROR, "one Sync_Valid per SYNC");
                    end loop;

                end loop;

                -- Also in the cycle of a reset communication
                Nmt_EnaPdo <= '1';
                clocks(2);
                step(syn => true, rc => true);
                wait until falling_edge(Clk);
                check_value(Sync_Valid, '1', ERROR, "Sync_Valid at a SYNC in the cycle of a reset communication");

            -- *** TC-PD-06: cyclic transmit PDOs ***
            elsif run("test_tpdo_cyclic") then
                Tt_v := (1,
                         2,
                         3,
                         17);

                for N in 0 to 3 loop
                    setTxType(N, Tt_v(N));
                end loop;

                doReset;
                clocks(2);
                cyclic(Tt_v, 40, "from the hardware reset");

                -- From a reset communication, with counts in progress
                for I in 1 to 5 loop
                    syncEv;
                    clocks(8);
                end loop;

                step(rc => true);
                clocks(2);
                cyclic(Tt_v, 40, "from a reset communication");

                -- A SYNC in the cycle of a reset communication is not counted
                for I in 1 to 4 loop
                    syncEv;
                    clocks(8);
                end loop;

                step(syn => true, rc => true);
                clocks(8);
                cyclic(Tt_v, 40, "SYNC in the cycle of a reset communication");

                -- From a change of the type
                for I in 1 to 5 loop
                    syncEv;
                    clocks(8);
                end loop;

                Tt_v := (2,
                         3,
                         17,
                         1);

                for N in 0 to 3 loop
                    setTxType(N, Tt_v(N));
                end loop;

                clocks(2);
                cyclic(Tt_v, 40, "from a change of the type");

                -- A SYNC in the cycle of a change of the type is not counted
                for I in 1 to 2 loop
                    syncEv;
                    clocks(8);
                end loop;

                Tt_v := (3,
                         1,
                         2,
                         17);

                for N in 0 to 3 loop
                    setTxType(N, Tt_v(N));
                end loop;

                syncEv;
                clocks(8);
                cyclic(Tt_v, 40, "SYNC in the cycle of a change of the type");

                -- Type 240
                Tt_v := (240,
                         254,
                         254,
                         254);
                setTxType(0, 240);
                setTxType(1, 254);
                setTxType(2, 254);
                setTxType(3, 254);
                clocks(2);
                cyclic(Tt_v, 480, "type 240", reqs => false, gap => 5);

                -- The request is held while TxTpdo_Ready is late: no window (PD-SY-03)
                setTxType(1, 1);
                RespRdy(1) <= 400;
                clocks(2);
                C_v        := TxCnt(1);
                syncEv;
                clocks(300);
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid(1), '1', ERROR, "request held while TxTpdo_Ready is late");
                waitCnt(TxCnt, 1, C_v + 1, 1000, "late take");
                check_value(TxLog(1, C_v mod 64), pdo(SyncData, 1), ERROR, "the data of the SYNC cycle after the wait");

            -- *** TC-PD-07: acyclic transmit PDOs (type 0) ***
            elsif run("test_tpdo_acyclic") then
                setTxTypes(0);
                clocks(2);
                -- A request, then a SYNC: one PDO with the data of the cycle of the SYNC
                B_v := TxCnt;
                step(req => "1111");
                clocks(5);
                check_value(TxCnt = B_v, ERROR, "no PDO before the SYNC");
                syncEv;
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid, "1111", ERROR, "requested one cycle after the SYNC");

                for N in 0 to 3 loop
                    check_value(pdo(TxTpdo_Data, N), pdo(SyncData, N), ERROR, "the data of the cycle of the SYNC");
                end loop;

                settle;

                -- Several requests: one PDO
                for N in 0 to 3 loop
                    B_v(N) := TxCnt(N) + 1;
                end loop;

                for I in 1 to 3 loop
                    step(req => "1111");
                    clocks(2);
                end loop;

                syncEv;
                settle;
                check_value(TxCnt = B_v, ERROR, "one PDO for several requests");

                -- No request: no PDO
                for I in 1 to 5 loop
                    syncEv;
                    clocks(8);
                end loop;

                check_value(TxCnt = B_v, ERROR, "no PDO without a request");
                -- A request in the cycle of a SYNC applies to the next SYNC
                step(syn => true, req => "1111");
                clocks(8);
                check_value(TxCnt = B_v, ERROR, "a request in the SYNC cycle not served at that SYNC");
                syncEv;
                settle;

                for N in 0 to 3 loop
                    B_v(N) := B_v(N) + 1;
                end loop;

                check_value(TxCnt = B_v, ERROR, "a request in the SYNC cycle served at the next SYNC");
                -- A change of the type while a request waits: discarded
                step(req => "1111");
                clocks(2);
                setTxTypes(255);
                clocks(1);
                setTxTypes(0);
                clocks(2);
                syncEv;
                clocks(8);
                check_value(TxCnt = B_v, ERROR, "a waiting request discarded at a change of the type");
                -- A request in the cycle of a change to type 0: the PDO at the next SYNC (PD-TX-03)
                setTxTypes(254);
                clocks(2);
                setTxTypes(0);
                step(req => "1111");
                clocks(5);
                check_value(TxCnt = B_v, ERROR, "type 0 now: no PDO at the request");
                syncEv;
                settle;

                for N in 0 to 3 loop
                    B_v(N) := B_v(N) + 1;
                end loop;

                check_value(TxCnt = B_v, ERROR, "a request in the cycle of a change to type 0: PDO at the next SYNC");
                -- A request in the cycle of a change to type 254 and to 255: requested at once (PD-TX-03, PD-TX-04)
                setTxType(0, 254);
                setTxType(1, 255);
                setTxType(2, 254);
                setTxType(3, 255);
                step(req => "1111");
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid, "1111", ERROR, "a request in the cycle of a change to 254, 255: requested");

                for N in 0 to 3 loop
                    check_value(pdo(TxTpdo_Data, N), pdo(ReqData, N), ERROR, "the data of the request cycle");
                end loop;

                settle;
                -- From types 1 and 2 to 255 and 254 with a request in the cycle of the change
                setTxType(0, 1);
                setTxType(1, 2);
                clocks(2);
                setTxType(0, 255);
                setTxType(1, 254);
                step(req => "0011");
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid(1 downto 0), "11", ERROR, "a request in the cycle of a change from 1, 2");
                settle;

            -- *** TC-PD-08: event-driven and reserved types of the transmit PDOs ***
            elsif run("test_tpdo_event") then

                for TI in 0 to 1 loop
                    setTxTypes(254 + TI);
                    clocks(2);

                    for I in 0 to 4 loop
                        if I < 4 then
                            Req_v    := "0000";
                            Req_v(I) := '1';
                        else
                            Req_v := "1111";
                        end if;
                        B_v := TxCnt;
                        step(req => Req_v);
                        wait until falling_edge(Clk);
                        check_value(TxTpdo_Valid, Req_v, ERROR, "requested one cycle after the request");

                        for N in 0 to 3 loop
                            if Req_v(N) = '1' then
                                check_value(pdo(TxTpdo_Data, N), pdo(ReqData, N), ERROR,
                                            "the data of the cycle of the request");
                            end if;
                        end loop;

                        settle;
                    end loop;

                    -- SYNCs without effect
                    B_v := TxCnt;

                    for I in 1 to 3 loop
                        syncEv(I mod 2);
                        clocks(8);
                    end loop;

                    check_value(TxCnt = B_v, ERROR, "no PDO at a SYNC with type " & integer'image(254 + TI));
                end loop;

                -- Types 241 to 253: no PDO at requests and SYNCs
                for T in 241 to 253 loop
                    setTxTypes(T);
                    clocks(1);
                    B_v := TxCnt;
                    step(req => "1111");
                    clocks(3);
                    syncEv;
                    clocks(3);
                    step(req => "1111");
                    syncEv;
                    clocks(5);
                    check_value(TxCnt = B_v, ERROR, "no PDO with type " & integer'image(T));
                end loop;

                -- Type 241 is not a cyclic type, also over 241 SYNCs
                Tt_v := (241,
                         241,
                         241,
                         241);
                setTxTypes(241);
                clocks(2);
                cyclic(Tt_v, 242, "type 241", reqs => false, gap => 4);

                -- No PDO without a trigger over 2000 ticks: no event timer (PD-TX-06)
                setTxTypes(254);
                TickPer <= 4;
                clocks(2);
                B_v     := TxCnt;
                clocks(8000);
                check_value(TxCnt = B_v, ERROR, "no PDO without a trigger");

            -- *** TC-PD-09: a PDO due while its request is pending ***
            elsif run("test_tpdo_busy") then
                setTxType(0, 254);
                setTxType(1, 1);
                setTxType(2, 0);
                setTxType(3, 255);
                RespHold <= (others => true);
                clocks(2);
                step(req => "1111");
                clocks(2);
                syncEv;
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid, "1111", ERROR, "all four offered");
                P_v      := TxTpdo_Data;
                wait until rising_edge(Clk);
                -- While offered: not requested, Err_TxBusy
                B_v := CntBusy;
                step(req => "1111");
                clocks(2);
                syncEv;
                clocks(3);

                for N in 0 to 3 loop
                    check_value(CntBusy(N), B_v(N) + 1, ERROR, "Err_TxBusy while offered, PDO " & integer'image(N + 1));
                end loop;

                -- TxTpdo_Ready held off for 1000 cycles: the request and its data unchanged
                clocks(1000);
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid, "1111", ERROR, "still offered after 1000 cycles");
                check_value(TxTpdo_Data, P_v, ERROR, "the data unchanged while offered");
                wait until rising_edge(Clk);
                -- While taken: not requested, Err_TxBusy
                RespCpl  <= (others => 200);
                RespHold <= (others => false);
                clocks(5);
                check_value(TxTpdo_Valid, "0000", ERROR, "taken");
                B_v      := CntBusy;
                B2_v     := TxCnt;
                step(req => "1111");
                clocks(2);
                syncEv;
                clocks(3);

                for N in 0 to 3 loop
                    check_value(CntBusy(N), B_v(N) + 1, ERROR, "Err_TxBusy while taken, PDO " & integer'image(N + 1));
                end loop;

                settle;
                check_value(TxCnt = B2_v, ERROR, "no request from a PDO due while pending");
                -- A request and a due SYNC in the cycle of the completion: requested with the new data
                Manual <= (others => true);
                setTxTypes(254);
                clocks(2);

                for K in 0 to 2 loop
                    step(req => "0001");
                    cplAndTrigger(0, K, false, "request, completion kind " & integer'image(K));
                    ManRdy(0)  <= '1';
                    clocks(1);
                    ManRdy(0)  <= '0';
                    ManDone(0) <= '1';
                    clocks(1);
                    ManDone(0) <= '0';
                    clocks(2);
                end loop;

                setTxType(1, 1);
                clocks(2);

                for K in 0 to 2 loop
                    syncEv;
                    cplAndTrigger(1, K, true, "due SYNC, completion kind " & integer'image(K));
                    ManRdy(1)  <= '1';
                    clocks(1);
                    ManRdy(1)  <= '0';
                    ManDone(1) <= '1';
                    clocks(1);
                    ManDone(1) <= '0';
                    clocks(2);
                end loop;

            -- *** TC-PD-10: transmit handshake ***
            elsif run("test_tpdo_handshake") then

                -- Delays of TxTpdo_Ready; completion as sent, as aborted after the take, and the reject path
                for RI in 0 to 3 loop

                    for K in 0 to 2 loop
                        RespRdy   <= (others => RdyDelays_c(RI));
                        RespAbort <= (others => K = 1);
                        RespRej   <= (others => K = 2);
                        RespCpl   <= (others => 5);
                        clocks(1);
                        B_v       := CntSent;
                        B2_v      := CntAbort;
                        B3_v      := TxCnt;
                        step(req => "1111");
                        settle;
                        clocks(50);

                        for N in 0 to 3 loop
                            check_value(TxCnt(N), B3_v(N) + 1, ERROR, "one request, no repetition");
                            if K = 0 then
                                check_value(CntSent(N), B_v(N) + 1, ERROR, "Evt_TpdoSent");
                                check_value(CntAbort(N), B2_v(N), ERROR, "no Evt_TpdoAborted");
                            else
                                check_value(CntSent(N), B_v(N), ERROR, "no Evt_TpdoSent");
                                check_value(CntAbort(N), B2_v(N) + 1, ERROR, "Evt_TpdoAborted");
                            end if;
                        end loop;

                    end loop;

                end loop;

                RespRdy   <= (others => 0);
                RespAbort <= (others => false);
                RespRej   <= (others => false);
                RespCpl   <= (others => 3);
                -- No completion: Err_TxTimeout 256 ticks after the take, no repetition; the other PDOs served
                TickPer    <= 4;
                RespCpl(0) <= 0;
                clocks(2);
                C_v        := TxCnt(0);
                L_v        := CntTmo(0);
                B_v        := CntSent;
                step(req => "0001");

                for I in 1 to 20 loop
                    step(req => "1110");
                    clocks(40);
                end loop;

                waitCnt(CntTmo, 0, L_v + 1, 5000, "Err_TxTimeout");
                check_value(TmoTicks(0), 256, ERROR, "Err_TxTimeout 256 ticks after the take");

                for N in 1 to 3 loop
                    check_value(CntSent(N), B_v(N) + 20, ERROR, "the other PDOs served during the wait");
                end loop;

                clocks(200);
                check_value(TxCnt(0), C_v + 1, ERROR, "no repetition after the time-out");
                RespCpl(0) <= 3;
                clocks(1);
                C_v        := CntSent(0);
                step(req => "0001");
                settle;
                check_value(CntSent(0), C_v + 1, ERROR, "the next request served after the time-out");
                -- Completions while no request waits: idle
                B_v  := CntSent;
                B2_v := CntAbort;

                for N in 0 to 3 loop
                    stray(N, false);
                    clocks(2);
                    stray(N, true);
                    clocks(2);
                end loop;

                clocks(3);
                check_value(CntSent = B_v and CntAbort = B2_v, ERROR, "completions ignored in idle");
                -- Offered without TxTpdo_Ready
                RespHold(0) <= true;
                clocks(1);
                step(req => "0001");
                clocks(3);
                stray(0, false);
                clocks(2);
                stray(0, true);
                clocks(3);
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid(0), '1', ERROR, "still offered after completions without TxTpdo_Ready");
                wait until rising_edge(Clk);
                check_value(CntSent(0) = B_v(0) and CntAbort(0) = B2_v(0), ERROR, "completions ignored while offered");
                RespHold(0) <= false;
                settle;
                check_value(CntSent(0), B_v(0) + 1, ERROR, "sent after the hold");
                -- Late after the time-out
                RespCpl(0) <= 0;
                clocks(1);
                L_v        := CntTmo(0);
                step(req => "0001");
                waitCnt(CntTmo, 0, L_v + 1, 5000, "Err_TxTimeout before the late completion");
                check_value(TmoTicks(0), 256, ERROR, "the second Err_TxTimeout 256 ticks after its take");
                B_v        := CntSent;
                B2_v       := CntAbort;
                stray(0, false);
                clocks(2);
                stray(0, true);
                clocks(3);
                check_value(CntSent(0) = B_v(0) and CntAbort(0) = B2_v(0), ERROR, "late completions ignored");
                RespCpl(0) <= 3;

            -- *** TC-PD-11: PDO enable ***
            elsif run("test_nmt") then
                -- Receive PDOs not processed while the PDO enable is cleared
                setRxType(0, 254);
                setRxType(1, 1);
                setRxType(2, 255);
                setRxType(3, 0);
                clocks(1);
                Nmt_EnaPdo <= '0';
                clocks(2);
                B_v        := RxCnt;
                L_v        := CntLen(0);

                for N in 0 to 3 loop
                    rpdo(N, mix(5000, N));
                    rpdo(N, mix(5001, N), 3);
                end loop;

                clocks(3);
                Nmt_EnaPdo <= '1';
                clocks(2);
                syncEv;
                clocks(3);
                check_value(RxCnt = B_v, ERROR, "receive PDOs not processed while the PDO enable is cleared");
                check_value(CntLen(0), L_v, ERROR, "no Err_RxLength while the PDO enable is cleared");
                -- Due PDOs not requested, without an event; requests without effect
                setTxType(0, 254);
                setTxType(1, 1);
                setTxType(2, 0);
                setTxType(3, 255);
                clocks(2);
                Nmt_EnaPdo <= '0';
                clocks(1);
                B_v        := TxCnt;
                B2_v       := CntBusy;
                step(req => "1111");
                clocks(2);
                syncEv;
                clocks(5);
                check_value(TxCnt = B_v and CntBusy = B2_v, ERROR, "no PDO and no event while the PDO enable is cleared");
                -- The SYNC counts continue: type 3 counted from the change of the type
                Nmt_EnaPdo <= '1';
                setTxType(1, 3);
                clocks(2);
                C_v        := TxCnt(1);

                for I in 1 to 6 loop
                    if I = 3 then
                        Nmt_EnaPdo <= '0';
                    elsif I = 5 then
                        Nmt_EnaPdo <= '1';
                    end if;
                    clocks(1);
                    syncEv;
                    clocks(8);
                    if I < 6 then
                        check_value(TxCnt(1), C_v, ERROR, "no PDO at SYNC " & integer'image(I));
                    end if;
                end loop;

                check_value(TxCnt(1), C_v + 1, ERROR, "the count continued while the PDO enable was cleared");
                -- The exit from Operational with held data of every PDO: not passed at the next SYNC
                setRxTypes(1);
                clocks(2);
                B_v := RxCnt;

                for N in 0 to 3 loop
                    rpdo(N, mix(5100, N));
                end loop;

                Nmt_EnaPdo <= '0';
                clocks(3);
                Nmt_EnaPdo <= '1';
                clocks(2);
                syncEv;
                clocks(3);
                check_value(RxCnt = B_v, ERROR, "held data discarded at the exit from Operational");

                -- Also when the SYNC comes in the cycle of the exit
                for N in 0 to 3 loop
                    rpdo(N, mix(5200, N));
                end loop;

                Nmt_EnaPdo <= '0';
                syncEv;
                clocks(2);
                Nmt_EnaPdo <= '1';
                clocks(2);
                syncEv;
                clocks(3);
                check_value(RxCnt = B_v, ERROR, "held data discarded at a SYNC in the cycle of the exit");
                -- A request of type 0 waiting: no PDO at the next SYNC, none after the return to Operational
                setTxTypes(0);
                clocks(2);
                B_v        := TxCnt;
                step(req => "1111");
                clocks(2);
                Nmt_EnaPdo <= '0';
                clocks(3);
                Nmt_EnaPdo <= '1';
                clocks(2);
                syncEv;
                clocks(5);
                step(req => "1111");
                Nmt_EnaPdo <= '0';
                clocks(1);
                syncEv;
                clocks(2);
                Nmt_EnaPdo <= '1';
                clocks(2);
                syncEv;
                clocks(5);
                check_value(TxCnt = B_v, ERROR, "a waiting request discarded at the exit from Operational");
                -- A request offered and a request taken at the exit complete as the responder reports them
                setTxTypes(254);
                RespHold(0) <= true;
                RespCpl(1)  <= 100;
                clocks(2);
                B_v         := CntSent;
                B2_v        := CntAbort;
                step(req => "0011");
                clocks(5);
                Nmt_EnaPdo  <= '0';
                clocks(5);
                RespRej(0)  <= true;
                RespHold(0) <= false;
                settle;
                check_value(CntAbort(0), B2_v(0) + 1, ERROR, "the offered request rejected");
                check_value(CntSent(1), B_v(1) + 1, ERROR, "the taken request completed as sent");
                Nmt_EnaPdo  <= '1';
                RespRej(0)  <= false;
                clocks(2);

            -- *** TC-PD-12: reset communication ***
            elsif run("test_reset_comm") then
                setTxType(0, 3);
                setTxType(1, 0);
                setTxType(2, 2);
                setTxType(3, 254);
                setRxTypes(1);
                clocks(2);
                -- Counts in progress, held data and a waiting request
                syncEv;
                clocks(8);
                syncEv;
                clocks(8);

                for N in 0 to 3 loop
                    rpdo(N, mix(6000, N));
                end loop;

                step(req => "0010");
                clocks(2);
                B_v  := TxCnt;
                B2_v := RxCnt;
                P_v  := Rpdo_Data;
                step(rc => true);
                clocks(2);
                check_value(Rpdo_Data, P_v, ERROR, "the data at the port kept");
                -- The counts restart: type 2 at the second and type 3 at the third SYNC from the event
                syncEv;
                clocks(8);
                check_value(TxCnt = B_v and RxCnt = B2_v, ERROR, "nothing at the first SYNC after the event");
                syncEv;
                clocks(8);
                check_value(TxCnt(2), B_v(2) + 1, ERROR, "type 2 at the second SYNC after the event");
                check_value(TxCnt(0), B_v(0), ERROR, "type 3 not at the second SYNC after the event");
                syncEv;
                clocks(8);
                check_value(TxCnt(0), B_v(0) + 1, ERROR, "type 3 at the third SYNC after the event");
                check_value(TxCnt(1), B_v(1), ERROR, "the waiting request discarded");
                check_value(RxCnt = B2_v, ERROR, "the held data discarded");
                -- A receive PDO and a SYNC in the cycle of the event: not processed, not counted
                setRxType(0, 254);
                setRxType(1, 0);
                clocks(2);
                B_v  := TxCnt;
                B2_v := RxCnt;
                rpdo(1, mix(6100, 1));
                clocks(2);
                step(syn => true, rp => 0, rdata => mix(6101, 0), rc => true);
                clocks(3);
                check_value(RxCnt = B2_v, ERROR, "no receive PDO processed in the cycle of the event");

                for I in 1 to 2 loop
                    syncEv;
                    clocks(8);
                end loop;

                check_value(TxCnt(0), B_v(0), ERROR, "the SYNC of the cycle of the event not counted");
                check_value(TxCnt(2), B_v(2) + 1, ERROR, "type 2 at the second SYNC after the event");
                syncEv;
                clocks(8);
                check_value(TxCnt(0), B_v(0) + 1, ERROR, "type 3 at the third SYNC after the event");
                check_value(RxCnt = B2_v, ERROR, "the PDO held before the event discarded");
                -- An offered and a taken request complete as the responder reports them
                setTxTypes(254);
                RespHold(0) <= true;
                RespCpl(1)  <= 100;
                clocks(2);
                B_v         := CntSent;
                B2_v        := CntAbort;
                step(req => "0011");
                clocks(5);
                step(rc => true);
                clocks(5);
                RespHold(0) <= false;
                settle;
                check_value(CntSent(0), B_v(0) + 1, ERROR, "the offered request served after the event");
                check_value(CntSent(1), B_v(1) + 1, ERROR, "the taken request completed after the event");
                -- With the PDO enable set in the cycle of the event: a request of type 0 waits for the next SYNC,
                -- a request of type 254 is requested (PD-TX-03)
                setTxType(1, 0);
                setTxType(3, 254);
                clocks(2);
                B_v := TxCnt;
                step(req => "1010", rc => true);
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid, "1000", ERROR, "type 254 requested in the cycle of the event");
                settle;
                check_value(TxCnt(1), B_v(1), ERROR, "type 0 not requested before the SYNC");
                syncEv;
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid(1), '1', ERROR, "the request of the cycle of the event served at the SYNC");
                settle;

            -- *** TC-PD-13: hardware reset ***
            elsif run("test_reset") then
                setTxType(0, 3);
                setTxType(1, 0);
                setTxType(2, 254);
                setTxType(3, 254);
                setRxTypes(1);
                RespHold(2) <= true;
                RespCpl(3)  <= 500;
                clocks(2);
                syncEv;
                clocks(8);
                syncEv;
                clocks(8);

                for N in 0 to 3 loop
                    rpdo(N, mix(7000, N));
                end loop;

                setRxTypes(254);
                rpdo(0, mix(7001, 0));
                setRxTypes(1);
                rpdo(1, mix(7002, 1));
                step(req => "1110");
                clocks(5);
                wait until falling_edge(Clk);
                check_value(Stat_TpdoBusy(3 downto 2), "11", ERROR, "pending before the reset");
                wait until rising_edge(Clk);
                doReset;
                RespHold(2) <= false;
                clocks(1);
                wait until falling_edge(Clk);
                check_value(TxTpdo_Valid, "0000", ERROR, "no request after the reset");
                check_value(Stat_TpdoBusy, "0000", ERROR, "nothing pending after the reset");
                check_value(Rpdo_Data, std_logic_vector(to_unsigned(0, 256)), ERROR, "the data at the port 0");
                wait until rising_edge(Clk);
                B_v         := TxCnt;
                B2_v        := RxCnt;
                syncEv;
                clocks(8);
                syncEv;
                clocks(8);
                check_value(TxCnt(0), B_v(0), ERROR, "type 3 counted from the reset");
                syncEv;
                clocks(8);
                check_value(TxCnt(0), B_v(0) + 1, ERROR, "type 3 at the third SYNC after the reset");
                check_value(TxCnt(1), B_v(1), ERROR, "no waiting request after the reset");
                check_value(RxCnt = B2_v, ERROR, "no held data after the reset");

            -- *** TC-PD-14: events back to back ***
            elsif run("test_back_to_back") then
                setTxTypes(1);
                setRxTypes(0);
                clocks(2);

                -- Receive PDOs in consecutive cycles, then the SYNC in the next cycle
                for N in 0 to 3 loop
                    rpdo(N, mix(8000, N));
                end loop;

                syncEv;
                wait until falling_edge(Clk);
                check_value(Rpdo_Valid, "1111", ERROR, "all held PDOs passed in the same cycle");
                check_value(TxTpdo_Valid, "1111", ERROR, "all four transmit PDOs requested in the same cycle");
                wait until rising_edge(Clk);
                settle;
                -- SYNC and receive PDOs 46 bit times apart at 1 Mbit/s (46 us, 1840 cycles)
                B_v  := TxCnt;
                B2_v := RxCnt;

                for I in 0 to 7 loop
                    if I mod 2 = 0 then
                        syncEv;
                    else
                        rpdo(I mod 4, mix(8100 + I, I));
                    end if;
                    clocks(1839);
                end loop;

                syncEv;
                settle;

                for N in 0 to 3 loop
                    check_value(TxCnt(N), B_v(N) + 5, ERROR, "a PDO at every SYNC 46 bit times apart");
                end loop;

                -- SYNCs and receive PDOs in consecutive cycles (the model checks every output)
                setRxTypes(254);

                for I in 0 to 15 loop
                    step(syn => I mod 2 = 0, rp => I mod 4, rdata => mix(8200 + I, I));
                end loop;

                settle;

            -- *** TC-PD-15: random events ***
            elsif run("test_random") then
                TickPer <= 2;
                SwR_v   := 0;
                SwT_v   := 0;
                CovR_v  := (others => '0');
                CovT_v  := (others => '0');

                for I in 1 to 20000 loop
                    -- The responders
                    -- The responders, each through the completion classes in turn: sent, aborted after the take, the
                    -- reject path, no completion, random
                    if random(1, 300) = 1 then
                        N_v          := random(0, 3);
                        K_v          := Mode_v(N_v) mod 5;
                        Mode_v(N_v)  := Mode_v(N_v) + 1;
                        RespRdy(N_v) <= random(0, 30);
                        if K_v = 3 or (K_v = 4 and random(1, 4) = 1) then
                            RespCpl(N_v) <= 0;
                        else
                            RespCpl(N_v) <= random(1, 40);
                        end if;
                        RespAbort(N_v) <= K_v = 1 or (K_v = 4 and random(1, 4) = 1);
                        RespRej(N_v)   <= K_v = 2 or (K_v = 4 and random(1, 6) = 1);
                        RespHold(N_v)  <= random(1, 12) = 1;
                    end if;
                    -- The types: every value of 0 to 255 in turn, and weighted values (also in the cycle of an
                    -- event)
                    if random(1, 30) = 1 then
                        N_v := random(0, 3);
                        if random(0, 1) = 0 then
                            T_v   := (SwT_v * 97 + 13) mod 256;
                            SwT_v := SwT_v + 1;
                        else
                            T_v := randType;
                        end if;
                        setTxType(N_v, T_v);
                        CovT_v(T_v) := '1';
                    end if;
                    if random(1, 30) = 1 then
                        N_v := random(0, 3);
                        if random(0, 1) = 0 then
                            T_v   := (SwR_v * 89 + 7) mod 256;
                            SwR_v := SwR_v + 1;
                        else
                            T_v := randType;
                        end if;
                        setRxType(N_v, T_v);
                        CovR_v(T_v) := '1';
                    end if;
                    -- The PDO enable
                    if random(1, 400) = 1 then
                        Nmt_EnaPdo <= not Nmt_EnaPdo;
                    end if;
                    -- Completions while no request waits, or in place of the responder
                    if random(1, 600) = 1 then
                        N_v := random(0, 3);
                        if random(0, 1) = 0 then
                            StrayDone(N_v) <= '1';
                        else
                            StrayAbt(N_v) <= '1';
                        end if;
                    end if;
                    -- The events of the cycle
                    Syn_v := random(1, 10) = 1;
                    if random(1, 4) = 1 then
                        Sdlc_v := random(0, 15);
                    else
                        Sdlc_v := random(0, 1);
                    end if;
                    Rp_v := -1;
                    if random(1, 6) = 1 then
                        Rp_v := random(0, 3);
                    end if;
                    if random(1, 5) = 1 then
                        Rdlc_v := random(0, 7);
                    else
                        Rdlc_v := random(8, 15);
                    end if;
                    Req_v := "0000";

                    for N in 0 to 3 loop
                        if random(1, 8) = 1 then
                            Req_v(N) := '1';
                        end if;
                    end loop;

                    Rc_v      := random(1, 1500) = 1;
                    step(syn => Syn_v, sdlc => Sdlc_v, rp => Rp_v, rdata => mix(I, 9000), rdlc => Rdlc_v,
                         req => Req_v, rc => Rc_v);
                    StrayDone <= (others => '0');
                    StrayAbt  <= (others => '0');
                end loop;

                -- The end: every type applied, every request completed
                check_value(CovT_v = AllCov_c, ERROR, "every transmission type of the transmit PDOs applied");
                check_value(CovR_v = AllCov_c, ERROR, "every transmission type of the receive PDOs applied");
                RespHold   <= (others => false);
                Nmt_EnaPdo <= '1';
                settle;

                for N in 0 to 3 loop
                    log(ID_SEQUENCER, "PDO " & integer'image(N + 1) & ": requests " & integer'image(TxCnt(N)) &
                        ", Evt_TpdoSent " & integer'image(CntSent(N)) & ", Evt_TpdoAborted " &
                        integer'image(CntAbort(N)) & ", Err_TxBusy " & integer'image(CntBusy(N)) & ", Err_TxTimeout " &
                        integer'image(CntTmo(N)) & ", receive PDOs passed " & integer'image(RxCnt(N)) &
                        ", Err_RxLength " & integer'image(CntLen(N)));
                    -- Every event class of a present PDO occurred
                    if N < NumTpdo_g then
                        check_value(CntSent(N) > 0 and CntAbort(N) > 0 and CntBusy(N) > 0 and CntTmo(N) > 0, ERROR,
                                    "every completion and error of transmit PDO " & integer'image(N + 1));
                    end if;
                    if N < NumRpdo_g then
                        check_value(RxCnt(N) > 0 and CntLen(N) > 0, ERROR,
                                    "passes and length errors of receive PDO " & integer'image(N + 1));
                    end if;
                end loop;

            -- *** TC-PD-18: absent PDOs ***
            elsif run("test_absent") then
                -- Receive PDO events with the numbers of absent PDOs are not processed; present PDOs are
                setRxTypes(254);
                clocks(2);

                for N in 0 to 3 loop
                    C_v := RxCnt(N);
                    L_v := CntLen(N);
                    rpdo(N, mix(9100, N));
                    rpdo(N, mix(9101, N), 4);
                    clocks(3);
                    if N < NumRpdo_g then
                        check_value(RxCnt(N), C_v + 1, ERROR, "present receive PDO " & integer'image(N + 1));
                        check_value(CntLen(N), L_v + 1, ERROR, "present receive PDO, short");
                    else
                        check_value(RxCnt(N), C_v, ERROR, "absent receive PDO " & integer'image(N + 1));
                        check_value(CntLen(N), L_v, ERROR, "absent receive PDO, short");
                    end if;
                end loop;

                setRxTypes(1);
                clocks(2);

                for N in 0 to 3 loop
                    rpdo(N, mix(9200, N));
                end loop;

                B_v := RxCnt;
                syncEv;
                clocks(3);

                for N in 0 to 3 loop
                    check_value(RxCnt(N), B_v(N) + boolean'pos(N < NumRpdo_g), ERROR,
                                "held receive PDO " & integer'image(N + 1));
                end loop;

                -- Requests of absent PDOs without effect; present PDOs requested
                B_v := TxCnt;
                step(req => "1111");
                settle;
                setTxTypes(1);
                clocks(2);
                syncEv;
                settle;

                for N in 0 to 3 loop
                    check_value(TxCnt(N), B_v(N) + 2 * boolean'pos(N < NumTpdo_g), ERROR,
                                "requests of transmit PDO " & integer'image(N + 1));
                end loop;

                -- The handshake inputs of absent PDOs without effect (the checker requires their outputs at 0)
                Manual <= (others => true);
                clocks(1);

                for N in 0 to 3 loop
                    if N >= NumTpdo_g then
                        ManRdy(N)  <= '1';
                        clocks(2);
                        ManDone(N) <= '1';
                        clocks(2);
                        ManAbt(N)  <= '1';
                        clocks(2);
                        ManRdy(N)  <= '0';
                        ManDone(N) <= '0';
                        ManAbt(N)  <= '0';
                        clocks(2);
                    end if;
                end loop;

                clocks(5);

            end if;

            clocks(10);

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
