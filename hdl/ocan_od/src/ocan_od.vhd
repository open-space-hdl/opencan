---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Object dictionary of OpenCAN: the object table and its access rules, two copies of every writable parameter,
-- the parameters to the blocks, the error register and the application port to the objects of the device
-- (ECSS-E-ST-50-15C clauses 6.8, 6.10, 7.1.2, 8.3.1, 9.2 to 9.5).
--
-- Documentation: hdl/ocan_od/docs/architecture.md

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
entity ocan_od is
    generic (
        MinimalSet_g     : boolean                       := false;
        NumRpdo_g        : natural range 0 to 4          := 4;
        NumTpdo_g        : natural range 0 to 4          := 4;
        TimePdos_g       : boolean                       := true;
        DeviceType_g     : std_logic_vector(31 downto 0) := (others => '0');
        VendorId_g       : std_logic_vector(31 downto 0) := (others => '0');
        ProductCode_g    : std_logic_vector(31 downto 0) := (others => '0');
        Revision_g       : std_logic_vector(31 downto 0) := (others => '0');
        SerialNumber_g   : std_logic_vector(31 downto 0) := (others => '0');
        ProducerHbTime_g : natural range 0 to 65535      := 1000;
        MasterNodeId_g   : natural range 0 to 127        := 1;
        MasterHbTime_g   : natural range 0 to 65535      := 1500;
        Bdefault_g       : natural range 0 to 1          := 0;
        Ttoggle_g        : natural range 0 to 255        := 1;
        Ntoggle_g        : natural range 0 to 255        := 3;
        RpdoType_g       : natural range 0 to 255        := 254;
        TpdoType_g       : natural range 0 to 255        := 254;
        SctCobId_g       : natural range 0 to 2047       := 0;
        SctType_g        : natural range 0 to 255        := 254;
        LtpCobId_g       : natural range 0 to 2047       := 0;
        LtpType_g        : natural range 0 to 255        := 254
    );
    port (
        -- Control
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        Tick_Ms          : in    std_logic;
        -- Access of ocan_sdo
        Acc_Valid        : in    std_logic                      := '0';
        Acc_Ready        : out   std_logic;
        Acc_Write        : in    std_logic                      := '0';
        Acc_Index        : in    std_logic_vector(15 downto 0)  := (others => '0');
        Acc_Sub          : in    std_logic_vector(7 downto 0)   := (others => '0');
        Acc_Data         : in    std_logic_vector(63 downto 0)  := (others => '0');
        Acc_Len          : in    std_logic_vector(3 downto 0)   := (others => '0');
        Rsp_Valid        : out   std_logic;
        Rsp_Data         : out   std_logic_vector(63 downto 0);
        Rsp_Len          : out   std_logic_vector(3 downto 0);
        Rsp_Abort        : out   std_logic_vector(31 downto 0);
        -- ocan_nmt
        Nmt_State        : in    std_logic_vector(1 downto 0);
        Nmt_NodeId       : in    std_logic_vector(6 downto 0);
        Nmt_ResetApp     : in    std_logic;
        Nmt_ResetComm    : in    std_logic;
        -- ocan_dispatch: COB-ID table in two copies (entry e in bits 12 e + 11 downto 12 e)
        Cfg_CobId        : out   std_logic_vector(143 downto 0);
        Cfg_CobIdCopy    : out   std_logic_vector(143 downto 0);
        -- ocan_nmt and ocan_redundancy
        Cfg_HbTime       : out   std_logic_vector(15 downto 0);
        Cfg_MasterHbTime : out   std_logic_vector(15 downto 0);
        Cfg_Bdefault     : out   std_logic;
        Cfg_Ttoggle      : out   std_logic_vector(7 downto 0);
        Cfg_Ntoggle      : out   std_logic_vector(7 downto 0);
        Cfg_Ctoggle      : out   std_logic_vector(7 downto 0);
        Cfg_CtoggleValid : out   std_logic;
        Stat_Ctoggle     : in    std_logic_vector(7 downto 0)   := (others => '0');
        Upd_Valid        : in    std_logic                      := '0';
        Upd_Bdefault     : in    std_logic                      := '0';
        -- ocan_time
        Cfg_SctType      : out   std_logic_vector(7 downto 0);
        Cfg_LtpType      : out   std_logic_vector(7 downto 0);
        Cfg_SetValid     : out   std_logic;
        Cfg_SetScet      : out   std_logic_vector(55 downto 0);
        Stat_Scet        : in    std_logic_vector(55 downto 0)  := (others => '0');
        -- ocan_pdo: transmission type of PDO n in bits 8 n + 7 downto 8 n
        Cfg_RpdoType     : out   std_logic_vector(31 downto 0);
        Cfg_TpdoType     : out   std_logic_vector(31 downto 0);
        -- Fault confinement state of the controller of the active bus (as at olo_intf_can)
        Link_State       : in    std_logic_vector(1 downto 0)   := "00";
        -- Application port
        App_ReqValid     : out   std_logic;
        App_ReqReady     : in    std_logic                      := '1';
        App_ReqWrite     : out   std_logic;
        App_ReqIndex     : out   std_logic_vector(15 downto 0);
        App_ReqSub       : out   std_logic_vector(7 downto 0);
        App_ReqData      : out   std_logic_vector(63 downto 0);
        App_ReqLen       : out   std_logic_vector(3 downto 0);
        App_RspValid     : in    std_logic                      := '1';
        App_RspData      : in    std_logic_vector(63 downto 0)  := (others => '0');
        App_RspLen       : in    std_logic_vector(3 downto 0)   := (others => '0');
        App_RspAbort     : in    std_logic_vector(31 downto 0)  := x"06020000";
        -- Status and events
        Stat_ErrReg      : out   std_logic_vector(7 downto 0);
        Err_ParamCopy    : out   std_logic;
        Err_AppTimeout   : out   std_logic;
        -- Test inputs: invert the selected bits of the protected registers (tie to 0 in a system)
        ErrInj_BitFlip   : in    std_logic_vector(557 downto 0) := (others => '0');
        ErrInj_Valid     : in    std_logic                      := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_od is

    -- *** Constants ***
    constant AbortNone_c     : std_logic_vector(31 downto 0) := x"00000000";
    constant AbortNoObj_c    : std_logic_vector(31 downto 0) := x"06020000";
    constant AbortNoSub_c    : std_logic_vector(31 downto 0) := x"06090011";
    constant AbortReadOnly_c : std_logic_vector(31 downto 0) := x"06010002";
    constant AbortWriteOnl_c : std_logic_vector(31 downto 0) := x"06010001";
    constant AbortLenHigh_c  : std_logic_vector(31 downto 0) := x"06070012";
    constant AbortLenLow_c   : std_logic_vector(31 downto 0) := x"06070013";
    constant AbortState_c    : std_logic_vector(31 downto 0) := x"08000022";
    constant AbortValue_c    : std_logic_vector(31 downto 0) := x"06090030";
    constant AbortIncompat_c : std_logic_vector(31 downto 0) := x"06040043";
    constant AbortGeneral_c  : std_logic_vector(31 downto 0) := x"08000000";
    constant CopyW_c         : natural                       := 279;
    constant AppTimeout_c    : natural                       := 256;

    -- *** Types ***
    -- COB-ID entry: bit 31 of the COB-ID, identifier relative to the NODE-ID, identifier
    type Cob_t is record
        NotValid : std_logic;
        Rel      : std_logic;
        Id       : unsigned(10 downto 0);
    end record;

    type Cob_a is array (0 to 10) of Cob_t;

    -- Transmission types in the order of the test layout: receive PDOs 1 to 4, transmit PDOs 1 to 4, Spacecraft
    -- Time PDO, Local Time PDO
    type Type_a is array (0 to 9) of unsigned(7 downto 0);

    -- One copy of the protected parameters (architecture, section 3)
    type Copy_t is record
        Cob    : Cob_a;
        HbNode : unsigned(6 downto 0);
        HbTime : unsigned(15 downto 0);
        HbProd : unsigned(15 downto 0);
        Typ    : Type_a;
        Bdef   : std_logic;
        Ttog   : unsigned(7 downto 0);
        Ntog   : unsigned(7 downto 0);
    end record;

    type Obj_t is (
        OAbsent, OApp, ODevType, OErrReg, OSyncCob, OHbConsN, OHbCons, OHbProd, OIdentN, OIdent, OCommN, OCob,
        OType, OMapN, OMap, ORedN, OBdef, OTtog, ONtog, OCtog, OScetSet, OScetGet
    );

    -- Decoded access: object, COB-ID entry (0 SYNC, 1 Spacecraft Time PDO, 2 to 5 receive PDOs, 6 to 9 transmit
    -- PDOs, 10 Local Time PDO), sub-index number, size in bytes, access and write states
    type Dec_t is record
        Obj    : Obj_t;
        SubOk  : boolean;
        Ent    : natural range 0 to 10;
        K      : natural range 0 to 8;
        Size   : natural range 1 to 7;
        Rd     : boolean;
        Wr     : boolean;
        PreOp1 : boolean;  -- writable in Pre-operational only
    end record;

    type AppState_t is (AppIdle_s, AppReq_s, AppWait_s);

    -- *** Functions ***
    -- Slot of the transmission type of COB-ID entry e (entries 1 to 10)
    function typeSlot (e : natural) return natural is
    begin
        if e >= 2 and e <= 9 then
            return e - 2;
        elsif e = 1 then
            return 8;
        else
            return 9;
        end if;
    end function;

    -- COB-ID entry of transmission type slot j
    function slotEntry (j : natural) return natural is
    begin
        if j <= 7 then
            return j + 2;
        elsif j = 8 then
            return 1;
        else
            return 10;
        end if;
    end function;

    -- Entry exists for the generics
    function entryExists (e : natural) return boolean is
    begin
        if e = 1 or e = 10 then
            return TimePdos_g;
        elsif e >= 2 and e <= 5 then
            return e - 2 < NumRpdo_g;
        elsif e >= 6 and e <= 9 then
            return e - 6 < NumTpdo_g;
        else
            return true;
        end if;
    end function;

    -- Base of the pre-defined connection set of entry e (2 to 9)
    function cobBase (e : natural) return natural is
    begin
        if e >= 2 and e <= 5 then
            return 16#200# + (e - 2) * 16#100#;
        else
            return 16#180# + (e - 6) * 16#100#;
        end if;
    end function;

    -- Restricted identifiers of [CiA301] section 7.3.5, table 40, and the free ranges of clause 9.5a
    function restricted (id : unsigned(10 downto 0)) return boolean is
        variable N_v : natural;
        variable R_v : boolean;
    begin
        N_v := to_integer(id);
        R_v := N_v <= 16#07F# or (N_v >= 16#101# and N_v <= 16#180#) or (N_v >= 16#581# and N_v <= 16#5FF#);
        R_v := R_v or (N_v >= 16#601# and N_v <= 16#67F#) or (N_v >= 16#6E0# and N_v <= 16#6FF#);
        R_v := R_v or (N_v >= 16#701# and N_v <= 16#77F#) or N_v >= 16#780#;
        -- Free ranges (clause 9.5a), inside the last range of table 40
        R_v := R_v or (N_v >= 16#781# and N_v <= 16#7DE#) or N_v >= 16#7F0#;
        return R_v;
    end function;

    -- Transmission types of OD-WR-06
    function typeOk (t : unsigned(7 downto 0)) return boolean is
    begin
        return t <= 240 or t >= 254;
    end function;

    function powerOn return Copy_t is
        variable C_v : Copy_t;
    begin
        -- SYNC 080h; the time PDOs from the generics; the PDOs 1 to 4 relative to the NODE-ID, valid
        C_v.Cob(0) := ('0',
                       '0',
                       to_unsigned(16#080#,
                                      11));
        if SctCobId_g = 0 then
            C_v.Cob(1) := ('1',
                           '0',
                           to_unsigned(0,
                                          11));
        else
            C_v.Cob(1) := ('0',
                           '0',
                           to_unsigned(SctCobId_g,
                                          11));
        end if;

        for E in 2 to 9 loop
            C_v.Cob(E) := ('0',
                           '1',
                           to_unsigned(0,
                                          11));
        end loop;

        if LtpCobId_g = 0 then
            C_v.Cob(10) := ('1',
                            '0',
                            to_unsigned(0,
                                           11));
        else
            C_v.Cob(10) := ('0',
                            '0',
                            to_unsigned(LtpCobId_g,
                                           11));
        end if;
        C_v.HbNode := to_unsigned(MasterNodeId_g, 7);
        C_v.HbTime := to_unsigned(MasterHbTime_g, 16);
        C_v.HbProd := to_unsigned(ProducerHbTime_g, 16);

        for J in 0 to 3 loop
            if MinimalSet_g then
                C_v.Typ(J)     := to_unsigned(254, 8);
                C_v.Typ(J + 4) := to_unsigned(254, 8);
            else
                C_v.Typ(J)     := to_unsigned(RpdoType_g, 8);
                C_v.Typ(J + 4) := to_unsigned(TpdoType_g, 8);
            end if;
        end loop;

        C_v.Typ(8) := to_unsigned(SctType_g, 8);
        C_v.Typ(9) := to_unsigned(LtpType_g, 8);
        if Bdefault_g = 1 then
            C_v.Bdef := '1';
        else
            C_v.Bdef := '0';
        end if;
        C_v.Ttog := to_unsigned(Ttoggle_g, 8);
        C_v.Ntog := to_unsigned(Ntoggle_g, 8);
        return C_v;
    end function;

    constant PowerOn_c : Copy_t := powerOn;

    -- The communication profile area of a copy to its power-on values; object 2000h kept (OD-RS-02, OD-RS-03)
    function commReset (c : Copy_t) return Copy_t is
        variable C_v : Copy_t;
    begin
        C_v      := PowerOn_c;
        C_v.Bdef := c.Bdef;
        C_v.Ttog := c.Ttog;
        C_v.Ntog := c.Ntog;
        return C_v;
    end function;

    -- A copy as the bits of the test layout (architecture, section 3.3) and back
    function toSlv (c : Copy_t) return std_logic_vector is
        variable S_v : std_logic_vector(CopyW_c - 1 downto 0);
    begin

        for E in 0 to 10 loop
            S_v(13 * E + 10 downto 13 * E) := std_logic_vector(c.Cob(E).Id);
            S_v(13 * E + 11)               := c.Cob(E).Rel;
            S_v(13 * E + 12)               := c.Cob(E).NotValid;
        end loop;

        S_v(158 downto 143) := std_logic_vector(c.HbTime);
        S_v(165 downto 159) := std_logic_vector(c.HbNode);
        S_v(181 downto 166) := std_logic_vector(c.HbProd);

        for J in 0 to 9 loop
            S_v(182 + 8 * J + 7 downto 182 + 8 * J) := std_logic_vector(c.Typ(J));
        end loop;

        S_v(262)            := c.Bdef;
        S_v(270 downto 263) := std_logic_vector(c.Ttog);
        S_v(278 downto 271) := std_logic_vector(c.Ntog);
        return S_v;
    end function;

    function fromSlv (s : std_logic_vector(CopyW_c - 1 downto 0)) return Copy_t is
        variable C_v : Copy_t;
    begin

        for E in 0 to 10 loop
            C_v.Cob(E).Id       := unsigned(s(13 * E + 10 downto 13 * E));
            C_v.Cob(E).Rel      := s(13 * E + 11);
            C_v.Cob(E).NotValid := s(13 * E + 12);
        end loop;

        C_v.HbTime := unsigned(s(158 downto 143));
        C_v.HbNode := unsigned(s(165 downto 159));
        C_v.HbProd := unsigned(s(181 downto 166));

        for J in 0 to 9 loop
            C_v.Typ(J) := unsigned(s(182 + 8 * J + 7 downto 182 + 8 * J));
        end loop;

        C_v.Bdef := s(262);
        C_v.Ttog := unsigned(s(270 downto 263));
        C_v.Ntog := unsigned(s(278 downto 271));
        return C_v;
    end function;

    -- Effective identifier of entry e of a copy (architecture, section 3.1)
    function effId (c : Copy_t; e : natural; node : std_logic_vector(6 downto 0)) return unsigned is
    begin
        if c.Cob(e).Rel = '1' and e >= 2 and e <= 9 then
            return to_unsigned(cobBase(e), 11) + resize(unsigned(node), 11);
        else
            return c.Cob(e).Id;
        end if;
    end function;

    -- COB-ID table of one copy (DS-IF-03); entry 11 from the protected NODE-ID of the master
    function cobTable (c : Copy_t; node : std_logic_vector(6 downto 0); hbNode : unsigned(6 downto 0))
        return std_logic_vector is
        variable T_v : std_logic_vector(143 downto 0);
    begin

        for E in 0 to 10 loop
            T_v(12 * E + 10 downto 12 * E) := std_logic_vector(effId(c, E, node));
            if E = 0 then
                T_v(12 * E + 11) := '1';
            else
                T_v(12 * E + 11) := not c.Cob(E).NotValid;
            end if;
            -- Absent entries: constant, not valid (architecture, section 3.3)
            if not entryExists(E) then
                T_v(12 * E + 11 downto 12 * E) := (others => '0');
            end if;
        end loop;

        T_v(142 downto 132) := std_logic_vector(to_unsigned(16#700#, 11) + resize(hbNode, 11));
        if hbNode /= 0 then
            T_v(143) := '1';
        else
            T_v(143) := '0';
        end if;
        return T_v;
    end function;

    -- Decoder: index and sub-index to an object of table 1 (architecture, section 2.2)
    function decode (index : std_logic_vector(15 downto 0); sub : std_logic_vector(7 downto 0)) return Dec_t is
        variable D_v   : Dec_t;
        variable I_v   : natural;
        variable S_v   : natural;
        variable Lo_v  : natural;
        variable Grp_v : natural;
    begin
        D_v   := (Obj => OAbsent,
                  SubOk => false,
                  Ent => 0,
                  K => 0,
                  Size => 1,
                  Rd => false,
                  Wr => false,
                  PreOp1 => false);
        I_v   := to_integer(unsigned(index));
        S_v   := to_integer(unsigned(sub));
        Lo_v  := I_v mod 256;
        Grp_v := I_v / 256;

        if I_v = 16#1000# then
            D_v := (ODevType,
                    S_v = 0,
                    0,
                    0,
                    4,
                    true,
                    false,
                    false);
        elsif I_v = 16#1001# then
            D_v := (OErrReg,
                    S_v = 0,
                    0,
                    0,
                    1,
                    true,
                    false,
                    false);
        elsif I_v = 16#1005# then
            D_v := (OSyncCob,
                    S_v = 0,
                    0,
                    0,
                    4,
                    true,
                    true,
                    true);
        elsif I_v = 16#1016# then
            if S_v = 1 then
                D_v := (OHbCons,
                        true,
                        0,
                        0,
                        4,
                        true,
                        true,
                        false);
            else
                D_v := (OHbConsN,
                        S_v = 0,
                        0,
                        0,
                        1,
                        true,
                        false,
                        false);
            end if;
        elsif I_v = 16#1017# then
            D_v := (OHbProd,
                    S_v = 0,
                    0,
                    0,
                    2,
                    true,
                    true,
                    false);
        elsif I_v = 16#1018# then
            if S_v >= 1 and S_v <= 4 then
                D_v := (OIdent,
                        true,
                        0,
                        S_v,
                        4,
                        true,
                        false,
                        false);
            else
                D_v := (OIdentN,
                        S_v = 0,
                        0,
                        0,
                        1,
                        true,
                        false,
                        false);
            end if;
        elsif (Grp_v = 16#14# or Grp_v = 16#18#) and Lo_v <= 4 then
            -- PDO communication: entries 2 to 5 and 1 (receive), 6 to 9 and 10 (transmit)
            if Grp_v = 16#14# then
                if Lo_v = 4 then
                    D_v.Ent := 1;
                else
                    D_v.Ent := 2 + Lo_v;
                end if;
            elsif Lo_v = 4 then
                D_v.Ent := 10;
            else
                D_v.Ent := 6 + Lo_v;
            end if;
            if entryExists(D_v.Ent) then
                if S_v = 1 then
                    D_v := (OCob,
                            true,
                            D_v.Ent,
                            0,
                            4,
                            true,
                            true,
                            true);
                elsif S_v = 2 then
                    D_v := (OType,
                            true,
                            D_v.Ent,
                            0,
                            1,
                            true,
                            true,
                            true);
                else
                    D_v := (OCommN,
                            S_v = 0,
                            D_v.Ent,
                            0,
                            1,
                            true,
                            false,
                            false);
                end if;
            end if;
        elsif (Grp_v = 16#16# or Grp_v = 16#1A#) and Lo_v <= 4 then
            -- PDO mapping
            if Grp_v = 16#16# then
                if Lo_v = 4 then
                    D_v.Ent := 1;
                else
                    D_v.Ent := 2 + Lo_v;
                end if;
            elsif Lo_v = 4 then
                D_v.Ent := 10;
            else
                D_v.Ent := 6 + Lo_v;
            end if;
            if entryExists(D_v.Ent) then
                if S_v = 0 then
                    D_v := (OMapN,
                            true,
                            D_v.Ent,
                            0,
                            1,
                            true,
                            false,
                            false);
                elsif (Lo_v = 4 and S_v = 1) or (Lo_v < 4 and S_v <= 8) then
                    D_v := (OMap,
                            true,
                            D_v.Ent,
                            S_v,
                            4,
                            true,
                            false,
                            false);
                else
                    D_v := (OMap,
                            false,
                            D_v.Ent,
                            0,
                            4,
                            true,
                            false,
                            false);
                end if;
            end if;
        elsif I_v = 16#2000# then

            case S_v is
                when 0 =>
                    D_v := (ORedN,
                            true,
                            0,
                            0,
                            1,
                            true,
                            false,
                            false);
                when 1 =>
                    D_v := (OBdef,
                            true,
                            0,
                            0,
                            1,
                            true,
                            true,
                            false);
                when 2 =>
                    D_v := (OTtog,
                            true,
                            0,
                            0,
                            1,
                            true,
                            true,
                            false);
                when 3 =>
                    D_v := (ONtog,
                            true,
                            0,
                            0,
                            1,
                            true,
                            true,
                            false);
                when 4 =>
                    D_v := (OCtog,
                            true,
                            0,
                            0,
                            1,
                            true,
                            true,
                            false);
                when others =>
                    D_v := (ORedN,
                            false,
                            0,
                            0,
                            1,
                            true,
                            false,
                            false);
            end case;

        elsif I_v = 16#2001# then
            D_v := (OScetSet,
                    S_v = 0,
                    0,
                    0,
                    7,
                    false,
                    true,
                    false);
        elsif I_v = 16#2002# then
            D_v := (OScetGet,
                    S_v = 0,
                    0,
                    0,
                    7,
                    true,
                    false,
                    false);
        elsif I_v >= 16#2003# and I_v <= 16#9FFF# then
            D_v.Obj := OApp;
        end if;
        return D_v;
    end function;

    -- *** Two process method ***
    type TwoProcess_r is record
        -- Protected parameters
        A        : Copy_t;
        B        : Copy_t;
        ErLatch  : std_logic;
        -- Answer
        RspValid : std_logic;
        RspData  : std_logic_vector(63 downto 0);
        RspLen   : std_logic_vector(3 downto 0);
        RspAbort : std_logic_vector(31 downto 0);
        -- Events to the blocks
        CtogVld  : std_logic;
        Ctog     : std_logic_vector(7 downto 0);
        SetValid : std_logic;
        SetScet  : std_logic_vector(55 downto 0);
        ErrTmo   : std_logic;
        -- Application port
        App      : AppState_t;
        AppWrite : std_logic;
        AppIndex : std_logic_vector(15 downto 0);
        AppSub   : std_logic_vector(7 downto 0);
        AppData  : std_logic_vector(63 downto 0);
        AppLen   : std_logic_vector(3 downto 0);
        TmoCnt   : unsigned(7 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- *** Protected values (copy A while both copies agree, the power-on value otherwise) ***
    signal OutPar : Copy_t;
    signal OkHb   : boolean;
    signal OkProd : boolean;
    signal OkTyp  : std_logic_vector(9 downto 0);
    signal OkBdef : boolean;
    signal OkTtog : boolean;
    signal OkNtog : boolean;
    signal CopyOk : boolean;
    signal ErrReg : std_logic_vector(7 downto 0);

begin

    assert not (MinimalSet_g and TimePdos_g and (NumRpdo_g > 3 or NumTpdo_g > 3))
        report "ocan_od: with MinimalSet_g and TimePdos_g, NumRpdo_g and NumTpdo_g must be at most 3 (OD-MS-05)"
        severity failure;
    -- The minimal set has no SDO server: a time PDO that is not valid could never become valid (OD-MS-03)
    assert not (MinimalSet_g and TimePdos_g and (SctCobId_g = 0 or LtpCobId_g = 0))
        report "ocan_od: with MinimalSet_g and TimePdos_g, SctCobId_g and LtpCobId_g must not be 0 (OD-MS-03)"
        severity failure;
    assert SctCobId_g = 0 or not restricted(to_unsigned(SctCobId_g, 11))
        report "ocan_od: SctCobId_g is a restricted or free identifier"
        severity failure;
    assert LtpCobId_g = 0 or not restricted(to_unsigned(LtpCobId_g, 11))
        report "ocan_od: LtpCobId_g is a restricted or free identifier"
        severity failure;
    assert SctCobId_g = 0 or SctCobId_g /= LtpCobId_g
        report "ocan_od: SctCobId_g and LtpCobId_g are equal"
        severity failure;
    -- The range of the transmission types (specification, section 4); the declared range ends at 255
    assert typeOk(to_unsigned(RpdoType_g, 8))
        report "ocan_od: RpdoType_g is not a transmission type of 0 to 240, 254 or 255"
        severity failure;
    assert typeOk(to_unsigned(TpdoType_g, 8))
        report "ocan_od: TpdoType_g is not a transmission type of 0 to 240, 254 or 255"
        severity failure;
    assert typeOk(to_unsigned(SctType_g, 8))
        report "ocan_od: SctType_g is not a transmission type of 0 to 240, 254 or 255"
        severity failure;
    assert typeOk(to_unsigned(LtpType_g, 8))
        report "ocan_od: LtpType_g is not a transmission type of 0 to 240, 254 or 255"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Compare of the copies of the parameters other than the COB-IDs (OD-PR-03)
    -----------------------------------------------------------------------------------------------
    p_ok : process (all) is
        variable O_v  : Copy_t;
        variable Ok_v : boolean;
    begin
        O_v    := r.A;
        Ok_v   := true;
        OkHb   <= r.A.HbNode = r.B.HbNode and r.A.HbTime = r.B.HbTime;
        OkProd <= r.A.HbProd = r.B.HbProd;
        OkBdef <= r.A.Bdef = r.B.Bdef;
        OkTtog <= r.A.Ttog = r.B.Ttog;
        OkNtog <= r.A.Ntog = r.B.Ntog;
        if r.A.HbNode /= r.B.HbNode or r.A.HbTime /= r.B.HbTime then
            O_v.HbNode := PowerOn_c.HbNode;
            O_v.HbTime := PowerOn_c.HbTime;
            Ok_v       := false;
        end if;
        if r.A.HbProd /= r.B.HbProd then
            O_v.HbProd := PowerOn_c.HbProd;
            Ok_v       := false;
        end if;

        -- Transmission types of absent PDOs have no effect (architecture, section 3.3)
        for J in 0 to 9 loop
            if entryExists(slotEntry(J)) and r.A.Typ(J) /= r.B.Typ(J) then
                O_v.Typ(J) := PowerOn_c.Typ(J);
                OkTyp(J)   <= '0';
                Ok_v       := false;
            else
                OkTyp(J) <= '1';
            end if;
        end loop;

        if r.A.Bdef /= r.B.Bdef then
            O_v.Bdef := PowerOn_c.Bdef;
            Ok_v     := false;
        end if;
        if r.A.Ttog /= r.B.Ttog then
            O_v.Ttog := PowerOn_c.Ttog;
            Ok_v     := false;
        end if;
        if r.A.Ntog /= r.B.Ntog then
            O_v.Ntog := PowerOn_c.Ntog;
            Ok_v     := false;
        end if;
        OutPar <= O_v;
        CopyOk <= Ok_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Error register (OD-ER-01)
    -----------------------------------------------------------------------------------------------
    p_errreg : process (all) is
        variable Cob_v  : boolean;
        variable Comm_v : std_logic;
    begin
        Cob_v := false;

        for E in 0 to 10 loop
            if entryExists(E) and r.A.Cob(E) /= r.B.Cob(E) then
                Cob_v := true;
            end if;
        end loop;

        if Link_State = "01" or Link_State = "10" or Link_State = "11" then
            Comm_v := '1';
        else
            Comm_v := '0';
        end if;
        ErrReg    <= (others => '0');
        ErrReg(4) <= Comm_v;
        ErrReg(7) <= r.ErLatch;
        if Comm_v = '1' or r.ErLatch = '1' or Cob_v then
            ErrReg(0) <= '1';
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable D_v     : Dec_t;
        variable Take_v  : boolean;
        variable Len_v   : natural range 0 to 15;
        variable W32_v   : unsigned(31 downto 0);
        variable Id_v    : unsigned(10 downto 0);
        variable Val_v   : std_logic_vector(63 downto 0);
        variable Abort_v : std_logic_vector(31 downto 0);
        variable Ok_v    : boolean;
        variable NewV_v  : boolean;
        variable Wr_v    : boolean;
        variable WrBd_v  : boolean;
        variable Rst_v   : boolean;
        variable SA_v    : std_logic_vector(CopyW_c - 1 downto 0);
        variable SB_v    : std_logic_vector(CopyW_c - 1 downto 0);
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.RspValid := '0';
        v.CtogVld  := '0';
        v.SetValid := '0';
        v.ErrTmo   := '0';
        Wr_v       := false;
        WrBd_v     := false;
        Rst_v      := Nmt_ResetApp = '1' or Nmt_ResetComm = '1';

        -- *** Repair of copies that disagree (OD-PR-03): the power-on value in both copies ***
        if not OkHb then
            v.A.HbNode := PowerOn_c.HbNode;
            v.A.HbTime := PowerOn_c.HbTime;
            v.B.HbNode := PowerOn_c.HbNode;
            v.B.HbTime := PowerOn_c.HbTime;
        end if;
        if not OkProd then
            v.A.HbProd := PowerOn_c.HbProd;
            v.B.HbProd := PowerOn_c.HbProd;
        end if;

        for J in 0 to 9 loop
            if OkTyp(J) = '0' then
                v.A.Typ(J) := PowerOn_c.Typ(J);
                v.B.Typ(J) := PowerOn_c.Typ(J);
            end if;
        end loop;

        if not OkBdef then
            v.A.Bdef := PowerOn_c.Bdef;
            v.B.Bdef := PowerOn_c.Bdef;
        end if;
        if not OkTtog then
            v.A.Ttog := PowerOn_c.Ttog;
            v.B.Ttog := PowerOn_c.Ttog;
        end if;
        if not OkNtog then
            v.A.Ntog := PowerOn_c.Ntog;
            v.B.Ntog := PowerOn_c.Ntog;
        end if;
        if not CopyOk then
            v.ErLatch := '1';
        end if;

        -- *** Access (OD-1) ***
        D_v    := decode(Acc_Index, Acc_Sub);
        Take_v := Acc_Valid = '1' and r.App = AppIdle_s and not MinimalSet_g;
        Len_v  := to_integer(unsigned(Acc_Len));
        W32_v  := unsigned(Acc_Data(31 downto 0));
        Id_v   := W32_v(10 downto 0);
        Val_v  := (others => '0');

        if Take_v and D_v.Obj /= OApp then
            -- Checks in the order of architecture section 2.3
            if D_v.Obj = OAbsent then
                Abort_v := AbortNoObj_c;
            elsif not D_v.SubOk then
                Abort_v := AbortNoSub_c;
            elsif Acc_Write = '1' and not D_v.Wr then
                Abort_v := AbortReadOnly_c;
            elsif Acc_Write = '0' and not D_v.Rd then
                Abort_v := AbortWriteOnl_c;
            -- The number of bytes, when indicated (OD-WR-02); 0: not indicated, the size of the data type is taken
            elsif Acc_Write = '1' and Len_v /= 0 and Len_v > D_v.Size then
                Abort_v := AbortLenHigh_c;
            elsif Acc_Write = '1' and Len_v /= 0 and Len_v < D_v.Size then
                Abort_v := AbortLenLow_c;
            elsif Acc_Write = '1' and D_v.PreOp1 and Nmt_State /= NmtPreOp_c then
                Abort_v := AbortState_c;
            elsif Acc_Write = '1' and not D_v.PreOp1 and Nmt_State /= NmtPreOp_c and Nmt_State /= NmtOp_c then
                Abort_v := AbortState_c;
            else
                Abort_v := AbortNone_c;
            end if;

            -- Value checks (OD-WR-04 to OD-WR-08)
            if Acc_Write = '1' and Abort_v = AbortNone_c then
                Ok_v   := true;
                NewV_v := false;

                case D_v.Obj is

                    when OSyncCob =>
                        -- SYNC consumer: bit 30 0, base frame, 11-bit identifier (OD-WR-04, OD-WR-05)
                        Ok_v   := W32_v(30) = '0' and W32_v(29) = '0' and W32_v(28 downto 11) = 0 and
                                  not restricted(Id_v);
                        NewV_v := true;

                    when OCob =>
                        Ok_v := W32_v(29) = '0' and W32_v(28 downto 11) = 0;
                        -- Transmit PDOs: no remote frames (bit 30 = 1)
                        if D_v.Ent >= 6 and W32_v(30) = '0' then
                            Ok_v := false;
                        end if;
                        -- Bits 0 to 29 locked while the PDO is valid in both copies
                        if r.A.Cob(D_v.Ent).NotValid = '0' and r.B.Cob(D_v.Ent).NotValid = '0' and
                           Id_v /= effId(r.A, D_v.Ent, Nmt_NodeId) then
                            Ok_v := false;
                        end if;
                        NewV_v := W32_v(31) = '0';
                        if NewV_v and restricted(Id_v) then
                            Ok_v := false;
                        end if;

                    when OType =>
                        Ok_v := typeOk(W32_v(7 downto 0));

                    when OHbCons =>
                        Ok_v := W32_v(31 downto 24) = 0 and W32_v(23 downto 16) <= 127;

                    when OBdef =>
                        Ok_v := W32_v(7 downto 0) <= 1;

                    when others =>
                        null;

                end case;

                if not Ok_v then
                    Abort_v := AbortValue_c;
                elsif NewV_v then

                    -- Another valid COB-ID of the node with the same identifier (OD-WR-05)
                    for E in 0 to 10 loop
                        if E /= D_v.Ent and entryExists(E) and (E = 0 or r.A.Cob(E).NotValid = '0') and
                           effId(r.A, E, Nmt_NodeId) = Id_v then
                            Abort_v := AbortIncompat_c;
                        end if;
                    end loop;

                end if;
            end if;

            -- A reset in the cycle of the access: no effect (OD-WR-10, architecture section 2.4)
            if Rst_v then
                Abort_v := AbortState_c;
            end if;

            -- Read values (OD-OB-03, OD-OB-04)
            if Acc_Write = '0' and Abort_v = AbortNone_c then

                case D_v.Obj is

                    when ODevType =>
                        Val_v(31 downto 0) := DeviceType_g;

                    when OErrReg =>
                        Val_v(7 downto 0) := ErrReg;

                    when OSyncCob =>
                        Val_v(31)          := r.A.Cob(0).NotValid;
                        Val_v(10 downto 0) := std_logic_vector(r.A.Cob(0).Id);

                    when OHbConsN =>
                        Val_v(7 downto 0) := x"01";

                    when OHbCons =>
                        Val_v(22 downto 16) := std_logic_vector(OutPar.HbNode);
                        Val_v(15 downto 0)  := std_logic_vector(OutPar.HbTime);

                    when OHbProd =>
                        Val_v(15 downto 0) := std_logic_vector(OutPar.HbProd);

                    when OIdentN =>
                        Val_v(7 downto 0) := x"04";

                    when OIdent =>
                        if D_v.K = 1 then
                            Val_v(31 downto 0) := VendorId_g;
                        elsif D_v.K = 2 then
                            Val_v(31 downto 0) := ProductCode_g;
                        elsif D_v.K = 3 then
                            Val_v(31 downto 0) := Revision_g;
                        else
                            Val_v(31 downto 0) := SerialNumber_g;
                        end if;

                    when OCommN =>
                        Val_v(7 downto 0) := x"02";

                    when OCob =>
                        Val_v(31) := r.A.Cob(D_v.Ent).NotValid;
                        if D_v.Ent >= 6 then
                            Val_v(30) := '1';
                        end if;
                        Val_v(10 downto 0) := std_logic_vector(effId(r.A, D_v.Ent, Nmt_NodeId));

                    when OType =>
                        Val_v(7 downto 0) := std_logic_vector(OutPar.Typ(typeSlot(D_v.Ent)));

                    when OMapN =>
                        if D_v.Ent = 1 or D_v.Ent = 10 then
                            Val_v(7 downto 0) := x"01";
                        else
                            Val_v(7 downto 0) := x"08";
                        end if;

                    when OMap =>
                        if D_v.Ent = 1 then
                            Val_v(31 downto 0) := x"20010038";
                        elsif D_v.Ent = 10 then
                            Val_v(31 downto 0) := x"20020038";
                        elsif D_v.Ent <= 5 then
                            Val_v(31 downto 16) := std_logic_vector(to_unsigned(16#2100# + D_v.Ent - 2, 16));
                            Val_v(15 downto 8)  := std_logic_vector(to_unsigned(D_v.K, 8));
                            Val_v(7 downto 0)   := x"08";
                        else
                            Val_v(31 downto 16) := std_logic_vector(to_unsigned(16#2200# + D_v.Ent - 6, 16));
                            Val_v(15 downto 8)  := std_logic_vector(to_unsigned(D_v.K, 8));
                            Val_v(7 downto 0)   := x"08";
                        end if;

                    when ORedN =>
                        Val_v(7 downto 0) := x"04";

                    when OBdef =>
                        Val_v(0) := OutPar.Bdef;

                    when OTtog =>
                        Val_v(7 downto 0) := std_logic_vector(OutPar.Ttog);

                    when ONtog =>
                        Val_v(7 downto 0) := std_logic_vector(OutPar.Ntog);

                    when OCtog =>
                        Val_v(7 downto 0) := Stat_Ctoggle;

                    when OScetGet =>
                        Val_v(55 downto 0) := Stat_Scet;

                    when others =>
                        null;

                end case;

            end if;

            -- Accepted write: both copies from the next cycle on (OD-WR-09)
            if Acc_Write = '1' and Abort_v = AbortNone_c then
                Wr_v := true;

                case D_v.Obj is

                    when OSyncCob | OCob =>
                        v.A.Cob(D_v.Ent) := (W32_v(31),
                                             '0',
                                             Id_v);
                        v.B.Cob(D_v.Ent) := (W32_v(31),
                                             '0',
                                             Id_v);

                    when OType =>
                        v.A.Typ(typeSlot(D_v.Ent)) := W32_v(7 downto 0);
                        v.B.Typ(typeSlot(D_v.Ent)) := W32_v(7 downto 0);

                    when OHbCons =>
                        v.A.HbNode := W32_v(22 downto 16);
                        v.A.HbTime := W32_v(15 downto 0);
                        v.B.HbNode := W32_v(22 downto 16);
                        v.B.HbTime := W32_v(15 downto 0);

                    when OHbProd =>
                        v.A.HbProd := W32_v(15 downto 0);
                        v.B.HbProd := W32_v(15 downto 0);

                    when OBdef =>
                        v.A.Bdef := W32_v(0);
                        v.B.Bdef := W32_v(0);
                        WrBd_v   := true;

                    when OTtog =>
                        v.A.Ttog := W32_v(7 downto 0);
                        v.B.Ttog := W32_v(7 downto 0);

                    when ONtog =>
                        v.A.Ntog := W32_v(7 downto 0);
                        v.B.Ntog := W32_v(7 downto 0);

                    when OCtog =>
                        v.CtogVld := '1';
                        v.Ctog    := Acc_Data(7 downto 0);

                    when OScetSet =>
                        v.SetValid := '1';
                        v.SetScet  := Acc_Data(55 downto 0);

                    when others =>
                        null;

                end case;

            end if;

            v.RspValid := '1';
            v.RspAbort := Abort_v;
            if Acc_Write = '0' and Abort_v = AbortNone_c then
                v.RspData := Val_v;
                v.RspLen  := std_logic_vector(to_unsigned(D_v.Size, 4));
            else
                v.RspData := (others => '0');
                v.RspLen  := (others => '0');
            end if;
        end if;

        -- *** Update of Bdefault by ocan_redundancy: a write of the same cycle wins (OD-WR-10) ***
        if Upd_Valid = '1' and not WrBd_v then
            v.A.Bdef := Upd_Bdefault;
            v.B.Bdef := Upd_Bdefault;
        end if;

        -- *** Application port (OD-4) ***
        case r.App is

            when AppIdle_s =>
                if Take_v and D_v.Obj = OApp then
                    v.App      := AppReq_s;
                    v.AppWrite := Acc_Write;
                    v.AppIndex := Acc_Index;
                    v.AppSub   := Acc_Sub;
                    v.AppData  := Acc_Data;
                    v.AppLen   := Acc_Len;
                    v.TmoCnt   := (others => '0');
                end if;

            when AppReq_s | AppWait_s =>
                if r.App = AppReq_s and App_ReqReady = '1' then
                    v.App := AppWait_s;
                end if;
                if r.App = AppWait_s and App_RspValid = '1' then
                    -- The response of the user logic is the answer (OD-AP-01)
                    v.App      := AppIdle_s;
                    v.RspValid := '1';
                    v.RspData  := App_RspData;
                    v.RspLen   := App_RspLen;
                    v.RspAbort := App_RspAbort;
                elsif Tick_Ms = '1' then
                    -- Bounded wait (OD-AP-03)
                    if r.TmoCnt >= AppTimeout_c - 1 then
                        v.App      := AppIdle_s;
                        v.RspValid := '1';
                        v.RspData  := (others => '0');
                        v.RspLen   := (others => '0');
                        v.RspAbort := AbortGeneral_c;
                        v.ErrTmo   := '1';
                    else
                        v.TmoCnt := r.TmoCnt + 1;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.App := AppIdle_s;
            -- coverage on

        end case;

        -- *** Resets (OD-RS-02, OD-RS-03): the communication profile area, 2000h kept ***
        if Rst_v then
            v.A := commReset(v.A);
            v.B := commReset(v.B);
            if Nmt_ResetComm = '1' then
                v.ErLatch := '0';
            end if;
            v.App := AppIdle_s;
            if r.App /= AppIdle_s then
                -- An outstanding request ends without an answer
                v.RspValid := '0';
                v.ErrTmo   := '0';
            elsif Take_v and D_v.Obj = OApp then
                -- An access to the user logic in the cycle of the reset: no request, as an own object
                v.RspValid := '1';
                v.RspData  := (others => '0');
                v.RspLen   := (others => '0');
                v.RspAbort := AbortState_c;
            end if;
        end if;

        -- *** Test inputs: the selected bits of both copies inverted (OD-PR-04) ***
        if ErrInj_Valid = '1' then
            SA_v := toSlv(v.A) xor ErrInj_BitFlip(CopyW_c - 1 downto 0);
            SB_v := toSlv(v.B) xor ErrInj_BitFlip(2 * CopyW_c - 1 downto CopyW_c);
            v.A  := fromSlv(SA_v);
            v.B  := fromSlv(SB_v);
        end if;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    Acc_Ready <= '1' when r.App = AppIdle_s and not MinimalSet_g else '0';
    Rsp_Valid <= r.RspValid;
    Rsp_Data  <= r.RspData;
    Rsp_Len   <= r.RspLen;
    Rsp_Abort <= r.RspAbort;

    Cfg_CobId        <= cobTable(r.A, Nmt_NodeId, OutPar.HbNode);
    Cfg_CobIdCopy    <= cobTable(r.B, Nmt_NodeId, OutPar.HbNode);
    Cfg_HbTime       <= std_logic_vector(OutPar.HbProd);
    Cfg_MasterHbTime <= std_logic_vector(OutPar.HbTime);
    Cfg_Bdefault     <= OutPar.Bdef;
    Cfg_Ttoggle      <= std_logic_vector(OutPar.Ttog);
    Cfg_Ntoggle      <= std_logic_vector(OutPar.Ntog);
    Cfg_Ctoggle      <= r.Ctog;
    Cfg_CtoggleValid <= r.CtogVld;
    Cfg_SctType      <= std_logic_vector(OutPar.Typ(8));
    Cfg_LtpType      <= std_logic_vector(OutPar.Typ(9));
    Cfg_SetValid     <= r.SetValid;
    Cfg_SetScet      <= r.SetScet;

    g_types : for N in 0 to 3 generate
        Cfg_RpdoType(8 * N + 7 downto 8 * N) <= std_logic_vector(OutPar.Typ(N));
        Cfg_TpdoType(8 * N + 7 downto 8 * N) <= std_logic_vector(OutPar.Typ(N + 4));
    end generate;

    App_ReqValid <= '1' when r.App = AppReq_s else '0';
    App_ReqWrite <= r.AppWrite;
    App_ReqIndex <= r.AppIndex;
    App_ReqSub   <= r.AppSub;
    App_ReqData  <= r.AppData;
    App_ReqLen   <= r.AppLen;

    Stat_ErrReg    <= ErrReg;
    Err_ParamCopy  <= '0' when CopyOk else '1';
    Err_AppTimeout <= r.ErrTmo;

    -- *** Sequential process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.A        <= PowerOn_c;
                r.B        <= PowerOn_c;
                r.ErLatch  <= '0';
                r.RspValid <= '0';
                r.CtogVld  <= '0';
                r.SetValid <= '0';
                r.ErrTmo   <= '0';
                r.App      <= AppIdle_s;
                r.TmoCnt   <= (others => '0');
            end if;
        end if;
    end process;

end architecture;
