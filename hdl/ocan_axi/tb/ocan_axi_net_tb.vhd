---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_axi: the test plays the software through the AXI-Lite VVC of UVVM (registers,
-- interrupt, mailbox), the CAN network model plays the NMT master, the Redundancy Master, the SYNC and time producer
-- and the peer of the PDOs and SDOs on bus A and bus B.
--
-- Documentation: hdl/ocan_axi/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ocan_regs_pkg.all;
    use work.ocan_tb_pkg.all;
    use work.ocan_tb_axi_pkg.all;
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_axi_net_tb is
    generic (
        runner_cfg   : string;
        BusAccess_g  : string               := "Selective";
        MinimalSet_g : boolean              := false;
        TimePdos_g   : boolean              := true;
        NumRpdo_g    : natural range 0 to 4 := 4;
        NumTpdo_g    : natural range 0 to 4 := 4;
        AutoEnable_g : boolean              := false;
        ErrInjRegs_g : boolean              := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_axi_net_tb is

    subtype Data_t is std_logic_vector(63 downto 0);
    subtype Word_t is std_logic_vector(31 downto 0);

    type Nat_a is array (0 to 3) of natural;

    constant Axi_c : natural := 0;

    constant NodeId_c   : natural := 5;
    constant HbId_c     : natural := 16#705#;
    constant MasterId_c : natural := 16#701#;
    constant SdoReqId_c : natural := 16#605#;
    constant SdoRspId_c : natural := 16#585#;
    constant SyncId_c   : natural := 16#080#;
    constant SctId_c    : natural := 16#0F0#;
    constant LtpId_c    : natural := 16#1F5#;
    constant RpdoId_c   : Nat_a   := (16#205#, 16#305#, 16#405#, 16#505#);
    constant TpdoId_c   : Nat_a   := (16#185#, 16#285#, 16#385#, 16#485#);

    -- NMT command specifier start ([CiA301] 7.2.8.3.1)
    constant Start_c : natural := 16#01#;

    -- NMT states in NODE.NMT_STATE
    constant StPreOp_c : natural := 1;
    constant StOp_c    : natural := 2;

    -- Bit timing of 1 Mbit/s at 50 MHz (2, 18, 6, 4); the reset value of the harness without AutoEnable_g is 500 kbit/s
    constant Timing_c : Word_t := x"46120002";

    -- Period of the master heartbeat; the consumer heartbeat time of the node is 10 ms
    constant MasterPeriod_c : time := 4 ms;

    function u8 (n : natural) return std_logic_vector is
        variable R_v : std_logic_vector(7 downto 0);
    begin
        R_v := std_logic_vector(to_unsigned(n, 8));
        return R_v;
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

    function muxOf (cmd : natural; idx : natural; sub : natural) return std_logic_vector is
        variable I_v : std_logic_vector(15 downto 0);
        variable R_v : std_logic_vector(31 downto 0);
    begin
        I_v := std_logic_vector(to_unsigned(idx, 16));
        R_v := u8(cmd) & I_v(7 downto 0) & I_v(15 downto 8) & u8(sub);
        return R_v;
    end function;

    function prescalerOf (auto : boolean) return positive is
    begin
        if auto then
            return 2;
        else
            return 4;
        end if;
    end function;

    signal Clk            : std_logic;
    signal Rst            : std_logic                    := '1';
    signal Irq            : std_logic;
    signal Pin_NodeId     : std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Pin_NodeIdCode : std_logic_vector(6 downto 0) := not std_logic_vector(to_unsigned(NodeId_c, 7));
    signal Bus_ForceDom   : std_logic_vector(1 downto 0) := "00";
    signal Bus_ForceRec   : std_logic_vector(1 downto 0) := "00";
    signal Bus_DutRec     : std_logic_vector(1 downto 0) := "00";
    signal Bus_Level      : std_logic_vector(1 downto 0);
    signal Can_TxEn       : std_logic_vector(1 downto 0);

    -- Master heartbeat of M1 of bus MasterBus while MasterOn
    signal MasterOn  : boolean              := false;
    signal MasterBus : natural range 0 to 1 := 0;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    i_th : entity work.ocan_axi_net_th
        generic map (
            BusAccess_g  => BusAccess_g,
            MinimalSet_g => MinimalSet_g,
            TimePdos_g   => TimePdos_g,
            NumRpdo_g    => NumRpdo_g,
            NumTpdo_g    => NumTpdo_g,
            AutoEnable_g => AutoEnable_g,
            Prescaler_g  => prescalerOf(AutoEnable_g),
            ErrInjRegs_g => ErrInjRegs_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Irq            => Irq,
            Pin_NodeId     => Pin_NodeId,
            Pin_NodeIdCode => Pin_NodeIdCode,
            Bus_ForceDom   => Bus_ForceDom,
            Bus_ForceRec   => Bus_ForceRec,
            Bus_DutRec     => Bus_DutRec,
            Bus_Level      => Bus_Level,
            Can_TxEn       => Can_TxEn
        );

    -----------------------------------------------------------------------------------------------
    -- Master heartbeat (state Operational) of M1 of the bus MasterBus
    -----------------------------------------------------------------------------------------------
    p_master : process is
    begin
        wait for MasterPeriod_c;
        if MasterOn and Net_v.txCount(2 * MasterBus) < 2 then
            Net_v.txPush(2 * MasterBus, canStd(MasterId_c, 1, x"0500000000000000"));
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer: the software of the processor system
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable M1_v : natural := 0;
        variable T_v  : time;
        variable D_v  : Word_t;
        variable E_v  : Word_t;
        variable R_v  : Data_t;
        variable I_v  : integer;
        variable L_v  : TbLog_t;
        variable N_v  : natural;
        variable Ok_v : boolean;

        procedure wr (addr : natural; data : Word_t) is
        begin
            regWrite(AXILITE_VVCT, Axi_c, addr, data);
        end procedure;

        procedure chk (addr : natural; data : Word_t; msg : string) is
        begin
            regCheck(AXILITE_VVCT, Axi_c, addr, data, msg);
        end procedure;

        procedure rd (addr : natural; data : out Word_t) is
        begin
            regRead(AXILITE_VVCT, Axi_c, addr, data);
        end procedure;

        -- Polls a register until (word and mask) = value, at most tmo
        procedure waitReg (addr : natural; mask : Word_t; value : Word_t; tmo : time; msg : string) is
            variable W_v : Word_t;
            variable T_v : time;
        begin
            T_v := now;

            loop
                rd(addr, W_v);
                exit when (W_v and mask) = value or now - T_v > tmo;
                wait for 20 us;
            end loop;

            check_value(W_v and mask, value, ERROR, msg);
        end procedure;

        procedure waitState (s : natural; tmo : time; msg : string) is
        begin
            waitReg(RegNode_c, x"00000003", std_logic_vector(to_unsigned(s, 32)), tmo, msg);
        end procedure;

        procedure waitIrq (tmo : time; msg : string) is
        begin
            if Irq /= '1' then
                wait until Irq = '1' for tmo;
            end if;
            check_value(Irq, '1', ERROR, msg);
        end procedure;

        -- Frames of the node with identifier id in the log of model node n after time t
        impure function firstFrame (n : natural; id : natural; t : time) return integer is
            variable E_v : TbLog_t;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    return I;
                end if;
            end loop;

            return -1;
        end function;

        impure function countFrames (n : natural; id : natural; t : time) return natural is
            variable E_v : TbLog_t;
            variable C_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and E_v.T > t and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = id then
                    C_v := C_v + 1;
                end if;
            end loop;

            return C_v;
        end function;

        procedure waitFrame (id : natural; t : time; tmo : time; idx : out integer) is
            variable W_v : time := 0 ns;
        begin
            idx := firstFrame(M1_v, id, t);

            while idx < 0 and W_v < tmo loop
                wait for 20 us;
                W_v := W_v + 20 us;
                idx := firstFrame(M1_v, id, t);
            end loop;

        end procedure;

        procedure send (id : natural; dlc : natural; d : Data_t := (others => '0')) is
        begin
            Net_v.txPush(M1_v, canStd(id, dlc, d));
        end procedure;

        procedure nmt (cs : natural) is
        begin
            send(0, 2, u8(cs) & u8(NodeId_c) & x"000000000000");
        end procedure;

        -- The software starts the node: bit timing and enable (also with AutoEnable_g), mailbox on. As a master
        -- does, M1 sends its first frame after the first frame of the node (boot-up message or heartbeat): only then
        -- has the controller joined the bus
        procedure startNode (start : boolean := true) is
            variable I_v : integer;
        begin
            MasterBus <= 0;
            MasterOn  <= true;
            M1_v      := 0;
            Rst       <= '1';
            wait for 103 ns;
            Rst       <= '0';
            wait for 1 us;
            wr(RegControl_c, x"00000000");
            wr(RegBitTiming_c, Timing_c);
            chk(RegBitTiming_c, Timing_c, "BIT_TIMING written while disabled");
            T_v       := now;
            wr(RegControl_c, x"00000003");
            waitFrame(HbId_c, T_v, 10 ms, I_v);
            check_value(I_v >= 0, ERROR, "first frame of the node after the enable");
            if MinimalSet_g then
                waitState(StOp_c, 10 ms, "Operational by local control");
            else
                waitState(StPreOp_c, 10 ms, "Pre-operational after the boot-up");
                if start then
                    nmt(Start_c);
                    waitState(StOp_c, 2 ms, "Operational after the start of M1");
                end if;
            end if;
        end procedure;

        -- An SDO request of M1 without waiting for the reply
        procedure sdoStart (req : Data_t) is
        begin
            T_v := now;
            send(SdoReqId_c, 8, req);
        end procedure;

        -- The reply of the last request, within tmo
        procedure sdoReply (rsp : out Data_t; ok : out boolean; tmo : time := 5 ms) is
            variable I_v : integer;
            variable E_v : TbLog_t;
        begin
            waitFrame(SdoRspId_c, T_v, tmo, I_v);
            ok  := I_v >= 0;
            rsp := (others => '0');
            if I_v >= 0 then
                E_v := Net_v.logGet(M1_v, I_v);
                rsp := E_v.Frame.Data;
            end if;
        end procedure;

        -- The software answers the request in the mailbox
        procedure appAnswer (data : Data_t; len : natural; abort : Word_t) is
        begin
            wr(RegAppRspHi_c, data(63 downto 32));
            wr(RegAppRspLo_c, data(31 downto 0));
            wr(RegAppRspLen_c, std_logic_vector(to_unsigned(len, 32)));
            wr(RegAppRspAbort_c, abort);
            wr(RegAppRspControl_c, x"00000001");
        end procedure;

        -- A CRC error at the receiver of the node: its receive line recessive at a dominant data bit of a frame of
        -- M2 of bus b
        procedure dutCrcError (b : natural; f : CanFrame_t) is
            variable W_v : CanBits_t;
            variable K_v : natural := 0;
        begin
            W_v := canStuff(canUnstuffed(f));

            for I in 22 to W_v.Len - 20 loop
                if K_v = 0 and W_v.Bits(I - 2 to I + 2) = "01010" and W_v.Stuff(I) = '0' then
                    K_v := I;
                end if;
            end loop;

            check_value(K_v > 0, TB_ERROR, "dominant data bit for the CRC error");

            loop
                wait until Bus_Level(b) = '0' for 20 us;
                exit when Bus_Level(b) = '1';
                wait until Bus_Level(b) = '1';
            end loop;

            Net_v.txPush(2 * b + 1, f);
            wait until Bus_Level(b) = '0' for 100 us;
            check_value(Bus_Level(b), '0', TB_ERROR, "start of the frame for the CRC error");
            wait for K_v * 1 us - 20 ns;
            Bus_DutRec(b) <= '1';
            wait for 1 us + 40 ns;
            Bus_DutRec(b) <= '0';
            wait for 1 ms;
        end procedure;

        constant NoData_c : Data_t := (others => '0');
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        shared_axilite_vvc_config(Axi_c).bfm_config.max_wait_cycles := 1000;

        while test_suite loop

            -- *** TC-AX-01: start-up by the software ***
            if run("test_startup") then
                log(ID_LOG_HDR, "The node waits for the software: bit timing, enable, boot-up, NMT start");
                MasterOn <= true;
                Rst      <= '1';
                wait for 103 ns;
                Rst      <= '0';
                T_v      := now;
                -- The generics of the core in GENERICS
                E_v               := (others => '0');
                E_v(26 downto 24) := "010";
                E_v(20 downto 16) := "11000";
                E_v(14 downto 12) := std_logic_vector(to_unsigned(NumTpdo_g, 3));
                E_v(10 downto 8)  := std_logic_vector(to_unsigned(NumRpdo_g, 3));
                E_v(4)            := '1' when ErrInjRegs_g else '0';
                E_v(3)            := '1';
                E_v(2)            := '1' when TimePdos_g else '0';
                E_v(1)            := '1' when MinimalSet_g else '0';
                E_v(0)            := '1' when BusAccess_g = "Parallel" else '0';
                chk(RegId_c, x"4F434101", "ID");
                chk(RegGenerics_c, E_v, "GENERICS of the core");
                chk(RegClkFrequency_c, std_logic_vector(to_unsigned(50000000, 32)), "CLK_FREQUENCY");
                chk(RegDominantLimit_c, std_logic_vector(to_unsigned(32, 32)), "DOMINANT_LIMIT");
                if AutoEnable_g then
                    -- The node starts without software
                    if MinimalSet_g then
                        waitState(StOp_c, 10 ms, "Operational by local control without software");
                    else
                        waitState(StPreOp_c, 10 ms, "Pre-operational without software");
                    end if;
                else
                    -- Without the software the node stays off the bus: no frame, no error at the model nodes, a
                    -- transmit error counter of 0
                    wait for 5 ms;
                    check_value(countFrames(M1_v, HbId_c, T_v), 0, ERROR, "no frame before the enable");
                    check_value(Net_v.count(0, TbCntErrors) + Net_v.count(1, TbCntErrors), 0, ERROR,
                                "no error on bus A before the enable");
                    rd(RegLinkA_c, D_v);
                    check_value(D_v(8 downto 0), "000000000", ERROR, "transmit error counter of controller A before the enable");
                    chk(RegControl_c, x"00000000", "CONTROL after the reset");
                    chk(RegBitTiming_c, x"46120004", "BIT_TIMING of the generics (500 kbit/s)");
                    wr(RegBitTiming_c, Timing_c);
                    T_v := now;
                    wr(RegControl_c, x"00000001");
                    if MinimalSet_g then
                        waitState(StOp_c, 10 ms, "Operational by local control");
                    else
                        waitFrame(HbId_c, T_v, 10 ms, I_v);
                        check_value(I_v >= 0, ERROR, "boot-up message after the enable");
                        if I_v >= 0 then
                            L_v := Net_v.logGet(M1_v, I_v);
                            check_value(L_v.Frame.Dlc, 1, ERROR, "boot-up message: DLC 1");
                            check_value(L_v.Frame.Data(63 downto 56), x"00", ERROR, "boot-up message: 00h");
                        end if;
                        waitState(StPreOp_c, 2 ms, "Pre-operational after the boot-up");
                        chk(RegNode_c, x"00008501", "NODE: NODE-ID 5 valid, Pre-operational, error register 0");
                        nmt(Start_c);
                        waitState(StOp_c, 2 ms, "Operational after the start of M1");
                    end if;
                    rd(RegEvents_c, D_v);
                    check_value(D_v(EventsResetComm_c), '1', ERROR, "RESET_COMM of the start-up");
                    rd(RegRedundancy_c, D_v);
                    check_value(D_v(RedundancyActiveBus_c), '0', ERROR, "active bus A");
                    waitReg(RegRedundancy_c, x"00000010", x"00000010", 10 ms, "master heartbeat present on bus A");
                end if;

            -- *** TC-AX-02: reset release ***
            elsif run("test_reset_release") then
                log(ID_LOG_HDR, "AXI accesses in the first cycles after the release and a frame at the release");
                MasterOn <= true;

                for k in 0 to 3 loop
                    Rst <= '1';
                    wait for 1 us;
                    -- A frame of M2 of bus A that is on the bus when the reset ends
                    Net_v.txPush(1, canStd(16#123#, 8, x"0102030405060708"));
                    wait until Bus_Level(0) = '0' for 100 us;
                    wait for k * 7 us + 13 ns;
                    -- A read and a write are queued before the release and start in its first cycles; the VVC drives
                    -- the read and the write channels independently, so the read back follows the completion
                    axilite_check(AXILITE_VVCT, Axi_c, to_unsigned(RegId_c, AxiAddrBits_c), x"4F434101",
                                  "ID read in the first cycles after the release");
                    axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(RegEventsIrqEn_c, AxiAddrBits_c), x"000003FF",
                                  "write in the first cycles after the release");
                    wait until rising_edge(Clk);
                    Rst <= '0';
                    await_completion(AXILITE_VVCT, Axi_c, 100 us);
                    chk(RegEventsIrqEn_c, x"000003FF", "EVENTS_IRQ_EN written in the first cycles after the release");
                    if not AutoEnable_g then
                        wr(RegBitTiming_c, Timing_c);
                        wr(RegControl_c, x"00000001");
                    end if;
                    -- The frame of M2 completes without an error, the node joins after it
                    wait for 300 us;
                    check_value(Net_v.count(1, TbCntErrors), 0, ERROR, "no error of the frame at the release");
                    if MinimalSet_g then
                        waitState(StOp_c, 10 ms, "Operational after the release");
                    else
                        waitState(StPreOp_c, 10 ms, "Pre-operational after the release");
                    end if;
                end loop;

            -- *** TC-AX-03: PDOs through the registers ***
            elsif run("test_pdo") then
                log(ID_LOG_HDR, "Receive PDOs with the interrupt, transmit PDOs by REQUEST, the SYNC flag");
                startNode;
                wr(RegPdoEventsIrqEn_c, x"0000000F");

                for n in 0 to NumRpdo_g - 1 loop
                    send(RpdoId_c(n), 8, mix(n, 1));
                    waitIrq(2 ms, "interrupt of the receive PDO");
                    chk(RegPdoEvents_c, std_logic_vector(to_unsigned(2 ** n, 32)), "RPDO_RECEIVED");
                    chk(RegRpdo1Hi_c + 8 * n, mix(n, 1)(63 downto 32), "RPDO HI: bytes 0 to 3 of the frame");
                    chk(RegRpdo1Lo_c + 8 * n, mix(n, 1)(31 downto 0), "RPDO LO: bytes 4 to 7 of the frame");
                    wr(RegPdoEvents_c, x"0000000F");
                    check_value(Irq, '0', ERROR, "interrupt after the clear");
                end loop;

                for n in 0 to NumTpdo_g - 1 loop
                    wr(RegTpdo1Hi_c + 8 * n, mix(n, 2)(63 downto 32));
                    wr(RegTpdo1Lo_c + 8 * n, mix(n, 2)(31 downto 0));
                    T_v := now;
                    wr(RegTpdoControl_c, std_logic_vector(to_unsigned(2 ** (8 + n), 32)));
                    waitFrame(TpdoId_c(n), T_v, 2 ms, I_v);
                    check_value(I_v >= 0, ERROR, "transmit PDO on the bus");
                    if I_v >= 0 then
                        L_v := Net_v.logGet(M1_v, I_v);
                        check_value(L_v.Frame.Dlc, 8, ERROR, "transmit PDO: DLC 8");
                        check_value(L_v.Frame.Data, mix(n, 2), ERROR, "transmit PDO: the bytes of TPDOn_HI, TPDOn_LO");
                    end if;
                    waitReg(RegPdoEvents_c, std_logic_vector(to_unsigned(2 ** (4 + n), 32)),
                            std_logic_vector(to_unsigned(2 ** (4 + n), 32)), 1 ms, "TPDO_SENT");
                end loop;

                send(SyncId_c, 0);
                waitReg(RegEvents_c, x"00000001", x"00000001", 2 ms, "SYNC flag");

            -- *** TC-AX-04: application objects through the mailbox ***
            elsif run("test_sdo_mailbox") then
                log(ID_LOG_HDR, "SDO access of 2100h and 2200h answered by the software through the mailbox");
                startNode(start => false);
                wr(RegEventsIrqEn_c, x"00000200");
                -- Download of one byte to 2100h sub-index 1
                sdoStart(muxOf(16#2F#, 16#2100#, 1) & x"AB000000");
                waitIrq(2 ms, "interrupt of the request");
                chk(RegAppReq_c, x"91012100", "APP_REQ: pending write of 1 byte to 2100h sub-index 1");
                rd(RegAppReqHi_c, D_v);
                rd(RegAppReqLo_c, E_v);
                log(ID_SEQUENCER, "write data: 0x" & to_hstring(D_v) & to_hstring(E_v));
                check_value(D_v & E_v, x"00000000000000AB", ERROR, "APP_REQ data: the byte in bits 7 to 0");
                wr(RegEvents_c, x"00000200");
                appAnswer(NoData_c, 0, x"00000000");
                sdoReply(R_v, Ok_v);
                check_value(Ok_v, ERROR, "download response");
                check_value(R_v(63 downto 56), x"60", ERROR, "download response 60h");
                -- Upload of 2100h sub-index 1: the software returns the byte
                sdoStart(muxOf(16#40#, 16#2100#, 1) & x"00000000");
                waitIrq(2 ms, "interrupt of the read request");
                chk(RegAppReq_c, x"80012100", "APP_REQ: pending read of 2100h sub-index 1");
                wr(RegEvents_c, x"00000200");
                appAnswer(x"00000000000000AB", 1, x"00000000");
                sdoReply(R_v, Ok_v);
                check_value(Ok_v, ERROR, "upload response");
                check_value(R_v(63 downto 56), x"4F", ERROR, "expedited upload of 1 byte");
                check_value(R_v(31 downto 24), x"AB", ERROR, "the byte of the software");
                -- The software refuses a write to 2200h sub-index 1 (read-only)
                sdoStart(muxOf(16#2F#, 16#2200#, 1) & x"55000000");
                waitIrq(2 ms, "interrupt of the refused request");
                wr(RegEvents_c, x"00000200");
                appAnswer(NoData_c, 0, x"06010002");
                sdoReply(R_v, Ok_v);
                check_value(Ok_v and R_v(63 downto 56) = x"80", ERROR, "SDO abort");
                check_value(R_v(31 downto 0), x"02000106", ERROR, "abort code 0601 0002h of the software");

            -- *** TC-AX-05: time ***
            elsif run("test_time") then
                log(ID_LOG_HDR, "Spacecraft Time PDO to TIME_COARSE and TIME_FINE, TIME_CONTROL.REQUEST to the Local Time PDO");
                startNode;
                -- Basic protocol (type 254): the time of the frame, fine bytes 0 to 2, coarse bytes 3 to 6
                send(SctId_c, 7, x"000080" & x"78563412" & x"00");
                waitReg(RegEvents_c, x"00000010", x"00000010", 2 ms, "TIME_SET flag");
                rd(RegTimeCoarse_c, D_v);
                rd(RegTimeFine_c, E_v);
                check_value(D_v, x"12345678", ERROR, "TIME_COARSE of the Spacecraft Time PDO");
                check_value(unsigned(E_v) >= x"00800000" and unsigned(E_v) < x"00C00000", ERROR,
                            "TIME_FINE after the set: 0x" & to_hstring(E_v));
                rd(RegNode_c, D_v);
                check_value(D_v(NodeTimeSet_c), '1', ERROR, "NODE.TIME_SET");
                T_v := now;
                wr(RegTimeControl_c, x"00000001");
                waitFrame(LtpId_c, T_v, 2 ms, I_v);
                check_value(I_v >= 0, ERROR, "Local Time PDO on request");
                if I_v >= 0 then
                    L_v := Net_v.logGet(M1_v, I_v);
                    check_value(L_v.Frame.Dlc, 7, ERROR, "Local Time PDO: DLC 7");
                    check_value(L_v.Frame.Data(39 downto 8), x"78563412", ERROR,
                                "Local Time PDO: the coarse time in bytes 3 to 6, least significant byte first");
                end if;

            -- *** TC-AX-06: bus monitoring and link errors ***
            elsif run("test_monitoring") then
                log(ID_LOG_HDR, "Master heartbeat lost, bus toggling, link errors in flags, counters and LINK_A");
                startNode;
                wr(RegErrorsIrqEn_c, x"00000008");
                -- A CRC error at the receiver of controller A
                dutCrcError(0, canStd(16#3A5#, 8, x"AAAA5555AAAA5555"));
                rd(RegLinkErrors_c, D_v);
                check_value(D_v(2), '1', ERROR, "LINK_ERRORS: CRC error of controller A");
                rd(RegLinkACounts0_c, D_v);
                check_value(unsigned(D_v(23 downto 16)) >= 1, ERROR, "LINK_A_COUNTS0: CRC errors");
                rd(RegLinkA_c, D_v);
                check_value(D_v(25 downto 24), "00", ERROR, "LINK_A: error active after one error");
                -- The master heartbeat stops: the node misses it and toggles the bus
                MasterOn <= false;
                waitIrq(30 ms, "interrupt of MASTER_HB_MISSING");
                rd(RegErrors_c, D_v);
                check_value(D_v(ErrorsMasterHbMissing_c), '1', ERROR, "MASTER_HB_MISSING");
                waitReg(RegRedundancy_c, x"00000001", x"00000001", 40 ms, "bus toggled to B");
                rd(RegRedundancy_c, D_v);
                check_value(unsigned(D_v(15 downto 8)) >= 1, ERROR, "Ctoggle counted");

            -- *** TC-AX-07: error injection through the registers ***
            elsif run("test_errinj") then
                log(ID_LOG_HDR, "Copy repair of a parameter, NODE-ID copy, dominant timeout and re-enable");
                startNode;
                wr(RegErrorsIrqEn_c, x"00000043");
                -- One bit of copy A of 1017h (bits 166 to 181: window 5, bit 6): repaired, PARAM_COPY
                wr(RegErrinjSelect_c, x"00000005");
                wr(RegErrinjMask0_c, x"00000040");
                wr(RegErrinjMask1_c, x"00000000");
                wr(RegErrinjControl_c, x"00000001");
                waitIrq(1 ms, "interrupt of PARAM_COPY");
                rd(RegErrors_c, D_v);
                check_value(D_v(ErrorsParamCopy_c), '1', ERROR, "PARAM_COPY after the upset of one copy");
                wr(RegErrors_c, x"0001FFFF");
                -- The heartbeat period stays 5 ms
                T_v := now;
                wait for 21 ms;
                N_v := countFrames(M1_v, HbId_c, T_v);
                check_value(N_v >= 4 and N_v <= 5, ERROR, "heartbeat period after the repair: " & integer'image(N_v));
                -- A bit of IdCopy: NODE_ID error and a new boot-up
                T_v := now;
                wr(RegErrinjSelect_c, x"00000100");
                wr(RegErrinjMask0_c, x"00000001");
                wr(RegErrinjControl_c, x"00000001");
                waitIrq(1 ms, "interrupt of NODE_ID");
                rd(RegErrors_c, D_v);
                check_value(D_v(ErrorsNodeId_c), '1', ERROR, "NODE_ID after the upset of a NODE-ID copy");
                waitFrame(HbId_c, T_v, 10 ms, I_v);
                check_value(I_v >= 0, ERROR, "boot-up after the reset communication");
                wr(RegErrors_c, x"0001FFFF");
                -- The transmit bit of controller A forced dominant: dominant timeout, then REENABLE_A
                wr(RegLinkErrorsIrqEn_c, x"00000020");
                wr(RegErrinjControl_c, x"00000100");
                waitIrq(2 ms, "interrupt of the dominant timeout");
                rd(RegLinkErrors_c, D_v);
                check_value(D_v(5), '1', ERROR, "LINK_ERRORS: dominant timeout of controller A");
                rd(RegLinkA_c, D_v);
                check_value(D_v(29), '1', ERROR, "LINK_A.DOM_TIMEOUT");
                wr(RegErrinjControl_c, x"00000000");
                wr(RegControl_c, x"00000203");
                waitReg(RegLinkA_c, x"20000000", x"00000000", 1 ms, "LINK_A.DOM_TIMEOUT after REENABLE_A");
            end if;

            await_completion(AXILITE_VVCT, Axi_c, 1 ms);
            MasterOn <= false;
            wait for 10 us;
        end loop;

        ocanTestEnd(runner);
    end process;

end architecture;
