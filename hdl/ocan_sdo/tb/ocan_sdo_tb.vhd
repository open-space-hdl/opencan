---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_sdo: the requests, the NMT inputs and the tick are driven cycle by cycle, a responder
-- answers the transmit handshake like ocan_dispatch, an object model answers the access interface like ocan_od
-- (objects of 0 to 9 bytes, delays in cycles or ticks, abort codes, the behaviour at the reset events), and a
-- reference model written from [CiA301] section 7.2.4 and the specification predicts every output in every cycle.
-- The tests compare the replies with frames written from [CiA301]. One run block per test case of the verification
-- plan.
--
-- Documentation: hdl/ocan_sdo/docs/verification_plan.md

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
entity ocan_sdo_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_sdo_tb is

    subtype Byte_t is std_logic_vector(7 downto 0);
    subtype Word_t is std_logic_vector(31 downto 0);
    subtype Frame_t is std_logic_vector(63 downto 0);
    subtype Value_t is std_logic_vector(63 downto 0);
    subtype Seg_t is std_logic_vector(55 downto 0);

    type Bytes_t is array (0 to 7) of Byte_t;

    constant Zero8_c  : Bytes_t := (others => x"00");
    constant NoSeg_c  : Seg_t   := (others => '0');
    constant NoWord_c : Word_t  := (others => '0');

    function u8 (n : natural) return Byte_t is
        variable R_v : Byte_t;
    begin
        R_v := std_logic_vector(to_unsigned(n, 8));
        return R_v;
    end function;

    function u32 (n : natural) return Word_t is
        variable R_v : Word_t;
    begin
        R_v := std_logic_vector(to_unsigned(n, 32));
        return R_v;
    end function;

    -- Frame of 8 bytes as ocan_dispatch passes it: byte 0 in bits 63 to 56
    function toFrame (b : Bytes_t) return Frame_t is
        variable F_v : Frame_t;
    begin

        for K in 0 to 7 loop
            F_v(63 - 8 * K downto 56 - 8 * K) := b(K);
        end loop;

        return F_v;
    end function;

    function bytesOf (f : Frame_t) return Bytes_t is
        variable B_v : Bytes_t;
    begin

        for K in 0 to 7 loop
            B_v(K) := f(63 - 8 * K downto 56 - 8 * K);
        end loop;

        return B_v;
    end function;

    -- Value of the access interface of ocan_od: byte k in bits 8 k + 7 downto 8 k (OD-IF-01)
    function toValue (b : Bytes_t) return Value_t is
        variable V_v : Value_t;
    begin

        for K in 0 to 7 loop
            V_v(8 * K + 7 downto 8 * K) := b(K);
        end loop;

        return V_v;
    end function;

    function bytesOfValue (d : Value_t) return Bytes_t is
        variable B_v : Bytes_t;
    begin

        for K in 0 to 7 loop
            B_v(K) := d(8 * K + 7 downto 8 * K);
        end loop;

        return B_v;
    end function;

    -- The first k bytes of a value, the others 0
    function firstBytes (d : Value_t; k : natural) return Value_t is
        variable V_v : Value_t := (others => '0');
    begin

        for J in 0 to 7 loop
            if J < k then
                V_v(8 * J + 7 downto 8 * J) := d(8 * J + 7 downto 8 * J);
            end if;
        end loop;

        return V_v;
    end function;

    -- Frame of [CiA301] 7.2.4.3 with a multiplexer: the command byte, the index (least significant byte first), the
    -- sub-index and 4 bytes, least significant byte first
    function muxFrame (cmd : natural; idx : std_logic_vector(15 downto 0); sub : Byte_t; d : Word_t) return Frame_t is
        variable B_v : Bytes_t;
        variable R_v : Frame_t;
    begin
        B_v(0) := u8(cmd);
        B_v(1) := idx(7 downto 0);
        B_v(2) := idx(15 downto 8);
        B_v(3) := sub;
        B_v(4) := d(7 downto 0);
        B_v(5) := d(15 downto 8);
        B_v(6) := d(23 downto 16);
        B_v(7) := d(31 downto 24);
        R_v    := toFrame(B_v);
        return R_v;
    end function;

    -- Frame of a segment: the command byte and bytes 1 to 7 (byte 1 in bits 55 to 48)
    function segFrame (cmd : natural; d : Seg_t) return Frame_t is
        variable F_v : Frame_t;
    begin
        F_v := u8(cmd) & d;
        return F_v;
    end function;

    -- Bytes 1 to k of a segment: bytes `first` to `first` + k - 1 of b; the others `fill`
    function segData (b : Bytes_t; first : natural; k : natural; fill : Byte_t := x"00") return Seg_t is
        variable S_v : Seg_t;
    begin

        for J in 0 to 6 loop
            if J < k and first + J <= 7 then
                S_v(55 - 8 * J downto 48 - 8 * J) := b(first + J);
            else
                S_v(55 - 8 * J downto 48 - 8 * J) := fill;
            end if;
        end loop;

        return S_v;
    end function;

    -- *** Requests of the client ([CiA301] 7.2.4.3) ***
    -- Initiate download, expedited with the size (e = 1, s = 1): 4 - n bytes
    function dlExp (idx : std_logic_vector(15 downto 0); sub : Byte_t; n : natural; d : Word_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#23# + 4 * n, idx, sub, d);
        return R_v;
    end function;

    -- Initiate download, expedited without the size (e = 1, s = 0)
    function dlExpNs (idx : std_logic_vector(15 downto 0); sub : Byte_t; d : Word_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#22#, idx, sub, d);
        return R_v;
    end function;

    -- Initiate download, segmented with the size (e = 0, s = 1)
    function dlInit (idx : std_logic_vector(15 downto 0); sub : Byte_t; size : Word_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#21#, idx, sub, size);
        return R_v;
    end function;

    -- Download segment with k data bytes (n = 7 - k)
    function dlSeg (t : natural; k : natural; c : natural; d : Seg_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := segFrame(16 * t + 2 * (7 - k) + c, d);
        return R_v;
    end function;

    function ulInit (idx : std_logic_vector(15 downto 0); sub : Byte_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#40#, idx, sub, NoWord_c);
        return R_v;
    end function;

    function ulSeg (t : natural) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := segFrame(16#60# + 16 * t, NoSeg_c);
        return R_v;
    end function;

    function abortReq (idx : std_logic_vector(15 downto 0); sub : Byte_t; code : Word_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#80#, idx, sub, code);
        return R_v;
    end function;

    -- *** Replies of the server ([CiA301] 7.2.4.3) ***
    function dlResp (idx : std_logic_vector(15 downto 0); sub : Byte_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#60#, idx, sub, NoWord_c);
        return R_v;
    end function;

    function dlSegResp (t : natural) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := segFrame(16#20# + 16 * t, NoSeg_c);
        return R_v;
    end function;

    -- Expedited initiate upload response with k bytes (e = 1, s = 1, n = 4 - k)
    function ulExpResp (idx : std_logic_vector(15 downto 0); sub : Byte_t; k : natural; d : Word_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#43# + 4 * (4 - k), idx, sub, d);
        return R_v;
    end function;

    -- Initiate upload response of a segmented upload (e = 0, s = 1) with the size
    function ulInitResp (idx : std_logic_vector(15 downto 0); sub : Byte_t; size : natural) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#41#, idx, sub, u32(size));
        return R_v;
    end function;

    -- Upload segment response with k data bytes (n = 7 - k)
    function ulSegResp (t : natural; k : natural; c : natural; d : Seg_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := segFrame(16 * t + 2 * (7 - k) + c, d);
        return R_v;
    end function;

    function abortResp (idx : std_logic_vector(15 downto 0); sub : Byte_t; code : Word_t) return Frame_t is
        variable R_v : Frame_t;
    begin
        R_v := muxFrame(16#80#, idx, sub, code);
        return R_v;
    end function;

    -- *** Objects of the object model ***
    type Obj_r is record
        Index : std_logic_vector(15 downto 0);
        Sub   : Byte_t;
        Size  : natural range 0 to 15; -- bytes of the data type; 0 and 9: the number of bytes of a read answer
        Init  : Value_t;               -- value after a load
        RdAb  : Word_t;                -- abort code of a read, 0: none
        WrAb  : Word_t;                -- abort code of a write, 0: none
        Dly   : positive;              -- cycles from the access to the answer; 1: an own object of ocan_od
        DlyTk : natural;               -- ticks from the access to the answer instead, 0: Dly
        Lost  : boolean;               -- the access is taken and never answered
    end record;

    type Obj_a is array (0 to 15) of Obj_r;

    type Val_a is array (0 to 15) of Value_t;

    function obj (
        idx  : std_logic_vector(15 downto 0);
        sub  : Byte_t;
        size : natural;
        init : Value_t;
        rdab : Word_t   := x"00000000";
        wrab : Word_t   := x"00000000";
        dly  : positive := 1) return Obj_r is
        variable O_v : Obj_r;
    begin
        O_v.Index := idx;
        O_v.Sub   := sub;
        O_v.Size  := size;
        O_v.Init  := init;
        O_v.RdAb  := rdab;
        O_v.WrAb  := wrab;
        O_v.Dly   := dly;
        O_v.DlyTk := 0;
        O_v.Lost  := false;
        return O_v;
    end function;

    -- An object with a delay above 1 cycle is served by the user logic through the application port of ocan_od
    constant Objects_c : Obj_a := (
        0  => obj(x"2000", x"01", 1, x"00000000000000A1"),
        1  => obj(x"2000", x"02", 2, x"000000000000B2A2"),
        2  => obj(x"2000", x"03", 3, x"0000000000C3B3A3"),
        3  => obj(x"2000", x"04", 4, x"00000000D4C4B4A4"),
        4  => obj(x"2001", x"01", 5, x"000000E5D5C5B5A5"),
        5  => obj(x"2001", x"02", 6, x"0000F6E6D6C6B6A6"),
        6  => obj(x"2001", x"03", 7, x"0017F7E7D7C7B7A7"),
        7  => obj(x"2001", x"04", 8, x"2818F8E8D8C8B8A8"),
        8  => obj(x"1000", x"00", 4, x"0000000080010191", wrab => x"06010002"),
        9  => obj(x"2002", x"00", 4, x"0000000012345678", rdab => x"06010001"),
        10 => obj(x"2003", x"00", 4, x"0000000039495969", dly => 20),
        11 => obj(x"2003", x"01", 8, x"7A6A5A4A3A2A1A0A", dly => 20),
        12 => obj(x"2004", x"00", 0, x"0000000000000000"),
        13 => obj(x"2004", x"01", 9, x"1B2B3B4B5B6B7B8B"),
        14 => obj(x"2005", x"00", 4, x"000000004C3C2C1C"),
        15 => obj(x"2005", x"01", 2, x"0000000000005D4D", wrab => x"06090030")
    );

    -- *** DUT signals ***
    signal Clk            : std_logic;
    signal Rst            : std_logic                    := '1';
    signal Tick_Ms        : std_logic                    := '0';
    signal Rx_Valid       : std_logic                    := '0';
    signal Rx_Dlc         : std_logic_vector(3 downto 0) := x"8";
    signal Rx_Data        : Frame_t                      := (others => '0');
    signal Tx_Valid       : std_logic;
    signal Tx_Ready       : std_logic;
    signal Tx_Dlc         : std_logic_vector(3 downto 0);
    signal Tx_Data        : Frame_t;
    signal Tx_Done        : std_logic;
    signal Tx_Aborted     : std_logic;
    signal Acc_Valid      : std_logic;
    signal Acc_Ready      : std_logic;
    signal Acc_Write      : std_logic;
    signal Acc_Index      : std_logic_vector(15 downto 0);
    signal Acc_Sub        : Byte_t;
    signal Acc_Data       : Value_t;
    signal Acc_Len        : std_logic_vector(3 downto 0);
    signal Rsp_Valid      : std_logic                    := '0';
    signal Rsp_Data       : Value_t                      := (others => '0');
    signal Rsp_Len        : std_logic_vector(3 downto 0) := (others => '0');
    signal Rsp_Abort      : Word_t                       := (others => '0');
    signal Nmt_EnaSdo     : std_logic                    := '1';
    signal Nmt_ResetApp   : std_logic                    := '0';
    signal Nmt_ResetComm  : std_logic                    := '0';
    signal Stat_Open      : std_logic;
    signal Err_RxDrop     : std_logic;
    signal Err_TxTimeout  : std_logic;
    signal Err_AccTimeout : std_logic;
    signal Evt_AbortTx    : std_logic;
    signal Evt_AbortRx    : std_logic;

    -- *** Cycle counter and tick generator (period TickPer cycles) ***
    signal Cyc     : natural  := 0;
    signal TickPer : positive := 16;

    -- *** Responder of the transmit handshake (behaviour of ocan_dispatch at its source port) ***
    signal RespHold  : boolean   := false; -- never take a reply
    signal RespRdy   : natural   := 0;     -- cycles of Tx_Valid before Tx_Ready
    signal RespCpl   : natural   := 3;     -- cycles from Tx_Ready to the completion, 0: no completion
    signal RespAbort : boolean   := false; -- complete with Tx_Aborted
    signal RespRej   : boolean   := false; -- reject path: Tx_Ready and Tx_Aborted together
    signal StrayDone : std_logic := '0';   -- completions driven by the test
    signal StrayAbt  : std_logic := '0';
    signal VCnt      : natural   := 0;
    signal Grant     : std_logic;
    signal RejNow    : std_logic;
    signal CplDone   : std_logic := '0';
    signal CplAbort  : std_logic := '0';
    signal RespBusy  : boolean   := false;

    type Data_a is array (0 to 8191) of Frame_t;

    signal TxCnt : natural := 0; -- replies taken (granted or rejected)
    signal TxLog : Data_a;

    -- *** Object model (behaviour of ocan_od at its access interface) ***
    signal ObjCfg    : Obj_a   := Objects_c;
    signal ObjLoad   : boolean := false; -- toggled by the test: every value set to Init
    signal ObjVal    : Val_a;
    signal AccRdyDly : natural := 0;     -- cycles of Acc_Valid before Acc_Ready
    signal AppBusy   : boolean := false; -- an access of the user logic outstanding: Acc_Ready '0'
    signal AccVCnt   : natural := 0;
    signal AccCnt    : natural := 0;     -- accesses taken

    -- *** Monitors ***
    signal CntDrop   : natural := 0;
    signal CntTmo    : natural := 0;
    signal CntAccTmo : natural := 0;
    signal CycAccTmo : natural := 0;     -- cycle of the last Err_AccTimeout
    signal CntAbTx   : natural := 0;
    signal CntAbRx   : natural := 0;
    signal CycRsp    : natural := 0;       -- last cycle with Rsp_Valid
    signal CycTx     : natural := 0;       -- first cycle of the last reply offered

    -- *** Reference model ***
    signal CheckEn     : boolean   := false;
    signal ModelIdle   : boolean   := true;
    signal ExpTxValid  : std_logic := '0';
    signal ExpTxData   : Frame_t   := (others => '0');
    signal ExpAccValid : std_logic := '0';
    signal ExpAccWrite : std_logic := '0';
    signal ExpAccIndex : std_logic_vector(15 downto 0);
    signal ExpAccSub   : Byte_t;
    signal ExpAccData  : Value_t;
    signal ExpAccLen   : std_logic_vector(3 downto 0);
    signal ExpOpen     : std_logic := '0';
    -- Err_RxDrop, Err_TxTimeout, Err_AccTimeout, Evt_AbortTx, Evt_AbortRx
    signal ExpEv       : std_logic_vector(4 downto 0) := (others => '0');

begin

    -- Simulated time: the random test takes about 10 ms
    test_runner_watchdog(runner, 100 ms);

    i_th : entity work.ocan_sdo_th
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Tick_Ms        => Tick_Ms,
            Rx_Valid       => Rx_Valid,
            Rx_Dlc         => Rx_Dlc,
            Rx_Data        => Rx_Data,
            Tx_Valid       => Tx_Valid,
            Tx_Ready       => Tx_Ready,
            Tx_Dlc         => Tx_Dlc,
            Tx_Data        => Tx_Data,
            Tx_Done        => Tx_Done,
            Tx_Aborted     => Tx_Aborted,
            Acc_Valid      => Acc_Valid,
            Acc_Ready      => Acc_Ready,
            Acc_Write      => Acc_Write,
            Acc_Index      => Acc_Index,
            Acc_Sub        => Acc_Sub,
            Acc_Data       => Acc_Data,
            Acc_Len        => Acc_Len,
            Rsp_Valid      => Rsp_Valid,
            Rsp_Data       => Rsp_Data,
            Rsp_Len        => Rsp_Len,
            Rsp_Abort      => Rsp_Abort,
            Nmt_EnaSdo     => Nmt_EnaSdo,
            Nmt_ResetApp   => Nmt_ResetApp,
            Nmt_ResetComm  => Nmt_ResetComm,
            Stat_Open      => Stat_Open,
            Err_RxDrop     => Err_RxDrop,
            Err_TxTimeout  => Err_TxTimeout,
            Err_AccTimeout => Err_AccTimeout,
            Evt_AbortTx    => Evt_AbortTx,
            Evt_AbortRx    => Evt_AbortRx
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
    -- Responder (one frame at a time, no grant in the cycle of a completion event, DS-TX-03)
    -----------------------------------------------------------------------------------------------
    Grant      <= '1' when Tx_Valid = '1' and not RespHold and not RespRej and not RespBusy and VCnt >= RespRdy and
                           CplDone = '0' and CplAbort = '0' else
                  '0';
    RejNow     <= '1' when Tx_Valid = '1' and not RespHold and RespRej and not RespBusy and VCnt >= RespRdy and
                           CplDone = '0' and CplAbort = '0' else
                  '0';
    Tx_Ready   <= Grant or RejNow;
    Tx_Done    <= CplDone or StrayDone;
    Tx_Aborted <= CplAbort or RejNow or StrayAbt;

    p_resp : process (Clk) is
        variable Left_v : integer := -1;
        variable Abt_v  : boolean := false;
    begin
        if rising_edge(Clk) then
            CplDone  <= '0';
            CplAbort <= '0';
            if Left_v > 0 then
                Left_v := Left_v - 1;
            end if;
            if Left_v = 0 then
                if Abt_v then
                    CplAbort <= '1';
                else
                    CplDone <= '1';
                end if;
                Left_v := -1;
            end if;
            if Tx_Valid = '1' and Tx_Ready = '1' then
                if TxCnt <= Data_a'high then
                    TxLog(TxCnt) <= Tx_Data;
                end if;
                TxCnt <= TxCnt + 1;
                VCnt  <= 0;
                if Grant = '1' and RespCpl > 0 then
                    Left_v := RespCpl - 1;
                    Abt_v  := RespAbort;
                    if Left_v = 0 then
                        if Abt_v then
                            CplAbort <= '1';
                        else
                            CplDone <= '1';
                        end if;
                        Left_v := -1;
                    end if;
                end if;
            elsif Tx_Valid = '1' then
                VCnt <= VCnt + 1;
            else
                VCnt <= 0;
            end if;
            RespBusy <= Left_v >= 0;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Object model: ocan_od at its access interface (OD-IF-01). An own object answers in the cycle after the
    -- access; an object of the user logic later, and a reset event ends its request without an answer (OD-RS-02);
    -- an access to it in the cycle of a reset event is answered with 0800 0022h. The checks of the number of bytes
    -- follow OD-WR-02.
    -----------------------------------------------------------------------------------------------
    Acc_Ready <= '1' when not AppBusy and AccVCnt >= AccRdyDly else '0';

    p_od : process (Clk) is
        variable Val_v   : Val_a;
        variable Load_v  : boolean := false;
        variable Pend_v  : boolean := false;
        variable Left_v  : natural := 0;
        variable InTk_v  : boolean := false;
        variable PData_v : Value_t;
        variable PLen_v  : natural;
        variable PAb_v   : Word_t;
        variable Own_v   : boolean := false;
        variable RstE_v  : boolean;
        variable I_v     : integer;
        variable Ix_v    : boolean;
        variable Len_v   : natural;
        variable Ab_v    : Word_t;
        variable D_v     : Value_t;
        variable N_v     : natural;
        variable App_v   : boolean;
    begin
        if rising_edge(Clk) then
            Rsp_Valid <= '0';
            RstE_v    := Nmt_ResetApp = '1' or Nmt_ResetComm = '1';
            if ObjLoad /= Load_v then

                for J in 0 to 15 loop
                    Val_v(J) := ObjCfg(J).Init;
                end loop;

                Load_v := ObjLoad;
            end if;

            -- The answer of the user logic
            if Pend_v then
                if RstE_v then
                    Pend_v := false;
                else
                    if not InTk_v or Tick_Ms = '1' then
                        Left_v := Left_v - 1;
                    end if;
                    if Left_v = 0 then
                        Rsp_Valid <= '1';
                        Rsp_Data  <= PData_v;
                        Rsp_Len   <= std_logic_vector(to_unsigned(PLen_v, 4));
                        Rsp_Abort <= PAb_v;
                        Pend_v    := false;
                    end if;
                end if;
            end if;

            -- An access
            if Acc_Valid = '1' and Acc_Ready = '1' then
                AccCnt <= AccCnt + 1;
                if Own_v then
                    alert(ERROR, "object model: an access in the cycle of the answer of the previous one");
                end if;
                I_v  := -1;
                Ix_v := false;

                for J in 0 to 15 loop
                    if ObjCfg(J).Index = Acc_Index then
                        Ix_v := true;
                        if ObjCfg(J).Sub = Acc_Sub then
                            I_v := J;
                        end if;
                    end if;
                end loop;

                D_v   := (others => '0');
                N_v   := 0;
                Ab_v  := (others => '0');
                App_v := false;
                if I_v < 0 then
                    if Ix_v then
                        Ab_v := x"06090011";
                    else
                        Ab_v := x"06020000";
                    end if;
                else
                    App_v := ObjCfg(I_v).Dly > 1 or ObjCfg(I_v).DlyTk > 0;
                    Len_v := to_integer(unsigned(Acc_Len));
                    if App_v and RstE_v then
                        Ab_v := x"08000022";
                    elsif Acc_Write = '1' then
                        if ObjCfg(I_v).WrAb /= x"00000000" then
                            Ab_v := ObjCfg(I_v).WrAb;
                        elsif Len_v /= 0 and Len_v > ObjCfg(I_v).Size then
                            Ab_v := x"06070012";
                        elsif Len_v /= 0 and Len_v < ObjCfg(I_v).Size then
                            Ab_v := x"06070013";
                        else
                            Val_v(I_v) := firstBytes(Acc_Data, ObjCfg(I_v).Size);
                        end if;
                    elsif ObjCfg(I_v).RdAb /= x"00000000" then
                        Ab_v := ObjCfg(I_v).RdAb;
                    else
                        D_v := firstBytes(Val_v(I_v), ObjCfg(I_v).Size);
                        N_v := ObjCfg(I_v).Size;
                    end if;
                end if;
                if I_v >= 0 and ObjCfg(I_v).Lost then
                    Own_v := false;
                elsif App_v and not RstE_v then
                    Pend_v := true;
                    InTk_v := ObjCfg(I_v).DlyTk > 0;
                    if InTk_v then
                        Left_v := ObjCfg(I_v).DlyTk;
                    else
                        Left_v := ObjCfg(I_v).Dly - 1;
                    end if;
                    PData_v := D_v;
                    PLen_v  := N_v;
                    PAb_v   := Ab_v;
                    Own_v   := false;
                else
                    Rsp_Valid <= '1';
                    Rsp_Data  <= D_v;
                    Rsp_Len   <= std_logic_vector(to_unsigned(N_v, 4));
                    Rsp_Abort <= Ab_v;
                    Own_v     := true;
                end if;
            else
                Own_v := false;
            end if;

            if Acc_Valid = '1' and Acc_Ready = '0' then
                AccVCnt <= AccVCnt + 1;
            else
                AccVCnt <= 0;
            end if;
            AppBusy <= Pend_v;
            ObjVal  <= Val_v;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------------------------
    p_mon : process (Clk) is
        variable TxV_v : std_logic := '0';
    begin
        if rising_edge(Clk) then
            if Err_RxDrop = '1' then
                CntDrop <= CntDrop + 1;
            end if;
            if Err_TxTimeout = '1' then
                CntTmo <= CntTmo + 1;
            end if;
            if Err_AccTimeout = '1' then
                CntAccTmo <= CntAccTmo + 1;
                CycAccTmo <= Cyc;
            end if;
            if Evt_AbortTx = '1' then
                CntAbTx <= CntAbTx + 1;
            end if;
            if Evt_AbortRx = '1' then
                CntAbRx <= CntAbRx + 1;
            end if;
            if Rsp_Valid = '1' then
                CycRsp <= Cyc;
            end if;
            if Tx_Valid = '1' and TxV_v = '0' then
                CycTx <= Cyc;
            end if;
            TxV_v := Tx_Valid;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Reference model of the server, written from [CiA301] 7.2.4.3 and the specification, with the timing of the
    -- architecture (section 7): a request is decoded in the cycle after its event, the reply follows the answer of
    -- the object dictionary by one cycle. The inputs of a cycle give the expectations of the next one.
    -----------------------------------------------------------------------------------------------
    p_model : process is
        type Open_t is (ONone, ODown, OUp);
        type Phase_t is (MFree, MAcc, MOffer, MAwait);
        type Use_t is (UDownExp, UDownLast, UUp);

        -- The open transfer (SD-RS-03)
        variable Open_v  : Open_t                        := ONone;
        variable OldO_v  : Open_t;
        variable MIdx_v  : std_logic_vector(15 downto 0) := (others => '0');
        variable MSub_v  : Byte_t                        := (others => '0');
        variable Tgl_v   : std_logic                     := '0';
        variable Size_v  : natural                       := 0;
        variable Cnt_v   : natural                       := 0;
        variable Buf_v   : Bytes_t                       := Zero8_c;
        -- The processing of one request (SD-PR-09)
        variable Ph_v    : Phase_t   := MFree;
        variable OldP_v  : Phase_t;
        variable Use_v   : Use_t     := UDownExp;
        variable LTgl_v  : std_logic := '0';
        variable Taken_v : boolean   := false;
        variable Drop_v  : boolean   := false;
        variable AccW_v  : std_logic := '0';
        variable AccD_v  : Bytes_t   := Zero8_c;
        variable AccL_v  : natural   := 0;
        variable Rep_v   : Bytes_t   := Zero8_c;
        variable Ticks_v : natural   := 0;
        -- Inputs of the cycle
        variable Ev_v    : std_logic_vector(4 downto 0);
        variable AccTk_v : natural := 0;
        variable B_v     : Bytes_t;
        variable Ccs_v   : natural;
        variable Stop_v  : boolean;
        variable RstE_v  : boolean;
        variable Quit_v  : boolean;
        variable K_v     : natural;
        variable L_v     : natural;
        variable S_v     : unsigned(31 downto 0);
        variable C_v     : std_logic;
        variable T_v     : std_logic;
        variable D_v     : Bytes_t;

        -- Abort transfer ([CiA301] 7.2.4.3.17)
        procedure abortReply (idx : std_logic_vector(15 downto 0); sub : Byte_t; code : Word_t) is
        begin
            Rep_v := bytesOf(muxFrame(16#80#, idx, sub, code));
        end procedure;

        -- A request with a DLC of 8 or more while no request is processed
        procedure request is
        begin
            Taken_v := false;
            Drop_v  := false;
            AccTk_v := 0;
            Ph_v    := MOffer;

            case Ccs_v is

                when 1 =>
                    -- Initiate download (7.2.4.3.3), which ends an open transfer (SD-PR-06)
                    Open_v := ONone;
                    MIdx_v := B_v(2) & B_v(1);
                    MSub_v := B_v(3);
                    if B_v(0)(1) = '1' then
                        -- Expedited: 4 - n bytes with s = 1, the number not indicated with s = 0 (SD-DL-01)
                        AccW_v := '1';
                        AccD_v := Zero8_c;

                        for J in 0 to 3 loop
                            AccD_v(J) := B_v(4 + J);
                        end loop;

                        if B_v(0)(0) = '1' then
                            AccL_v := 4 - to_integer(unsigned(B_v(0)(3 downto 2)));
                        else
                            AccL_v := 0;
                        end if;
                        Use_v := UDownExp;
                        Ph_v  := MAcc;
                    else
                        -- Segmented, with the size in bytes 4 to 7 (SD-DL-02)
                        S_v := unsigned(Word_t'(B_v(7) & B_v(6) & B_v(5) & B_v(4)));
                        if B_v(0)(0) = '0' or S_v = 0 then
                            abortReply(MIdx_v, MSub_v, x"06070010");
                        elsif S_v > 8 then
                            abortReply(MIdx_v, MSub_v, x"06070012");
                        else
                            Open_v := ODown;
                            Tgl_v  := '0';
                            Cnt_v  := 0;
                            Size_v := to_integer(S_v);
                            Buf_v  := Zero8_c;
                            Rep_v  := bytesOf(muxFrame(16#60#, MIdx_v, MSub_v, NoWord_c));
                        end if;
                    end if;

                when 0 =>
                    -- Download segment (7.2.4.3.4): 000t nnnc, 7 - n bytes (SD-DL-03, SD-DL-04)
                    T_v := B_v(0)(4);
                    K_v := 7 - to_integer(unsigned(B_v(0)(3 downto 1)));
                    C_v := B_v(0)(0);
                    if Open_v = ONone then
                        abortReply(x"0000", x"00", x"05040001");
                    elsif Open_v = OUp then
                        abortReply(MIdx_v, MSub_v, x"05040001");
                        Open_v := ONone;
                    elsif T_v /= Tgl_v then
                        abortReply(MIdx_v, MSub_v, x"05030000");
                        Open_v := ONone;
                    elsif Cnt_v + K_v > 8 then
                        abortReply(MIdx_v, MSub_v, x"05040005");
                        Open_v := ONone;
                    else

                        for J in 0 to 6 loop
                            if J < K_v then
                                Buf_v(Cnt_v + J) := B_v(1 + J);
                            end if;
                        end loop;

                        Cnt_v := Cnt_v + K_v;
                        Tgl_v := not Tgl_v;
                        if C_v = '0' then
                            Rep_v    := Zero8_c;
                            Rep_v(0) := "001" & T_v & "0000";
                        else
                            Open_v := ONone;
                            if Cnt_v /= Size_v then
                                abortReply(MIdx_v, MSub_v, x"06070010");
                            else
                                AccW_v := '1';
                                AccD_v := Buf_v;
                                AccL_v := Cnt_v;
                                Use_v  := UDownLast;
                                LTgl_v := T_v;
                                Ph_v   := MAcc;
                            end if;
                        end if;
                    end if;

                when 2 =>
                    -- Initiate upload (7.2.4.3.6), which ends an open transfer (SD-PR-06)
                    Open_v := ONone;
                    MIdx_v := B_v(2) & B_v(1);
                    MSub_v := B_v(3);
                    AccW_v := '0';
                    AccD_v := Zero8_c;
                    AccL_v := 0;
                    Use_v  := UUp;
                    Ph_v   := MAcc;

                when 3 =>
                    -- Upload segment (7.2.4.3.7): 011t xxxx (SD-UL-02)
                    T_v := B_v(0)(4);
                    if Open_v = ONone then
                        abortReply(x"0000", x"00", x"05040001");
                    elsif Open_v = ODown then
                        abortReply(MIdx_v, MSub_v, x"05040001");
                        Open_v := ONone;
                    elsif T_v /= Tgl_v then
                        abortReply(MIdx_v, MSub_v, x"05030000");
                        Open_v := ONone;
                    else
                        K_v := Size_v - Cnt_v;
                        if K_v > 7 then
                            K_v := 7;
                        end if;
                        if Cnt_v + K_v = Size_v then
                            C_v := '1';
                        else
                            C_v := '0';
                        end if;
                        Rep_v    := Zero8_c;
                        Rep_v(0) := "000" & T_v & std_logic_vector(to_unsigned(7 - K_v, 3)) & C_v;

                        for J in 0 to 6 loop
                            if J < K_v then
                                Rep_v(1 + J) := Buf_v(Cnt_v + J);
                            end if;
                        end loop;

                        Cnt_v := Cnt_v + K_v;
                        Tgl_v := not Tgl_v;
                        if C_v = '1' then
                            Open_v := ONone;
                        end if;
                    end if;

                when others =>
                    -- Block transfer and command specifier 7 (SD-PR-03)
                    abortReply(B_v(2) & B_v(1), B_v(3), x"05040001");
                    Open_v := ONone;

            end case;

        end procedure;

        -- The answer of ocan_od (SD-DL-01, SD-DL-04, SD-UL-01)
        procedure answer is
        begin
            L_v  := to_integer(unsigned(Rsp_Len));
            D_v  := bytesOfValue(Rsp_Data);
            Ph_v := MOffer;
            if Rsp_Abort /= x"00000000" then
                abortReply(MIdx_v, MSub_v, Rsp_Abort);
            elsif Use_v = UDownExp then
                Rep_v := bytesOf(muxFrame(16#60#, MIdx_v, MSub_v, NoWord_c));
            elsif Use_v = UDownLast then
                Rep_v    := Zero8_c;
                Rep_v(0) := "001" & LTgl_v & "0000";
            elsif L_v = 0 or L_v > 8 then
                abortReply(MIdx_v, MSub_v, x"08000000");
            elsif L_v <= 4 then
                Rep_v := bytesOf(muxFrame(16#43# + 4 * (4 - L_v), MIdx_v, MSub_v, NoWord_c));

                for J in 0 to 3 loop
                    if J < L_v then
                        Rep_v(4 + J) := D_v(J);
                    end if;
                end loop;

            else
                Rep_v  := bytesOf(muxFrame(16#41#, MIdx_v, MSub_v, u32(L_v)));
                Open_v := OUp;
                Tgl_v  := '0';
                Cnt_v  := 0;
                Size_v := L_v;
                Buf_v  := D_v;
            end if;
        end procedure;

        variable TkNow_v : boolean;
    begin
        wait until rising_edge(Clk);
        Ev_v := "00000";
        if Rst = '1' then
            -- No transfer and no request in processing (SD-RS-04)
            Open_v  := ONone;
            Ph_v    := MFree;
            Taken_v := false;
            Drop_v  := false;
        else
            Stop_v := Nmt_EnaSdo = '0';
            RstE_v := Nmt_ResetApp = '1' or Nmt_ResetComm = '1';
            B_v    := bytesOf(Rx_Data);
            Ccs_v  := to_integer(unsigned(B_v(0)(7 downto 5)));
            -- The processing ends without a reply (SD-PR-09, SD-RS-01, SD-RS-02)
            Quit_v := (Rx_Valid = '1' and unsigned(Rx_Dlc) >= 8 and Ccs_v = 4) or Stop_v or RstE_v;
            OldO_v := Open_v;
            OldP_v := Ph_v;

            case Ph_v is

                when MAcc =>
                    -- The access is held until ocan_od takes it; its answer is not used after an abort or a stop,
                    -- and a reset event ends an outstanding request of ocan_od without an answer (OD-RS-02)
                    TkNow_v := not Taken_v and Acc_Ready = '1';
                    if Taken_v and Rsp_Valid = '1' then
                        if Drop_v or Quit_v then
                            Ph_v := MFree;
                        else
                            answer;
                        end if;
                    elsif RstE_v and not TkNow_v then
                        Ph_v := MFree;
                    elsif Quit_v then
                        Drop_v := true;
                    end if;
                    if TkNow_v then
                        Taken_v := true;
                    end if;
                    -- No answer within 512 ticks (SD-TX-04)
                    if Ph_v = MAcc and Tick_Ms = '1' then
                        AccTk_v := AccTk_v + 1;
                        if AccTk_v = 512 then
                            Ev_v(2) := '1';
                            if Drop_v or Quit_v then
                                Ph_v := MFree;
                            else
                                abortReply(MIdx_v, MSub_v, x"08000000");
                                Ph_v := MOffer;
                            end if;
                        end if;
                    end if;

                when MOffer =>
                    if Tx_Ready = '1' then
                        if Tx_Aborted = '1' then
                            -- Rejected: the transfer ends (SD-TX-03)
                            Ph_v   := MFree;
                            Open_v := ONone;
                        else
                            Ph_v    := MAwait;
                            Ticks_v := 0;
                        end if;
                    elsif Quit_v then
                        Ph_v := MFree;
                    end if;

                when MAwait =>
                    if Tx_Done = '1' then
                        Ph_v := MFree;
                        if Rep_v(0)(7 downto 5) = "100" then
                            Ev_v(1) := '1';
                        end if;
                    elsif Tx_Aborted = '1' then
                        Ph_v   := MFree;
                        Open_v := ONone;
                    elsif Tick_Ms = '1' then
                        -- 256 ticks without a completion (SD-TX-02)
                        Ticks_v := Ticks_v + 1;
                        if Ticks_v = 256 then
                            Ph_v    := MFree;
                            Ev_v(3) := '1';
                        end if;
                    end if;

                when MFree =>
                    null;

            end case;

            if Rx_Valid = '1' then
                if unsigned(Rx_Dlc) < 8 then
                    -- SD-PR-02
                    Ev_v(4) := '1';
                elsif Ccs_v = 4 then
                    -- SD-PR-07: ignored without a transfer and without a request in processing
                    if OldO_v /= ONone or OldP_v /= MFree then
                        Ev_v(0) := '1';
                    end if;
                    Open_v := ONone;
                elsif OldP_v /= MFree then
                    -- SD-PR-09
                    Ev_v(4) := '1';
                else
                    request;
                end if;
            end if;

            -- SD-RS-01, SD-RS-02
            if Stop_v or RstE_v then
                Open_v := ONone;
                if OldP_v /= MAcc then
                    Ph_v := MFree;
                end if;
            end if;
        end if;

        ModelIdle   <= Ph_v = MFree;
        ExpTxValid  <= '1' when Ph_v = MOffer else '0';
        ExpTxData   <= toFrame(Rep_v);
        ExpAccValid <= '1' when Ph_v = MAcc and not Taken_v else '0';
        ExpAccWrite <= AccW_v;
        ExpAccIndex <= MIdx_v;
        ExpAccSub   <= MSub_v;
        ExpAccData  <= toValue(AccD_v);
        ExpAccLen   <= std_logic_vector(to_unsigned(AccL_v, 4));
        ExpOpen     <= '0' when Open_v = ONone else '1';
        ExpEv       <= Ev_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Checkers in every cycle
    -----------------------------------------------------------------------------------------------
    p_check : process is
        variable Ev_v : std_logic_vector(4 downto 0);

        procedure cmp (dut : std_logic_vector; exp : std_logic_vector; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & to_hstring(dut) & ", reference model " & to_hstring(exp));
            end if;
        end procedure;

        procedure cmp (dut : std_logic; exp : std_logic; name : string) is
        begin
            if dut /= exp then
                alert(ERROR, name & " = " & std_logic'image(dut) & ", reference model " & std_logic'image(exp));
            end if;
        end procedure;

        constant Dlc8_c : std_logic_vector(3 downto 0) := "1000";
    begin
        wait until falling_edge(Clk);
        if CheckEn and Rst = '0' then
            cmp(Tx_Valid, ExpTxValid, "Tx_Valid");
            if Tx_Valid = '1' then
                cmp(Tx_Data, ExpTxData, "Tx_Data");
                cmp(Tx_Dlc, Dlc8_c, "Tx_Dlc");
            end if;
            cmp(Acc_Valid, ExpAccValid, "Acc_Valid");
            if Acc_Valid = '1' then
                cmp(Acc_Write, ExpAccWrite, "Acc_Write");
                cmp(Acc_Index, ExpAccIndex, "Acc_Index");
                cmp(Acc_Sub, ExpAccSub, "Acc_Sub");
                cmp(Acc_Data, ExpAccData, "Acc_Data");
                cmp(Acc_Len, ExpAccLen, "Acc_Len");
            end if;
            cmp(Stat_Open, ExpOpen, "Stat_Open");
            Ev_v := Err_RxDrop & Err_TxTimeout & Err_AccTimeout & Evt_AbortTx & Evt_AbortRx;
            cmp(Ev_v, ExpEv, "Err_RxDrop & Err_TxTimeout & Err_AccTimeout & Evt_AbortTx & Evt_AbortRx");
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable C0_v   : natural;
        variable C1_v   : natural;
        variable N_v    : natural;
        variable R_v    : natural;
        variable B_v    : Bytes_t;
        variable W_v    : Word_t;
        variable V_v    : Value_t;
        variable Obj_v  : natural;
        variable K_v    : natural;
        variable T_v    : natural;
        variable Cl_v   : natural;
        variable ClT_v  : natural;
        variable ClSz_v : natural;
        variable ClC_v  : natural;
        variable F_v    : Frame_t;
        variable Dlc_v  : natural;
        variable Seg_v  : boolean;
        variable SegK_v : natural;
        variable SegT_v : natural;
        variable Ini_v  : natural;
        variable IniS_v : natural;
        variable Idx_v  : std_logic_vector(15 downto 0);
        variable Sub_v  : Byte_t;

        type Nat_a is array (natural range <>) of natural;

        constant DlData_c : Nat_a(0 to 3) := (16#4C3D2E1F#, 16#7B3A6958#, 16#70E1D2C3#, 16#19283746#);

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

        procedure loadObjects is
        begin
            wait until rising_edge(Clk);
            ObjLoad <= not ObjLoad;
            clocks(2);
        end procedure;

        -- A request event in the current cycle, and in the next cycle
        procedure reqNow (f : Frame_t; dlc : natural := 8) is
        begin
            Rx_Valid <= '1';
            Rx_Dlc   <= std_logic_vector(to_unsigned(dlc, 4));
            Rx_Data  <= f;
            wait until rising_edge(Clk);
            Rx_Valid <= '0';
        end procedure;

        procedure req (f : Frame_t; dlc : natural := 8) is
        begin
            wait until rising_edge(Clk);
            reqNow(f, dlc);
        end procedure;

        -- Until the server is idle and the responder has completed
        procedure settle is
            variable N_v : natural := 0;
        begin
            clocks(2);

            while not ModelIdle or RespBusy or Tx_Valid = '1' or Acc_Valid = '1' loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                if N_v > 100000 then
                    alert(ERROR, "timeout: the server does not become idle");
                    exit;
                end if;
            end loop;

            clocks(2);
        end procedure;

        -- A request answered with the reply exp
        procedure transact (f : Frame_t; exp : Frame_t; msg : string; dlc : natural := 8) is
            variable N_v : natural;
        begin
            N_v := TxCnt;
            req(f, dlc);
            waitCnt(TxCnt, N_v + 1, 100000, msg & ": reply");
            if TxCnt > N_v then
                check_value(TxLog(N_v), exp, ERROR, msg);
            end if;
            settle;
        end procedure;

        -- A request without a reply
        procedure noReply (f : Frame_t; msg : string; dlc : natural := 8; n : natural := 40) is
            variable N_v : natural;
        begin
            N_v := TxCnt;
            req(f, dlc);
            clocks(n);
            check_value(TxCnt, N_v, ERROR, msg & ": no reply");
        end procedure;

        procedure checkObj (i : natural; val : Value_t; msg : string) is
        begin
            wait until falling_edge(Clk);
            check_value(ObjVal(i), val, ERROR, msg);
        end procedure;

        procedure checkOpen (exp : std_logic; msg : string) is
        begin
            wait until falling_edge(Clk);
            check_value(Stat_Open, exp, ERROR, msg);
        end procedure;

        -- An NMT event in the current cycle: 0 the SDO enable cleared for len cycles, 1 reset application, 2 reset
        -- communication
        procedure nmtNow (e : natural; len : natural := 3) is
        begin
            if e = 0 then
                Nmt_EnaSdo <= '0';
                clocks(len);
                Nmt_EnaSdo <= '1';
            elsif e = 1 then
                Nmt_ResetApp <= '1';
                clocks(1);
                Nmt_ResetApp <= '0';
            else
                Nmt_ResetComm <= '1';
                clocks(1);
                Nmt_ResetComm <= '0';
            end if;
        end procedure;

        procedure nmtEvent (e : natural; len : natural := 3) is
        begin
            wait until rising_edge(Clk);
            nmtNow(e, len);
        end procedure;

        -- A completion while no reply is outstanding
        procedure stray (abt : boolean) is
        begin
            wait until rising_edge(Clk);
            if abt then
                StrayAbt <= '1';
            else
                StrayDone <= '1';
            end if;
            wait until rising_edge(Clk);
            StrayAbt  <= '0';
            StrayDone <= '0';
        end procedure;

        -- Segmented download of the first bytes of val in segments of plan(j) bytes; abt: the abort code expected at
        -- the last segment, 0: success
        procedure segDownload (
            idx  : std_logic_vector(15 downto 0);
            sub  : Byte_t;
            val  : Value_t;
            plan : integer_vector;
            msg  : string;
            abt  : Word_t := x"00000000") is
            variable B_v  : Bytes_t;
            variable P_v  : natural := 0;
            variable Sz_v : natural := 0;
            variable T_v  : natural := 0;
            variable C_v  : natural;
        begin

            for J in plan'range loop
                Sz_v := Sz_v + plan(J);
            end loop;

            B_v := bytesOfValue(val);
            transact(dlInit(idx, sub, u32(Sz_v)), dlResp(idx, sub), msg & ": initiate");

            for J in plan'range loop
                if J = plan'high then
                    C_v := 1;
                else
                    C_v := 0;
                end if;
                if C_v = 1 and abt /= x"00000000" then
                    transact(dlSeg(T_v, plan(J), C_v, segData(B_v, P_v, plan(J))), abortResp(idx, sub, abt),
                             msg & ": last segment");
                else
                    transact(dlSeg(T_v, plan(J), C_v, segData(B_v, P_v, plan(J))), dlSegResp(T_v),
                             msg & ": segment " & to_string(J));
                end if;
                P_v := P_v + plan(J);
                T_v := 1 - T_v;
            end loop;

        end procedure;

        -- Segmented upload of object i of the defaults (5 to 8 bytes)
        procedure segUpload (
            idx  : std_logic_vector(15 downto 0);
            sub  : Byte_t;
            val  : Value_t;
            size : natural;
            msg  : string) is
            variable B_v : Bytes_t;
        begin
            B_v := bytesOfValue(val);
            transact(ulInit(idx, sub), ulInitResp(idx, sub, size), msg & ": initiate");
            if size <= 7 then
                transact(ulSeg(0), ulSegResp(0, size, 1, segData(B_v, 0, size)), msg & ": segment");
            else
                transact(ulSeg(0), ulSegResp(0, 7, 0, segData(B_v, 0, 7)), msg & ": first segment");
                transact(ulSeg(1), ulSegResp(1, size - 7, 1, segData(B_v, 7, size - 7)), msg & ": last segment");
            end if;
        end procedure;

        function nmtName (e : natural) return string is
        begin
            if e = 0 then
                return "SDO enable cleared";
            elsif e = 1 then
                return "reset application";
            else
                return "reset communication";
            end if;
        end function;

        constant RdyDelays_c  : integer_vector := (0, 1, 7, 50);
        constant AbortCodes_c : Nat_a(0 to 3)  := (16#06090030#, 16#06010002#, 16#08000020#, 16#06040047#);
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            -- Defaults of every test
            CheckEn       <= false;
            TickPer       <= 16;
            RespHold      <= false;
            RespRdy       <= 0;
            RespCpl       <= 3;
            RespAbort     <= false;
            RespRej       <= false;
            StrayDone     <= '0';
            StrayAbt      <= '0';
            Rx_Valid      <= '0';
            Rx_Dlc        <= x"8";
            Nmt_EnaSdo    <= '1';
            Nmt_ResetApp  <= '0';
            Nmt_ResetComm <= '0';
            ObjCfg        <= Objects_c;
            AccRdyDly     <= 0;
            loadObjects;
            doReset;
            clocks(2);
            CheckEn       <= true;

            -- *** TC-SD-01: expedited download ***
            if run("test_expedited_download") then

                -- s = 1, n = 0 to 3: 4 - n bytes to the objects of 4 - n bytes
                for N in 0 to 3 loop
                    W_v := u32(DlData_c(N));
                    transact(dlExp(x"2000", u8(4 - N), N, W_v), dlResp(x"2000", u8(4 - N)),
                             "expedited download, n = " & to_string(N));
                    checkObj(3 - N, firstBytes(x"00000000" & W_v, 4 - N), "value after the download, n = " & to_string(N));
                end loop;

                -- s = 0: the number of bytes not indicated, the size of the data type is taken
                for S in 1 to 4 loop
                    W_v := u32(DlData_c(S - 1)) xor x"FFFFFFFF";
                    transact(dlExpNs(x"2000", u8(S), W_v), dlResp(x"2000", u8(S)),
                             "expedited download, s = 0, " & to_string(S) & " bytes");
                    checkObj(S - 1, firstBytes(x"00000000" & W_v, S), "value after the download with s = 0");
                end loop;

                -- The abort codes of the object model passed on
                transact(dlExp(x"2000", x"02", 0, x"11223344"), abortResp(x"2000", x"02", x"06070012"),
                         "4 bytes to an object of 2 bytes");
                transact(dlExp(x"2000", x"04", 3, x"11223344"), abortResp(x"2000", x"04", x"06070013"),
                         "1 byte to an object of 4 bytes");
                transact(dlExp(x"1000", x"00", 0, x"11223344"), abortResp(x"1000", x"00", x"06010002"),
                         "read-only object");
                transact(dlExp(x"3000", x"00", 0, x"11223344"), abortResp(x"3000", x"00", x"06020000"),
                         "absent object");
                transact(dlExp(x"2000", x"09", 0, x"11223344"), abortResp(x"2000", x"09", x"06090011"),
                         "absent sub-index");
                transact(dlExpNs(x"2005", x"01", x"11223344"), abortResp(x"2005", x"01", x"06090030"),
                         "value range of the object exceeded");
                checkObj(1, firstBytes(x"00000000" & (u32(DlData_c(1)) xor x"FFFFFFFF"), 2),
                         "object of 2 bytes unchanged by the refused write");
                checkObj(15, Objects_c(15).Init, "object 2005h sub-index 01h unchanged");

            -- *** TC-SD-02: segmented download ***
            elsif run("test_segmented_download") then
                -- Every n from 0 to 7: n = 7 - the number of bytes of a segment
                segDownload(x"2000", x"01", x"00000000000000E1", (0 => 1), "1 byte (n = 6)");
                checkObj(0, x"00000000000000E1", "1 byte");
                segDownload(x"2000", x"02", x"000000000000E2D2", (0, 2), "2 bytes after an empty segment (n = 7, 5)");
                checkObj(1, x"000000000000E2D2", "2 bytes");
                segDownload(x"2000", x"03", x"0000000000E3D3C3", (0 => 3), "3 bytes (n = 4)");
                checkObj(2, x"0000000000E3D3C3", "3 bytes");
                segDownload(x"2000", x"04", x"00000000E4D4C4B4", (0 => 4), "4 bytes (n = 3)");
                checkObj(3, x"00000000E4D4C4B4", "4 bytes");
                segDownload(x"2001", x"01", x"000000E5D5C5B5A5", (0 => 5), "5 bytes (n = 2)");
                checkObj(4, x"000000E5D5C5B5A5", "5 bytes");
                segDownload(x"2001", x"02", x"0000F6E6D6C6B6A6", (0 => 6), "6 bytes (n = 1)");
                checkObj(5, x"0000F6E6D6C6B6A6", "6 bytes");
                segDownload(x"2001", x"03", x"0017F7E7D7C7B7A7", (0 => 7), "7 bytes (n = 0)");
                checkObj(6, x"0017F7E7D7C7B7A7", "7 bytes");
                segDownload(x"2001", x"04", x"F8E8D8C8B8A89888", (1, 1, 1, 1, 1, 1, 1, 1), "8 segments of 1 byte");
                checkObj(7, x"F8E8D8C8B8A89888", "8 bytes in 8 segments");
                segDownload(x"2001", x"04", x"0102030405060708", (6, 2), "8 bytes (n = 1, 5)");
                checkObj(7, x"0102030405060708", "8 bytes in segments of 6 and 2");
                segDownload(x"2001", x"04", x"8090A0B0C0D0E0F0", (7, 1), "8 bytes (n = 0, 6)");
                checkObj(7, x"8090A0B0C0D0E0F0", "8 bytes in segments of 7 and 1");
                -- An abort code of the object model at the last segment, the write the only access
                C0_v := AccCnt;
                segDownload(x"1000", x"00", x"0000000011223344", (3, 1), "read-only object", x"06010002");
                check_value(AccCnt, C0_v + 1, ERROR, "one access, at the last segment");
                checkOpen('0', "no transfer after the last segment");

            -- *** TC-SD-03: sizes of a segmented download ***
            elsif run("test_download_sizes") then
                C0_v := AccCnt;
                transact(dlInit(x"2001", x"04", u32(9)), abortResp(x"2001", x"04", x"06070012"), "size 9");
                transact(dlInit(x"2001", x"04", x"FFFFFFFF"), abortResp(x"2001", x"04", x"06070012"), "size FFFF FFFFh");
                transact(muxFrame(16#20#, x"2001", x"04", u32(8)), abortResp(x"2001", x"04", x"06070010"),
                         "no size indicated");
                transact(dlInit(x"2001", x"04", u32(0)), abortResp(x"2001", x"04", x"06070010"), "size 0");
                checkOpen('0', "no transfer after the refused initiates");
                -- The segments end short of the indicated size
                transact(dlInit(x"2001", x"02", u32(6)), dlResp(x"2001", x"02"), "initiate of 6 bytes");
                transact(dlSeg(0, 5, 1, x"11223344556677"), abortResp(x"2001", x"02", x"06070010"), "5 of 6 bytes");
                checkOpen('0', "transfer ended");
                -- The segments go beyond the indicated size
                transact(dlInit(x"2001", x"01", u32(5)), dlResp(x"2001", x"01"), "initiate of 5 bytes");
                transact(dlSeg(0, 4, 0, x"11223344556677"), dlSegResp(0), "4 of 5 bytes");
                transact(dlSeg(1, 3, 1, x"11223344556677"), abortResp(x"2001", x"01", x"06070010"), "7 of 5 bytes");
                -- More than 8 bytes: 0504 0005h, the transfer ends
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate of 8 bytes");
                transact(dlSeg(0, 7, 0, x"11223344556677"), dlSegResp(0), "7 of 8 bytes");
                transact(dlSeg(1, 2, 0, x"11223344556677"), abortResp(x"2001", x"04", x"05040005"), "9 bytes");
                transact(dlSeg(0, 1, 1, x"11223344556677"), abortResp(x"0000", x"00", x"05040001"),
                         "segment after the end");
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate of 8 bytes");
                transact(dlSeg(0, 7, 0, x"11223344556677"), dlSegResp(0), "7 of 8 bytes");
                transact(dlSeg(1, 7, 1, x"11223344556677"), abortResp(x"2001", x"04", x"05040005"),
                         "14 bytes at the last segment");
                checkOpen('0', "transfer ended");
                check_value(AccCnt, C0_v, ERROR, "no access");
                checkObj(7, Objects_c(7).Init, "object unchanged");

            -- *** TC-SD-04: expedited upload ***
            elsif run("test_expedited_upload") then

                for S in 1 to 4 loop
                    transact(ulInit(x"2000", u8(S)), ulExpResp(x"2000", u8(S), S, Objects_c(S - 1).Init(31 downto 0)),
                             "upload of " & to_string(S) & " bytes");
                end loop;

                transact(ulInit(x"1000", x"00"), ulExpResp(x"1000", x"00", 4, x"80010191"), "read-only object");
                transact(ulInit(x"2002", x"00"), abortResp(x"2002", x"00", x"06010001"), "write-only object");
                transact(ulInit(x"3000", x"00"), abortResp(x"3000", x"00", x"06020000"), "absent object");
                transact(ulInit(x"2000", x"09"), abortResp(x"2000", x"09", x"06090011"), "absent sub-index");
                -- An answer with 0 or more than 8 bytes (architecture, section 4)
                transact(ulInit(x"2004", x"00"), abortResp(x"2004", x"00", x"08000000"), "answer with 0 bytes");
                transact(ulInit(x"2004", x"01"), abortResp(x"2004", x"01", x"08000000"), "answer with 9 bytes");
                checkOpen('0', "no transfer after the uploads");

            -- *** TC-SD-05: segmented upload ***
            elsif run("test_segmented_upload") then

                for S in 5 to 8 loop
                    segUpload(x"2001", u8(S - 4), Objects_c(S - 1).Init, S, "upload of " & to_string(S) & " bytes");
                    checkOpen('0', "no transfer after the last segment");
                end loop;

                -- The value of a download
                segDownload(x"2001", x"04", x"0123456789ABCDEF", (7, 1), "download before the upload");
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate");
                checkOpen('1', "segmented upload open");
                B_v := bytesOfValue(x"0123456789ABCDEF");
                transact(ulSeg(0), ulSegResp(0, 7, 0, segData(B_v, 0, 7)), "first segment");
                checkOpen('1', "segmented upload open after the first segment");
                transact(ulSeg(1), ulSegResp(1, 1, 1, segData(B_v, 7, 1)), "last segment");
                checkOpen('0', "no transfer after the last segment");

            -- *** TC-SD-06: toggle bit ***
            elsif run("test_toggle") then
                -- Download: the first segment with t = 1
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                transact(dlSeg(1, 7, 0, x"11223344556677"), abortResp(x"2001", x"04", x"05030000"),
                         "first download segment with t = 1");
                checkOpen('0', "transfer ended by the toggle error");
                transact(dlSeg(0, 1, 1, x"11223344556677"), abortResp(x"0000", x"00", x"05040001"),
                         "segment after the toggle error");
                -- Download: a later segment with the toggle bit not alternated
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                transact(dlSeg(0, 1, 0, x"11223344556677"), dlSegResp(0), "first segment");
                transact(dlSeg(1, 1, 0, x"11223344556677"), dlSegResp(1), "second segment");
                transact(dlSeg(1, 1, 0, x"11223344556677"), abortResp(x"2001", x"04", x"05030000"),
                         "third download segment with t = 1");
                checkOpen('0', "transfer ended by the toggle error");
                -- Upload: the first segment with t = 1
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload");
                transact(ulSeg(1), abortResp(x"2001", x"04", x"05030000"), "first upload segment with t = 1");
                checkOpen('0', "transfer ended by the toggle error");
                -- Upload: the second segment with t = 0
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload");
                B_v := bytesOfValue(Objects_c(7).Init);
                transact(ulSeg(0), ulSegResp(0, 7, 0, segData(B_v, 0, 7)), "first upload segment");
                transact(ulSeg(0), abortResp(x"2001", x"04", x"05030000"), "second upload segment with t = 0");
                checkOpen('0', "transfer ended by the toggle error");
                checkObj(7, Objects_c(7).Init, "object unchanged by the aborted downloads");

            -- *** TC-SD-07: command specifiers and reserved bits ***
            elsif run("test_command_errors") then

                for C in 5 to 7 loop
                    transact(muxFrame(32 * C, x"2000", x"01", x"12345678"), abortResp(x"2000", x"01", x"05040001"),
                             "command specifier " & to_string(C));
                    transact(muxFrame(32 * C + 16#1F#, x"2001", x"03", x"FFFFFFFF"),
                             abortResp(x"2001", x"03", x"05040001"), "command specifier " & to_string(C) & ", bits 4 to 0 set");
                end loop;

                -- Segments without a transfer
                transact(dlSeg(0, 7, 1, x"11223344556677"), abortResp(x"0000", x"00", x"05040001"),
                         "download segment without a transfer");
                transact(ulSeg(0), abortResp(x"0000", x"00", x"05040001"), "upload segment without a transfer");
                -- Segments during a transfer of the other direction: the transfer ends
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload");
                transact(dlSeg(0, 7, 0, x"11223344556677"), abortResp(x"2001", x"04", x"05040001"),
                         "download segment during an upload");
                checkOpen('0', "upload ended");
                transact(dlInit(x"2001", x"03", u32(7)), dlResp(x"2001", x"03"), "initiate download");
                transact(ulSeg(0), abortResp(x"2001", x"03", x"05040001"), "upload segment during a download");
                checkOpen('0', "download ended");
                -- A block request during a transfer: the abort with its own index and sub-index, the transfer ends
                transact(dlInit(x"2001", x"03", u32(7)), dlResp(x"2001", x"03"), "initiate download");
                transact(muxFrame(16#C6#, x"2000", x"02", u32(4)), abortResp(x"2000", x"02", x"05040001"),
                         "block download during a download");
                checkOpen('0', "download ended by the block request");
                -- Reserved bits set (SD-PR-08): processed as without them
                transact(muxFrame(16#33#, x"2000", x"04", x"55667788"), dlResp(x"2000", x"04"),
                         "expedited download with bit 4 set");
                checkObj(3, x"0000000055667788", "4 bytes written");
                transact(muxFrame(16#3E#, x"2000", x"03", x"99AABBCC"), dlResp(x"2000", x"03"),
                         "expedited download, s = 0, with bit 4 and n set");
                checkObj(2, x"0000000000AABBCC", "3 bytes written");
                transact(muxFrame(16#3D#, x"2001", x"01", u32(5)), dlResp(x"2001", x"01"),
                         "segmented download with bit 4 and n set");
                transact(dlSeg(0, 5, 1, x"F1F2F3F4F5FFFF"), dlSegResp(0), "5 bytes, the unused bytes not 0");
                checkObj(4, x"000000F5F4F3F2F1", "5 bytes written");
                transact(muxFrame(16#5F#, x"2000", x"02", x"FFFFFFFF"), ulExpResp(x"2000", x"02", 2, x"0000B2A2"),
                         "initiate upload with bits 4 to 0 and bytes 4 to 7 set");
                transact(muxFrame(16#5F#, x"2001", x"04", x"FFFFFFFF"), ulInitResp(x"2001", x"04", 8),
                         "segmented initiate upload with bits 4 to 0 set");
                B_v := bytesOfValue(Objects_c(7).Init);
                transact(segFrame(16#6F#, x"FFFFFFFFFFFFFF"), ulSegResp(0, 7, 0, segData(B_v, 0, 7)),
                         "upload segment with bits 3 to 0 and bytes 1 to 7 set");
                transact(segFrame(16#7F#, x"FFFFFFFFFFFFFF"), ulSegResp(1, 1, 1, segData(B_v, 7, 1)),
                         "last upload segment with bits 3 to 0 set");
                -- An abort request with bits 4 to 0 set ends a transfer
                transact(dlInit(x"2001", x"03", u32(7)), dlResp(x"2001", x"03"), "initiate download");
                C0_v := CntAbRx;
                noReply(muxFrame(16#9F#, x"2001", x"03", x"08000000"), "abort request with bits 4 to 0 set");
                checkOpen('0', "download ended by the abort request");
                check_value(CntAbRx, C0_v + 1, ERROR, "Evt_AbortRx");

            -- *** TC-SD-08: abort of the client ***
            elsif run("test_client_abort") then
                -- During an open download and upload: the transfer ends without a reply
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                C0_v := CntAbRx;
                noReply(abortReq(x"2001", x"04", x"08000000"), "abort during a download");
                checkOpen('0', "download ended by the abort");
                check_value(CntAbRx, C0_v + 1, ERROR, "Evt_AbortRx of the abort during a download");
                transact(dlSeg(0, 7, 0, x"11223344556677"), abortResp(x"0000", x"00", x"05040001"),
                         "segment after the abort");
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload");
                noReply(abortReq(x"2001", x"04", x"08000000"), "abort during an upload");
                checkOpen('0', "upload ended by the abort");
                -- While idle: ignored
                C0_v := CntAbRx;
                noReply(abortReq(x"2001", x"04", x"08000000"), "abort while idle");
                check_value(CntAbRx, C0_v, ERROR, "no Evt_AbortRx while idle");
                -- During the access of an expedited download: no reply, the write took effect
                noReply(dlExp(x"2003", x"00", 0, x"5A6B7C8D"), "expedited download of an object of the user logic", n => 5);
                noReply(abortReq(x"2003", x"00", x"08000000"), "abort during the write", n => 40);
                checkObj(10, x"000000005A6B7C8D", "the aborted write took effect");
                -- During the access of the last segment
                transact(dlInit(x"2003", x"01", u32(8)), dlResp(x"2003", x"01"), "initiate download");
                transact(dlSeg(0, 7, 0, x"01020304050607"), dlSegResp(0), "first segment");
                noReply(dlSeg(1, 1, 1, x"08000000000000"), "last segment", n => 5);
                noReply(abortReq(x"2003", x"01", x"08000000"), "abort during the write of the last segment", n => 40);
                checkObj(11, x"0807060504030201", "the aborted write of the last segment took effect");
                -- During the access of an upload
                noReply(ulInit(x"2003", x"01"), "initiate upload of an object of the user logic", n => 5);
                noReply(abortReq(x"2003", x"01", x"08000000"), "abort during the read", n => 40);
                checkOpen('0', "no transfer after the aborted read");
                -- Around the answer, cycle by cycle: the request in cycle R, the access taken in R + 1, the answer in
                -- R + 6, the reply offered from R + 7 and taken in R + 9; the abort in R + 1 + D
                ObjCfg(14).Dly <= 5;
                loadObjects;
                RespRdy        <= 2;

                for D in 0 to 9 loop
                    N_v := TxCnt;
                    req(ulInit(x"2005", x"00"));
                    clocks(D);
                    reqNow(abortReq(x"2005", x"00", x"08000000"));
                    clocks(30);
                    if D <= 7 then
                        check_value(TxCnt, N_v, ERROR, "no reply, abort in R + " & to_string(D + 1));
                    else
                        check_value(TxCnt, N_v + 1, ERROR, "the taken reply completes, abort in R + " & to_string(D + 1));
                    end if;
                    settle;
                end loop;

                -- During an offered and a taken reply
                RespRdy <= 30;
                noReply(ulInit(x"2000", x"01"), "initiate upload, reply offered", n => 10);
                noReply(abortReq(x"2000", x"01", x"08000000"), "abort during an offered reply", n => 50);
                RespRdy <= 0;
                RespCpl <= 40;
                N_v     := TxCnt;
                req(ulInit(x"2001", x"04"));
                clocks(8);
                check_value(TxCnt, N_v + 1, ERROR, "reply taken");
                C0_v    := CntAbRx;
                req(abortReq(x"2001", x"04", x"08000000"));
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "no further reply after the abort during a taken reply");
                check_value(CntAbRx, C0_v + 1, ERROR, "Evt_AbortRx during a taken reply");
                checkOpen('0', "upload ended by the abort during the taken reply");
                RespCpl <= 3;
                transact(ulInit(x"2000", x"01"), ulExpResp(x"2000", x"01", 1, x"000000A1"), "request after the aborts");

            -- *** TC-SD-09: new initiate and an abandoned transfer ***
            elsif run("test_new_initiate") then
                -- During an open download: the old transfer ends without an abort
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                transact(dlSeg(0, 7, 0, x"11223344556677"), dlSegResp(0), "first segment");
                C0_v := CntAbTx;
                transact(dlExp(x"2000", x"04", 0, x"0A0B0C0D"), dlResp(x"2000", x"04"), "new expedited download");
                check_value(CntAbTx, C0_v, ERROR, "no abort for the old transfer");
                checkOpen('0', "no transfer after the expedited download");
                checkObj(7, Objects_c(7).Init, "the object of the old transfer unchanged");
                checkObj(3, x"000000000A0B0C0D", "the new object written");
                -- A new segmented download during a segmented download: the toggle starts at 0
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                transact(dlSeg(0, 7, 0, x"11223344556677"), dlSegResp(0), "first segment");
                segDownload(x"2001", x"01", x"0000001122334455", (2, 3), "new segmented download");
                checkObj(4, x"0000001122334455", "the new object written");
                -- During an open upload
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload");
                transact(ulInit(x"2000", x"02"), ulExpResp(x"2000", x"02", 2, x"0000B2A2"), "new upload");
                checkOpen('0', "no transfer after the expedited upload");
                transact(ulSeg(0), abortResp(x"0000", x"00", x"05040001"), "segment of the old upload");
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload");
                segUpload(x"2001", x"03", Objects_c(6).Init, 7, "new segmented upload");
                -- An abandoned transfer: the client silent for 2000 ticks
                TickPer <= 4;
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                clocks(8000);
                checkOpen('1', "transfer open after 2000 ticks");
                transact(ulInit(x"2000", x"01"), ulExpResp(x"2000", x"01", 1, x"000000A1"), "initiate after 2000 ticks");
                checkOpen('0', "no transfer after the new initiate");

            -- *** TC-SD-10: DLC ***
            elsif run("test_dlc") then
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");

                for D in 0 to 7 loop
                    C0_v := CntDrop;
                    noReply(dlSeg(0, 1, 0, x"11223344556677"), "segment with DLC " & to_string(D), dlc => D);
                    check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop for DLC " & to_string(D));
                    checkOpen('1', "transfer open after DLC " & to_string(D));
                end loop;

                C0_v := CntDrop;
                noReply(abortReq(x"2001", x"04", x"08000000"), "abort request with DLC 4", dlc => 4);
                noReply(ulInit(x"2000", x"01"), "initiate upload with DLC 7", dlc => 7);
                check_value(CntDrop, C0_v + 2, ERROR, "Err_RxDrop for the initiates with DLC below 8");
                checkOpen('1', "transfer open after the requests with DLC below 8");

                -- DLC 8 to 15: processed
                for D in 8 to 15 loop
                    transact(dlSeg((D - 8) mod 2, 1, D / 15, segData(bytesOfValue(x"0F0E0D0C0B0A0908"), D - 8, 1)),
                             dlSegResp((D - 8) mod 2), "segment with DLC " & to_string(D), dlc => D);
                end loop;

                checkObj(7, x"0F0E0D0C0B0A0908", "8 bytes written");

            -- *** TC-SD-11: one request at a time ***
            elsif run("test_busy") then
                -- While an access is outstanding
                C0_v := CntDrop;
                N_v  := TxCnt;
                C1_v := AccCnt;
                req(ulInit(x"2003", x"00"));
                clocks(3);
                req(ulInit(x"2000", x"01"));
                req(dlExp(x"2000", x"01", 3, x"000000FF"));
                waitCnt(TxCnt, N_v + 1, 100, "reply to the first request");
                check_value(TxLog(N_v), ulExpResp(x"2003", x"00", 4, x"39495969"), ERROR, "reply to the first request");
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "one reply while an access is outstanding");
                check_value(CntDrop, C0_v + 2, ERROR, "Err_RxDrop while an access is outstanding");
                check_value(AccCnt, C1_v + 1, ERROR, "one access while an access is outstanding");
                checkObj(0, Objects_c(0).Init, "object not written by the dropped request");
                -- While a reply is offered
                RespRdy <= 20;
                C0_v    := CntDrop;
                N_v     := TxCnt;
                req(ulInit(x"2000", x"01"));
                clocks(8);
                req(ulInit(x"2000", x"02"));
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "one reply while a reply is offered");
                check_value(TxLog(N_v), ulExpResp(x"2000", x"01", 1, x"000000A1"), ERROR, "reply to the first request");
                check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop while a reply is offered");
                -- While a reply is taken
                RespRdy <= 0;
                RespCpl <= 20;
                C0_v    := CntDrop;
                N_v     := TxCnt;
                req(ulInit(x"2000", x"01"));
                clocks(8);
                req(ulInit(x"2000", x"02"));
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "one reply while a reply is taken");
                check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop while a reply is taken");
                -- In the cycle of the completion (taken in T, completed in T + 3; waitCnt returns at the start of
                -- T + 2): not processed; one cycle later: processed
                RespCpl <= 3;
                C0_v    := CntDrop;
                N_v     := TxCnt;
                req(ulInit(x"2000", x"01"));
                waitCnt(TxCnt, N_v + 1, 100, "reply");
                req(ulInit(x"2000", x"02"));
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "a request in the cycle of the completion not processed");
                check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop in the cycle of the completion");
                N_v     := TxCnt;
                req(ulInit(x"2000", x"01"));
                waitCnt(TxCnt, N_v + 1, 100, "reply");
                clocks(1);
                req(ulInit(x"2000", x"02"));
                settle;
                check_value(TxCnt, N_v + 2, ERROR, "a request in the cycle after the completion processed");
                -- Requests in consecutive cycles: the second one is not processed
                C0_v     := CntDrop;
                N_v      := TxCnt;
                wait until rising_edge(Clk);
                Rx_Valid <= '1';
                Rx_Data  <= ulInit(x"2000", x"03");
                wait until rising_edge(Clk);
                Rx_Data  <= ulInit(x"2000", x"04");
                wait until rising_edge(Clk);
                Rx_Valid <= '0';
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "one reply to requests in consecutive cycles");
                check_value(TxLog(N_v), ulExpResp(x"2000", x"03", 3, x"00C3B3A3"), ERROR, "reply to the first request");
                check_value(CntDrop, C0_v + 1, ERROR, "Err_RxDrop for the second request");

            -- *** TC-SD-12: transmit handshake ***
            elsif run("test_reply_handshake") then

                -- Delays of Tx_Ready
                for D in RdyDelays_c'range loop
                    RespRdy <= RdyDelays_c(D);
                    transact(ulInit(x"2000", x"02"), ulExpResp(x"2000", x"02", 2, x"0000B2A2"),
                             "Tx_Ready after " & to_string(RdyDelays_c(D)) & " cycles");
                end loop;

                RespRdy <= 0;
                -- The reject path: the transfer ends
                RespRej <= true;
                transact(ulInit(x"2001", x"04"), ulInitResp(x"2001", x"04", 8), "initiate upload response rejected");
                RespRej <= false;
                checkOpen('0', "upload ended by the reject");
                transact(ulSeg(0), abortResp(x"0000", x"00", x"05040001"), "segment after the reject");
                -- Tx_Aborted after the take: the transfer ends
                RespAbort <= true;
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download response aborted");
                RespAbort <= false;
                checkOpen('0', "download ended by Tx_Aborted");
                -- Evt_AbortTx at the completion of an abort frame, not at its abort
                C0_v      := CntAbTx;
                transact(ulInit(x"3000", x"00"), abortResp(x"3000", x"00", x"06020000"), "abort frame sent");
                check_value(CntAbTx, C0_v + 1, ERROR, "Evt_AbortTx of the abort frame sent");
                RespAbort <= true;
                transact(ulInit(x"3000", x"00"), abortResp(x"3000", x"00", x"06020000"), "abort frame aborted");
                RespAbort <= false;
                check_value(CntAbTx, C0_v + 1, ERROR, "no Evt_AbortTx for the aborted abort frame");
                -- No completion: Err_TxTimeout after 256 ticks, no repetition
                TickPer <= 4;
                RespCpl <= 0;
                C0_v    := CntTmo;
                N_v     := TxCnt;
                req(ulInit(x"2000", x"02"));
                waitCnt(TxCnt, N_v + 1, 100, "reply taken");
                C1_v    := Cyc;
                waitCnt(CntTmo, C0_v + 1, 256 * 4 + 50, "Err_TxTimeout");
                check_value(Cyc - C1_v >= 255 * 4 and Cyc - C1_v <= 257 * 4 + 2, true, ERROR,
                            "Err_TxTimeout after 256 ticks (" & to_string(Cyc - C1_v) & " cycles)");
                clocks(2000);
                check_value(TxCnt, N_v + 1, ERROR, "no repetition after the time-out");
                check_value(CntTmo, C0_v + 1, ERROR, "one Err_TxTimeout");

                -- The 256 ticks count from the take, also after an access answered after 200 ticks and after the
                -- time-out of an access (512 ticks)
                for A in 0 to 1 loop
                    if A = 0 then
                        ObjCfg(14).DlyTk <= 200;
                    else
                        ObjCfg(14).Lost <= true;
                    end if;
                    loadObjects;
                    C0_v := CntTmo;
                    N_v  := TxCnt;
                    req(ulInit(x"2005", x"00"));
                    waitCnt(TxCnt, N_v + 1, 512 * 4 + 100, "reply taken after the access " & to_string(A));
                    C1_v := Cyc;
                    if A = 0 then
                        check_value(TxLog(N_v), ulExpResp(x"2005", x"00", 4, x"4C3C2C1C"), ERROR,
                                    "reply after an access of 200 ticks");
                    else
                        check_value(TxLog(N_v), abortResp(x"2005", x"00", x"08000000"), ERROR,
                                    "abort after an access without an answer");
                    end if;
                    waitCnt(CntTmo, C0_v + 1, 256 * 4 + 50, "Err_TxTimeout after the access " & to_string(A));
                    check_value(Cyc - C1_v >= 255 * 4 and Cyc - C1_v <= 257 * 4 + 2, true, ERROR,
                                "Err_TxTimeout 256 ticks after the take of the reply after the access " &
                                to_string(A) & " (" & to_string(Cyc - C1_v) & " cycles)");
                end loop;

                ObjCfg(14).DlyTk <= 0;
                ObjCfg(14).Lost  <= false;
                loadObjects;
                RespCpl          <= 3;
                transact(ulInit(x"2000", x"02"), ulExpResp(x"2000", x"02", 2, x"0000B2A2"), "request after the time-out");
                -- Completions while no reply is outstanding: ignored
                stray(false);
                stray(true);
                transact(dlInit(x"2003", x"01", u32(8)), dlResp(x"2003", x"01"), "initiate download");
                stray(false);
                stray(true);
                checkOpen('1', "download open after completions while idle");
                transact(dlSeg(0, 7, 0, x"11223344556677"), dlSegResp(0), "first segment");
                -- During an outstanding access of the user logic (20 cycles) and during an offered reply
                N_v     := TxCnt;
                req(dlSeg(1, 1, 1, x"88000000000000"));
                stray(true);
                stray(false);
                waitCnt(TxCnt, N_v + 1, 100, "reply");
                check_value(TxLog(N_v), dlSegResp(1), ERROR, "reply after completions during the access");
                settle;
                checkObj(11, x"8877665544332211", "8 bytes written");
                RespRdy <= 20;
                N_v     := TxCnt;
                req(ulInit(x"2000", x"02"));
                clocks(6);
                stray(true);
                stray(false);
                settle;
                check_value(TxCnt, N_v + 1, ERROR, "one reply after completions during the offer");
                check_value(TxLog(N_v), ulExpResp(x"2000", x"02", 2, x"0000B2A2"), ERROR,
                            "reply after completions during the offer");

            -- *** TC-SD-13: NMT state ***
            elsif run("test_nmt") then

                for E in 0 to 2 loop
                    -- During an open transfer
                    transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate, " & nmtName(E));
                    C0_v := CntAbTx;
                    nmtEvent(E);
                    clocks(5);
                    checkOpen('0', "transfer ended by " & nmtName(E));
                    check_value(CntAbTx, C0_v, ERROR, "no abort at " & nmtName(E));
                    transact(dlSeg(0, 7, 0, x"11223344556677"), abortResp(x"0000", x"00", x"05040001"),
                             "segment after " & nmtName(E));
                    -- An access not yet taken
                    AccRdyDly <= 10;
                    N_v       := TxCnt;
                    req(ulInit(x"2000", x"01"));
                    clocks(3);
                    nmtEvent(E);
                    clocks(40);
                    check_value(TxCnt, N_v, ERROR, "no reply, access not taken at " & nmtName(E));
                    AccRdyDly <= 0;
                    settle;
                    -- An access of the user logic outstanding
                    N_v := TxCnt;
                    req(dlExp(x"2003", x"00", 0, x"10203040"));
                    clocks(5);
                    nmtEvent(E);
                    clocks(40);
                    check_value(TxCnt, N_v, ERROR, "no reply, access outstanding at " & nmtName(E));
                    settle;

                    -- An access taken in the cycle of the event: own object, object of the user logic. After a reset
                    -- event the processing ends with the answer in the next cycle: a request in that cycle is not
                    -- processed
                    for O in 0 to 1 loop
                        N_v := TxCnt;
                        if O = 0 then
                            req(ulInit(x"2000", x"01"));
                        else
                            req(ulInit(x"2003", x"00"));
                        end if;
                        nmtNow(E);
                        if E > 0 then
                            C0_v := CntDrop;
                            reqNow(ulInit(x"2000", x"02"));
                            clocks(40);
                            check_value(CntDrop, C0_v + 1, ERROR,
                                        "request in the cycle of the answer after " & nmtName(E) & " not processed");
                        else
                            clocks(40);
                        end if;
                        check_value(TxCnt, N_v, ERROR, "no reply, access taken in the cycle of " & nmtName(E));
                        settle;
                    end loop;

                    -- The event in the cycle of the answer of an own object
                    N_v := TxCnt;
                    req(ulInit(x"2000", x"01"));
                    clocks(1);
                    nmtNow(E);
                    clocks(40);
                    check_value(TxCnt, N_v, ERROR, "no reply, answer in the cycle of " & nmtName(E));
                    settle;
                    -- An offered reply: withdrawn
                    RespRdy <= 30;
                    N_v     := TxCnt;
                    req(ulInit(x"2000", x"01"));
                    clocks(6);
                    nmtEvent(E);
                    clocks(50);
                    check_value(TxCnt, N_v, ERROR, "offered reply withdrawn at " & nmtName(E));
                    RespRdy <= 0;
                    settle;
                    -- A taken reply: not awaited, its completion is ignored; the next request is processed at once
                    RespCpl <= 30;
                    N_v     := TxCnt;
                    req(ulInit(x"2001", x"04"));
                    clocks(6);
                    nmtEvent(E);
                    checkOpen('0', "upload ended by " & nmtName(E));
                    transact(ulInit(x"2000", x"02"), ulExpResp(x"2000", x"02", 2, x"0000B2A2"),
                             "request after " & nmtName(E) & " during a taken reply");
                    check_value(TxCnt, N_v + 2, ERROR, "taken reply and the next one at " & nmtName(E));
                    RespCpl <= 3;
                    settle;
                    -- A request in the cycle of the event: not processed
                    N_v      := TxCnt;
                    wait until rising_edge(Clk);
                    Rx_Valid <= '1';
                    Rx_Data  <= ulInit(x"2000", x"01");
                    Rx_Dlc   <= x"8";
                    nmtNow(E, 1);
                    Rx_Valid <= '0';
                    clocks(40);
                    check_value(TxCnt, N_v, ERROR, "request in the cycle of " & nmtName(E) & " not processed");
                    -- The server works afterwards
                    transact(ulInit(x"2000", x"01"), ulExpResp(x"2000", x"01", 1, x"000000A1"),
                             "upload after " & nmtName(E));
                end loop;

            -- *** TC-SD-14: timing of the access ***
            elsif run("test_access_timing") then
                TickPer <= 4;
                -- 1 cycle: an own object of ocan_od
                transact(ulInit(x"2005", x"00"), ulExpResp(x"2005", x"00", 4, x"4C3C2C1C"), "answer after 1 cycle");
                check_value(CycTx, CycRsp + 1, ERROR, "reply 1 cycle after the answer of 1 cycle");
                -- 100 cycles
                ObjCfg(14).Dly <= 100;
                loadObjects;
                C0_v           := Cyc;
                transact(ulInit(x"2005", x"00"), ulExpResp(x"2005", x"00", 4, x"4C3C2C1C"), "answer after 100 cycles");
                check_value(CycTx, CycRsp + 1, ERROR, "reply 1 cycle after the answer of 100 cycles");
                transact(dlExp(x"2005", x"00", 0, x"0A0B0C0D"), dlResp(x"2005", x"00"), "write answered after 100 cycles");
                checkObj(14, x"000000000A0B0C0D", "value after the write");
                -- 255 ticks
                ObjCfg(14).DlyTk <= 255;
                loadObjects;
                transact(ulInit(x"2005", x"00"), ulExpResp(x"2005", x"00", 4, x"4C3C2C1C"), "answer after 255 ticks");
                check_value(CycTx, CycRsp + 1, ERROR, "reply 1 cycle after the answer of 255 ticks");
                -- 256 ticks: the time-out of ocan_od with 0800 0000h
                ObjCfg(14).DlyTk <= 256;
                ObjCfg(14).RdAb  <= x"08000000";
                loadObjects;
                transact(ulInit(x"2005", x"00"), abortResp(x"2005", x"00", x"08000000"), "time-out of the user logic");
                check_value(CycTx, CycRsp + 1, ERROR, "reply 1 cycle after the time-out");
                -- No answer: 0800 0000h and Err_AccTimeout at the 512th tick after the access (SD-TX-04)
                ObjCfg(14).Lost <= true;
                loadObjects;
                C0_v            := CntAccTmo;
                N_v             := TxCnt;
                req(ulInit(x"2005", x"00"));
                C1_v            := Cyc;
                waitCnt(TxCnt, N_v + 1, 512 * 4 + 100, "reply after an access without an answer");
                check_value(TxLog(N_v), abortResp(x"2005", x"00", x"08000000"), ERROR,
                            "abort 0800 0000h after an access without an answer");
                check_value(CntAccTmo, C0_v + 1, ERROR, "Err_AccTimeout");
                check_value(CycAccTmo - C1_v >= 511 * 4 and CycAccTmo - C1_v <= 512 * 4 + 2, true, ERROR,
                            "Err_AccTimeout after 512 ticks (" & to_string(CycAccTmo - C1_v) & " cycles)");
                settle;
                transact(ulInit(x"2000", x"01"), ulExpResp(x"2000", x"01", 1, x"000000A1"),
                         "request after the time-out of the access");
                -- An abandoned access without an answer: the time-out ends it without a reply
                C0_v := CntAccTmo;
                noReply(dlExp(x"2005", x"00", 0, x"11223344"), "access without an answer", n => 10);
                noReply(abortReq(x"2005", x"00", x"08000000"), "abort during the access", n => 512 * 4 + 100);
                check_value(CntAccTmo, C0_v + 1, ERROR, "Err_AccTimeout of the abandoned access");
                transact(ulInit(x"2000", x"01"), ulExpResp(x"2000", x"01", 1, x"000000A1"),
                         "request after the time-out of the abandoned access");

            -- *** TC-SD-15: hardware reset ***
            elsif run("test_reset") then
                -- During an open transfer
                transact(dlInit(x"2001", x"04", u32(8)), dlResp(x"2001", x"04"), "initiate download");
                doReset;
                checkOpen('0', "no transfer after Rst");
                transact(dlSeg(0, 7, 0, x"11223344556677"), abortResp(x"0000", x"00", x"05040001"), "segment after Rst");
                -- During an outstanding access: its answer is ignored
                N_v := TxCnt;
                req(ulInit(x"2003", x"00"));
                clocks(5);
                doReset;
                clocks(40);
                check_value(TxCnt, N_v, ERROR, "no reply after Rst during an access");
                -- During an offered reply
                RespRdy <= 30;
                N_v     := TxCnt;
                req(ulInit(x"2000", x"01"));
                clocks(6);
                doReset;
                clocks(50);
                check_value(TxCnt, N_v, ERROR, "no reply after Rst during an offered reply");
                RespRdy <= 0;
                -- During a taken reply: its completion is ignored
                RespCpl <= 30;
                N_v     := TxCnt;
                req(ulInit(x"2001", x"04"));
                clocks(6);
                doReset;
                clocks(50);
                check_value(TxCnt, N_v + 1, ERROR, "reply taken before Rst");
                checkOpen('0', "no transfer after Rst during a taken reply");
                RespCpl <= 3;
                transact(ulInit(x"2000", x"01"), ulExpResp(x"2000", x"01", 1, x"000000A1"), "upload after Rst");

            -- *** TC-SD-16: random requests ***
            elsif run("test_random") then
                TickPer        <= 2;
                ObjCfg(14).Dly <= 3;
                loadObjects;
                Cl_v           := 0;
                ClT_v          := 0;
                ClSz_v         := 0;
                ClC_v          := 0;

                for I in 1 to 5000 loop
                    -- Environment
                    if random(1, 10) = 1 then
                        RespRdy <= random(0, 12);
                    else
                        RespRdy <= random(0, 2);
                    end if;
                    if random(1, 100) = 1 then
                        RespCpl <= 0;
                    else
                        RespCpl <= random(1, 6);
                    end if;
                    RespAbort <= random(1, 100) <= 4;
                    RespRej   <= random(1, 100) <= 3;
                    if random(1, 10) = 1 then
                        AccRdyDly <= random(1, 4);
                    else
                        AccRdyDly <= 0;
                    end if;
                    if random(1, 20) = 1 then
                        ObjCfg(15).WrAb <= u32(AbortCodes_c(random(0, 3)));
                        ObjCfg(9).RdAb  <= u32(AbortCodes_c(random(0, 3)));
                    end if;

                    -- The request
                    Obj_v := random(0, 16);
                    if Obj_v = 16 then
                        Idx_v := x"3000";
                        Sub_v := x"00";
                    else
                        Idx_v := ObjCfg(Obj_v).Index;
                        Sub_v := ObjCfg(Obj_v).Sub;
                    end if;
                    F_v   := muxFrame(16#00#, Idx_v, Sub_v, NoWord_c);
                    W_v   := std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 30)) & "01";
                    Dlc_v := 8 + random(0, 7) * boolean'pos(random(1, 8) = 1);
                    Seg_v := false;
                    Ini_v := 0;
                    R_v   := random(1, 100);
                    if R_v <= 22 then
                        -- Initiate download
                        K_v := random(1, 10);
                        if K_v <= 4 then
                            F_v := muxFrame(16#23# + 4 * random(0, 3) + 16 * random(0, 1), Idx_v, Sub_v, W_v);
                        elsif K_v <= 5 then
                            F_v := muxFrame(16#22# + 4 * random(0, 3), Idx_v, Sub_v, W_v);
                        else
                            if Obj_v < 16 and random(1, 10) <= 8 then
                                IniS_v := ObjCfg(Obj_v).Size;
                            elsif random(1, 50) = 1 then
                                IniS_v := 16#7FFFFFFF#;
                            else
                                IniS_v := random(0, 10);
                            end if;
                            if random(1, 50) = 1 then
                                F_v := muxFrame(16#20#, Idx_v, Sub_v, u32(IniS_v));
                            else
                                F_v := muxFrame(16#21# + 4 * random(0, 3), Idx_v, Sub_v, u32(IniS_v));
                            end if;
                            Ini_v := 1;
                        end if;
                    elsif R_v <= 40 then
                        -- Initiate upload, the reserved bits random
                        F_v   := muxFrame(16#40# + random(0, 31) * boolean'pos(random(1, 4) = 1), Idx_v, Sub_v, W_v);
                        Ini_v := 2;
                    elsif R_v <= 70 then
                        -- The next segment in the view of the client
                        if random(1, 10) = 1 then
                            SegT_v := 1 - ClT_v;
                        else
                            SegT_v := ClT_v;
                        end if;
                        if Cl_v = 2 then
                            F_v := segFrame(16#60# + 16 * SegT_v + random(0, 15) * boolean'pos(random(1, 4) = 1),
                                            std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 30)) & x"ABCDEF" & "11");
                        else
                            SegK_v := random(0, 7);
                            if ClC_v + SegK_v >= ClSz_v and random(1, 5) <= 4 then
                                SegK_v := ClSz_v - minimum(ClC_v, ClSz_v);
                                if SegK_v > 7 then
                                    SegK_v := 7;
                                end if;
                            end if;
                            if ClC_v + SegK_v >= ClSz_v then
                                T_v := 1;
                            else
                                T_v := random(0, 1) * boolean'pos(random(1, 10) = 1);
                            end if;
                            F_v   := dlSeg(SegT_v, SegK_v, T_v, std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 30)) &
                                           x"123456" & "10");
                            Seg_v := true;
                        end if;
                    elsif R_v <= 78 then
                        -- A segment of either direction with random bits
                        F_v := segFrame(16#00# + 16#60# * random(0, 1) + random(0, 31),
                                        std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 30)) & x"654321" & "01");
                    elsif R_v <= 84 then
                        F_v := muxFrame(16#80# + random(0, 31) * boolean'pos(random(1, 4) = 1), Idx_v,
                                        Sub_v, x"08000000");
                    elsif R_v <= 88 then
                        F_v := muxFrame(32 * random(5, 7) + random(0, 31), Idx_v, Sub_v, W_v);
                    elsif R_v <= 93 then
                        Dlc_v := random(0, 7);
                    else
                        F_v := std_logic_vector(to_unsigned(random(0, 2 ** 30 - 1), 30)) & F_v(33 downto 32) & W_v;
                    end if;

                    -- Send it, with an event at a random offset
                    N_v := TxCnt;
                    req(F_v, Dlc_v);
                    R_v := random(1, 100);
                    if R_v <= 3 then
                        clocks(random(0, 10));
                        nmtNow(random(0, 2), random(1, 5));
                    elsif R_v <= 4 then
                        clocks(random(0, 10));
                        doReset;
                    elsif R_v <= 6 then
                        clocks(random(0, 8));
                        stray(random(0, 1) = 1);
                    elsif R_v <= 10 then
                        clocks(random(0, 12));
                        reqNow(abortReq(Idx_v, Sub_v, x"08000000"));
                    end if;

                    -- Until idle, or a few cycles
                    if random(1, 4) <= 3 then
                        settle;
                    else
                        clocks(random(0, 6));
                    end if;

                    -- The view of the client: the transfer from Stat_Open, the toggle bit from the replies
                    wait until falling_edge(Clk);
                    if Stat_Open = '0' then
                        Cl_v := 0;
                    elsif Ini_v /= 0 and TxCnt > N_v then
                        Cl_v   := Ini_v;
                        ClT_v  := 0;
                        ClC_v  := 0;
                        ClSz_v := IniS_v;
                    elsif Seg_v and TxCnt > N_v and TxLog(N_v)(63 downto 61) /= "100" then
                        ClT_v := 1 - SegT_v;
                        ClC_v := ClC_v + SegK_v;
                    elsif Cl_v = 2 and TxCnt > N_v and TxLog(N_v)(63 downto 61) = "000" then
                        ClT_v := 1 - to_integer(unsigned'('0' & TxLog(N_v)(60)));
                    end if;
                end loop;

                settle;
                log(ID_SEQUENCER, integer'image(TxCnt) & " replies, " & integer'image(AccCnt) & " accesses, " &
                    integer'image(CntDrop) & " Err_RxDrop, " & integer'image(CntTmo) & " Err_TxTimeout, " &
                    integer'image(CntAbTx) & " Evt_AbortTx, " & integer'image(CntAbRx) & " Evt_AbortRx");

            end if;

            clocks(10);

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
