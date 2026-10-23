---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_pdo: ocan_pdo with ocan_nmt, ocan_od, ocan_time, ocan_dispatch and ocan_link on the CAN
-- network model. The model node M1 of the active bus is the NMT master, the SYNC producer, the producer of the
-- receive PDOs and the consumer of the transmit PDOs; the test is the user logic at the port of ocan_pdo and writes
-- the transmission types through the access interface of ocan_od. The PDOs on both buses in the NMT states that M1
-- sets, their SYNC phase against the Local Time PDO (TC-PD-16), and the minimal set (TC-PD-17).
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
    use work.ocan_pkg.all;
    use work.ocan_tb_pkg.all;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_pdo_net_tb is
    generic (
        runner_cfg   : string;
        MinimalSet_g : boolean := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_pdo_net_tb is

    subtype Data_t is std_logic_vector(63 downto 0);

    type Data_a is array (0 to 3) of Data_t;

    type Nat_a is array (0 to 3) of natural;

    constant NodeId_c : natural := 5;
    constant SyncId_c : natural := 16#080#;
    constant LtpId_c  : natural := 16#1F5#;

    -- Pre-defined connection set of NODE-ID 5 (receive PDO n: 100h x (n + 1) + 5, transmit PDO n: 100h x n + 85h)
    constant RpdoId_c : Nat_a := (16#205#, 16#305#, 16#405#, 16#505#);
    constant TpdoId_c : Nat_a := (16#185#, 16#285#, 16#385#, 16#485#);

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

    function pdo (v : std_logic_vector(255 downto 0); n : natural) return Data_t is
    begin
        return v(64 * n + 63 downto 64 * n);
    end function;

    signal Clk             : std_logic;
    signal Rst             : std_logic                      := '1';
    signal Bus_Sel         : std_logic                      := '0';
    signal Acc_Valid       : std_logic                      := '0';
    signal Acc_Ready       : std_logic;
    signal Acc_Write       : std_logic                      := '0';
    signal Acc_Index       : std_logic_vector(15 downto 0)  := (others => '0');
    signal Acc_Sub         : std_logic_vector(7 downto 0)   := (others => '0');
    signal Acc_Data        : std_logic_vector(63 downto 0)  := (others => '0');
    signal Acc_Len         : std_logic_vector(3 downto 0)   := (others => '0');
    signal Rsp_Valid       : std_logic;
    signal Rsp_Abort       : std_logic_vector(31 downto 0);
    signal Sync_Valid      : std_logic;
    signal Rpdo_Valid      : std_logic_vector(3 downto 0);
    signal Rpdo_Data       : std_logic_vector(255 downto 0);
    signal Tpdo_Req        : std_logic_vector(3 downto 0)   := (others => '0');
    signal Tpdo_Data       : std_logic_vector(255 downto 0) := (others => '0');
    signal Stat_TpdoBusy   : std_logic_vector(3 downto 0);
    signal Stat_PdoEnabled : std_logic;
    signal Evt_TpdoSent    : std_logic_vector(3 downto 0);
    signal Evt_TpdoAborted : std_logic_vector(3 downto 0);
    signal Err_RxLength    : std_logic_vector(3 downto 0);
    signal Err_TxBusy      : std_logic_vector(3 downto 0);
    signal Err_TxTimeout   : std_logic_vector(3 downto 0);
    signal Stat_State      : std_logic_vector(1 downto 0);
    signal Stat_ActiveBus  : std_logic;

    -- *** Model of the user logic ***
    signal TestReq   : std_logic_vector(3 downto 0) := (others => '0'); -- requests of the test (one cycle)
    signal UserData  : Data_a                       := (others => (others => '0'));
    signal AutoReply : boolean                      := false; -- receive PDO 1 requests transmit PDO 1 in reply
    signal AutoSync  : boolean                      := false; -- every Sync_Valid requests transmit PDO 2
    signal ReplyData : Data_t                       := (others => '0');

    -- *** Monitors ***
    signal RxCnt    : Nat_a   := (others => 0);
    signal AllRxCyc : boolean := false; -- the last passes of all four receive PDOs in the same cycle

begin

    test_runner_watchdog(runner, 400 ms);

    i_th : entity work.ocan_pdo_net_th
        generic map (
            MinimalSet_g => MinimalSet_g
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            Bus_Sel         => Bus_Sel,
            Acc_Valid       => Acc_Valid,
            Acc_Ready       => Acc_Ready,
            Acc_Write       => Acc_Write,
            Acc_Index       => Acc_Index,
            Acc_Sub         => Acc_Sub,
            Acc_Data        => Acc_Data,
            Acc_Len         => Acc_Len,
            Rsp_Valid       => Rsp_Valid,
            Rsp_Abort       => Rsp_Abort,
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
            Err_TxTimeout   => Err_TxTimeout,
            Stat_State      => Stat_State,
            Stat_ActiveBus  => Stat_ActiveBus
        );

    -----------------------------------------------------------------------------------------------
    -- Model of the user logic: the data of the transmit PDOs, the requests of the test, the reply to receive PDO 1
    -- (a telemetry request, clause 9.4.3b.1) and the request of transmit PDO 2 at every SYNC event (9.4.3b.2)
    -----------------------------------------------------------------------------------------------
    p_user : process (Clk) is
    begin
        if rising_edge(Clk) then
            Tpdo_Req <= TestReq;

            for N in 0 to 3 loop
                Tpdo_Data(64 * N + 63 downto 64 * N) <= UserData(N);
            end loop;

            if AutoReply and Rpdo_Valid(0) = '1' then
                Tpdo_Req(0)            <= '1';
                Tpdo_Data(63 downto 0) <= not pdo(Rpdo_Data, 0);
                ReplyData              <= not pdo(Rpdo_Data, 0);
            end if;
            if AutoSync and Sync_Valid = '1' then
                Tpdo_Req(1) <= '1';
            end if;
        end if;
    end process;

    p_mon : process (Clk) is
    begin
        if rising_edge(Clk) then

            for N in 0 to 3 loop
                if Rpdo_Valid(N) = '1' then
                    RxCnt(N) <= RxCnt(N) + 1;
                end if;
            end loop;

            if Rpdo_Valid /= "0000" then
                AllRxCyc <= Rpdo_Valid = "1111";
            end if;
            if Rst = '0' and (Err_RxLength or Err_TxBusy or Err_TxTimeout or Evt_TpdoAborted) /= "0000" then
                alert(ERROR, "event of ocan_pdo that no test expects: Err_RxLength " & to_hstring(Err_RxLength) &
                      ", Err_TxBusy " & to_hstring(Err_TxBusy) & ", Err_TxTimeout " & to_hstring(Err_TxTimeout) &
                      ", Evt_TpdoAborted " & to_hstring(Evt_TpdoAborted));
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable M1_v   : natural;
        variable T_v    : time;
        variable B_v    : Nat_a;
        variable D_v    : Data_a;
        variable K_v    : natural;
        variable Ix_v   : integer;
        variable Il_v   : integer;
        variable L_v    : natural;
        variable Due3_v : boolean;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        procedure request (n : natural) is
        begin
            wait until rising_edge(Clk);
            TestReq(n) <= '1';
            wait until rising_edge(Clk);
            TestReq(n) <= '0';
        end procedure;

        -- NMT message of M1 to the node
        procedure nmt (cs : natural) is
            variable D_v : Data_t := (others => '0');
        begin
            D_v(63 downto 56) := std_logic_vector(to_unsigned(cs, 8));
            D_v(55 downto 48) := std_logic_vector(to_unsigned(NodeId_c, 8));
            Net_v.txPush(M1_v, canStd(0, 2, D_v));
        end procedure;

        procedure waitState (s : std_logic_vector(1 downto 0); msg : string) is
        begin
            if Stat_State /= s then
                wait until Stat_State = s for 20 ms;
            end if;
            check_value(Stat_State, s, ERROR, msg);
        end procedure;

        -- Write of a transmission type (UNSIGNED8) through the access interface of ocan_od
        procedure writeType (idx : natural; t : natural) is
            variable N_v : natural := 0;
        begin
            wait until rising_edge(Clk);
            Acc_Valid <= '1';
            Acc_Write <= '1';
            Acc_Index <= std_logic_vector(to_unsigned(idx, 16));
            Acc_Sub   <= x"02";
            Acc_Data  <= std_logic_vector(to_unsigned(t, 64));
            Acc_Len   <= x"1";

            loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                exit when Acc_Ready = '1' or N_v > 1000;
            end loop;

            Acc_Valid <= '0';
            Acc_Write <= '0';
            N_v       := 0;

            loop
                exit when Rsp_Valid = '1' or N_v > 1000;
                wait until rising_edge(Clk);
                N_v := N_v + 1;
            end loop;

            check_value(Rsp_Valid, '1', ERROR, "answer of ocan_od");
            check_value(Rsp_Abort, x"00000000", ERROR, "write of the type of " & integer'image(idx));
        end procedure;

        -- Frames of identifier id that M1 received after time t
        impure function countFrames (id : natural; t : time) return natural is
            variable E_v : TbLog_t;
            variable N_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(M1_v) - 1 loop
                E_v := Net_v.logGet(M1_v, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    N_v := N_v + 1;
                end if;
            end loop;

            return N_v;
        end function;

        -- Log index of the first frame of identifier id that M1 received after time t; -1: none
        impure function firstFrame (id : natural; t : time) return integer is
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(M1_v) - 1 loop
                E_v := Net_v.logGet(M1_v, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    return I;
                end if;
            end loop;

            return -1;
        end function;

        -- Identifier of transmit source s of DS-TX-01: transmit PDOs 1 to 4 (0 to 3), the Local Time PDO (4)
        function idOf (s : natural) return natural is
        begin
            if s <= 3 then
                return TpdoId_c(s);
            end if;
            return LtpId_c;
        end function;

        -- Transmit source of the last frame of the node that M1 received up to time t, in the order of DS-TX-01:
        -- transmit PDOs 1 to 4 (0 to 3), the Local Time PDO (4), the SDO reply (5), NMT error control (6); 6 when none
        impure function lastSource (t : time) return natural is
            variable E_v  : TbLog_t;
            variable Id_v : natural;
            variable S_v  : natural := 6;
        begin

            for I in 0 to Net_v.logCount(M1_v) - 1 loop
                E_v  := Net_v.logGet(M1_v, I);
                Id_v := to_integer(unsigned(E_v.Frame.Id(28 downto 18)));
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T <= t then

                    for N in 0 to 3 loop
                        if Id_v = TpdoId_c(N) then
                            S_v := N;
                        end if;
                    end loop;

                    if Id_v = LtpId_c then
                        S_v := 4;
                    elsif Id_v = 16#580# + NodeId_c then
                        S_v := 5;
                    elsif Id_v = 16#700# + NodeId_c then
                        S_v := 6;
                    end if;
                end if;
            end loop;

            return S_v;
        end function;

        -- A frame of identifier id after time t: DLC 8 and the data d
        procedure checkFrame (id : natural; t : time; d : Data_t; msg : string) is
            variable I_v : integer;
            variable E_v : TbLog_t;
        begin
            I_v := firstFrame(id, t);
            check_value(I_v >= 0, ERROR, msg & ": frame on the bus");
            if I_v >= 0 then
                E_v := Net_v.logGet(M1_v, I_v);
                check_value(E_v.Frame.Dlc, 8, ERROR, msg & ": DLC");
                check_value(E_v.Frame.Data, d, ERROR, msg & ": data bytes");
            end if;
        end procedure;

        -- A SYNC of M1 (DLC 0, or DLC 1 with the counter byte 5Ah); T_v is the time of the SYNC event
        procedure sync (dlc : natural := 0) is
        begin
            Net_v.txPush(M1_v, canStd(SyncId_c, dlc, x"5A00000000000000"));
            wait until Sync_Valid = '1' for 2 ms;
            check_value(Sync_Valid, '1', ERROR, "Sync_Valid after a SYNC of M1");
            T_v := now;
        end procedure;

        constant Start_c   : natural := 16#01#; -- NMT command specifiers of [CiA301] 7.2.8.3.1
        constant EnterPo_c : natural := 16#80#;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            -- *** TC-PD-16: PDOs on both buses in the NMT states that M1 sets ***
            if run("test_net_pdo") then

                for B in 0 to 1 loop
                    M1_v      := 2 * B;
                    Net_v.logClear(0);
                    Net_v.logClear(2);
                    AutoReply <= false;
                    AutoSync  <= false;
                    if B = 1 then
                        Bus_Sel <= '1';
                    end if;
                    Rst <= '1';
                    wait for 250 ns;
                    wait until rising_edge(Clk);
                    Rst <= '0';
                    waitState(NmtPreOp_c, "Pre-operational after the boot-up");
                    check_value(Stat_ActiveBus = '1', B = 1, ERROR, "active bus");
                    -- Transmission types: transmit PDOs 254, 1, 3 and 0, receive PDOs 254
                    writeType(16#1800#, 254);
                    writeType(16#1801#, 1);
                    writeType(16#1802#, 3);
                    writeType(16#1803#, 0);

                    for N in 0 to 3 loop
                        writeType(16#1400# + N, 254);
                    end loop;

                    -- In Pre-operational no PDO
                    B_v := RxCnt;
                    T_v := now;
                    Net_v.txPush(M1_v, canStd(RpdoId_c(0), 8, mix(B, 1)));
                    request(0);
                    wait for 1 ms;
                    check_value(RxCnt = B_v, ERROR, "no receive PDO in Pre-operational");
                    check_value(countFrames(TpdoId_c(0), T_v), 0, ERROR, "no transmit PDO in Pre-operational");
                    -- Start
                    nmt(Start_c);
                    waitState(NmtOp_c, "Operational after the start of M1");

                    -- Receive PDOs of type 254: passed at once, data byte 0 the first on the bus
                    for N in 0 to 3 loop
                        D_v(N) := mix(10 * B + N, 2);
                        Net_v.txPush(M1_v, canStd(RpdoId_c(N), 8, D_v(N)));
                        wait until Rpdo_Valid(N) = '1' for 2 ms;
                        check_value(Rpdo_Valid(N), '1', ERROR, "receive PDO " & integer'image(N + 1) & " passed");
                        wait until falling_edge(Clk);
                        check_value(pdo(Rpdo_Data, N), D_v(N), ERROR, "data of receive PDO " & integer'image(N + 1));
                    end loop;

                    -- Transmit PDO 1 (type 254) at a request of the user logic
                    UserData(0) <= mix(20 + B, 3);
                    T_v         := now;
                    request(0);
                    wait for 1 ms;
                    check_value(countFrames(TpdoId_c(0), T_v), 1, ERROR, "transmit PDO 1 at the request");
                    checkFrame(TpdoId_c(0), T_v, mix(20 + B, 3), "transmit PDO 1");

                    -- SYNCs: transmit PDO 2 (type 1) at every SYNC, transmit PDO 3 (type 3) at the SYNCs of the Local
                    -- Time PDO (type 3), transmit PDO 4 (type 0) at the SYNC after a request
                    for I in 1 to 6 loop

                        for N in 1 to 3 loop
                            UserData(N) <= mix(100 * B + 10 * I + N, 4);
                        end loop;

                        if I = 3 then
                            request(3);
                        end if;
                        clocks(2);
                        sync(I mod 2);
                        wait for 2 ms;
                        check_value(countFrames(TpdoId_c(1), T_v), 1, ERROR, "transmit PDO 2 at SYNC " &
                                    integer'image(I));
                        checkFrame(TpdoId_c(1), T_v, mix(100 * B + 10 * I + 1, 4), "transmit PDO 2");
                        Due3_v := countFrames(LtpId_c, T_v) = 1;
                        check_value(countFrames(TpdoId_c(2), T_v) = 1, Due3_v, ERROR,
                                    "transmit PDO 3 at the SYNCs of the Local Time PDO, SYNC " & integer'image(I));
                        check_value(Due3_v, I mod 3 = 0, ERROR, "the Local Time PDO at every third SYNC");
                        check_value(countFrames(TpdoId_c(3), T_v), boolean'pos(I = 3), ERROR,
                                    "transmit PDO 4 at the SYNC after its request");
                        if Due3_v then
                            checkFrame(TpdoId_c(2), T_v, mix(100 * B + 10 * I + 2, 4), "transmit PDO 3");
                            -- The frames due at this SYNC in the round-robin order of DS-TX-01, which starts after the
                            -- source of the last frame before the SYNC
                            L_v := lastSource(T_v);

                            for S1 in 1 to 4 loop

                                for S2 in 1 to 4 loop
                                    Ix_v := firstFrame(idOf(S1), T_v);
                                    Il_v := firstFrame(idOf(S2), T_v);
                                    if Ix_v >= 0 and Il_v >= 0 and (S1 - L_v + 6) mod 7 < (S2 - L_v + 6) mod 7 then
                                        check_value(Ix_v < Il_v, ERROR, "round-robin order of the sources " &
                                                    integer'image(S1) & " and " & integer'image(S2) & " at SYNC " &
                                                    integer'image(I));
                                    end if;
                                end loop;

                            end loop;

                            -- After a SYNC with transmit PDO 2 alone the Local Time PDO comes before transmit PDO 2
                            check_value(L_v, 1, ERROR, "transmit PDO 2 the last frame before SYNC " & integer'image(I));
                            check_value(firstFrame(LtpId_c, T_v) < firstFrame(TpdoId_c(1), T_v), ERROR,
                                        "the Local Time PDO before transmit PDO 2 at SYNC " & integer'image(I));
                        end if;
                        if I = 3 then
                            checkFrame(TpdoId_c(3), T_v, mix(100 * B + 10 * I + 3, 4), "transmit PDO 4");
                        end if;
                    end loop;

                    -- Receive PDOs of type 1: in Pre-operational, then started again
                    nmt(EnterPo_c);
                    waitState(NmtPreOp_c, "Pre-operational for the receive types");

                    for N in 0 to 3 loop
                        writeType(16#1400# + N, 1);
                    end loop;

                    nmt(Start_c);
                    waitState(NmtOp_c, "Operational with the receive types 1");
                    B_v := RxCnt;

                    for N in 0 to 3 loop
                        D_v(N) := mix(30 * B + N, 5);
                        Net_v.txPush(M1_v, canStd(RpdoId_c(N), 8, D_v(N)));
                    end loop;

                    wait for 1 ms;
                    check_value(RxCnt = B_v, ERROR, "type 1: not passed before the SYNC");
                    sync;
                    wait until falling_edge(Clk);
                    check_value(Rpdo_Valid, x"F", ERROR, "type 1: all four passed with Sync_Valid");

                    for N in 0 to 3 loop
                        check_value(pdo(Rpdo_Data, N), D_v(N), ERROR, "type 1: data of receive PDO " &
                                    integer'image(N + 1));
                    end loop;

                    wait for 1 ms;
                    -- Pre-operational after a receive PDO of type 1 and a request of type 0, before the SYNC: no data
                    -- passed and no transmit PDO, also after the next start
                    B_v := RxCnt;
                    Net_v.txPush(M1_v, canStd(RpdoId_c(0), 8, mix(40 + B, 6)));
                    wait for 500 us;
                    request(3);
                    nmt(EnterPo_c);
                    waitState(NmtPreOp_c, "Pre-operational with held data and a waiting request");
                    T_v := now;
                    sync;
                    request(0);
                    Net_v.txPush(M1_v, canStd(RpdoId_c(1), 8, mix(50 + B, 6)));
                    wait for 2 ms;

                    for N in 0 to 3 loop
                        check_value(countFrames(TpdoId_c(N), T_v), 0, ERROR, "no transmit PDO " &
                                    integer'image(N + 1) & " in Pre-operational");
                    end loop;

                    check_value(RxCnt = B_v, ERROR, "no data passed in Pre-operational");
                    nmt(Start_c);
                    waitState(NmtOp_c, "Operational again");
                    T_v := now;
                    sync;
                    wait for 2 ms;
                    check_value(RxCnt = B_v, ERROR, "the held data discarded at the exit from Operational");
                    check_value(countFrames(TpdoId_c(3), T_v), 0, ERROR,
                                "the waiting request discarded at the exit from Operational");
                    check_value(countFrames(TpdoId_c(1), T_v), 1, ERROR, "transmit PDO 2 after the restart");
                end loop;

            -- *** TC-PD-17: minimal set ***
            elsif run("test_net_minimal") then
                M1_v := 0;
                Net_v.logClear(0);
                Rst  <= '1';
                wait for 250 ns;
                wait until rising_edge(Clk);
                Rst  <= '0';
                waitState(NmtOp_c, "Operational by local control");
                -- The node is in Operational a few cycles after the reset; its controller integrates on the bus
                -- (11 recessive bits) before it takes a frame
                wait for 100 us;
                -- A receive PDO of M1 (a telemetry request) passed at once, the transmit PDO of the reply on the bus
                AutoReply <= true;

                for I in 0 to 2 loop
                    D_v(0) := mix(60 + I, 7);
                    T_v    := now;
                    Net_v.txPush(M1_v, canStd(RpdoId_c(0), 8, D_v(0)));
                    wait until Rpdo_Valid(0) = '1' for 2 ms;
                    check_value(Rpdo_Valid(0), '1', ERROR, "the telemetry request passed at once");
                    wait until falling_edge(Clk);
                    check_value(pdo(Rpdo_Data, 0), D_v(0), ERROR, "data of the telemetry request");
                    wait for 1 ms;
                    check_value(countFrames(TpdoId_c(0), T_v), 1, ERROR, "the reply on the bus");
                    checkFrame(TpdoId_c(0), T_v, not D_v(0), "the reply");
                end loop;

                AutoReply <= false;
                -- A transmit PDO at every SYNC event (clause 9.4.3b.2)
                AutoSync <= true;

                for I in 1 to 3 loop
                    UserData(1) <= mix(70 + I, 8);
                    clocks(2);
                    sync(I mod 2);
                    wait for 1 ms;
                    check_value(countFrames(TpdoId_c(1), T_v), 1, ERROR, "transmit PDO 2 after SYNC " &
                                integer'image(I));
                    checkFrame(TpdoId_c(1), T_v, mix(70 + I, 8), "transmit PDO 2 after the SYNC");
                end loop;

                AutoSync <= false;

            end if;

            wait for 10 us;

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
