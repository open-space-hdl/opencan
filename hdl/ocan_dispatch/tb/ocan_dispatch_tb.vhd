---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_dispatch: the link events are driven cycle by cycle, the transmit stream is answered by
-- a responder, and every expected output is checked in its cycle. One run block per test case of the verification
-- plan.
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
entity ocan_dispatch_tb is
    generic (
        runner_cfg  : string;
        NumRpdo_g   : natural := 4;
        NumTpdo_g   : natural := 4;
        TimePdos_g  : boolean := true;
        SdoServer_g : boolean := true
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_dispatch_tb is

    constant NodeId_c : natural := 5;

    -- Default COB-IDs: SYNC 080h, Spacecraft Time PDO 0F0h, receive PDOs 200h/300h/400h/500h + NODE-ID, transmit
    -- PDOs 180h/280h/380h/480h + NODE-ID, Local Time PDO 1F5h, master heartbeat 701h
    type Ids_t is array (0 to 11) of natural;

    constant DefIds_c : Ids_t := (16#080#, 16#0F0#, 16#205#, 16#305#, 16#405#, 16#505#, 16#185#, 16#285#, 16#385#,
                                  16#485#, 16#1F5#, 16#701#);

    function table (ids : Ids_t; valid : std_logic_vector(11 downto 0) := (others => '1')) return std_logic_vector is
        variable T_v : std_logic_vector(143 downto 0);
    begin

        for E in 0 to 11 loop
            T_v(12 * E + 11)               := valid(E);
            T_v(12 * E + 10 downto 12 * E) := std_logic_vector(to_unsigned(ids(E), 11));
        end loop;

        return T_v;
    end function;

    -- *** DUT signals ***
    signal Clk                : std_logic;
    signal Rst                : std_logic                      := '1';
    signal LinkRx_Valid       : std_logic_vector(1 downto 0)   := "00";
    signal LinkRx_Id          : std_logic_vector(57 downto 0)  := (others => '0');
    signal LinkRx_Ide         : std_logic_vector(1 downto 0)   := "00";
    signal LinkRx_Rtr         : std_logic_vector(1 downto 0)   := "00";
    signal LinkRx_Dlc         : std_logic_vector(7 downto 0)   := (others => '0');
    signal LinkRx_Data        : std_logic_vector(127 downto 0) := (others => '0');
    signal LinkTx_Valid       : std_logic;
    signal LinkTx_Ready       : std_logic                      := '0';
    signal LinkTx_Id          : std_logic_vector(28 downto 0);
    signal LinkTx_Dlc         : std_logic_vector(3 downto 0);
    signal LinkTx_Data        : std_logic_vector(63 downto 0);
    signal LinkTx_Abort       : std_logic;
    signal LinkTx_Done        : std_logic                      := '0';
    signal LinkTx_Aborted     : std_logic                      := '0';
    signal Red_ActiveBus      : std_logic                      := '0';
    signal Red_Selecting      : std_logic                      := '0';
    signal Nmt_NodeId         : std_logic_vector(6 downto 0)   := std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Nmt_NodeIdValid    : std_logic                      := '1';
    signal Nmt_EnaSdo         : std_logic                      := '1';
    signal Nmt_EnaPdo         : std_logic                      := '1';
    signal Nmt_EnaSync        : std_logic                      := '1';
    signal Cfg_CobId          : std_logic_vector(143 downto 0) := table(DefIds_c);
    signal Cfg_CobIdCopy      : std_logic_vector(143 downto 0) := table(DefIds_c);
    signal RxNmt_Valid        : std_logic;
    signal RxNmt_Cs           : std_logic_vector(7 downto 0);
    signal RxSync_Valid       : std_logic;
    signal RxSync_Dlc         : std_logic_vector(3 downto 0);
    signal RxSync_Data        : std_logic_vector(7 downto 0);
    signal RxRpdo_Valid       : std_logic;
    signal RxRpdo_Num         : std_logic_vector(1 downto 0);
    signal RxRpdo_Dlc         : std_logic_vector(3 downto 0);
    signal RxRpdo_Data        : std_logic_vector(63 downto 0);
    signal RxTime_Valid       : std_logic;
    signal RxTime_Dlc         : std_logic_vector(3 downto 0);
    signal RxTime_Data        : std_logic_vector(63 downto 0);
    signal RxSdo_Valid        : std_logic;
    signal RxSdo_Dlc          : std_logic_vector(3 downto 0);
    signal RxSdo_Data         : std_logic_vector(63 downto 0);
    signal RxRed_NmtValid     : std_logic_vector(1 downto 0);
    signal RxRed_HbValid      : std_logic_vector(1 downto 0);
    signal RxRed_HbDlc        : std_logic_vector(7 downto 0);
    signal RxRed_HbState      : std_logic_vector(15 downto 0);
    signal TxTpdo_Valid       : std_logic_vector(3 downto 0);
    signal TxTpdo_Ready       : std_logic_vector(3 downto 0);
    signal TxTpdo_Dlc         : std_logic_vector(15 downto 0);
    signal TxTpdo_Data        : std_logic_vector(255 downto 0);
    signal TxTpdo_Done        : std_logic_vector(3 downto 0);
    signal TxTpdo_Aborted     : std_logic_vector(3 downto 0);
    signal TxTime_Valid       : std_logic;
    signal TxTime_Ready       : std_logic;
    signal TxTime_Dlc         : std_logic_vector(3 downto 0);
    signal TxTime_Data        : std_logic_vector(63 downto 0);
    signal TxTime_Done        : std_logic;
    signal TxTime_Aborted     : std_logic;
    signal TxSdo_Valid        : std_logic;
    signal TxSdo_Ready        : std_logic;
    signal TxSdo_Dlc          : std_logic_vector(3 downto 0);
    signal TxSdo_Data         : std_logic_vector(63 downto 0);
    signal TxSdo_Done         : std_logic;
    signal TxSdo_Aborted      : std_logic;
    signal TxNmt_Valid        : std_logic;
    signal TxNmt_Ready        : std_logic;
    signal TxNmt_Data         : std_logic_vector(7 downto 0);
    signal TxNmt_Done         : std_logic;
    signal TxNmt_Aborted      : std_logic;
    signal Err_Protocol       : std_logic;
    signal Err_CobId          : std_logic;
    signal Stat_CobIdMismatch : std_logic_vector(11 downto 0);

    -- *** Sources: index 0 to 3 transmit PDOs, 4 Local Time PDO, 5 SDO reply, 6 NMT error control ***
    type Nat7_a is array (0 to 6) of natural;
    type Bool7_a is array (0 to 6) of boolean;
    type Dlc7_a is array (0 to 6) of std_logic_vector(3 downto 0);
    type Data7_a is array (0 to 6) of std_logic_vector(63 downto 0);

    signal SrcValid  : std_logic_vector(6 downto 0);
    signal SrcReady  : std_logic_vector(6 downto 0);
    signal SrcDone   : std_logic_vector(6 downto 0);
    signal SrcAbort  : std_logic_vector(6 downto 0);
    signal SrcDlc    : Dlc7_a  := (others => "0010");
    signal SrcData   : Data7_a := (others => x"0102030405060708");
    signal ReqCnt    : Nat7_a  := (others => 0);
    signal AutoReq   : Bool7_a := (others => false);
    signal RandomGap : boolean := false;
    signal CntTaken  : Nat7_a  := (others => 0);
    signal CntDone   : Nat7_a  := (others => 0);
    signal CntAbort  : Nat7_a  := (others => 0);

    -- *** Link responder ***
    signal RespReady  : natural := 0;    -- cycles before LinkTx_Ready
    signal RespDone   : natural := 3;    -- cycles from the acceptance to the completion
    signal RespAbort  : boolean := false; -- complete as aborted
    signal CntAbortRq : natural := 0;     -- LinkTx_Abort pulses

begin

    test_runner_watchdog(runner, 50 ms);

    i_th : entity work.ocan_dispatch_th
        generic map (
            NumRpdo_g   => NumRpdo_g,
            NumTpdo_g   => NumTpdo_g,
            TimePdos_g  => TimePdos_g,
            SdoServer_g => SdoServer_g
        )
        port map (
            Clk                => Clk,
            Rst                => Rst,
            LinkRx_Valid       => LinkRx_Valid,
            LinkRx_Id          => LinkRx_Id,
            LinkRx_Ide         => LinkRx_Ide,
            LinkRx_Rtr         => LinkRx_Rtr,
            LinkRx_Dlc         => LinkRx_Dlc,
            LinkRx_Data        => LinkRx_Data,
            LinkTx_Valid       => LinkTx_Valid,
            LinkTx_Ready       => LinkTx_Ready,
            LinkTx_Id          => LinkTx_Id,
            LinkTx_Dlc         => LinkTx_Dlc,
            LinkTx_Data        => LinkTx_Data,
            LinkTx_Abort       => LinkTx_Abort,
            LinkTx_Done        => LinkTx_Done,
            LinkTx_Aborted     => LinkTx_Aborted,
            Red_ActiveBus      => Red_ActiveBus,
            Red_Selecting      => Red_Selecting,
            Nmt_NodeId         => Nmt_NodeId,
            Nmt_NodeIdValid    => Nmt_NodeIdValid,
            Nmt_EnaSdo         => Nmt_EnaSdo,
            Nmt_EnaPdo         => Nmt_EnaPdo,
            Nmt_EnaSync        => Nmt_EnaSync,
            Cfg_CobId          => Cfg_CobId,
            Cfg_CobIdCopy      => Cfg_CobIdCopy,
            RxNmt_Valid        => RxNmt_Valid,
            RxNmt_Cs           => RxNmt_Cs,
            RxSync_Valid       => RxSync_Valid,
            RxSync_Dlc         => RxSync_Dlc,
            RxSync_Data        => RxSync_Data,
            RxRpdo_Valid       => RxRpdo_Valid,
            RxRpdo_Num         => RxRpdo_Num,
            RxRpdo_Dlc         => RxRpdo_Dlc,
            RxRpdo_Data        => RxRpdo_Data,
            RxTime_Valid       => RxTime_Valid,
            RxTime_Dlc         => RxTime_Dlc,
            RxTime_Data        => RxTime_Data,
            RxSdo_Valid        => RxSdo_Valid,
            RxSdo_Dlc          => RxSdo_Dlc,
            RxSdo_Data         => RxSdo_Data,
            RxRed_NmtValid     => RxRed_NmtValid,
            RxRed_HbValid      => RxRed_HbValid,
            RxRed_HbDlc        => RxRed_HbDlc,
            RxRed_HbState      => RxRed_HbState,
            TxTpdo_Valid       => TxTpdo_Valid,
            TxTpdo_Ready       => TxTpdo_Ready,
            TxTpdo_Dlc         => TxTpdo_Dlc,
            TxTpdo_Data        => TxTpdo_Data,
            TxTpdo_Done        => TxTpdo_Done,
            TxTpdo_Aborted     => TxTpdo_Aborted,
            TxTime_Valid       => TxTime_Valid,
            TxTime_Ready       => TxTime_Ready,
            TxTime_Dlc         => TxTime_Dlc,
            TxTime_Data        => TxTime_Data,
            TxTime_Done        => TxTime_Done,
            TxTime_Aborted     => TxTime_Aborted,
            TxSdo_Valid        => TxSdo_Valid,
            TxSdo_Ready        => TxSdo_Ready,
            TxSdo_Dlc          => TxSdo_Dlc,
            TxSdo_Data         => TxSdo_Data,
            TxSdo_Done         => TxSdo_Done,
            TxSdo_Aborted      => TxSdo_Aborted,
            TxNmt_Valid        => TxNmt_Valid,
            TxNmt_Ready        => TxNmt_Ready,
            TxNmt_Data         => TxNmt_Data,
            TxNmt_Done         => TxNmt_Done,
            TxNmt_Aborted      => TxNmt_Aborted,
            Err_Protocol       => Err_Protocol,
            Err_CobId          => Err_CobId,
            Stat_CobIdMismatch => Stat_CobIdMismatch
        );

    -----------------------------------------------------------------------------------------------
    -- Sources
    -----------------------------------------------------------------------------------------------
    g_tpdo : for N in 0 to 3 generate
        TxTpdo_Valid(N)                        <= SrcValid(N);
        TxTpdo_Dlc(4 * N + 3 downto 4 * N)     <= SrcDlc(N);
        TxTpdo_Data(64 * N + 63 downto 64 * N) <= SrcData(N);
        SrcReady(N)                            <= TxTpdo_Ready(N);
        SrcDone(N)                             <= TxTpdo_Done(N);
        SrcAbort(N)                            <= TxTpdo_Aborted(N);
    end generate;

    TxTime_Valid <= SrcValid(4);
    TxTime_Dlc   <= SrcDlc(4);
    TxTime_Data  <= SrcData(4);
    SrcReady(4)  <= TxTime_Ready;
    SrcDone(4)   <= TxTime_Done;
    SrcAbort(4)  <= TxTime_Aborted;
    TxSdo_Valid  <= SrcValid(5);
    TxSdo_Dlc    <= SrcDlc(5);
    TxSdo_Data   <= SrcData(5);
    SrcReady(5)  <= TxSdo_Ready;
    SrcDone(5)   <= TxSdo_Done;
    SrcAbort(5)  <= TxSdo_Aborted;
    TxNmt_Valid  <= SrcValid(6);
    TxNmt_Data   <= SrcData(6)(63 downto 56);
    SrcReady(6)  <= TxNmt_Ready;
    SrcDone(6)   <= TxNmt_Done;
    SrcAbort(6)  <= TxNmt_Aborted;

    -- One process per source: a request per increment of ReqCnt, or requests without pause while AutoReq; every
    -- request is logged (channel 3, identifier = source, time = start of the request)
    g_src : for S in 0 to 6 generate

        p_src : process is
            variable Issued_v : natural := 0;
            variable F_v      : CanFrame_t;
        begin
            SrcValid(S) <= '0';

            loop
                wait until rising_edge(Clk);
                if AutoReq(S) or Issued_v < ReqCnt(S) then
                    if RandomGap then

                        for I in 1 to random(0, 200) loop
                            wait until rising_edge(Clk);
                        end loop;

                    end if;
                    F_v         := canStd(S, 0);
                    DutLog_v.push(3, F_v);
                    SrcValid(S) <= '1';

                    loop
                        wait until rising_edge(Clk);
                        exit when SrcReady(S) = '1';
                    end loop;

                    SrcValid(S) <= '0';
                    if not AutoReq(S) then
                        Issued_v := Issued_v + 1;
                    end if;
                    CntTaken(S) <= CntTaken(S) + 1;
                end if;
            end loop;

        end process;

    end generate;

    p_cpl : process (Clk) is
    begin
        if rising_edge(Clk) then

            for S in 0 to 6 loop
                if SrcDone(S) = '1' then
                    CntDone(S) <= CntDone(S) + 1;
                end if;
                if SrcAbort(S) = '1' then
                    CntAbort(S) <= CntAbort(S) + 1;
                end if;
            end loop;

            if LinkTx_Abort = '1' then
                CntAbortRq <= CntAbortRq + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Link responder: takes one frame at a time and completes it; frames are logged in channel 2
    -----------------------------------------------------------------------------------------------
    p_link : process is
        variable F_v       : CanFrame_t;
        variable Aborted_v : boolean;
        variable Id_v      : natural;
    begin
        LinkTx_Ready   <= '0';
        LinkTx_Done    <= '0';
        LinkTx_Aborted <= '0';

        loop
            wait until rising_edge(Clk);
            if LinkTx_Valid = '1' then

                for I in 1 to RespReady loop
                    wait until rising_edge(Clk);
                    exit when LinkTx_Valid = '0';
                end loop;

                if LinkTx_Valid = '1' then
                    LinkTx_Ready <= '1';
                    wait until rising_edge(Clk);
                    LinkTx_Ready <= '0';
                    F_v.Ide      := '0';
                    F_v.Id       := LinkTx_Id;
                    F_v.Rtr      := '0';
                    F_v.Dlc      := to_integer(unsigned(LinkTx_Dlc));
                    F_v.Data     := LinkTx_Data;
                    DutLog_v.push(2, F_v);
                    -- No frame with a free COB-ID (DS-TX-05)
                    Id_v := to_integer(unsigned(LinkTx_Id(28 downto 18)));
                    if (Id_v >= 16#781# and Id_v <= 16#7DE#) or Id_v >= 16#7F0# then
                        alert(ERROR, "frame with a free COB-ID " & to_hstring(LinkTx_Id(28 downto 18)));
                    end if;
                    Aborted_v := RespAbort;

                    for I in 1 to RespDone loop
                        wait until rising_edge(Clk);
                        if LinkTx_Abort = '1' then
                            Aborted_v := true;
                        end if;
                        -- One frame at a time: no new frame before the completion
                        if LinkTx_Valid = '1' then
                            alert(ERROR, "frame offered before the completion of the previous one");
                        end if;
                    end loop;

                    if Aborted_v then
                        LinkTx_Aborted <= '1';
                    else
                        LinkTx_Done <= '1';
                    end if;
                    wait until rising_edge(Clk);
                    LinkTx_Done    <= '0';
                    LinkTx_Aborted <= '0';
                end if;
            end if;
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        type Out_t is record
            Nmt    : std_logic;
            Sync   : std_logic;
            Rpdo   : std_logic;
            Time   : std_logic;
            Sdo    : std_logic;
            RedNmt : std_logic_vector(1 downto 0);
            RedHb  : std_logic_vector(1 downto 0);
            Prot   : std_logic;
        end record;

        constant None_c : Out_t := ('0', '0', '0', '0', '0', "00", "00", '0');

        variable Ids_v   : Ids_t := DefIds_c;
        variable E_v     : TbFrameEntry_t;
        variable Exp_v   : Out_t;
        variable N_v     : natural;
        variable Base_v  : Nat7_a;
        variable Order_v : natural;

        impure function outputs return Out_t is
        begin
            return (RxNmt_Valid, RxSync_Valid, RxRpdo_Valid, RxTime_Valid, RxSdo_Valid, RxRed_NmtValid,
                    RxRed_HbValid, Err_Protocol);
        end function;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- Drives the link events of one cycle (Valid of a bus '0': no frame) and checks the outputs of the next cycle
        procedure rxCycle (
            v0  : std_logic;
            f0  : CanFrame_t;
            v1  : std_logic;
            f1  : CanFrame_t;
            exp : Out_t;
            msg : string) is
        begin
            wait until rising_edge(Clk);
            LinkRx_Valid            <= v1 & v0;
            LinkRx_Id(28 downto 0)  <= f0.Id;
            LinkRx_Id(57 downto 29) <= f1.Id;
            LinkRx_Ide              <= f1.Ide & f0.Ide;
            LinkRx_Rtr              <= f1.Rtr & f0.Rtr;
            LinkRx_Dlc              <= std_logic_vector(to_unsigned(f1.Dlc, 4)) & std_logic_vector(to_unsigned(f0.Dlc, 4));
            LinkRx_Data             <= f1.Data & f0.Data;
            wait until rising_edge(Clk);
            LinkRx_Valid            <= "00";
            wait for 1 ns;
            check_value(outputs = exp, ERROR, msg);
        end procedure;

        -- One frame on bus b
        procedure rx (
            b   : natural;
            f   : CanFrame_t;
            exp : Out_t;
            msg : string) is
            constant N_c : CanFrame_t := canStd(0, 0);
        begin
            if b = 0 then
                rxCycle('1', f, '0', N_c, exp, msg);
            else
                rxCycle('0', N_c, '1', f, exp, msg);
            end if;
        end procedure;

        function withNmt (b : natural) return Out_t is
            variable O_v : Out_t := None_c;
        begin
            O_v.Nmt       := '1';
            O_v.RedNmt(b) := '1';
            return O_v;
        end function;

        function nmt (cs : natural; node : natural; dlc : natural := 2) return CanFrame_t is
            variable D_v : std_logic_vector(63 downto 0) := (others => '0');
        begin
            D_v(63 downto 56) := std_logic_vector(to_unsigned(cs, 8));
            D_v(55 downto 48) := std_logic_vector(to_unsigned(node, 8));
            return canStd(0, dlc, D_v);
        end function;

        procedure request (s : natural) is
        begin
            ReqCnt(s) <= ReqCnt(s) + 1;
            wait until rising_edge(Clk);
        end procedure;

        -- Waits until every source is idle and the link responder has completed
        procedure waitTx (timeout : time := 2 ms) is
            constant End_c : time := now + timeout;
        begin
            clocks(4);

            while (SrcValid /= "0000000" or LinkTx_Valid = '1' or LinkTx_Ready = '1') and now < End_c loop
                wait until rising_edge(Clk);
            end loop;

            clocks(RespDone + 8);
        end procedure;

        procedure setCfg (ids : Ids_t; valid : std_logic_vector(11 downto 0) := (others => '1')) is
        begin
            Cfg_CobId     <= table(ids, valid);
            Cfg_CobIdCopy <= table(ids, valid);
            clocks(2);
        end procedure;

        impure function sourceOf (id : std_logic_vector(28 downto 0)) return natural is
            constant I_c : natural := to_integer(unsigned(id(28 downto 18)));
        begin

            for N in 0 to 3 loop
                if I_c = Ids_v(6 + N) then
                    return N;
                end if;
            end loop;

            if I_c = Ids_v(10) then
                return 4;
            elsif I_c = 16#580# + NodeId_c then
                return 5;
            else
                return 6;
            end if;
        end function;

        variable ReqT_v : time;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);

        while test_suite loop

            Rst <= '1';
            clocks(5);
            Rst <= '0';
            clocks(4);

            -- *** Every class on the active bus, bus A and bus B ***
            if run("test_rx_classes") then

                for B in 0 to 1 loop
                    if B = 1 then
                        Red_ActiveBus <= '1';
                    end if;
                    rx(B, nmt(16#01#, NodeId_c), withNmt(B), "NMT to the node");
                    check_value(RxNmt_Cs, x"01", ERROR, "NMT command specifier");
                    rx(B, nmt(16#80#, 0), withNmt(B), "NMT to all nodes");
                    check_value(RxNmt_Cs, x"80", ERROR, "NMT command specifier, all nodes");
                    Exp_v          := None_c;
                    Exp_v.Sync     := '1';
                    rx(B, canStd(16#080#, 0), Exp_v, "SYNC without counter");
                    check_value(RxSync_Dlc, x"0", ERROR, "SYNC DLC 0");
                    rx(B, canStd(16#080#, 1, x"2A00000000000000"), Exp_v, "SYNC with counter");
                    check_value(RxSync_Data, x"2A", ERROR, "SYNC counter");
                    Exp_v          := None_c;
                    Exp_v.RedHb(B) := '1';
                    rx(B, canStd(16#701#, 1, x"0500000000000000"), Exp_v, "master heartbeat");
                    check_value(RxRed_HbState(8 * B + 7 downto 8 * B), x"05", ERROR, "heartbeat state");
                    check_value(RxRed_HbDlc(4 * B + 3 downto 4 * B), x"1", ERROR, "heartbeat DLC");
                    Exp_v          := None_c;
                    Exp_v.Sdo      := '1';
                    rx(B, canStd(16#605#, 8, x"4017100000000000"), Exp_v, "SDO request");
                    check_value(RxSdo_Data, x"4017100000000000", ERROR, "SDO data");
                    Exp_v          := None_c;
                    Exp_v.Rpdo     := '1';

                    for N in 0 to 3 loop
                        rx(B, canStd(DefIds_c(2 + N), N + 1, x"1122334455667788"), Exp_v, "receive PDO");
                        check_value(to_integer(unsigned(RxRpdo_Num)), N, ERROR, "receive PDO number");
                        check_value(to_integer(unsigned(RxRpdo_Dlc)), N + 1, ERROR, "receive PDO DLC");
                    end loop;

                    Exp_v      := None_c;
                    Exp_v.Time := '1';
                    rx(B, canStd(16#0F0#, 7, x"0102030405060700"), Exp_v, "Spacecraft Time PDO");
                    check_value(RxTime_Data, x"0102030405060700", ERROR, "time data");
                end loop;

            -- *** Near misses of every receive rule ***
            elsif run("test_rx_near_miss") then
                Exp_v      := None_c;
                Exp_v.Prot := '1';
                rx(0, nmt(1, NodeId_c, 1), Exp_v, "NMT with DLC 1: protocol error");
                rx(0, nmt(1, NodeId_c, 3), Exp_v, "NMT with DLC 3: protocol error");
                rx(0, nmt(1, NodeId_c + 1), None_c, "NMT to another node");

                for E in 0 to 11 loop
                    if E /= 6 and E /= 7 and E /= 8 and E /= 9 and E /= 10 then
                        rx(0, canStd(DefIds_c(E) + 1, 2), None_c, "identifier + 1 of entry " & integer'image(E));
                        rx(0, canStd(DefIds_c(E) - 1, 2), None_c, "identifier - 1 of entry " & integer'image(E));
                        rx(0, canExt(DefIds_c(E) * 2 ** 18, 2), None_c, "extended frame of entry " & integer'image(E));
                        rx(0, canStd(DefIds_c(E), 2, Rtr => '1'), None_c, "remote frame of entry " & integer'image(E));
                    end if;
                end loop;

                rx(0, canStd(16#605# + 1, 8), None_c, "SDO to another node");
                rx(0, canStd(16#585#, 8), None_c, "SDO reply identifier");
                rx(0, canExt(16#605# * 2 ** 18, 8), None_c, "SDO as extended frame");
                rx(0, canStd(16#605#, 8, Rtr => '1'), None_c, "SDO as remote frame");
                rx(0, canExt(0, 2, x"0105000000000000"), None_c, "NMT as extended frame");
                rx(0, canStd(0, 2, x"0105000000000000", '1'), None_c, "NMT as remote frame");

                -- Receive PDO 1 configured in the free ranges
                for K in 0 to 3 loop

                    case K is
                        when 0 =>
                            Ids_v(2) := 16#781#;
                        when 1 =>
                            Ids_v(2) := 16#7DE#;
                        when 2 =>
                            Ids_v(2) := 16#7F0#;
                        when others =>
                            Ids_v(2) := 16#7FF#;
                    end case;

                    setCfg(Ids_v);
                    rx(0, canStd(Ids_v(2), 2), None_c, "receive PDO 1 at a free COB-ID " & integer'image(Ids_v(2)));
                end loop;

                Ids_v := DefIds_c;
                -- Valid flag clear and copies that differ in one bit
                setCfg(Ids_v, "111111111011");
                rx(0, canStd(DefIds_c(2), 2), None_c, "receive PDO 1 not valid");
                setCfg(Ids_v);
                Cfg_CobIdCopy(12 * 2 + 4) <= not Cfg_CobId(12 * 2 + 4);
                clocks(2);
                rx(0, canStd(DefIds_c(2), 2), None_c, "receive PDO 1 with differing copies");
                Cfg_CobIdCopy             <= Cfg_CobId;
                clocks(2);
                Exp_v                     := None_c;
                Exp_v.Rpdo                := '1';
                rx(0, canStd(DefIds_c(2), 2), Exp_v, "receive PDO 1 with equal copies again");

            -- *** Service enables and the NODE-ID ***
            elsif run("test_rx_enables") then
                Nmt_EnaSdo      <= '0';
                Nmt_EnaPdo      <= '0';
                Nmt_EnaSync     <= '0';
                clocks(2);
                rx(0, canStd(16#605#, 8), None_c, "SDO disabled");
                rx(0, canStd(DefIds_c(2), 2), None_c, "receive PDO disabled");
                rx(0, canStd(16#0F0#, 7), None_c, "Spacecraft Time PDO disabled");
                rx(0, canStd(16#080#, 0), None_c, "SYNC disabled");
                rx(0, nmt(1, NodeId_c), withNmt(0), "NMT passes");
                Exp_v           := None_c;
                Exp_v.RedHb(0)  := '1';
                rx(0, canStd(16#701#, 1), Exp_v, "master heartbeat passes");
                Nmt_EnaSdo      <= '1';
                Nmt_EnaPdo      <= '1';
                Nmt_EnaSync     <= '1';
                Nmt_NodeIdValid <= '0';
                clocks(2);
                rx(0, nmt(1, NodeId_c), None_c, "NODE-ID invalid: no NMT");
                rx(0, canStd(16#701#, 1), None_c, "NODE-ID invalid: no heartbeat");
                rx(0, canStd(DefIds_c(2), 2), None_c, "NODE-ID invalid: no receive PDO");
                N_v             := DutLog_v.count(2);

                for S in 0 to 6 loop
                    request(S);
                end loop;

                waitTx;
                check_value(DutLog_v.count(2), N_v, ERROR, "NODE-ID invalid: no frame sent");

                for S in 0 to 6 loop
                    check_value(CntAbort(S), 1, ERROR, "NODE-ID invalid: request " & integer'image(S) & " aborted");
                end loop;

            -- *** Events of both buses in the same cycle ***
            elsif run("test_rx_both_buses") then
                Exp_v           := withNmt(0);
                Exp_v.RedHb(1)  := '1';
                rxCycle('1', nmt(1, NodeId_c), '1', canStd(16#701#, 1), Exp_v, "NMT on A, heartbeat on B");
                Exp_v           := None_c;
                Exp_v.Rpdo      := '1';
                Exp_v.RedNmt(1) := '1';
                rxCycle('1', canStd(DefIds_c(3), 3), '1', nmt(1, 0), Exp_v, "PDO on A, NMT on B");
                Exp_v           := None_c;
                Exp_v.RedHb     := "11";
                rxCycle('1', canStd(16#701#, 1), '1', canStd(16#701#, 1), Exp_v, "heartbeats on both buses");
                Exp_v           := None_c;
                Exp_v.Sync      := '1';
                rxCycle('1', canStd(16#080#, 0), '1', canStd(16#605#, 8), Exp_v, "SYNC on A, SDO on B: SDO not passed");
                Red_ActiveBus   <= '1';
                clocks(1);
                Exp_v           := None_c;
                Exp_v.Sdo       := '1';
                rxCycle('1', canStd(16#080#, 0), '1', canStd(16#605#, 8), Exp_v, "bus B active: SDO passed");

            -- *** Held NMT message of the inactive bus ***
            elsif run("test_held_nmt") then
                Red_Selecting   <= '1';
                clocks(1);
                Exp_v           := None_c;
                Exp_v.RedNmt(1) := '1';
                rxCycle('1', canStd(DefIds_c(2), 2), '1', nmt(1, NodeId_c), Exp_v, "NMT of the inactive bus held");
                Exp_v           := None_c;
                Exp_v.RedHb(0)  := '1';
                rx(0, canStd(16#701#, 1), Exp_v, "held: only the per-bus event");
                rx(0, canStd(DefIds_c(2), 2), None_c, "held: no receive PDO of bus A");
                rx(1, canStd(DefIds_c(2), 2), None_c, "held: no receive PDO of bus B");
                -- The active bus changes to bus B: the held message is passed one cycle later
                wait until rising_edge(Clk);
                Red_ActiveBus <= '1';
                wait until rising_edge(Clk);
                wait for 1 ns;
                check_value(RxNmt_Valid, '1', ERROR, "held NMT message passed in the cycle after the change");
                check_value(RxNmt_Cs, x"01", ERROR, "held command specifier");
                Exp_v         := None_c;
                Exp_v.Rpdo    := '1';
                rx(1, canStd(DefIds_c(2), 2), Exp_v, "frames of bus B pass again");
                -- Held, then the selection ends without a change of the bus: discarded
                rxCycle('0', canStd(0, 0), '0', canStd(0, 0), None_c, "idle");
                Exp_v           := None_c;
                Exp_v.RedNmt(0) := '1';
                rx(0, nmt(2, 0), Exp_v, "NMT of bus A (inactive) held");
                wait until rising_edge(Clk);
                Red_Selecting   <= '0';
                clocks(4);
                check_value(RxNmt_Valid, '0', ERROR, "discarded at the end of the selection");
                Exp_v           := None_c;
                Exp_v.Rpdo      := '1';
                rx(1, canStd(DefIds_c(2), 2), Exp_v, "not held any more");
                -- NMT messages on both buses in the same cycle: the active bus wins, nothing is held
                Red_Selecting <= '1';
                clocks(1);
                Exp_v         := withNmt(1);
                Exp_v.RedNmt  := "11";
                rxCycle('1', nmt(3, NodeId_c), '1', nmt(4, NodeId_c), Exp_v, "tie: active bus B");
                check_value(RxNmt_Cs, x"04", ERROR, "message of the active bus");
                Exp_v         := None_c;
                Exp_v.Rpdo    := '1';
                rx(1, canStd(DefIds_c(2), 2), Exp_v, "nothing held after the tie");

            -- *** Without SDO server ***
            elsif run("test_sdo_absent") then
                rx(0, canStd(16#605#, 8), None_c, "SDO request discarded");
                N_v := DutLog_v.count(2);
                request(5);
                waitTx;
                check_value(CntAbort(5), 1, ERROR, "SDO reply aborted");
                check_value(DutLog_v.count(2), N_v, ERROR, "no frame");

            -- *** Frames of every source and their completions ***
            elsif run("test_tx_frames") then

                for S in 0 to 6 loop
                    SrcDlc(S)  <= std_logic_vector(to_unsigned(S + 1, 4));
                    SrcData(S) <= std_logic_vector(to_unsigned(S + 1, 8)) & x"A1A2A3A4A5A6A7";
                end loop;

                for S in 0 to 6 loop
                    request(S);
                    waitTx;
                    E_v := DutLog_v.get(2, DutLog_v.count(2) - 1);
                    check_value(sourceOf(E_v.Frame.Id), S, ERROR, "identifier of source " & integer'image(S));
                    if S = 6 then
                        check_value(E_v.Frame.Dlc, 1, ERROR, "NMT error control DLC");
                        check_value(E_v.Frame.Data(63 downto 56), x"07", ERROR, "NMT error control data");
                    else
                        check_value(E_v.Frame.Dlc, S + 1, ERROR, "DLC of source " & integer'image(S));
                        -- The log keeps the bytes within the DLC
                        check_value(E_v.Frame.Data, canStd(0, S + 1, SrcData(S)).Data, ERROR,
                                    "data of source " & integer'image(S));
                    end if;

                    for T in 0 to 6 loop
                        if T = S then
                            check_value(CntDone(T), 1, ERROR, "done to source " & integer'image(T));
                        elsif T > S then
                            check_value(CntDone(T), 0, ERROR, "no done to source " & integer'image(T));
                        end if;
                    end loop;

                end loop;

                RespAbort <= true;
                request(2);
                waitTx;
                check_value(CntAbort(2), 1, ERROR, "aborted by the link: reported to the owner");
                check_value(CntDone(2), 1, ERROR, "no done");

            -- *** Round robin ***
            elsif run("test_tx_round_robin") then
                RespDone <= 1;
                N_v      := DutLog_v.count(2);

                for S in 0 to 6 loop
                    AutoReq(S) <= true;
                end loop;

                while DutLog_v.count(2) < N_v + 28 loop
                    wait until rising_edge(Clk);
                end loop;

                for S in 0 to 6 loop
                    AutoReq(S) <= false;
                end loop;

                waitTx;
                -- From the first complete round on, the order is cyclic: TPDO1 to TPDO4, LTP, SDO, NMT
                Order_v := sourceOf(DutLog_v.get(2, N_v + 7).Frame.Id);

                for I in N_v + 7 to N_v + 27 loop
                    check_value(sourceOf(DutLog_v.get(2, I).Frame.Id), (Order_v + I - N_v - 7) mod 7, ERROR,
                                "cyclic order at frame " & integer'image(I - N_v));
                end loop;

                -- Random requests: a pending request waits for at most one frame of each other source. The k-th
                -- request of a source (channel 3) belongs to its k-th frame (channel 2).
                DutLog_v.clear(2);
                DutLog_v.clear(3);
                RandomGap <= true;

                for S in 0 to 6 loop
                    AutoReq(S) <= true;
                end loop;

                while DutLog_v.count(2) < 300 loop
                    wait until rising_edge(Clk);
                end loop;

                for S in 0 to 6 loop
                    AutoReq(S) <= false;
                end loop;

                RandomGap <= false;
                waitTx;
                Base_v    := (others => 0);

                for I in 0 to DutLog_v.count(2) - 1 loop
                    E_v := DutLog_v.get(2, I);
                    N_v := sourceOf(E_v.Frame.Id);
                    -- Start of the request: the Base_v(N_v)-th request of the source
                    Order_v := 0;

                    for J in 0 to DutLog_v.count(3) - 1 loop
                        if to_integer(unsigned(DutLog_v.get(3, J).Frame.Id(28 downto 18))) = N_v then
                            if Order_v = Base_v(N_v) then
                                ReqT_v := DutLog_v.get(3, J).T;
                                exit;
                            end if;
                            Order_v := Order_v + 1;
                        end if;
                    end loop;

                    Base_v(N_v) := Base_v(N_v) + 1;

                    -- Frames of every other source between the start of the request and this frame
                    for S in 0 to 6 loop
                        if S /= N_v then
                            Order_v := 0;

                            for K in 0 to I - 1 loop
                                if DutLog_v.get(2, K).T > ReqT_v and sourceOf(DutLog_v.get(2, K).Frame.Id) = S then
                                    Order_v := Order_v + 1;
                                end if;
                            end loop;

                            if Order_v > 1 then
                                alert(ERROR, "frame " & integer'image(I) & " of source " & integer'image(N_v) &
                                      " waited for " & integer'image(Order_v) & " frames of source " &
                                      integer'image(S));
                            end if;
                        end if;
                    end loop;

                end loop;

                log(ID_SEQUENCER, "bound checked for " & integer'image(DutLog_v.count(2)) & " frames");

            -- *** Reject, withdraw and abort ***
            elsif run("test_tx_reject") then
                N_v             := DutLog_v.count(2);
                Nmt_EnaPdo      <= '0';
                clocks(1);
                request(0);
                clocks(4);
                check_value(CntAbort(0), 1, ERROR, "transmit PDO without the PDO enable: aborted");
                Nmt_EnaPdo      <= '1';
                Ids_v           := DefIds_c;
                setCfg(Ids_v, "110111111111");
                request(3);
                clocks(4);
                check_value(CntAbort(3), 1, ERROR, "transmit PDO 4 without a valid COB-ID: aborted");
                setCfg(Ids_v);
                Nmt_NodeIdValid <= '0';
                clocks(1);
                request(6);
                clocks(4);
                check_value(CntAbort(6), 1, ERROR, "NMT error control without a valid NODE-ID: aborted");
                Nmt_NodeIdValid <= '1';
                check_value(DutLog_v.count(2), N_v, ERROR, "no frame of a rejected request");
                -- Withdraw in Send_s: the link does not take the frame
                RespReady  <= 50;
                request(0);
                wait until rising_edge(Clk) and LinkTx_Valid = '1';
                clocks(5);
                Nmt_EnaPdo <= '0';
                clocks(4);
                check_value(LinkTx_Valid, '0', ERROR, "frame withdrawn");
                check_value(CntAbort(0), 2, ERROR, "withdrawn frame aborted");
                Nmt_EnaPdo <= '1';
                RespReady  <= 0;
                clocks(60);
                check_value(DutLog_v.count(2), N_v, ERROR, "the withdrawn frame was not taken");
                -- Abort in Wait_s: one abort request, completion as reported by the link
                RespDone   <= 100;
                request(1);
                wait until rising_edge(Clk) and LinkTx_Ready = '1';
                clocks(10);
                N_v        := CntAbortRq;
                Nmt_EnaPdo <= '0';
                clocks(20);
                check_value(CntAbortRq, N_v + 1, ERROR, "one abort request");
                waitTx;
                check_value(CntAbort(1), 1, ERROR, "aborted frame reported");
                check_value(CntDone(1), 0, ERROR, "no done");
                Nmt_EnaPdo <= '1';

            -- *** Free COB-IDs in transmission ***
            elsif run("test_tx_free_range") then
                Ids_v     := DefIds_c;
                Ids_v(6)  := 16#7F0#;
                Ids_v(10) := 16#781#;
                setCfg(Ids_v);
                N_v       := DutLog_v.count(2);
                request(0);
                request(4);
                waitTx;
                check_value(CntAbort(0), 1, ERROR, "transmit PDO 1 at a free COB-ID: aborted");
                check_value(CntAbort(4), 1, ERROR, "Local Time PDO at a free COB-ID: aborted");
                check_value(DutLog_v.count(2), N_v, ERROR, "no frame at a free COB-ID");

            -- *** COB-ID copies ***
            elsif run("test_cob_id_copies") then

                for E in 0 to 11 loop
                    N_v                       := 0;
                    wait until rising_edge(Clk);
                    Cfg_CobIdCopy(12 * E + 3) <= not Cfg_CobId(12 * E + 3);

                    for I in 1 to 6 loop
                        wait until rising_edge(Clk);
                        if Err_CobId = '1' then
                            N_v := N_v + 1;
                        end if;
                    end loop;

                    check_value(N_v, 1, ERROR, "one event for entry " & integer'image(E));
                    check_value(Stat_CobIdMismatch(E), '1', ERROR, "mismatch state of entry " & integer'image(E));
                    if E >= 2 and E <= 5 then
                        rx(0, canStd(DefIds_c(E), 2), None_c, "unequal copies: receive PDO not passed");
                    elsif E >= 6 and E <= 9 then
                        request(E - 6);
                        clocks(4);
                        check_value(CntAbort(E - 6), 1, ERROR, "unequal copies: transmit PDO aborted");
                    end if;
                    Cfg_CobIdCopy <= Cfg_CobId;
                    clocks(3);
                    check_value(Stat_CobIdMismatch(E), '0', ERROR, "copies equal again");
                end loop;

            -- *** A request while the own frame is awaited: no grant in the cycle of the completion event ***
            elsif run("test_tx_completion_grant") then

                for K in 0 to 1 loop
                    RespAbort <= K = 1;

                    for I in 0 to 2 loop
                        if I = 0 then
                            N_v := 0;
                        elsif I = 1 then
                            N_v := 5;
                        else
                            N_v := 6;
                        end if;
                        -- Two requests in a row: the second waits while the first frame is awaited
                        request(N_v);
                        request(N_v);
                        Order_v := 0;

                        loop
                            wait until falling_edge(Clk);
                            Order_v := Order_v + 1;
                            exit when SrcDone(N_v) = '1' or SrcAbort(N_v) = '1' or Order_v > 200;
                        end loop;

                        check_value(SrcDone(N_v) = '1' or SrcAbort(N_v) = '1', ERROR, "completion event of the first frame");
                        check_value(SrcReady(N_v), '0', ERROR, "no grant in the cycle of the own completion event");
                        wait until falling_edge(Clk);
                        check_value(SrcReady(N_v), '1', ERROR, "grant one cycle after the completion event");
                        waitTx;
                    end loop;

                end loop;

            -- *** Absent objects for the generics ***
            elsif run("test_generics") then

                for N in 0 to 3 loop
                    if N < NumRpdo_g then
                        Exp_v      := None_c;
                        Exp_v.Rpdo := '1';
                    else
                        Exp_v := None_c;
                    end if;
                    rx(0, canStd(DefIds_c(2 + N), 2), Exp_v, "receive PDO " & integer'image(N + 1));
                end loop;

                for N in 0 to 3 loop
                    request(N);
                    waitTx;
                    if N < NumTpdo_g then
                        check_value(CntDone(N), 1, ERROR, "transmit PDO " & integer'image(N + 1) & " sent");
                    else
                        check_value(CntAbort(N), 1, ERROR, "absent transmit PDO " & integer'image(N + 1) & " aborted");
                    end if;
                end loop;

                if TimePdos_g then
                    Exp_v      := None_c;
                    Exp_v.Time := '1';
                else
                    Exp_v := None_c;
                end if;
                rx(0, canStd(16#0F0#, 7), Exp_v, "Spacecraft Time PDO");
                request(4);
                waitTx;
                if TimePdos_g then
                    check_value(CntDone(4), 1, ERROR, "Local Time PDO sent");
                else
                    check_value(CntAbort(4), 1, ERROR, "absent Local Time PDO aborted");
                end if;

            end if;

        end loop;

        ocanTestEnd(runner);

    end process;

end architecture;
