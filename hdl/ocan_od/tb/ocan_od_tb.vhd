---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_od (TC-OD-01 to TC-OD-20): drivers of the access interface, the NMT inputs, the block
-- updates and the test inputs, a responder of the application port, and a reference model of the object
-- dictionary written from the specification that predicts every output in every cycle.
--
-- Documentation: hdl/ocan_od/docs/verification_plan.md

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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_od_tb is
    generic (
        runner_cfg       : string;
        MinimalSet_g     : boolean                       := false;
        NumRpdo_g        : natural                       := 4;
        NumTpdo_g        : natural                       := 4;
        TimePdos_g       : boolean                       := true;
        DeviceType_g     : std_logic_vector(31 downto 0) := (others => '0');
        VendorId_g       : std_logic_vector(31 downto 0) := (others => '0');
        ProductCode_g    : std_logic_vector(31 downto 0) := (others => '0');
        Revision_g       : std_logic_vector(31 downto 0) := (others => '0');
        SerialNumber_g   : std_logic_vector(31 downto 0) := (others => '0');
        ProducerHbTime_g : natural                       := 1000;
        MasterNodeId_g   : natural                       := 1;
        MasterHbTime_g   : natural                       := 1500;
        Bdefault_g       : natural                       := 0;
        Ttoggle_g        : natural                       := 1;
        Ntoggle_g        : natural                       := 3;
        RpdoType_g       : natural                       := 254;
        TpdoType_g       : natural                       := 254;
        SctCobId_g       : natural                       := 0;
        SctType_g        : natural                       := 254;
        LtpCobId_g       : natural                       := 0;
        LtpType_g        : natural                       := 254;
        AppPort_g        : boolean                       := true
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_od_tb is

    -- *** Reference model: one copy of the protected parameters (specification, table 1 and OD-PR-01) ***
    type Sl11_a is array (0 to 10) of std_logic;
    type Nat11_a is array (0 to 10) of natural;
    type Nat10_a is array (1 to 10) of natural;

    type MCopy_t is record
        NV   : Sl11_a;   -- bit 31 of the COB-ID of entry e
        Rel  : Sl11_a;   -- identifier = base + NODE-ID
        Id   : Nat11_a;
        Node : natural;  -- 1016h sub-index 01h
        HbT  : natural;
        Prod : natural;  -- 1017h
        Typ  : Nat10_a;  -- transmission type of entry e
        Bdef : natural;
        Ttog : natural;
        Ntog : natural;
    end record;

    type MKind_t is (
        KNone, KApp, KDev, KErr, KSync, KHbN, KHb, KProd, KIdN, KId, KCommN, KCob, KTyp, KMapN, KMap, KRedN, KBdef,
        KTtog, KNtog, KCtog, KSet, KGet
    );

    -- Object of table 1: kind, sub-index present, entry, sub-index number, size, readable, writable, Pre-op only
    type MObj_t is record
        Kind  : MKind_t;
        SubOk : boolean;
        Ent   : natural;
        K     : natural;
        Size  : natural;
        Rd    : boolean;
        Wr    : boolean;
        Pre   : boolean;
    end record;

    -- Entry e of the COB-ID table exists for the generics
    function mExists (e : natural) return boolean is
    begin

        case e is
            when 0 =>
                return true;
            when 1 | 10 =>
                return TimePdos_g;
            when 2 to 5 =>
                return e - 2 < NumRpdo_g;
            when 6 to 9 =>
                return e - 6 < NumTpdo_g;
            when others =>
                return false;
        end case;

    end function;

    -- Entry of the transmission type slot j of the test layout (architecture, section 3.3)
    function mSlotEntry (j : natural) return natural is
    begin
        if j <= 7 then
            return j + 2;
        elsif j = 8 then
            return 1;
        else
            return 10;
        end if;
    end function;

    function bitOf (n : natural) return std_logic is
    begin
        if n = 0 then
            return '0';
        else
            return '1';
        end if;
    end function;

    -- Restricted identifiers ([CiA301] table 40) and the free ranges of clause 9.5a
    function mRestricted (id : natural) return boolean is
    begin
        if id = 0 or (id >= 16#001# and id <= 16#07F#) then
            return true;
        elsif (id >= 16#101# and id <= 16#180#) or (id >= 16#581# and id <= 16#5FF#) then
            return true;
        elsif (id >= 16#601# and id <= 16#67F#) or (id >= 16#6E0# and id <= 16#6FF#) then
            return true;
        elsif (id >= 16#701# and id <= 16#77F#) or (id >= 16#780# and id <= 16#7FF#) then
            return true;
        else
            return false;
        end if;
    end function;

    function mPowerOn return MCopy_t is
        variable C_v : MCopy_t;
    begin
        C_v.NV(0)  := '0';
        C_v.Rel(0) := '0';
        C_v.Id(0)  := 16#080#;

        for E in 2 to 9 loop
            C_v.NV(E)  := '0';
            C_v.Rel(E) := '1';
            C_v.Id(E)  := 0;
        end loop;

        C_v.Rel(1)  := '0';
        C_v.Id(1)   := SctCobId_g;
        C_v.Rel(10) := '0';
        C_v.Id(10)  := LtpCobId_g;
        if SctCobId_g = 0 then
            C_v.NV(1) := '1';
        else
            C_v.NV(1) := '0';
        end if;
        if LtpCobId_g = 0 then
            C_v.NV(10) := '1';
        else
            C_v.NV(10) := '0';
        end if;
        C_v.Node := MasterNodeId_g;
        C_v.HbT  := MasterHbTime_g;
        C_v.Prod := ProducerHbTime_g;

        for E in 2 to 9 loop
            if MinimalSet_g then
                C_v.Typ(E) := 254;
            elsif E <= 5 then
                C_v.Typ(E) := RpdoType_g;
            else
                C_v.Typ(E) := TpdoType_g;
            end if;
        end loop;

        C_v.Typ(1)  := SctType_g;
        C_v.Typ(10) := LtpType_g;
        C_v.Bdef    := Bdefault_g;
        C_v.Ttog    := Ttoggle_g;
        C_v.Ntog    := Ntoggle_g;
        return C_v;
    end function;

    constant MPower_c : MCopy_t := mPowerOn;

    -- Identifier of entry e for the NODE-ID (architecture, section 3.1)
    function mId (c : MCopy_t; e : natural; node : natural) return natural is
    begin
        if c.Rel(e) = '1' and e >= 2 and e <= 9 then
            if e <= 5 then
                return 16#200# + (e - 2) * 16#100# + node;
            else
                return 16#180# + (e - 6) * 16#100# + node;
            end if;
        else
            return c.Id(e);
        end if;
    end function;

    -- Inversion of bits of a copy in the layout of architecture section 3.3
    function mFlip (c : MCopy_t; f : std_logic_vector(278 downto 0)) return MCopy_t is
        variable C_v : MCopy_t;
        variable E_v : natural;
    begin
        C_v := c;

        for E in 0 to 10 loop
            C_v.Id(E)  := to_integer(to_unsigned(c.Id(E), 11) xor unsigned(f(13 * E + 10 downto 13 * E)));
            C_v.Rel(E) := c.Rel(E) xor f(13 * E + 11);
            C_v.NV(E)  := c.NV(E) xor f(13 * E + 12);
        end loop;

        C_v.HbT  := to_integer(to_unsigned(c.HbT, 16) xor unsigned(f(158 downto 143)));
        C_v.Node := to_integer(to_unsigned(c.Node, 7) xor unsigned(f(165 downto 159)));
        C_v.Prod := to_integer(to_unsigned(c.Prod, 16) xor unsigned(f(181 downto 166)));

        for J in 0 to 9 loop
            if J <= 7 then
                E_v := J + 2;
            elsif J = 8 then
                E_v := 1;
            else
                E_v := 10;
            end if;
            C_v.Typ(E_v) := to_integer(to_unsigned(c.Typ(E_v), 8) xor unsigned(f(182 + 8 * J + 7 downto 182 + 8 * J)));
        end loop;

        if f(262) = '1' then
            C_v.Bdef := 1 - c.Bdef;
        end if;
        C_v.Ttog := to_integer(to_unsigned(c.Ttog, 8) xor unsigned(f(270 downto 263)));
        C_v.Ntog := to_integer(to_unsigned(c.Ntog, 8) xor unsigned(f(278 downto 271)));
        return C_v;
    end function;

    -- Table 1 of the specification
    function mObj (index : natural; sub : natural) return MObj_t is
        variable O_v : MObj_t;
        variable N_v : natural;
        variable E_v : natural;
    begin
        O_v := (KNone,
                false,
                0,
                0,
                1,
                false,
                false,
                false);
        if index >= 16#2003# and index <= 16#9FFF# then
            O_v.Kind := KApp;
            return O_v;
        end if;

        case index is
            when 16#1000# =>
                O_v := (KDev,
                        sub = 0,
                        0,
                        0,
                        4,
                        true,
                        false,
                        false);
            when 16#1001# =>
                O_v := (KErr,
                        sub = 0,
                        0,
                        0,
                        1,
                        true,
                        false,
                        false);
            when 16#1005# =>
                O_v := (KSync,
                        sub = 0,
                        0,
                        0,
                        4,
                        true,
                        true,
                        true);
            when 16#1016# =>
                if sub = 0 then
                    O_v := (KHbN,
                            true,
                            0,
                            0,
                            1,
                            true,
                            false,
                            false);
                else
                    O_v := (KHb,
                            sub = 1,
                            0,
                            0,
                            4,
                            true,
                            true,
                            false);
                end if;
            when 16#1017# =>
                O_v := (KProd,
                        sub = 0,
                        0,
                        0,
                        2,
                        true,
                        true,
                        false);
            when 16#1018# =>
                if sub = 0 then
                    O_v := (KIdN,
                            true,
                            0,
                            0,
                            1,
                            true,
                            false,
                            false);
                else
                    O_v := (KId,
                            sub <= 4,
                            0,
                            sub,
                            4,
                            true,
                            false,
                            false);
                end if;
            when 16#2000# =>

                case sub is
                    when 0 =>
                        O_v := (KRedN,
                                true,
                                0,
                                0,
                                1,
                                true,
                                false,
                                false);
                    when 1 =>
                        O_v := (KBdef,
                                true,
                                0,
                                0,
                                1,
                                true,
                                true,
                                false);
                    when 2 =>
                        O_v := (KTtog,
                                true,
                                0,
                                0,
                                1,
                                true,
                                true,
                                false);
                    when 3 =>
                        O_v := (KNtog,
                                true,
                                0,
                                0,
                                1,
                                true,
                                true,
                                false);
                    when 4 =>
                        O_v := (KCtog,
                                true,
                                0,
                                0,
                                1,
                                true,
                                true,
                                false);
                    when others =>
                        O_v := (KRedN,
                                false,
                                0,
                                0,
                                1,
                                true,
                                false,
                                false);
                end case;

            when 16#2001# =>
                O_v := (KSet,
                        sub = 0,
                        0,
                        0,
                        7,
                        false,
                        true,
                        false);
            when 16#2002# =>
                O_v := (KGet,
                        sub = 0,
                        0,
                        0,
                        7,
                        true,
                        false,
                        false);
            when others =>
                -- PDO communication and mapping: 14xxh, 18xxh, 16xxh, 1Axxh with xx = 0 to 4
                N_v := index mod 256;
                if N_v <= 4 and (index / 256 = 16#14# or index / 256 = 16#16# or index / 256 = 16#18# or
                                 index / 256 = 16#1A#) then
                    if index / 256 = 16#14# or index / 256 = 16#16# then
                        if N_v = 4 then
                            E_v := 1;
                        else
                            E_v := N_v + 2;
                        end if;
                    elsif N_v = 4 then
                        E_v := 10;
                    else
                        E_v := N_v + 6;
                    end if;
                    if mExists(E_v) then
                        if index / 256 = 16#14# or index / 256 = 16#18# then

                            case sub is
                                when 0 =>
                                    O_v := (KCommN,
                                            true,
                                            E_v,
                                            0,
                                            1,
                                            true,
                                            false,
                                            false);
                                when 1 =>
                                    O_v := (KCob,
                                            true,
                                            E_v,
                                            0,
                                            4,
                                            true,
                                            true,
                                            true);
                                when 2 =>
                                    O_v := (KTyp,
                                            true,
                                            E_v,
                                            0,
                                            1,
                                            true,
                                            true,
                                            true);
                                when others =>
                                    O_v := (KCommN,
                                            false,
                                            E_v,
                                            0,
                                            1,
                                            true,
                                            false,
                                            false);
                            end case;

                        elsif sub = 0 then
                            O_v := (KMapN,
                                    true,
                                    E_v,
                                    0,
                                    1,
                                    true,
                                    false,
                                    false);
                        elsif (N_v = 4 and sub = 1) or (N_v < 4 and sub <= 8) then
                            O_v := (KMap,
                                    true,
                                    E_v,
                                    sub,
                                    4,
                                    true,
                                    false,
                                    false);
                        else
                            O_v := (KMap,
                                    false,
                                    E_v,
                                    sub,
                                    4,
                                    true,
                                    false,
                                    false);
                        end if;
                    end if;
                end if;
        end case;

        return O_v;
    end function;

    -- *** DUT signals ***
    signal Clk              : std_logic;
    signal Rst              : std_logic                      := '1';
    signal Tick_Ms          : std_logic                      := '0';
    signal Acc_Valid        : std_logic                      := '0';
    signal Acc_Ready        : std_logic;
    signal Acc_Write        : std_logic                      := '0';
    signal Acc_Index        : std_logic_vector(15 downto 0)  := (others => '0');
    signal Acc_Sub          : std_logic_vector(7 downto 0)   := (others => '0');
    signal Acc_Data         : std_logic_vector(63 downto 0)  := (others => '0');
    signal Acc_Len          : std_logic_vector(3 downto 0)   := (others => '0');
    signal Rsp_Valid        : std_logic;
    signal Rsp_Data         : std_logic_vector(63 downto 0);
    signal Rsp_Len          : std_logic_vector(3 downto 0);
    signal Rsp_Abort        : std_logic_vector(31 downto 0);
    signal Nmt_State        : std_logic_vector(1 downto 0)   := NmtPreOp_c;
    signal Nmt_NodeId       : std_logic_vector(6 downto 0)   := std_logic_vector(to_unsigned(5, 7));
    signal Nmt_ResetApp     : std_logic                      := '0';
    signal Nmt_ResetComm    : std_logic                      := '0';
    signal Cfg_CobId        : std_logic_vector(143 downto 0);
    signal Cfg_CobIdCopy    : std_logic_vector(143 downto 0);
    signal Cfg_HbTime       : std_logic_vector(15 downto 0);
    signal Cfg_MasterHbTime : std_logic_vector(15 downto 0);
    signal Cfg_Bdefault     : std_logic;
    signal Cfg_Ttoggle      : std_logic_vector(7 downto 0);
    signal Cfg_Ntoggle      : std_logic_vector(7 downto 0);
    signal Cfg_Ctoggle      : std_logic_vector(7 downto 0);
    signal Cfg_CtoggleValid : std_logic;
    signal Stat_Ctoggle     : std_logic_vector(7 downto 0)   := x"00";
    signal Upd_Valid        : std_logic                      := '0';
    signal Upd_Bdefault     : std_logic                      := '0';
    signal Cfg_SctType      : std_logic_vector(7 downto 0);
    signal Cfg_LtpType      : std_logic_vector(7 downto 0);
    signal Cfg_SetValid     : std_logic;
    signal Cfg_SetScet      : std_logic_vector(55 downto 0);
    signal Stat_Scet        : std_logic_vector(55 downto 0)  := (others => '0');
    signal Cfg_RpdoType     : std_logic_vector(31 downto 0);
    signal Cfg_TpdoType     : std_logic_vector(31 downto 0);
    signal Link_State       : std_logic_vector(1 downto 0)   := "00";
    signal App_ReqValid     : std_logic;
    signal App_ReqReady     : std_logic                      := '0';
    signal App_ReqWrite     : std_logic;
    signal App_ReqIndex     : std_logic_vector(15 downto 0);
    signal App_ReqSub       : std_logic_vector(7 downto 0);
    signal App_ReqData      : std_logic_vector(63 downto 0);
    signal App_ReqLen       : std_logic_vector(3 downto 0);
    signal App_RspValid     : std_logic                      := '0';
    signal App_RspData      : std_logic_vector(63 downto 0)  := (others => '0');
    signal App_RspLen       : std_logic_vector(3 downto 0)   := (others => '0');
    signal App_RspAbort     : std_logic_vector(31 downto 0)  := (others => '0');
    signal Stat_ErrReg      : std_logic_vector(7 downto 0);
    signal Err_ParamCopy    : std_logic;
    signal Err_AppTimeout   : std_logic;
    signal ErrInj_BitFlip   : std_logic_vector(557 downto 0) := (others => '0');
    signal ErrInj_Valid     : std_logic                      := '0';

    -- *** Bench control ***
    signal CheckEn   : boolean                       := false;
    signal TickPer   : natural                       := 8;      -- clock cycles per tick
    signal AppDelay  : natural                       := 0;      -- cycles from the request to App_ReqReady
    signal AppRspDly : natural                       := 0;      -- cycles from the taken request to App_RspValid
    signal AppNoRdy  : boolean                       := false;  -- never ready
    signal AppNoRsp  : boolean                       := false;  -- no response
    signal AppLate   : natural                       := 0;      -- with AppNoRsp: a response this many ticks after the request, 0 none
    signal AppStray  : boolean                       := false;  -- stray responses while no request is outstanding
    signal AppAbort  : std_logic_vector(31 downto 0) := (others => '0');
    signal AppCnt    : natural                       := 0;      -- requests seen by the responder
    signal CntCopy   : natural                       := 0;      -- cycles with Err_ParamCopy
    signal CntTmo    : natural                       := 0;      -- Err_AppTimeout events
    signal CntSet    : natural                       := 0;      -- Cfg_SetValid events
    signal CntCtog   : natural                       := 0;      -- Cfg_CtoggleValid events

begin

    test_runner_watchdog(runner, 200 ms);

    i_th : entity work.ocan_od_th
        generic map (
            MinimalSet_g     => MinimalSet_g,
            NumRpdo_g        => NumRpdo_g,
            NumTpdo_g        => NumTpdo_g,
            TimePdos_g       => TimePdos_g,
            DeviceType_g     => DeviceType_g,
            VendorId_g       => VendorId_g,
            ProductCode_g    => ProductCode_g,
            Revision_g       => Revision_g,
            SerialNumber_g   => SerialNumber_g,
            ProducerHbTime_g => ProducerHbTime_g,
            MasterNodeId_g   => MasterNodeId_g,
            MasterHbTime_g   => MasterHbTime_g,
            Bdefault_g       => Bdefault_g,
            Ttoggle_g        => Ttoggle_g,
            Ntoggle_g        => Ntoggle_g,
            RpdoType_g       => RpdoType_g,
            TpdoType_g       => TpdoType_g,
            SctCobId_g       => SctCobId_g,
            SctType_g        => SctType_g,
            LtpCobId_g       => LtpCobId_g,
            LtpType_g        => LtpType_g,
            AppPort_g        => AppPort_g
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            Tick_Ms          => Tick_Ms,
            Acc_Valid        => Acc_Valid,
            Acc_Ready        => Acc_Ready,
            Acc_Write        => Acc_Write,
            Acc_Index        => Acc_Index,
            Acc_Sub          => Acc_Sub,
            Acc_Data         => Acc_Data,
            Acc_Len          => Acc_Len,
            Rsp_Valid        => Rsp_Valid,
            Rsp_Data         => Rsp_Data,
            Rsp_Len          => Rsp_Len,
            Rsp_Abort        => Rsp_Abort,
            Nmt_State        => Nmt_State,
            Nmt_NodeId       => Nmt_NodeId,
            Nmt_ResetApp     => Nmt_ResetApp,
            Nmt_ResetComm    => Nmt_ResetComm,
            Cfg_CobId        => Cfg_CobId,
            Cfg_CobIdCopy    => Cfg_CobIdCopy,
            Cfg_HbTime       => Cfg_HbTime,
            Cfg_MasterHbTime => Cfg_MasterHbTime,
            Cfg_Bdefault     => Cfg_Bdefault,
            Cfg_Ttoggle      => Cfg_Ttoggle,
            Cfg_Ntoggle      => Cfg_Ntoggle,
            Cfg_Ctoggle      => Cfg_Ctoggle,
            Cfg_CtoggleValid => Cfg_CtoggleValid,
            Stat_Ctoggle     => Stat_Ctoggle,
            Upd_Valid        => Upd_Valid,
            Upd_Bdefault     => Upd_Bdefault,
            Cfg_SctType      => Cfg_SctType,
            Cfg_LtpType      => Cfg_LtpType,
            Cfg_SetValid     => Cfg_SetValid,
            Cfg_SetScet      => Cfg_SetScet,
            Stat_Scet        => Stat_Scet,
            Cfg_RpdoType     => Cfg_RpdoType,
            Cfg_TpdoType     => Cfg_TpdoType,
            Link_State       => Link_State,
            App_ReqValid     => App_ReqValid,
            App_ReqReady     => App_ReqReady,
            App_ReqWrite     => App_ReqWrite,
            App_ReqIndex     => App_ReqIndex,
            App_ReqSub       => App_ReqSub,
            App_ReqData      => App_ReqData,
            App_ReqLen       => App_ReqLen,
            App_RspValid     => App_RspValid,
            App_RspData      => App_RspData,
            App_RspLen       => App_RspLen,
            App_RspAbort     => App_RspAbort,
            Stat_ErrReg      => Stat_ErrReg,
            Err_ParamCopy    => Err_ParamCopy,
            Err_AppTimeout   => Err_AppTimeout,
            ErrInj_BitFlip   => ErrInj_BitFlip,
            ErrInj_Valid     => ErrInj_Valid
        );

    -----------------------------------------------------------------------------------------------
    -- Tick every TickPer clock cycles
    -----------------------------------------------------------------------------------------------
    p_tick : process is
        variable N_v : natural := 0;
    begin
        wait until rising_edge(Clk);
        N_v := N_v + 1;
        if N_v >= TickPer then
            N_v     := 0;
            Tick_Ms <= '1';
        else
            Tick_Ms <= '0';
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Event counters
    -----------------------------------------------------------------------------------------------
    p_count : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Err_ParamCopy = '1' then
                CntCopy <= CntCopy + 1;
            end if;
            if Err_AppTimeout = '1' then
                CntTmo <= CntTmo + 1;
            end if;
            if Cfg_SetValid = '1' then
                CntSet <= CntSet + 1;
            end if;
            if Cfg_CtoggleValid = '1' then
                CntCtog <= CntCtog + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Responder of the application port (the user logic)
    -----------------------------------------------------------------------------------------------
    p_app : process is
        variable N_v   : natural;
        variable Req_v : std_logic_vector(63 downto 0);
    begin
        App_ReqReady <= '0';
        App_RspValid <= '0';

        loop
            wait until rising_edge(Clk);
            App_RspValid <= '0';
            if App_ReqValid = '1' then
                AppCnt <= AppCnt + 1;
                Req_v  := App_ReqData;
                if AppNoRdy then
                    wait until rising_edge(Clk) and App_ReqValid = '0';
                else

                    for I in 1 to AppDelay loop
                        -- A stray response while the request waits for App_ReqReady is ignored (OD-AP-02)
                        if AppStray then
                            App_RspValid <= '1';
                            App_RspData  <= x"0BAD0BAD0BAD0BAD";
                            App_RspLen   <= x"2";
                        end if;
                        wait until rising_edge(Clk);
                        App_RspValid <= '0';
                    end loop;

                    App_ReqReady <= '1';
                    wait until rising_edge(Clk);
                    App_ReqReady <= '0';
                    if AppNoRsp then
                        if AppLate > 0 then
                            wait for AppLate * TickPer * 25 ns;
                            wait until rising_edge(Clk);
                            App_RspValid <= '1';
                            App_RspData  <= x"5A5A5A5A5A5A5A5A";
                            App_RspLen   <= x"8";
                            App_RspAbort <= x"00000000";
                        end if;
                    else

                        for I in 1 to AppRspDly loop
                            wait until rising_edge(Clk);
                        end loop;

                        App_RspValid <= '1';
                        App_RspData  <= Req_v xor x"0123456789ABCDEF";
                        App_RspLen   <= std_logic_vector(to_unsigned(random(1, 8), 4));
                        App_RspAbort <= AppAbort;
                    end if;
                end if;
            elsif AppStray and random(0, 3) = 0 then
                -- A response while no request is outstanding (OD-AP-02)
                App_RspValid <= '1';
                App_RspData  <= x"DEADBEEFDEADBEEF";
                App_RspLen   <= x"4";
                App_RspAbort <= x"00000000";
            end if;
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Reference model: predicts every output in every cycle (verification plan, section 1)
    -----------------------------------------------------------------------------------------------
    p_model : process is
        variable A_v : MCopy_t := MPower_c;

        -- Quiet checks: an alert only when the DUT differs from the model
        procedure mchk (a : boolean; b : boolean; msg : string) is
        begin
            if a /= b then
                alert(ERROR, msg);
            end if;
        end procedure;

        procedure mchk (a : std_logic_vector; b : std_logic_vector; msg : string) is
        begin
            if a /= b then
                alert(ERROR, msg & ": " & to_hstring(a) & " instead of " & to_hstring(b));
            end if;
        end procedure;

        procedure mchk (a : integer; b : integer; msg : string) is
        begin
            if a /= b then
                alert(ERROR, msg & ": " & to_string(a) & " instead of " & to_string(b));
            end if;
        end procedure;

        variable B_v      : MCopy_t                       := MPower_c;
        variable Latch_v  : boolean                       := false;
        variable App_v    : natural                       := 0;      -- 0 idle, 1 request, 2 wait
        variable Tmo_v    : natural                       := 0;
        variable AReq_v   : std_logic_vector(92 downto 0);
        variable PRsp_v   : boolean                       := false;
        variable PData_v  : std_logic_vector(63 downto 0);
        variable PLen_v   : natural;
        variable PAbort_v : std_logic_vector(31 downto 0);
        variable PTmo_v   : boolean                       := false;
        variable PCtog_v  : boolean                       := false;
        variable Ctog_v   : std_logic_vector(7 downto 0)  := x"00";
        variable PSet_v   : boolean                       := false;
        variable Scet_v   : std_logic_vector(55 downto 0) := (others => '0');
        variable Node_v   : natural;
        variable OkHb_v   : boolean;
        variable OkPr_v   : boolean;
        variable OkTy_v   : boolean;
        variable OkBd_v   : boolean;
        variable OkTt_v   : boolean;
        variable OkNt_v   : boolean;
        variable OutC_v   : MCopy_t;
        variable Cob_v    : boolean;
        variable ErrR_v   : std_logic_vector(7 downto 0);
        variable Tab_v    : std_logic_vector(143 downto 0);
        variable TabB_v   : std_logic_vector(143 downto 0);
        variable Take_v   : boolean;
        variable O_v      : MObj_t;
        variable Idx_v    : natural;
        variable Sub_v    : natural;
        variable Len_v    : natural;
        variable W_v      : unsigned(31 downto 0);
        variable Id_v     : natural;
        variable Ab_v     : std_logic_vector(31 downto 0);
        variable Val_v    : std_logic_vector(63 downto 0);
        variable NewV_v   : boolean;
        variable WrBd_v   : boolean;
        variable Rst_v    : boolean;
        variable St_v     : natural;
        variable Rdy_v    : std_logic;
        variable RsV_v    : std_logic;
        variable RsD_v    : std_logic_vector(63 downto 0);
        variable RsL_v    : natural;
        variable RsA_v    : std_logic_vector(31 downto 0);
    begin
        wait until rising_edge(Clk);

        -- *** Outputs of the cycle before this edge, from the state of that cycle ***
        Node_v := to_integer(unsigned(Nmt_NodeId));
        OkHb_v := A_v.Node = B_v.Node and A_v.HbT = B_v.HbT;
        OkPr_v := A_v.Prod = B_v.Prod;
        OkTy_v := true;

        for E in 1 to 10 loop
            if mExists(E) and A_v.Typ(E) /= B_v.Typ(E) then
                OkTy_v := false;
            end if;
        end loop;

        OkBd_v := A_v.Bdef = B_v.Bdef;
        OkTt_v := A_v.Ttog = B_v.Ttog;
        OkNt_v := A_v.Ntog = B_v.Ntog;
        OutC_v := A_v;
        if not OkHb_v then
            OutC_v.Node := MPower_c.Node;
            OutC_v.HbT  := MPower_c.HbT;
        end if;
        if not OkPr_v then
            OutC_v.Prod := MPower_c.Prod;
        end if;

        for E in 1 to 10 loop
            if mExists(E) and A_v.Typ(E) /= B_v.Typ(E) then
                OutC_v.Typ(E) := MPower_c.Typ(E);
            end if;
        end loop;

        if not OkBd_v then
            OutC_v.Bdef := MPower_c.Bdef;
        end if;
        if not OkTt_v then
            OutC_v.Ttog := MPower_c.Ttog;
        end if;
        if not OkNt_v then
            OutC_v.Ntog := MPower_c.Ntog;
        end if;

        -- COB-ID table of both copies (OD-IF-02, OD-PR-02)
        for E in 0 to 10 loop
            Tab_v(12 * E + 10 downto 12 * E)  := std_logic_vector(to_unsigned(mId(A_v, E, Node_v) mod 2048, 11));
            TabB_v(12 * E + 10 downto 12 * E) := std_logic_vector(to_unsigned(mId(B_v, E, Node_v) mod 2048, 11));
            if E = 0 then
                Tab_v(11)  := '1';
                TabB_v(11) := '1';
            else
                Tab_v(12 * E + 11)  := not A_v.NV(E);
                TabB_v(12 * E + 11) := not B_v.NV(E);
            end if;
        end loop;

        Tab_v(142 downto 132)  := std_logic_vector(to_unsigned(16#700# + OutC_v.Node, 11));
        TabB_v(142 downto 132) := std_logic_vector(to_unsigned(16#700# + OutC_v.Node, 11));
        if OutC_v.Node /= 0 then
            Tab_v(143)  := '1';
            TabB_v(143) := '1';
        else
            Tab_v(143)  := '0';
            TabB_v(143) := '0';
        end if;

        -- Error register (OD-ER-01)
        Cob_v := false;

        for E in 0 to 10 loop
            if mExists(E) and (A_v.NV(E) /= B_v.NV(E) or A_v.Rel(E) /= B_v.Rel(E) or A_v.Id(E) /= B_v.Id(E)) then
                Cob_v := true;
            end if;
        end loop;

        ErrR_v := x"00";
        if Link_State /= "00" then
            ErrR_v(4) := '1';
        end if;
        if Latch_v then
            ErrR_v(7) := '1';
        end if;
        if ErrR_v(4) = '1' or ErrR_v(7) = '1' or Cob_v then
            ErrR_v(0) := '1';
        end if;

        if CheckEn then
            mchk(Acc_Ready = '1', App_v = 0 and not MinimalSet_g, "model: Acc_Ready");
            mchk(Rsp_Valid = '1', PRsp_v, "model: Rsp_Valid");
            if PRsp_v then
                mchk(Rsp_Abort, PAbort_v, "model: Rsp_Abort");
                mchk(Rsp_Data, PData_v, "model: Rsp_Data");
                mchk(to_integer(unsigned(Rsp_Len)), PLen_v, "model: Rsp_Len");
            end if;

            for E in 0 to 11 loop
                if E = 11 or mExists(E) then
                    mchk(Cfg_CobId(12 * E + 11 downto 12 * E), Tab_v(12 * E + 11 downto 12 * E),
                                "model: Cfg_CobId entry " & to_string(E));
                    mchk(Cfg_CobIdCopy(12 * E + 11 downto 12 * E), TabB_v(12 * E + 11 downto 12 * E),
                                "model: Cfg_CobIdCopy entry " & to_string(E));
                else
                    -- Absent entries: constant, not valid (architecture, section 3.3)
                    mchk(Cfg_CobId(12 * E + 11 downto 12 * E), x"000",
                                "model: absent entry " & to_string(E));
                    mchk(Cfg_CobIdCopy(12 * E + 11 downto 12 * E), x"000",
                                "model: absent entry " & to_string(E) & " (copy)");
                end if;
            end loop;

            mchk(to_integer(unsigned(Cfg_HbTime)), OutC_v.Prod, "model: Cfg_HbTime");
            mchk(to_integer(unsigned(Cfg_MasterHbTime)), OutC_v.HbT, "model: Cfg_MasterHbTime");
            mchk(Cfg_Bdefault = '1', OutC_v.Bdef = 1, "model: Cfg_Bdefault");
            mchk(to_integer(unsigned(Cfg_Ttoggle)), OutC_v.Ttog, "model: Cfg_Ttoggle");
            mchk(to_integer(unsigned(Cfg_Ntoggle)), OutC_v.Ntog, "model: Cfg_Ntoggle");
            mchk(Cfg_CtoggleValid = '1', PCtog_v, "model: Cfg_CtoggleValid");
            if PCtog_v then
                mchk(Cfg_Ctoggle, Ctog_v, "model: Cfg_Ctoggle");
            end if;
            mchk(Cfg_SetValid = '1', PSet_v, "model: Cfg_SetValid");
            if PSet_v then
                mchk(Cfg_SetScet, Scet_v, "model: Cfg_SetScet");
            end if;
            if TimePdos_g then
                mchk(to_integer(unsigned(Cfg_SctType)), OutC_v.Typ(1), "model: Cfg_SctType");
                mchk(to_integer(unsigned(Cfg_LtpType)), OutC_v.Typ(10), "model: Cfg_LtpType");
            end if;

            for N in 0 to 3 loop
                if N < NumRpdo_g then
                    mchk(to_integer(unsigned(Cfg_RpdoType(8 * N + 7 downto 8 * N))), OutC_v.Typ(N + 2),
                                "model: Cfg_RpdoType " & to_string(N));
                end if;
                if N < NumTpdo_g then
                    mchk(to_integer(unsigned(Cfg_TpdoType(8 * N + 7 downto 8 * N))), OutC_v.Typ(N + 6),
                                "model: Cfg_TpdoType " & to_string(N));
                end if;
            end loop;

            mchk(Stat_ErrReg, ErrR_v, "model: Stat_ErrReg");
            mchk(Err_ParamCopy = '1', not (OkHb_v and OkPr_v and OkTy_v and OkBd_v and OkTt_v and OkNt_v),
                        "model: Err_ParamCopy");
            mchk(Err_AppTimeout = '1', PTmo_v, "model: Err_AppTimeout");
            mchk(App_ReqValid = '1', App_v = 1, "model: App_ReqValid");
            if App_v = 1 then
                mchk(App_ReqWrite & App_ReqIndex & App_ReqSub & App_ReqData & App_ReqLen, AReq_v,
                            "model: request of the application port");
            end if;
        end if;

        -- *** Next state ***
        PRsp_v  := false;
        PTmo_v  := false;
        PCtog_v := false;
        PSet_v  := false;
        WrBd_v  := false;
        Rst_v   := Nmt_ResetApp = '1' or Nmt_ResetComm = '1';

        -- Repair of copies that disagree (OD-PR-03)
        if not (OkHb_v and OkPr_v and OkTy_v and OkBd_v and OkTt_v and OkNt_v) then
            Latch_v := true;
        end if;
        if not OkHb_v then
            A_v.Node := MPower_c.Node;
            A_v.HbT  := MPower_c.HbT;
            B_v.Node := MPower_c.Node;
            B_v.HbT  := MPower_c.HbT;
        end if;
        if not OkPr_v then
            A_v.Prod := MPower_c.Prod;
            B_v.Prod := MPower_c.Prod;
        end if;

        for E in 1 to 10 loop
            if mExists(E) and A_v.Typ(E) /= B_v.Typ(E) then
                A_v.Typ(E) := MPower_c.Typ(E);
                B_v.Typ(E) := MPower_c.Typ(E);
            end if;
        end loop;

        if not OkBd_v then
            A_v.Bdef := MPower_c.Bdef;
            B_v.Bdef := MPower_c.Bdef;
        end if;
        if not OkTt_v then
            A_v.Ttog := MPower_c.Ttog;
            B_v.Ttog := MPower_c.Ttog;
        end if;
        if not OkNt_v then
            A_v.Ntog := MPower_c.Ntog;
            B_v.Ntog := MPower_c.Ntog;
        end if;

        -- Access of the cycle (OD-1)
        Take_v := Acc_Valid = '1' and App_v = 0 and not MinimalSet_g;
        Idx_v  := to_integer(unsigned(Acc_Index));
        Sub_v  := to_integer(unsigned(Acc_Sub));
        Len_v  := to_integer(unsigned(Acc_Len));
        W_v    := unsigned(Acc_Data(31 downto 0));
        Id_v   := to_integer(W_v(10 downto 0));
        O_v    := mObj(Idx_v, Sub_v);

        if Take_v and O_v.Kind /= KApp then
            Val_v := (others => '0');
            if O_v.Kind = KNone then
                Ab_v := x"06020000";
            elsif not O_v.SubOk then
                Ab_v := x"06090011";
            elsif Acc_Write = '1' and not O_v.Wr then
                Ab_v := x"06010002";
            elsif Acc_Write = '0' and not O_v.Rd then
                Ab_v := x"06010001";
            elsif Acc_Write = '1' and Len_v /= 0 and Len_v > O_v.Size then
                Ab_v := x"06070012";
            elsif Acc_Write = '1' and Len_v /= 0 and Len_v < O_v.Size then
                Ab_v := x"06070013";
            elsif Acc_Write = '1' and O_v.Pre and Nmt_State /= NmtPreOp_c then
                Ab_v := x"08000022";
            elsif Acc_Write = '1' and Nmt_State /= NmtPreOp_c and Nmt_State /= NmtOp_c then
                Ab_v := x"08000022";
            else
                Ab_v := x"00000000";
            end if;

            -- Values of the writes (OD-WR-04 to OD-WR-08)
            NewV_v := false;
            if Acc_Write = '1' and Ab_v = x"00000000" then

                case O_v.Kind is

                    when KSync =>
                        NewV_v := true;
                        if W_v(30) = '1' or W_v(29) = '1' or W_v(28 downto 11) /= 0 or mRestricted(Id_v) then
                            Ab_v := x"06090030";
                        end if;

                    when KCob =>
                        NewV_v := W_v(31) = '0';
                        if W_v(29) = '1' or W_v(28 downto 11) /= 0 then
                            Ab_v := x"06090030";
                        elsif O_v.Ent >= 6 and W_v(30) = '0' then
                            Ab_v := x"06090030";
                        elsif A_v.NV(O_v.Ent) = '0' and B_v.NV(O_v.Ent) = '0' and Id_v /= mId(A_v, O_v.Ent, Node_v) then
                            Ab_v := x"06090030";
                        elsif NewV_v and mRestricted(Id_v) then
                            Ab_v := x"06090030";
                        end if;

                    when KTyp =>
                        if W_v(7 downto 0) > 240 and W_v(7 downto 0) < 254 then
                            Ab_v := x"06090030";
                        end if;

                    when KHb =>
                        if W_v(31 downto 24) /= 0 or W_v(23 downto 16) > 127 then
                            Ab_v := x"06090030";
                        end if;

                    when KBdef =>
                        if W_v(7 downto 0) > 1 then
                            Ab_v := x"06090030";
                        end if;

                    when others =>
                        null;

                end case;

                if Ab_v = x"00000000" and NewV_v then

                    for E in 0 to 10 loop
                        if E /= O_v.Ent and mExists(E) and (E = 0 or A_v.NV(E) = '0') and
                           mId(A_v, E, Node_v) = Id_v then
                            Ab_v := x"06040043";
                        end if;
                    end loop;

                end if;
            end if;

            if Rst_v then
                Ab_v := x"08000022";
            end if;

            -- Read values (OD-OB-03, OD-OB-04)
            if Acc_Write = '0' and Ab_v = x"00000000" then

                case O_v.Kind is

                    when KDev =>
                        Val_v(31 downto 0) := DeviceType_g;
                    when KErr =>
                        Val_v(7 downto 0) := ErrR_v;
                    when KSync =>
                        Val_v(31)          := A_v.NV(0);
                        Val_v(10 downto 0) := std_logic_vector(to_unsigned(A_v.Id(0), 11));
                    when KHbN =>
                        Val_v(7 downto 0) := x"01";
                    when KHb =>
                        Val_v(23 downto 16) := std_logic_vector(to_unsigned(OutC_v.Node, 8));
                        Val_v(15 downto 0)  := std_logic_vector(to_unsigned(OutC_v.HbT, 16));
                    when KProd =>
                        Val_v(15 downto 0) := std_logic_vector(to_unsigned(OutC_v.Prod, 16));
                    when KIdN =>
                        Val_v(7 downto 0) := x"04";
                    when KId =>
                        if O_v.K = 1 then
                            Val_v(31 downto 0) := VendorId_g;
                        elsif O_v.K = 2 then
                            Val_v(31 downto 0) := ProductCode_g;
                        elsif O_v.K = 3 then
                            Val_v(31 downto 0) := Revision_g;
                        else
                            Val_v(31 downto 0) := SerialNumber_g;
                        end if;
                    when KCommN =>
                        Val_v(7 downto 0) := x"02";
                    when KCob =>
                        Val_v(31) := A_v.NV(O_v.Ent);
                        if O_v.Ent >= 6 then
                            Val_v(30) := '1';
                        end if;
                        Val_v(10 downto 0) := std_logic_vector(to_unsigned(mId(A_v, O_v.Ent, Node_v) mod 2048, 11));
                    when KTyp =>
                        Val_v(7 downto 0) := std_logic_vector(to_unsigned(OutC_v.Typ(O_v.Ent), 8));
                    when KMapN =>
                        if O_v.Ent = 1 or O_v.Ent = 10 then
                            Val_v(7 downto 0) := x"01";
                        else
                            Val_v(7 downto 0) := x"08";
                        end if;
                    when KMap =>
                        if O_v.Ent = 1 then
                            Val_v(31 downto 0) := x"20010038";
                        elsif O_v.Ent = 10 then
                            Val_v(31 downto 0) := x"20020038";
                        elsif O_v.Ent <= 5 then
                            Val_v(31 downto 0) := std_logic_vector(to_unsigned(16#2100# + O_v.Ent - 2, 16)) &
                                                  std_logic_vector(to_unsigned(O_v.K, 8)) & x"08";
                        else
                            Val_v(31 downto 0) := std_logic_vector(to_unsigned(16#2200# + O_v.Ent - 6, 16)) &
                                                  std_logic_vector(to_unsigned(O_v.K, 8)) & x"08";
                        end if;
                    when KRedN =>
                        Val_v(7 downto 0) := x"04";
                    when KBdef =>
                        Val_v(7 downto 0) := std_logic_vector(to_unsigned(OutC_v.Bdef, 8));
                    when KTtog =>
                        Val_v(7 downto 0) := std_logic_vector(to_unsigned(OutC_v.Ttog, 8));
                    when KNtog =>
                        Val_v(7 downto 0) := std_logic_vector(to_unsigned(OutC_v.Ntog, 8));
                    when KCtog =>
                        Val_v(7 downto 0) := Stat_Ctoggle;
                    when KGet =>
                        Val_v(55 downto 0) := Stat_Scet;
                    when others =>
                        null;

                end case;

            end if;

            -- Accepted writes (OD-WR-09)
            if Acc_Write = '1' and Ab_v = x"00000000" then

                case O_v.Kind is

                    when KSync | KCob =>
                        A_v.NV(O_v.Ent)  := W_v(31);
                        A_v.Rel(O_v.Ent) := '0';
                        A_v.Id(O_v.Ent)  := Id_v;
                        B_v.NV(O_v.Ent)  := W_v(31);
                        B_v.Rel(O_v.Ent) := '0';
                        B_v.Id(O_v.Ent)  := Id_v;
                    when KTyp =>
                        A_v.Typ(O_v.Ent) := to_integer(W_v(7 downto 0));
                        B_v.Typ(O_v.Ent) := to_integer(W_v(7 downto 0));
                    when KHb =>
                        A_v.Node := to_integer(W_v(22 downto 16));
                        A_v.HbT  := to_integer(W_v(15 downto 0));
                        B_v.Node := A_v.Node;
                        B_v.HbT  := A_v.HbT;
                    when KProd =>
                        A_v.Prod := to_integer(W_v(15 downto 0));
                        B_v.Prod := A_v.Prod;
                    when KBdef =>
                        A_v.Bdef := to_integer(W_v(0 downto 0));
                        B_v.Bdef := A_v.Bdef;
                        WrBd_v   := true;
                    when KTtog =>
                        A_v.Ttog := to_integer(W_v(7 downto 0));
                        B_v.Ttog := A_v.Ttog;
                    when KNtog =>
                        A_v.Ntog := to_integer(W_v(7 downto 0));
                        B_v.Ntog := A_v.Ntog;
                    when KCtog =>
                        PCtog_v := true;
                        Ctog_v  := Acc_Data(7 downto 0);
                    when KSet =>
                        PSet_v := true;
                        Scet_v := Acc_Data(55 downto 0);
                    when others =>
                        null;

                end case;

            end if;

            PRsp_v   := true;
            PAbort_v := Ab_v;
            if Acc_Write = '0' and Ab_v = x"00000000" then
                PData_v := Val_v;
                PLen_v  := O_v.Size;
            else
                PData_v := (others => '0');
                PLen_v  := 0;
            end if;
        end if;

        -- Update of Bdefault (OD-IF-04, OD-WR-10)
        if Upd_Valid = '1' and not WrBd_v then
            if Upd_Bdefault = '1' then
                A_v.Bdef := 1;
            else
                A_v.Bdef := 0;
            end if;
            B_v.Bdef := A_v.Bdef;
        end if;

        -- Application port (OD-4, architecture section 5); an unconnected port has the default inputs (OD-AP-04)
        St_v := App_v;
        if AppPort_g then
            Rdy_v := App_ReqReady;
            RsV_v := App_RspValid;
            RsD_v := App_RspData;
            RsL_v := to_integer(unsigned(App_RspLen));
            RsA_v := App_RspAbort;
        else
            Rdy_v := '1';
            RsV_v := '1';
            RsD_v := (others => '0');
            RsL_v := 0;
            RsA_v := x"06020000";
        end if;
        if St_v = 0 then
            if Take_v and O_v.Kind = KApp then
                App_v  := 1;
                Tmo_v  := 0;
                AReq_v := Acc_Write & Acc_Index & Acc_Sub & Acc_Data & Acc_Len;
            end if;
        else
            if St_v = 1 and Rdy_v = '1' then
                App_v := 2;
            end if;
            if St_v = 2 and RsV_v = '1' then
                -- The response of the user logic, taken in AppWait_s only (OD-AP-02)
                App_v    := 0;
                PRsp_v   := true;
                PData_v  := RsD_v;
                PLen_v   := RsL_v;
                PAbort_v := RsA_v;
            elsif Tick_Ms = '1' then
                if Tmo_v >= 255 then
                    App_v    := 0;
                    PRsp_v   := true;
                    PData_v  := (others => '0');
                    PLen_v   := 0;
                    PAbort_v := x"08000000";
                    PTmo_v   := true;
                else
                    Tmo_v := Tmo_v + 1;
                end if;
            end if;
        end if;

        -- Resets (OD-RS-02, OD-RS-03)
        if Rst_v then
            Latch_v := Latch_v and Nmt_ResetComm = '0';

            for E in 0 to 10 loop
                A_v.NV(E)  := MPower_c.NV(E);
                A_v.Rel(E) := MPower_c.Rel(E);
                A_v.Id(E)  := MPower_c.Id(E);
            end loop;

            A_v.Node := MPower_c.Node;
            A_v.HbT  := MPower_c.HbT;
            A_v.Prod := MPower_c.Prod;
            A_v.Typ  := MPower_c.Typ;
            B_v.NV   := A_v.NV;
            B_v.Rel  := A_v.Rel;
            B_v.Id   := A_v.Id;
            B_v.Node := A_v.Node;
            B_v.HbT  := A_v.HbT;
            B_v.Prod := A_v.Prod;
            B_v.Typ  := A_v.Typ;
            if St_v /= 0 then
                PRsp_v := false;
                PTmo_v := false;
            elsif Take_v and O_v.Kind = KApp then
                PRsp_v   := true;
                PData_v  := (others => '0');
                PLen_v   := 0;
                PAbort_v := x"08000022";
            end if;
            App_v := 0;
        end if;

        -- Test inputs (OD-PR-04)
        if ErrInj_Valid = '1' then
            A_v := mFlip(A_v, ErrInj_BitFlip(278 downto 0));
            B_v := mFlip(B_v, ErrInj_BitFlip(557 downto 279));
        end if;

        -- Hardware reset
        if Rst = '1' then
            A_v     := MPower_c;
            B_v     := MPower_c;
            Latch_v := false;
            App_v   := 0;
            Tmo_v   := 0;
            PRsp_v  := false;
            PTmo_v  := false;
            PCtog_v := false;
            PSet_v  := false;
            CheckEn <= true;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable Ab_v  : std_logic_vector(31 downto 0);
        variable Dat_v : std_logic_vector(63 downto 0);
        variable Len_v : natural;

        procedure clocks (n : natural) is
        begin

            for I in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- One access of ocan_sdo: taken at the first clock edge with Acc_Ready, answered by Rsp_Valid
        procedure acc (
            wr   : std_logic;
            idx  : natural;
            sub  : natural;
            data : std_logic_vector(63 downto 0);
            len  : natural) is
            variable N_v : natural;
        begin
            wait until rising_edge(Clk);
            Acc_Valid <= '1';
            Acc_Write <= wr;
            Acc_Index <= std_logic_vector(to_unsigned(idx, 16));
            Acc_Sub   <= std_logic_vector(to_unsigned(sub, 8));
            Acc_Data  <= data;
            Acc_Len   <= std_logic_vector(to_unsigned(len, 4));
            N_v       := 0;

            loop
                wait until rising_edge(Clk);
                N_v := N_v + 1;
                exit when Acc_Ready = '1' or N_v > 100000;
            end loop;

            Acc_Valid <= '0';
            N_v       := 0;

            loop
                exit when Rsp_Valid = '1' or N_v > 400 * TickPer;
                wait until rising_edge(Clk);
                N_v := N_v + 1;
            end loop;

            check_value(Rsp_Valid, '1', ERROR, "answer of the access to " & to_hstring(to_unsigned(idx, 16)));
            Ab_v  := Rsp_Abort;
            Dat_v := Rsp_Data;
            Len_v := to_integer(unsigned(Rsp_Len));
        end procedure;

        procedure wr (
            idx   : natural;
            sub   : natural;
            value : natural;
            len   : natural;
            abort : std_logic_vector(31 downto 0);
            msg   : string) is
        begin
            acc('1', idx, sub, std_logic_vector(to_unsigned(value, 64)), len);
            check_value(Ab_v, abort, ERROR, msg);
        end procedure;

        procedure wr32 (
            idx   : natural;
            sub   : natural;
            value : std_logic_vector(31 downto 0);
            abort : std_logic_vector(31 downto 0);
            msg   : string) is
        begin
            acc('1', idx, sub, x"00000000" & value, 4);
            check_value(Ab_v, abort, ERROR, msg);
        end procedure;

        procedure rd (idx : natural; sub : natural; abort : std_logic_vector(31 downto 0); msg : string) is
        begin
            acc('0', idx, sub, (others => '0'), 0);
            check_value(Ab_v, abort, ERROR, msg);
        end procedure;

        -- Inversion of selected bits through the test inputs, in one clock cycle
        procedure inject (bits : std_logic_vector(557 downto 0)) is
        begin
            wait until rising_edge(Clk);
            ErrInj_BitFlip <= bits;
            ErrInj_Valid   <= '1';
            wait until rising_edge(Clk);
            ErrInj_Valid   <= '0';
            ErrInj_BitFlip <= (others => '0');
        end procedure;

        procedure resetComm is
        begin
            wait until rising_edge(Clk);
            Nmt_ResetComm <= '1';
            wait until rising_edge(Clk);
            Nmt_ResetComm <= '0';
        end procedure;

        -- Index of the communication object of COB-ID entry e
        function commIndex (e : natural) return natural is
        begin
            if e = 0 then
                return 16#1005#;
            elsif e = 1 then
                return 16#1404#;
            elsif e <= 5 then
                return 16#1400# + e - 2;
            elsif e <= 9 then
                return 16#1800# + e - 6;
            else
                return 16#1804#;
            end if;
        end function;

        function single (n : natural) return std_logic_vector is
            variable S_v : std_logic_vector(557 downto 0) := (others => '0');
        begin
            S_v(n) := '1';
            return S_v;
        end function;

        variable Exists_v : boolean;
        variable Val_v    : natural;
        variable Id_v     : natural;
        variable Bits_v   : std_logic_vector(557 downto 0);
        variable N_v      : natural;
        variable Idx_v    : natural;
        variable Sub_v    : natural;
    begin
        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            Rst        <= '1';
            Nmt_State  <= NmtPreOp_c;
            Nmt_NodeId <= std_logic_vector(to_unsigned(5, 7));
            AppDelay   <= 0;
            AppRspDly  <= 0;
            AppNoRdy   <= false;
            AppNoRsp   <= false;
            AppLate    <= 0;
            AppStray   <= false;
            AppAbort   <= (others => '0');
            TickPer    <= 8;
            Link_State <= "00";
            clocks(4);
            Rst        <= '0';
            clocks(4);

            -- *** TC-OD-01: every object of table 1 read ***
            if run("test_read_all") then
                rd(16#1000#, 0, x"00000000", "1000h");
                rd(16#1001#, 0, x"00000000", "1001h");
                rd(16#1005#, 0, x"00000000", "1005h");
                rd(16#1016#, 0, x"00000000", "1016h sub-index 00h");
                rd(16#1016#, 1, x"00000000", "1016h sub-index 01h");
                rd(16#1017#, 0, x"00000000", "1017h");

                for S in 0 to 4 loop
                    rd(16#1018#, S, x"00000000", "1018h");
                end loop;

                for E in 1 to 10 loop
                    if mExists(E) then
                        Idx_v := commIndex(E);

                        for S in 0 to 2 loop
                            rd(Idx_v, S, x"00000000", "communication object of entry " & to_string(E));
                        end loop;

                        if E = 1 or E = 10 then
                            N_v := 1;
                        else
                            N_v := 8;
                        end if;

                        for S in 0 to N_v loop
                            rd(Idx_v + 16#200#, S, x"00000000", "mapping object of entry " & to_string(E));
                        end loop;

                    end if;
                end loop;

                for S in 0 to 4 loop
                    rd(16#2000#, S, x"00000000", "2000h");
                end loop;

                rd(16#2002#, 0, x"00000000", "2002h");
                -- After writes
                wr32(16#1016#, 1, x"00230ABC", x"00000000", "write 1016h");
                wr(16#1017#, 0, 16#1234#, 2, x"00000000", "write 1017h");
                wr(16#2000#, 1, 1, 1, x"00000000", "write Bdefault");
                wr(16#2000#, 2, 77, 1, x"00000000", "write Ttoggle");
                wr(16#2000#, 3, 99, 1, x"00000000", "write Ntoggle");
                if NumRpdo_g > 0 then
                    wr(16#1400#, 2, 17, 1, x"00000000", "write a transmission type");
                    rd(16#1400#, 2, x"00000000", "transmission type read back");
                end if;
                rd(16#1016#, 1, x"00000000", "1016h read back");
                rd(16#1017#, 0, x"00000000", "1017h read back");

                for S in 1 to 3 loop
                    rd(16#2000#, S, x"00000000", "2000h read back");
                end loop;

            -- *** TC-OD-02: absent objects and sub-indices ***
            elsif run("test_absent") then

                for I in 0 to 17 loop

                    case I is
                        when 0 => Idx_v := 16#0000#;
                        when 1 => Idx_v := 16#0FFF#;
                        when 2 => Idx_v := 16#1002#;
                        when 3 => Idx_v := 16#1003#;
                        when 4 => Idx_v := 16#1006#;
                        when 5 => Idx_v := 16#100C#;
                        when 6 => Idx_v := 16#1010#;
                        when 7 => Idx_v := 16#1012#;
                        when 8 => Idx_v := 16#1014#;
                        when 9 => Idx_v := 16#1019#;
                        when 10 => Idx_v := 16#1200#;
                        when 11 => Idx_v := 16#1405#;
                        when 12 => Idx_v := 16#1605#;
                        when 13 => Idx_v := 16#1805#;
                        when 14 => Idx_v := 16#1A05#;
                        when 15 => Idx_v := 16#1FFF#;
                        when 16 => Idx_v := 16#A000#;
                        when others => Idx_v := 16#FFFF#;
                    end case;

                    rd(Idx_v, 0, x"06020000", "absent index " & to_hstring(to_unsigned(Idx_v, 16)));
                    wr(Idx_v, 0, 0, 1, x"06020000", "absent index " & to_hstring(to_unsigned(Idx_v, 16)));
                end loop;

                -- Objects of absent PDOs
                for E in 1 to 10 loop
                    if not mExists(E) then
                        rd(commIndex(E), 1, x"06020000", "absent communication object of entry " & to_string(E));
                        rd(commIndex(E) + 16#200#, 0, x"06020000", "absent mapping object of entry " & to_string(E));
                    end if;
                end loop;

                -- Absent sub-indices
                rd(16#1000#, 1, x"06090011", "1000h sub-index 01h");
                rd(16#1001#, 1, x"06090011", "1001h sub-index 01h");
                rd(16#1005#, 1, x"06090011", "1005h sub-index 01h");
                rd(16#1016#, 2, x"06090011", "1016h sub-index 02h");
                rd(16#1017#, 1, x"06090011", "1017h sub-index 01h");
                rd(16#1018#, 5, x"06090011", "1018h sub-index 05h");
                rd(16#2000#, 5, x"06090011", "2000h sub-index 05h");
                rd(16#2001#, 1, x"06090011", "2001h sub-index 01h");
                rd(16#2002#, 1, x"06090011", "2002h sub-index 01h");

                for E in 1 to 10 loop
                    if mExists(E) then
                        rd(commIndex(E), 3, x"06090011", "communication sub-index 03h");
                        rd(commIndex(E), 6, x"06090011", "communication sub-index 06h");
                        if E = 1 or E = 10 then
                            rd(commIndex(E) + 16#200#, 2, x"06090011", "mapping sub-index 02h");
                        else
                            rd(commIndex(E) + 16#200#, 9, x"06090011", "mapping sub-index 09h");
                        end if;
                    end if;
                end loop;

            -- *** TC-OD-03: access types ***
            elsif run("test_access_types") then
                wr(16#1000#, 0, 0, 4, x"06010002", "write 1000h");
                wr(16#1001#, 0, 0, 1, x"06010002", "write 1001h");
                wr(16#1016#, 0, 1, 1, x"06010002", "write 1016h sub-index 00h");

                for S in 0 to 4 loop
                    wr(16#1018#, S, 0, 4, x"06010002", "write 1018h");
                end loop;

                for E in 1 to 10 loop
                    if mExists(E) then
                        wr(commIndex(E), 0, 2, 1, x"06010002", "write a highest sub-index");
                        wr(commIndex(E) + 16#200#, 0, 8, 1, x"06010002", "write a mapping object");
                        wr(commIndex(E) + 16#200#, 1, 0, 4, x"06010002", "write a mapped object");
                    end if;
                end loop;

                wr(16#2000#, 0, 4, 1, x"06010002", "write 2000h sub-index 00h");
                acc('1', 16#2002#, 0, (others => '0'), 7);
                check_value(Ab_v, x"06010002", ERROR, "write 2002h");
                rd(16#2001#, 0, x"06010001", "read 2001h");

            -- *** TC-OD-04: number of data bytes ***
            elsif run("test_lengths") then

                -- The number of bytes not indicated (0): the size of the data type, no length check (OD-WR-02)
                wr(16#1005#, 0, 16#80#, 0, x"00000000", "1005h, number not indicated");
                wr(16#1017#, 0, 16#0BB8#, 0, x"00000000", "1017h, number not indicated");
                wr32(16#1016#, 1, x"000307D0", x"00000000", "1016h, number 4");
                acc('1', 16#1016#, 1, x"FFFFFFFF000307D1", 0);
                check_value(Ab_v, x"00000000", ERROR, "1016h, number not indicated, upper bytes ignored");

                for S in 1 to 4 loop
                    wr(16#2000#, S, 1, 0, x"00000000", "2000h, number not indicated");
                end loop;

                acc('1', 16#2001#, 0, x"FF11223344556677", 0);
                check_value(Ab_v, x"00000000", ERROR, "2001h, number not indicated");
                if NumTpdo_g > 0 then
                    wr(16#1800#, 2, 254, 0, x"00000000", "1800h sub-index 02h, number not indicated");
                end if;
                rd(16#1017#, 0, x"00000000", "1017h read back");
                rd(16#1016#, 1, x"00000000", "1016h read back");

                for L in 1 to 8 loop
                    -- 1005h, 4 bytes, the value 080h
                    if L > 4 then
                        wr(16#1005#, 0, 16#80#, L, x"06070012", "1005h");
                    elsif L < 4 then
                        wr(16#1005#, 0, 16#80#, L, x"06070013", "1005h");
                    else
                        wr(16#1005#, 0, 16#80#, L, x"00000000", "1005h");
                    end if;
                    -- 1017h, 2 bytes
                    if L > 2 then
                        wr(16#1017#, 0, 500, L, x"06070012", "1017h");
                    elsif L < 2 then
                        wr(16#1017#, 0, 500, L, x"06070013", "1017h");
                    else
                        wr(16#1017#, 0, 500, L, x"00000000", "1017h");
                    end if;

                    -- 2000h, 1 byte
                    for S in 1 to 4 loop
                        if L > 1 then
                            wr(16#2000#, S, 1, L, x"06070012", "2000h");
                        else
                            wr(16#2000#, S, 1, L, x"00000000", "2000h");
                        end if;
                    end loop;

                    -- 1016h sub-index 01h, 4 bytes
                    if L > 4 then
                        wr(16#1016#, 1, 16#00050100#, L, x"06070012", "1016h");
                    elsif L < 4 then
                        wr(16#1016#, 1, 16#00050100#, L, x"06070013", "1016h");
                    else
                        wr(16#1016#, 1, 16#00050100#, L, x"00000000", "1016h");
                    end if;
                    -- 2001h, 7 bytes
                    acc('1', 16#2001#, 0, x"0011223344556677", L);
                    if L > 7 then
                        check_value(Ab_v, x"06070012", ERROR, "2001h");
                    elsif L < 7 then
                        check_value(Ab_v, x"06070013", ERROR, "2001h");
                    else
                        check_value(Ab_v, x"00000000", ERROR, "2001h");
                    end if;
                    -- Transmission type, 1 byte
                    if NumTpdo_g > 0 then
                        if L > 1 then
                            wr(16#1800#, 2, 1, L, x"06070012", "1800h sub-index 02h");
                        else
                            wr(16#1800#, 2, 1, L, x"00000000", "1800h sub-index 02h");
                        end if;
                    end if;
                end loop;

            -- *** TC-OD-05: NMT states ***
            elsif run("test_states") then

                for S in 0 to 3 loop
                    Nmt_State <= std_logic_vector(to_unsigned(S, 2));
                    clocks(1);
                    -- Communication parameters: Pre-operational only
                    if std_logic_vector(to_unsigned(S, 2)) = NmtPreOp_c then
                        wr(16#1005#, 0, 16#80#, 4, x"00000000", "1005h in Pre-operational");
                    else
                        wr(16#1005#, 0, 16#80#, 4, x"08000022", "1005h outside Pre-operational");
                    end if;
                    if NumRpdo_g > 0 then
                        if std_logic_vector(to_unsigned(S, 2)) = NmtPreOp_c then
                            wr(16#1400#, 2, 254, 1, x"00000000", "transmission type in Pre-operational");
                        else
                            wr(16#1400#, 2, 254, 1, x"08000022", "transmission type outside Pre-operational");
                        end if;
                    end if;
                    -- Heartbeat times, 2000h, 2001h: Pre-operational and Operational
                    if std_logic_vector(to_unsigned(S, 2)) = NmtPreOp_c or std_logic_vector(to_unsigned(S, 2)) = NmtOp_c then
                        wr(16#1017#, 0, 1000, 2, x"00000000", "1017h");
                        wr(16#2000#, 2, 3, 1, x"00000000", "Ttoggle");
                        wr32(16#1016#, 1, x"000105DC", x"00000000", "1016h");
                    else
                        wr(16#1017#, 0, 1000, 2, x"08000022", "1017h");
                        wr(16#2000#, 2, 3, 1, x"08000022", "Ttoggle");
                        wr32(16#1016#, 1, x"000105DC", x"08000022", "1016h");
                    end if;
                end loop;

                Nmt_State <= NmtPreOp_c;

            -- *** TC-OD-06: COB-ID rules ***
            elsif run("test_cob_id_rules") then
                Nmt_NodeId <= std_logic_vector(to_unsigned(5, 7));
                clocks(2);

                for E in 2 to 9 loop
                    if mExists(E) then
                        Idx_v := commIndex(E);
                        -- Valid: no change of the identifier, an invalidation is taken
                        if E <= 5 then
                            Id_v := 16#200# + (E - 2) * 16#100# + 5;
                            wr32(Idx_v, 1, std_logic_vector(to_unsigned(Id_v + 1, 32)), x"06090030", "change while valid");
                            wr32(Idx_v, 1, x"80000000" or std_logic_vector(to_unsigned(Id_v, 32)), x"00000000", "invalidate");
                        else
                            Id_v := 16#180# + (E - 6) * 16#100# + 5;
                            wr32(Idx_v, 1, x"40000000" or std_logic_vector(to_unsigned(Id_v + 1, 32)), x"06090030",
                                 "change while valid");
                            wr32(Idx_v, 1, x"C0000000" or std_logic_vector(to_unsigned(Id_v, 32)), x"00000000", "invalidate");
                            -- Remote frames refused
                            wr32(Idx_v, 1, x"80000000" or std_logic_vector(to_unsigned(Id_v, 32)), x"06090030",
                                 "bit 30 = 0");
                        end if;
                        -- 29-bit identifier, bits 28 to 11
                        wr32(Idx_v, 1, x"E0000000" or std_logic_vector(to_unsigned(Id_v, 32)), x"06090030", "bit 29");
                        wr32(Idx_v, 1, x"C0000800" or std_logic_vector(to_unsigned(Id_v, 32)), x"06090030", "bit 11");

                        -- Restricted and free identifiers at both ends and inside (table 40, clause 9.5a)
                        for R in 0 to 19 loop

                            case R is
                                when 0 => Val_v := 16#000#;
                                when 1 => Val_v := 16#001#;
                                when 2 => Val_v := 16#07F#;
                                when 3 => Val_v := 16#101#;
                                when 4 => Val_v := 16#140#;
                                when 5 => Val_v := 16#180#;
                                when 6 => Val_v := 16#581#;
                                when 7 => Val_v := 16#5FF#;
                                when 8 => Val_v := 16#601#;
                                when 9 => Val_v := 16#67F#;
                                when 10 => Val_v := 16#6E0#;
                                when 11 => Val_v := 16#6FF#;
                                when 12 => Val_v := 16#701#;
                                when 13 => Val_v := 16#77F#;
                                when 14 => Val_v := 16#780#;
                                when 15 => Val_v := 16#781#;
                                when 16 => Val_v := 16#7DE#;
                                when 17 => Val_v := 16#7DF#;
                                when 18 => Val_v := 16#7F0#;
                                when others => Val_v := 16#7FF#;
                            end case;

                            wr32(Idx_v, 1, x"40000000" or std_logic_vector(to_unsigned(Val_v, 32)), x"06090030",
                                 "restricted identifier " & to_hstring(to_unsigned(Val_v, 12)));
                            -- Not valid: any identifier is taken
                            wr32(Idx_v, 1, x"C0000000" or std_logic_vector(to_unsigned(Val_v, 32)), x"00000000",
                                 "restricted identifier, not valid");
                        end loop;

                        -- Neighbours outside the restricted ranges
                        for R in 0 to 4 loop

                            case R is
                                when 0 => Val_v := 16#100#;
                                when 1 => Val_v := 16#580#;
                                when 2 => Val_v := 16#600#;
                                when 3 => Val_v := 16#680#;
                                when others => Val_v := 16#6DF#;
                            end case;

                            wr32(Idx_v, 1, x"40000000" or std_logic_vector(to_unsigned(Val_v, 32)), x"00000000",
                                 "identifier next to a restricted range");
                            wr32(Idx_v, 1, x"C0000000" or std_logic_vector(to_unsigned(Val_v, 32)), x"00000000",
                                 "invalidate");
                        end loop;

                        -- Duplicates of every other valid entry
                        for D in 0 to 10 loop
                            if D /= E and mExists(D) and D >= 2 and D <= 9 then
                                if D <= 5 then
                                    Val_v := 16#200# + (D - 2) * 16#100# + 5;
                                else
                                    Val_v := 16#180# + (D - 6) * 16#100# + 5;
                                end if;
                                wr32(Idx_v, 1, x"40000000" or std_logic_vector(to_unsigned(Val_v, 32)), x"06040043",
                                     "duplicate of entry " & to_string(D));
                            end if;
                        end loop;

                        wr32(Idx_v, 1, x"40000080", x"06040043", "duplicate of SYNC");
                        -- The abort order: the NMT state before the value
                        Nmt_State <= NmtOp_c;
                        wr32(Idx_v, 1, x"E0000000", x"08000022", "state before value");
                        Nmt_State <= NmtPreOp_c;
                        -- Back to the default
                        wr32(Idx_v, 1, x"40000000" or std_logic_vector(to_unsigned(Id_v, 32)), x"00000000", "valid again");
                    end if;
                end loop;

                -- SYNC
                wr32(16#1005#, 0, x"40000080", x"06090030", "SYNC producer");
                wr32(16#1005#, 0, x"20000080", x"06090030", "SYNC 29 bits");
                wr32(16#1005#, 0, x"00000880", x"06090030", "SYNC bit 11");
                wr32(16#1005#, 0, x"00000001", x"06090030", "SYNC restricted");
                wr32(16#1005#, 0, x"80000090", x"00000000", "SYNC with bit 31");
                wr32(16#1005#, 0, x"00000080", x"00000000", "SYNC 080h");

            -- *** TC-OD-07: transmission types ***
            elsif run("test_types") then

                for E in 1 to 10 loop
                    if mExists(E) then

                        for T in 0 to 255 loop
                            if T <= 240 or T >= 254 then
                                wr(commIndex(E), 2, T, 1, x"00000000", "transmission type " & to_string(T));
                            else
                                wr(commIndex(E), 2, T, 1, x"06090030", "transmission type " & to_string(T));
                            end if;
                        end loop;

                    end if;
                end loop;

            -- *** TC-OD-08: 1016h and 2000h ***
            elsif run("test_redundancy_objects") then
                wr32(16#1016#, 1, x"01010100", x"06090030", "reserved bits");
                wr32(16#1016#, 1, x"00800100", x"06090030", "NODE-ID 128");
                wr32(16#1016#, 1, x"00000100", x"00000000", "NODE-ID 0");
                wr32(16#1016#, 1, x"00010000", x"00000000", "time 0");
                wr32(16#1016#, 1, x"007FFFFF", x"00000000", "NODE-ID 127");
                wr32(16#1016#, 1, x"00010640", x"00000000", "NODE-ID 1");

                for V in 0 to 255 loop
                    if V <= 1 then
                        wr(16#2000#, 1, V, 1, x"00000000", "Bdefault " & to_string(V));
                    else
                        wr(16#2000#, 1, V, 1, x"06090030", "Bdefault " & to_string(V));
                    end if;
                end loop;

                wr(16#2000#, 2, 0, 1, x"00000000", "Ttoggle 0");
                wr(16#2000#, 2, 255, 1, x"00000000", "Ttoggle 255");
                wr(16#2000#, 3, 0, 1, x"00000000", "Ntoggle 0");
                wr(16#2000#, 3, 255, 1, x"00000000", "Ntoggle 255");
                N_v := CntCtog;
                wr(16#2000#, 4, 42, 1, x"00000000", "write Ctoggle");
                clocks(2);
                check_value(CntCtog, N_v + 1, ERROR, "Ctoggle write event");

                for I in 1 to 20 loop
                    Stat_Ctoggle <= std_logic_vector(to_unsigned(random(0, 255), 8));
                    rd(16#2000#, 4, x"00000000", "read Ctoggle");
                end loop;

            -- *** TC-OD-09: parameters at the outputs, the NODE-ID ***
            elsif run("test_outputs") then

                for I in 1 to 3 loop
                    Nmt_NodeId <= std_logic_vector(to_unsigned(random(1, 127), 7));
                    clocks(3);
                    wr32(16#1016#, 1, std_logic_vector(to_unsigned(random(0, 127) * 65536 + random(0, 65535), 32)),
                         x"00000000", "1016h");
                    wr(16#1017#, 0, random(0, 65535), 2, x"00000000", "1017h");
                    wr(16#2000#, 1, random(0, 1), 1, x"00000000", "Bdefault");
                    wr(16#2000#, 2, random(0, 255), 1, x"00000000", "Ttoggle");
                    wr(16#2000#, 3, random(0, 255), 1, x"00000000", "Ntoggle");

                    for E in 1 to 10 loop
                        if mExists(E) then
                            wr(commIndex(E), 2, random(0, 240), 1, x"00000000", "transmission type");
                        end if;
                    end loop;

                    if mExists(2) then
                        rd(16#1400#, 1, x"00000000", "receive PDO 1");
                        wr32(16#1400#, 1, x"80000000" or Dat_v(31 downto 0), x"00000000", "receive PDO 1 not valid");
                        wr32(16#1400#, 1, std_logic_vector(to_unsigned(16#3F0# + I, 32)), x"00000000",
                             "receive PDO 1 with an absolute identifier");
                    end if;
                end loop;

                if TimePdos_g then
                    wr32(16#1404#, 1, x"000000F1", x"00000000", "Spacecraft Time PDO valid");
                    wr32(16#1804#, 1, x"400001F7", x"00000000", "Local Time PDO valid");
                end if;
                clocks(5);

            -- *** TC-OD-10: Local SCET Set and Get ***
            elsif run("test_scet_objects") then

                for I in 1 to 50 loop
                    Dat_v     := std_logic_vector(to_unsigned(random(0, 2 ** 28 - 1), 28)) &
                                 std_logic_vector(to_unsigned(random(0, 2 ** 28 - 1), 28)) & x"00";
                    N_v       := CntSet;
                    acc('1', 16#2001#, 0, x"00" & Dat_v(63 downto 8), 7);
                    check_value(Ab_v, x"00000000", ERROR, "write 2001h");
                    clocks(1);
                    check_value(CntSet, N_v + 1, ERROR, "Cfg_SetValid");
                    Stat_Scet <= Dat_v(55 downto 0);
                    rd(16#2002#, 0, x"00000000", "read 2002h");
                    check_value(Len_v, 7, ERROR, "seven bytes");
                end loop;

            -- *** TC-OD-11: same-cycle rules ***
            elsif run("test_same_cycle") then

                -- A write of Bdefault in the cycle of the update by ocan_redundancy: the write wins
                for V in 0 to 1 loop
                    wait until rising_edge(Clk);
                    Acc_Valid    <= '1';
                    Acc_Write    <= '1';
                    Acc_Index    <= x"2000";
                    Acc_Sub      <= x"01";
                    Acc_Data     <= std_logic_vector(to_unsigned(V, 64));
                    Acc_Len      <= x"1";
                    Upd_Valid    <= '1';
                    Upd_Bdefault <= '1' when V = 0 else '0';
                    wait until rising_edge(Clk);
                    Acc_Valid    <= '0';
                    Upd_Valid    <= '0';
                    clocks(3);
                    check_value(Cfg_Bdefault = '1', V = 1, ERROR, "the write wins over the update");
                end loop;

                -- A reset in the cycle of an access: the access has no effect
                for K in 0 to 1 loop
                    wait until rising_edge(Clk);
                    Acc_Valid <= '1';
                    Acc_Write <= '1';
                    Acc_Index <= x"1017";
                    Acc_Sub   <= x"00";
                    Acc_Data  <= x"0000000000000777";
                    Acc_Len   <= x"2";
                    if K = 0 then
                        Nmt_ResetApp <= '1';
                    else
                        Nmt_ResetComm <= '1';
                    end if;
                    wait until rising_edge(Clk);
                    Acc_Valid     <= '0';
                    Nmt_ResetApp  <= '0';
                    Nmt_ResetComm <= '0';
                    clocks(3);
                    check_value(to_integer(unsigned(Cfg_HbTime)), ProducerHbTime_g, ERROR, "no effect of the access");
                end loop;

                -- A reset in the cycle of an access to the user logic: the state abort, no request to the user logic
                for K in 0 to 1 loop
                    N_v       := AppCnt;
                    wait until rising_edge(Clk);
                    Acc_Valid <= '1';
                    Acc_Write <= '0';
                    Acc_Index <= x"2100";
                    Acc_Sub   <= x"00";
                    Acc_Data  <= (others => '0');
                    Acc_Len   <= x"0";
                    if K = 0 then
                        Nmt_ResetApp <= '1';
                    else
                        Nmt_ResetComm <= '1';
                    end if;
                    wait until rising_edge(Clk);
                    Acc_Valid     <= '0';
                    Nmt_ResetApp  <= '0';
                    Nmt_ResetComm <= '0';
                    clocks(5);
                    check_value(AppCnt, N_v, ERROR, "no request to the user logic in the cycle of a reset");
                end loop;

                -- A write in the cycle of an injected disagreement of the same parameter: the write wins
                wait until rising_edge(Clk);
                Acc_Valid      <= '1';
                Acc_Write      <= '1';
                Acc_Index      <= x"1017";
                Acc_Sub        <= x"00";
                Acc_Data       <= x"0000000000000321";
                Acc_Len        <= x"2";
                ErrInj_BitFlip <= single(170);
                ErrInj_Valid   <= '1';
                wait until rising_edge(Clk);
                Acc_Valid      <= '0';
                ErrInj_Valid   <= '0';
                ErrInj_BitFlip <= (others => '0');
                clocks(4);
                resetComm;
                clocks(2);

                -- A write in the cycle after the injection, while the copies disagree: the write wins over the repair
                wait until rising_edge(Clk);
                ErrInj_BitFlip <= single(170);
                ErrInj_Valid   <= '1';
                wait until rising_edge(Clk);
                ErrInj_Valid   <= '0';
                ErrInj_BitFlip <= (others => '0');
                Acc_Valid      <= '1';
                Acc_Write      <= '1';
                Acc_Index      <= x"1017";
                Acc_Sub        <= x"00";
                Acc_Data       <= x"0000000000000654";
                Acc_Len        <= x"2";
                wait until rising_edge(Clk);
                Acc_Valid      <= '0';
                clocks(3);
                check_value(to_integer(unsigned(Cfg_HbTime)), 16#654#, ERROR, "the write wins over the repair");
                check_value(Stat_ErrReg(7), '1', ERROR, "the disagreement is latched all the same");

            -- *** TC-OD-12: COB-ID copies ***
            elsif run("test_cob_copies") then

                for E in 0 to 10 loop
                    if mExists(E) then

                        for Bt in 0 to 12 loop

                            for Cp in 0 to 1 loop
                                inject(single(279 * Cp + 13 * E + Bt));
                                clocks(3);
                                check_value(Stat_ErrReg(0), '1', ERROR, "bit 0 while the copies disagree");
                                -- A read returns the first copy; the disagreement persists
                                if E = 0 then
                                    rd(16#1005#, 0, x"00000000", "read while the copies disagree");
                                else
                                    rd(commIndex(E), 1, x"00000000", "read while the copies disagree");
                                end if;
                                clocks(3);
                                if Bt mod 2 = 0 and Bt /= 12 then
                                    resetComm;
                                else
                                    -- A write of the object repairs both copies; invalidate first if valid
                                    if E = 0 then
                                        wr32(16#1005#, 0, x"00000080", x"00000000", "repair by a write");
                                    else
                                        acc('1', commIndex(E), 1, x"00000000C0000000", 4);
                                        resetComm;
                                    end if;
                                end if;
                                clocks(2);
                                check_value(Stat_ErrReg(0), '0', ERROR, "copies equal again");
                            end loop;

                        end loop;

                    else

                        -- An absent entry: a flip has no effect, both copies of the table stay 0, so that
                        -- ocan_dispatch sees no disagreement (Err_CobId); no Err_ParamCopy (architecture, section 3.3)
                        for Bt in 0 to 12 loop

                            for Cp in 0 to 1 loop
                                N_v := CntCopy;
                                inject(single(279 * Cp + 13 * E + Bt));
                                clocks(3);
                                check_value(Stat_ErrReg(0), '0', ERROR, "no effect of a flip of absent entry " &
                                            to_string(E));
                                check_value(Cfg_CobId(12 * E + 11 downto 12 * E) = Cfg_CobIdCopy(12 * E + 11 downto 12 * E),
                                            true, ERROR, "both copies of absent entry " & to_string(E) & " equal");
                                check_value(CntCopy, N_v, ERROR, "no Err_ParamCopy");
                            end loop;

                        end loop;

                    end if;
                end loop;

            -- *** TC-OD-13: copies of the other parameters ***
            elsif run("test_param_copies") then

                for Bt in 143 to 278 loop
                    -- Bits of absent transmission types have no effect
                    Exists_v := true;
                    if Bt >= 182 and Bt <= 261 then
                        N_v := (Bt - 182) / 8;
                        if N_v <= 3 then
                            Exists_v := N_v < NumRpdo_g;
                        elsif N_v <= 7 then
                            Exists_v := N_v - 4 < NumTpdo_g;
                        else
                            Exists_v := TimePdos_g;
                        end if;
                    end if;

                    for Cp in 0 to 1 loop
                        N_v := CntCopy;
                        inject(single(279 * Cp + Bt));
                        clocks(3);
                        if Exists_v then
                            check_value(CntCopy, N_v + 1, ERROR, "one cycle of Err_ParamCopy for bit " & to_string(Bt));
                            check_value(Stat_ErrReg(7), '1', ERROR, "bit 7 latched");
                        else
                            check_value(CntCopy, N_v, ERROR, "no effect of bit " & to_string(Bt) & " of an absent PDO");
                        end if;
                        resetComm;
                        clocks(2);
                        check_value(Stat_ErrReg(7), '0', ERROR, "bit 7 cleared by the reset communication");
                    end loop;

                end loop;

                -- Bdefault after an update, then a disagreement
                wait until rising_edge(Clk);
                Upd_Valid    <= '1';
                Upd_Bdefault <= '1';
                wait until rising_edge(Clk);
                Upd_Valid    <= '0';
                clocks(2);
                inject(single(262));
                clocks(3);

            -- *** TC-OD-14: error register ***
            elsif run("test_error_register") then

                for St in 0 to 3 loop
                    Link_State <= std_logic_vector(to_unsigned(St, 2));
                    clocks(3);
                    rd(16#1001#, 0, x"00000000", "1001h");
                    inject(single(13 * 0 + 3));
                    clocks(2);
                    rd(16#1001#, 0, x"00000000", "1001h with a COB-ID disagreement");
                    inject(single(170));
                    clocks(3);
                    rd(16#1001#, 0, x"00000000", "1001h with the latch");
                    resetComm;
                    clocks(2);
                end loop;

                Link_State <= "00";

            -- *** TC-OD-15: resets ***
            elsif run("test_resets") then

                for K in 0 to 2 loop
                    wr32(16#1016#, 1, x"000A0123", x"00000000", "1016h");
                    wr(16#1017#, 0, 4321, 2, x"00000000", "1017h");
                    wr(16#2000#, 1, 1 - Bdefault_g, 1, x"00000000", "Bdefault");
                    wr(16#2000#, 2, 9, 1, x"00000000", "Ttoggle");
                    wr(16#2000#, 3, 11, 1, x"00000000", "Ntoggle");
                    wr32(16#1005#, 0, x"00000091", x"00000000", "1005h");
                    if mExists(2) then
                        rd(16#1400#, 1, x"00000000", "1400h");
                        wr32(16#1400#, 1, x"80000000" or Dat_v(31 downto 0), x"00000000", "1400h invalid");
                        wr(16#1400#, 2, 7, 1, x"00000000", "1400h type");
                    end if;
                    inject(single(170));
                    clocks(3);
                    Nmt_NodeId <= std_logic_vector(to_unsigned(random(1, 127), 7));
                    if K = 0 then
                        Rst <= '1';
                        clocks(2);
                        Rst <= '0';
                    elsif K = 1 then
                        wait until rising_edge(Clk);
                        Nmt_ResetApp <= '1';
                        wait until rising_edge(Clk);
                        Nmt_ResetApp <= '0';
                        resetComm;
                    else
                        resetComm;
                    end if;
                    clocks(3);
                    rd(16#2000#, 1, x"00000000", "Bdefault after the reset");
                end loop;

                -- An outstanding request of the application port ends without an answer
                AppNoRsp  <= true;
                wait until rising_edge(Clk);
                Acc_Valid <= '1';
                Acc_Write <= '0';
                Acc_Index <= x"3000";
                Acc_Sub   <= x"00";
                wait until rising_edge(Clk);
                Acc_Valid <= '0';
                clocks(5);
                resetComm;
                clocks(5);
                AppNoRsp  <= false;
                rd(16#3000#, 0, x"00000000", "next request after the reset");
                -- A reset communication in the cycle of the response of the user logic: no answer either
                wait until rising_edge(Clk);
                Acc_Valid <= '1';
                Acc_Write <= '0';
                Acc_Index <= x"3001";
                Acc_Sub   <= x"00";
                -- Cycle 0: taken; cycle 1: AppReq_s; cycle 2: App_ReqReady; cycle 3: App_RspValid
                wait until rising_edge(Clk);
                Acc_Valid     <= '0';
                clocks(2);
                Nmt_ResetComm <= '1';
                wait until rising_edge(Clk);
                check_value(App_RspValid, '1', ERROR, "the response came in the cycle of the reset");
                Nmt_ResetComm <= '0';
                clocks(5);
                rd(16#3002#, 0, x"00000000", "next request after the reset in the cycle of the response");

            -- *** TC-OD-16: application port ***
            elsif run("test_app_port") then
                rd(16#2002#, 0, x"00000000", "2002h is an object of the dictionary");
                N_v := AppCnt;
                rd(16#2003#, 0, x"00000000", "2003h to the user logic");
                rd(16#9FFF#, 255, x"00000000", "9FFFh to the user logic");
                rd(16#A000#, 0, x"06020000", "A000h absent");
                check_value(AppCnt, N_v + 2, ERROR, "two requests");

                for I in 1 to 30 loop
                    AppDelay  <= random(0, 3);
                    AppRspDly <= random(0, 40);
                    if random(0, 2) = 0 then
                        AppAbort <= x"06090011";
                    else
                        AppAbort <= x"00000000";
                    end if;
                    acc(bitOf(random(0, 1)), random(16#2003#, 16#9FFF#), random(0, 255),
                        std_logic_vector(to_unsigned(random(0, 2 ** 30), 32)) &
                        std_logic_vector(to_unsigned(random(0, 2 ** 30), 32)), random(1, 8));
                end loop;

                AppRspDly <= 1000;
                AppAbort  <= (others => '0');
                rd(16#4000#, 0, x"00000000", "response after 1000 cycles");
                AppRspDly <= 0;
                -- Stray responses before, during and after requests
                AppStray <= true;

                for I in 1 to 20 loop
                    AppRspDly <= random(0, 20);
                    rd(random(16#2003#, 16#9FFF#), 0, x"00000000", "request with stray responses");
                    clocks(random(0, 10));
                end loop;

                AppStray <= false;

            -- *** TC-OD-17: time-out of the application port ***
            elsif run("test_app_timeout") then
                TickPer  <= 4;
                AppNoRdy <= true;
                N_v      := CntTmo;
                rd(16#3000#, 0, x"08000000", "no App_ReqReady");
                clocks(1);
                check_value(CntTmo, N_v + 1, ERROR, "Err_AppTimeout");
                AppNoRdy <= false;
                AppNoRsp <= true;
                rd(16#3001#, 0, x"08000000", "no response");
                AppLate  <= 300;
                rd(16#3002#, 0, x"08000000", "late response");
                wait for 100 * 4 * 25 ns;
                AppNoRsp <= false;
                AppLate  <= 0;
                rd(16#3003#, 0, x"00000000", "next access served");

            -- *** TC-OD-18: unconnected application port ***
            elsif run("test_app_unconnected") then

                for I in 1 to 10 loop
                    rd(random(16#2003#, 16#9FFF#), 0, x"06020000", "unconnected port");
                end loop;

            -- *** TC-OD-19: minimal set ***
            elsif run("test_minimal") then

                for I in 1 to 10 loop
                    wait until rising_edge(Clk);
                    Acc_Valid <= '1';
                    Acc_Index <= x"1017";
                    wait until rising_edge(Clk);
                    Acc_Valid <= '0';
                    clocks(3);
                end loop;

                Nmt_NodeId   <= std_logic_vector(to_unsigned(77, 7));
                clocks(3);
                wait until rising_edge(Clk);
                Upd_Valid    <= '1';
                Upd_Bdefault <= '1';
                wait until rising_edge(Clk);
                Upd_Valid    <= '0';
                clocks(3);
                inject(single(262));
                clocks(3);
                inject(single(279 + 262));
                clocks(3);
                Link_State   <= "11";
                clocks(3);
                Link_State   <= "00";
                clocks(3);

            -- *** TC-OD-20: random accesses ***
            elsif run("test_random") then
                AppRspDly <= 2;

                for I in 1 to 20000 loop

                    case random(0, 9) is
                        when 0 =>
                            Nmt_State <= std_logic_vector(to_unsigned(random(0, 3), 2));
                        when 1 =>
                            if random(0, 20) = 0 then
                                Nmt_NodeId <= std_logic_vector(to_unsigned(random(1, 127), 7));
                                resetComm;
                            end if;
                        when 2 =>
                            if random(0, 50) = 0 then
                                inject(single(random(0, 557)));
                            end if;
                        when 3 =>
                            if random(0, 10) = 0 then
                                wait until rising_edge(Clk);
                                Upd_Valid    <= '1';
                                Upd_Bdefault <= bitOf(random(0, 1));
                                wait until rising_edge(Clk);
                                Upd_Valid    <= '0';
                            end if;
                        when others =>
                            null;
                    end case;

                    case random(0, 5) is
                        when 0 =>
                            Idx_v := random(16#1000#, 16#101F#);
                        when 1 =>
                            Idx_v := 16#1400# + random(0, 5) + 16#200# * random(0, 3);
                        when 2 =>
                            Idx_v := random(16#2000#, 16#2004#);
                        when 3 =>
                            Idx_v := random(0, 16#FFFF#);
                        when others =>
                            Idx_v := commIndex(random(0, 10));
                    end case;

                    Sub_v := random(0, 9);
                    if random(0, 1) = 0 then
                        acc('0', Idx_v, Sub_v, (others => '0'), 0);
                    else
                        if random(0, 2) = 0 then
                            Val_v := random(0, 255);
                        else
                            Val_v := random(0, 2 ** 30);
                        end if;
                        acc('1', Idx_v, Sub_v,
                            std_logic_vector(to_unsigned(random(0, 1), 1)) &
                            std_logic_vector(to_unsigned(random(0, 1), 1)) & std_logic_vector(to_unsigned(Val_v, 62)),
                            random(1, 8));
                    end if;
                end loop;

            end if;

            clocks(10);
        end loop;

        ocanTestEnd(runner);
    end process;

end architecture;
