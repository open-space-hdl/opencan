---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Classification of the received frames of OpenCAN by COB-ID, the bus gate with the NMT message of the inactive
-- bus, and the transmit arbitration of the protocol blocks with the protected COB-IDs (ECSS-E-ST-50-15C 6.10, 8.3.3,
-- 9.5).
--
-- Documentation: hdl/ocan_dispatch/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_dispatch is
    generic (
        NumRpdo_g   : natural range 0 to 4 := 4;
        NumTpdo_g   : natural range 0 to 4 := 4;
        TimePdos_g  : boolean              := true;
        SdoServer_g : boolean              := true
    );
    port (
        -- Control
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        -- Received frames of ocan_link, per bus
        LinkRx_Valid       : in    std_logic_vector(1 downto 0);
        LinkRx_Id          : in    std_logic_vector(57 downto 0);
        LinkRx_Ide         : in    std_logic_vector(1 downto 0);
        LinkRx_Rtr         : in    std_logic_vector(1 downto 0);
        LinkRx_Dlc         : in    std_logic_vector(7 downto 0);
        LinkRx_Data        : in    std_logic_vector(127 downto 0);
        -- Frame to send to ocan_link
        LinkTx_Valid       : out   std_logic;
        LinkTx_Ready       : in    std_logic;
        LinkTx_Id          : out   std_logic_vector(28 downto 0);
        LinkTx_Dlc         : out   std_logic_vector(3 downto 0);
        LinkTx_Data        : out   std_logic_vector(63 downto 0);
        LinkTx_Abort       : out   std_logic;
        LinkTx_Done        : in    std_logic;
        LinkTx_Aborted     : in    std_logic;
        -- Redundancy and NMT state
        Red_ActiveBus      : in    std_logic;
        Red_Selecting      : in    std_logic;
        Nmt_NodeId         : in    std_logic_vector(6 downto 0);
        Nmt_NodeIdValid    : in    std_logic;
        Nmt_EnaSdo         : in    std_logic;
        Nmt_EnaPdo         : in    std_logic;
        Nmt_EnaSync        : in    std_logic;
        -- COB-ID table, two copies (entry e in bits 12 e + 11 downto 12 e: valid flag and identifier)
        Cfg_CobId          : in    std_logic_vector(143 downto 0);
        Cfg_CobIdCopy      : in    std_logic_vector(143 downto 0);
        -- Received objects to the protocol blocks
        RxNmt_Valid        : out   std_logic;
        RxNmt_Cs           : out   std_logic_vector(7 downto 0);
        RxSync_Valid       : out   std_logic;
        RxSync_Dlc         : out   std_logic_vector(3 downto 0);
        RxSync_Data        : out   std_logic_vector(7 downto 0);
        RxRpdo_Valid       : out   std_logic;
        RxRpdo_Num         : out   std_logic_vector(1 downto 0);
        RxRpdo_Dlc         : out   std_logic_vector(3 downto 0);
        RxRpdo_Data        : out   std_logic_vector(63 downto 0);
        RxTime_Valid       : out   std_logic;
        RxTime_Dlc         : out   std_logic_vector(3 downto 0);
        RxTime_Data        : out   std_logic_vector(63 downto 0);
        RxSdo_Valid        : out   std_logic;
        RxSdo_Dlc          : out   std_logic_vector(3 downto 0);
        RxSdo_Data         : out   std_logic_vector(63 downto 0);
        -- Per bus to ocan_redundancy
        RxRed_NmtValid     : out   std_logic_vector(1 downto 0);
        RxRed_HbValid      : out   std_logic_vector(1 downto 0);
        RxRed_HbDlc        : out   std_logic_vector(7 downto 0);
        RxRed_HbState      : out   std_logic_vector(15 downto 0);
        -- Transmit requests of the protocol blocks
        TxTpdo_Valid       : in    std_logic_vector(3 downto 0)   := (others => '0');
        TxTpdo_Ready       : out   std_logic_vector(3 downto 0);
        TxTpdo_Dlc         : in    std_logic_vector(15 downto 0)  := (others => '0');
        TxTpdo_Data        : in    std_logic_vector(255 downto 0) := (others => '0');
        TxTpdo_Done        : out   std_logic_vector(3 downto 0);
        TxTpdo_Aborted     : out   std_logic_vector(3 downto 0);
        TxTime_Valid       : in    std_logic                      := '0';
        TxTime_Ready       : out   std_logic;
        TxTime_Dlc         : in    std_logic_vector(3 downto 0)   := (others => '0');
        TxTime_Data        : in    std_logic_vector(63 downto 0)  := (others => '0');
        TxTime_Done        : out   std_logic;
        TxTime_Aborted     : out   std_logic;
        TxSdo_Valid        : in    std_logic                      := '0';
        TxSdo_Ready        : out   std_logic;
        TxSdo_Dlc          : in    std_logic_vector(3 downto 0)   := (others => '0');
        TxSdo_Data         : in    std_logic_vector(63 downto 0)  := (others => '0');
        TxSdo_Done         : out   std_logic;
        TxSdo_Aborted      : out   std_logic;
        TxNmt_Valid        : in    std_logic                      := '0';
        TxNmt_Ready        : out   std_logic;
        TxNmt_Data         : in    std_logic_vector(7 downto 0)   := (others => '0');
        TxNmt_Done         : out   std_logic;
        TxNmt_Aborted      : out   std_logic;
        -- Status and error events
        Err_Protocol       : out   std_logic;
        Err_CobId          : out   std_logic;
        Stat_CobIdMismatch : out   std_logic_vector(11 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_dispatch is

    -- *** Entries of the COB-ID table ***
    constant ESync_c : natural := 0;
    constant ESct_c  : natural := 1;
    constant ERpdo_c : natural := 2;  -- 2 to 5
    constant ETpdo_c : natural := 6;  -- 6 to 9
    constant ELtp_c  : natural := 10;
    constant EMhb_c  : natural := 11;

    -- *** Transmit sources in the order of the default identifiers (source s is requester bit 6 - s) ***
    constant STpdo_c : natural := 0;  -- 0 to 3
    constant SLtp_c  : natural := 4;
    constant SSdo_c  : natural := 5;
    constant SNmt_c  : natural := 6;

    -- Entry e exists for the generics
    function entryExists (e : natural) return boolean is
    begin
        if e = ESct_c or e = ELtp_c then
            return TimePdos_g;
        elsif e >= ERpdo_c and e < ERpdo_c + 4 then
            return e - ERpdo_c < NumRpdo_g;
        elsif e >= ETpdo_c and e < ETpdo_c + 4 then
            return e - ETpdo_c < NumTpdo_g;
        else
            return true;
        end if;
    end function;

    -- *** Classification of a received frame ***
    type Class_t is (CNone, CNmt, CProtErr, CSync, CHb, CSdo, CRpdo, CSct);

    type Classified_t is record
        Kind : Class_t;
        Num  : natural range 0 to 3;  -- receive PDO
        Dlc  : std_logic_vector(3 downto 0);
        Data : std_logic_vector(63 downto 0);
    end record;

    type Classified_a is array (0 to 1) of Classified_t;

    -- *** Transmit state machine ***
    type TxState_t is (Idle_s, Send_s, Wait_s);

    -- *** Two process method ***
    type TwoProcess_r is record
        -- COB-ID protection
        Usable     : std_logic_vector(11 downto 0);
        Mismatch   : std_logic_vector(11 downto 0);
        ErrCobId   : std_logic;
        -- Receive outputs
        NmtValid   : std_logic;
        NmtCs      : std_logic_vector(7 downto 0);
        SyncValid  : std_logic;
        SyncDlc    : std_logic_vector(3 downto 0);
        SyncData   : std_logic_vector(7 downto 0);
        RpdoValid  : std_logic;
        RpdoNum    : std_logic_vector(1 downto 0);
        RpdoDlc    : std_logic_vector(3 downto 0);
        RpdoData   : std_logic_vector(63 downto 0);
        TimeValid  : std_logic;
        TimeDlc    : std_logic_vector(3 downto 0);
        TimeData   : std_logic_vector(63 downto 0);
        SdoValid   : std_logic;
        SdoDlc     : std_logic_vector(3 downto 0);
        SdoData    : std_logic_vector(63 downto 0);
        RedNmt     : std_logic_vector(1 downto 0);
        RedHb      : std_logic_vector(1 downto 0);
        RedHbDlc   : std_logic_vector(7 downto 0);
        RedHbState : std_logic_vector(15 downto 0);
        ErrProt    : std_logic;
        -- Held NMT message of the inactive bus
        Hold       : std_logic;
        HoldBus    : std_logic;
        HoldCs     : std_logic_vector(7 downto 0);
        -- Transmit
        TxState    : TxState_t;
        Owner      : natural range 0 to 6;
        TxId       : std_logic_vector(10 downto 0);
        TxDlc      : std_logic_vector(3 downto 0);
        TxData     : std_logic_vector(63 downto 0);
        AbortSent  : std_logic;
        AbortPulse : std_logic;
        Rej        : std_logic_vector(6 downto 0);
        CplDone    : std_logic_vector(6 downto 0);
        CplAbort   : std_logic_vector(6 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- *** Arbiter ***
    signal ArbReq   : std_logic_vector(6 downto 0);
    signal ArbGrant : std_logic_vector(6 downto 0);
    signal ArbValid : std_logic;
    signal ArbReady : std_logic;

    -- *** Transmit sources ***
    signal SrcValid   : std_logic_vector(6 downto 0);
    signal SrcAllowed : std_logic_vector(6 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Transmit sources: valid flags and the condition for a frame (DS-TX-04, DS-TX-05)
    -----------------------------------------------------------------------------------------------
    p_src : process (all) is
        variable NodeOk_v : boolean;
    begin
        NodeOk_v := Nmt_NodeIdValid = '1';

        for N in 0 to 3 loop
            SrcValid(STpdo_c + N) <= TxTpdo_Valid(N);
            if N < NumTpdo_g and r.Usable(ETpdo_c + N) = '1' and Nmt_EnaPdo = '1' and NodeOk_v then
                SrcAllowed(STpdo_c + N) <= '1';
            else
                SrcAllowed(STpdo_c + N) <= '0';
            end if;
        end loop;

        SrcValid(SLtp_c) <= TxTime_Valid;
        if TimePdos_g and r.Usable(ELtp_c) = '1' and Nmt_EnaPdo = '1' and NodeOk_v then
            SrcAllowed(SLtp_c) <= '1';
        else
            SrcAllowed(SLtp_c) <= '0';
        end if;
        SrcValid(SSdo_c) <= TxSdo_Valid;
        if SdoServer_g and Nmt_EnaSdo = '1' and NodeOk_v then
            SrcAllowed(SSdo_c) <= '1';
        else
            SrcAllowed(SSdo_c) <= '0';
        end if;
        SrcValid(SNmt_c) <= TxNmt_Valid;
        if NodeOk_v then
            SrcAllowed(SNmt_c) <= '1';
        else
            SrcAllowed(SNmt_c) <= '0';
        end if;
    end process;

    -- Requester bit 6 - s of source s; the arbiter is served in Idle_s only. No grant to a source in the cycle of its
    -- own completion event, so that Ready with Aborted is the reject path only and Ready never comes with Done (DS-TX-03)
    g_req : for S in 0 to 6 generate
        ArbReq(6 - S) <= SrcValid(S) and SrcAllowed(S) and not r.Rej(S) and not r.CplDone(S) and not r.CplAbort(S);
    end generate;

    ArbReady <= '1' when r.TxState = Idle_s else '0';

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Ent_v     : std_logic_vector(11 downto 0);
        variable Copy_v    : std_logic_vector(11 downto 0);
        variable Free_v    : boolean;
        variable Cls_v     : Classified_a;
        variable Id_v      : unsigned(10 downto 0);
        variable B_v       : natural range 0 to 1;
        variable A_v       : natural range 0 to 1;
        variable I_v       : natural range 0 to 1;
        variable Byte1_v   : std_logic_vector(7 downto 0);
        variable Node_v    : std_logic_vector(7 downto 0);
        variable S_v       : natural range 0 to 6;
        variable OwnerOk_v : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values of the events ***
        v.ErrCobId   := '0';
        v.NmtValid   := '0';
        v.SyncValid  := '0';
        v.RpdoValid  := '0';
        v.TimeValid  := '0';
        v.SdoValid   := '0';
        v.RedNmt     := "00";
        v.RedHb      := "00";
        v.ErrProt    := '0';
        v.AbortPulse := '0';
        v.Rej        := (others => '0');
        v.CplDone    := (others => '0');
        v.CplAbort   := (others => '0');

        -- *** COB-ID protection (DS-CP-01, DS-CP-02, DS-TX-05) ***
        for E in 0 to 11 loop
            Ent_v  := Cfg_CobId(12 * E + 11 downto 12 * E);
            Copy_v := Cfg_CobIdCopy(12 * E + 11 downto 12 * E);
            Id_v   := unsigned(Ent_v(10 downto 0));
            Free_v := (Id_v >= 16#781# and Id_v <= 16#7DE#) or Id_v >= 16#7F0#;
            if Ent_v /= Copy_v then
                v.Mismatch(E) := '1';
            else
                v.Mismatch(E) := '0';
            end if;
            if entryExists(E) and Ent_v = Copy_v and Ent_v(11) = '1' and not Free_v then
                v.Usable(E) := '1';
            else
                v.Usable(E) := '0';
            end if;
            if v.Mismatch(E) = '1' and r.Mismatch(E) = '0' then
                v.ErrCobId := '1';
            end if;
        end loop;

        -- *** Receive filter, one per bus (DS-RX-01 to DS-RX-03, DS-RX-07, DS-RX-08) ***
        Node_v := '0' & Nmt_NodeId;

        for B in 0 to 1 loop
            Cls_v(B).Kind := CNone;
            Cls_v(B).Num  := 0;
            Cls_v(B).Dlc  := LinkRx_Dlc(4 * B + 3 downto 4 * B);
            Cls_v(B).Data := LinkRx_Data(64 * B + 63 downto 64 * B);
            Id_v          := unsigned(LinkRx_Id(29 * B + 28 downto 29 * B + 18));
            Byte1_v       := LinkRx_Data(64 * B + 55 downto 64 * B + 48);
            if LinkRx_Valid(B) = '1' and LinkRx_Ide(B) = '0' and LinkRx_Rtr(B) = '0' and Nmt_NodeIdValid = '1' then
                if Id_v = 0 then
                    if Cls_v(B).Dlc /= "0010" then
                        Cls_v(B).Kind := CProtErr;
                    elsif Byte1_v = Node_v or Byte1_v = x"00" then
                        Cls_v(B).Kind := CNmt;
                    end if;
                elsif r.Usable(ESync_c) = '1' and Id_v = unsigned(Cfg_CobId(12 * ESync_c + 10 downto 12 * ESync_c)) then
                    Cls_v(B).Kind := CSync;
                elsif r.Usable(EMhb_c) = '1' and Id_v = unsigned(Cfg_CobId(12 * EMhb_c + 10 downto 12 * EMhb_c)) then
                    Cls_v(B).Kind := CHb;
                elsif SdoServer_g and Id_v = 16#600# + resize(unsigned(Nmt_NodeId), 11) then
                    Cls_v(B).Kind := CSdo;
                else

                    for N in 3 downto 0 loop
                        if r.Usable(ERpdo_c + N) = '1' and
                           Id_v = unsigned(Cfg_CobId(12 * (ERpdo_c + N) + 10 downto 12 * (ERpdo_c + N))) then
                            Cls_v(B).Kind := CRpdo;
                            Cls_v(B).Num  := N;
                        end if;
                    end loop;

                    if Cls_v(B).Kind = CNone and TimePdos_g and r.Usable(ESct_c) = '1' and
                       Id_v = unsigned(Cfg_CobId(12 * ESct_c + 10 downto 12 * ESct_c)) then
                        Cls_v(B).Kind := CSct;
                    end if;
                end if;
            end if;
            -- Per-bus events to ocan_redundancy (DS-BG-02) and protocol errors
            if Cls_v(B).Kind = CNmt then
                v.RedNmt(B) := '1';
            end if;
            if Cls_v(B).Kind = CHb then
                v.RedHb(B)                           := '1';
                v.RedHbDlc(4 * B + 3 downto 4 * B)   := Cls_v(B).Dlc;
                v.RedHbState(8 * B + 7 downto 8 * B) := Cls_v(B).Data(63 downto 56);
            end if;
            if Cls_v(B).Kind = CProtErr then
                v.ErrProt := '1';
            end if;
        end loop;

        -- *** Bus gate (DS-BG-01, DS-BG-03, DS-BG-04) ***
        if Red_ActiveBus = '1' then
            A_v := 1;
            I_v := 0;
        else
            A_v := 0;
            I_v := 1;
        end if;

        if r.Hold = '1' then
            -- Held NMT message: delivered when its bus is active, discarded when the selection ends without it;
            -- no other frame reaches the protocol outputs meanwhile
            if Red_ActiveBus = r.HoldBus then
                v.NmtValid := '1';
                v.NmtCs    := r.HoldCs;
                v.Hold     := '0';
            elsif Red_Selecting = '0' then
                v.Hold := '0';
            end if;
        elsif Red_Selecting = '1' and Cls_v(I_v).Kind = CNmt and Cls_v(A_v).Kind /= CNmt then
            v.Hold    := '1';
            v.HoldBus := not Red_ActiveBus;
            v.HoldCs  := Cls_v(I_v).Data(63 downto 56);
        else

            -- Frame of the active bus to its protocol block, with the service enables (DS-RX-06)
            case Cls_v(A_v).Kind is
                when CNmt =>
                    v.NmtValid := '1';
                    v.NmtCs    := Cls_v(A_v).Data(63 downto 56);
                when CSync =>
                    if Nmt_EnaSync = '1' then
                        v.SyncValid := '1';
                        v.SyncDlc   := Cls_v(A_v).Dlc;
                        v.SyncData  := Cls_v(A_v).Data(63 downto 56);
                    end if;
                when CSdo =>
                    if Nmt_EnaSdo = '1' then
                        v.SdoValid := '1';
                        v.SdoDlc   := Cls_v(A_v).Dlc;
                        v.SdoData  := Cls_v(A_v).Data;
                    end if;
                when CRpdo =>
                    if Nmt_EnaPdo = '1' then
                        v.RpdoValid := '1';
                        v.RpdoNum   := std_logic_vector(to_unsigned(Cls_v(A_v).Num, 2));
                        v.RpdoDlc   := Cls_v(A_v).Dlc;
                        v.RpdoData  := Cls_v(A_v).Data;
                    end if;
                when CSct =>
                    if Nmt_EnaPdo = '1' then
                        v.TimeValid := '1';
                        v.TimeDlc   := Cls_v(A_v).Dlc;
                        v.TimeData  := Cls_v(A_v).Data;
                    end if;
                when others =>
                    null;
            end case;

        end if;

        -- *** Reject path: requests that may not send complete as aborted one cycle later (DS-TX-04) ***
        for S in 0 to 6 loop
            if SrcValid(S) = '1' and SrcAllowed(S) = '0' and r.Rej(S) = '0' then
                v.Rej(S) := '1';
            end if;
        end loop;

        -- *** Transmit state machine (DS-TX-01 to DS-TX-03) ***
        case r.Owner is
            when STpdo_c to STpdo_c + 3 | SLtp_c =>
                OwnerOk_v := Nmt_EnaPdo = '1' and Nmt_NodeIdValid = '1';
            when SSdo_c =>
                OwnerOk_v := Nmt_EnaSdo = '1' and Nmt_NodeIdValid = '1';
            when others =>
                OwnerOk_v := Nmt_NodeIdValid = '1';
        end case;

        case r.TxState is

            when Idle_s =>
                if ArbValid = '1' then
                    S_v := 0;

                    for S in 0 to 6 loop
                        if ArbGrant(6 - S) = '1' then
                            S_v := S;
                        end if;
                    end loop;

                    v.Owner := S_v;

                    case S_v is
                        when STpdo_c to STpdo_c + 3 =>
                            v.TxId   := Cfg_CobId(12 * (ETpdo_c + S_v) + 10 downto 12 * (ETpdo_c + S_v));
                            v.TxDlc  := TxTpdo_Dlc(4 * S_v + 3 downto 4 * S_v);
                            v.TxData := TxTpdo_Data(64 * S_v + 63 downto 64 * S_v);
                        when SLtp_c =>
                            v.TxId   := Cfg_CobId(12 * ELtp_c + 10 downto 12 * ELtp_c);
                            v.TxDlc  := TxTime_Dlc;
                            v.TxData := TxTime_Data;
                        when SSdo_c =>
                            v.TxId   := std_logic_vector(16#580# + resize(unsigned(Nmt_NodeId), 11));
                            v.TxDlc  := TxSdo_Dlc;
                            v.TxData := TxSdo_Data;
                        when others =>
                            v.TxId   := std_logic_vector(16#700# + resize(unsigned(Nmt_NodeId), 11));
                            v.TxDlc  := "0001";
                            v.TxData := TxNmt_Data & x"00000000000000";
                    end case;

                    v.AbortSent := '0';
                    v.TxState   := Send_s;
                end if;

            when Send_s =>
                if LinkTx_Ready = '1' then
                    v.TxState := Wait_s;
                elsif not OwnerOk_v then
                    -- The link has not taken the frame: withdrawn
                    v.CplAbort(r.Owner) := '1';
                    v.TxState           := Idle_s;
                end if;

            when Wait_s =>
                if LinkTx_Done = '1' then
                    v.CplDone(r.Owner) := '1';
                    v.TxState          := Idle_s;
                elsif LinkTx_Aborted = '1' then
                    v.CplAbort(r.Owner) := '1';
                    v.TxState           := Idle_s;
                elsif not OwnerOk_v and r.AbortSent = '0' then
                    v.AbortPulse := '1';
                    v.AbortSent  := '1';
                end if;

            -- coverage off
            when others =>
                v.TxState := Idle_s;
            -- coverage on

        end case;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    LinkTx_Valid <= '1' when r.TxState = Send_s else '0';
    LinkTx_Id    <= r.TxId & "000000000000000000";
    LinkTx_Dlc   <= r.TxDlc;
    LinkTx_Data  <= r.TxData;
    LinkTx_Abort <= r.AbortPulse;

    RxNmt_Valid    <= r.NmtValid;
    RxNmt_Cs       <= r.NmtCs;
    RxSync_Valid   <= r.SyncValid;
    RxSync_Dlc     <= r.SyncDlc;
    RxSync_Data    <= r.SyncData;
    RxRpdo_Valid   <= r.RpdoValid;
    RxRpdo_Num     <= r.RpdoNum;
    RxRpdo_Dlc     <= r.RpdoDlc;
    RxRpdo_Data    <= r.RpdoData;
    RxTime_Valid   <= r.TimeValid;
    RxTime_Dlc     <= r.TimeDlc;
    RxTime_Data    <= r.TimeData;
    RxSdo_Valid    <= r.SdoValid;
    RxSdo_Dlc      <= r.SdoDlc;
    RxSdo_Data     <= r.SdoData;
    RxRed_NmtValid <= r.RedNmt;
    RxRed_HbValid  <= r.RedHb;
    RxRed_HbDlc    <= r.RedHbDlc;
    RxRed_HbState  <= r.RedHbState;

    Err_Protocol       <= r.ErrProt;
    Err_CobId          <= r.ErrCobId;
    Stat_CobIdMismatch <= r.Mismatch;

    -- Handshake of the sources: a grant in Idle_s, or the registered rejection
    p_ready : process (all) is
        variable Rdy_v : std_logic_vector(6 downto 0);
    begin

        for S in 0 to 6 loop
            if (r.TxState = Idle_s and ArbGrant(6 - S) = '1') or r.Rej(S) = '1' then
                Rdy_v(S) := '1';
            else
                Rdy_v(S) := '0';
            end if;
        end loop;

        TxTpdo_Ready <= Rdy_v(3 downto 0);
        TxTime_Ready <= Rdy_v(SLtp_c);
        TxSdo_Ready  <= Rdy_v(SSdo_c);
        TxNmt_Ready  <= Rdy_v(SNmt_c);
    end process;

    TxTpdo_Done    <= r.CplDone(3 downto 0);
    TxTpdo_Aborted <= r.CplAbort(3 downto 0) or r.Rej(3 downto 0);
    TxTime_Done    <= r.CplDone(SLtp_c);
    TxTime_Aborted <= r.CplAbort(SLtp_c) or r.Rej(SLtp_c);
    TxSdo_Done     <= r.CplDone(SSdo_c);
    TxSdo_Aborted  <= r.CplAbort(SSdo_c) or r.Rej(SSdo_c);
    TxNmt_Done     <= r.CplDone(SNmt_c);
    TxNmt_Aborted  <= r.CplAbort(SNmt_c) or r.Rej(SNmt_c);

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Usable     <= (others => '0');
                r.Mismatch   <= (others => '0');
                r.ErrCobId   <= '0';
                r.NmtValid   <= '0';
                r.SyncValid  <= '0';
                r.RpdoValid  <= '0';
                r.TimeValid  <= '0';
                r.SdoValid   <= '0';
                r.RedNmt     <= "00";
                r.RedHb      <= "00";
                r.ErrProt    <= '0';
                r.Hold       <= '0';
                r.TxState    <= Idle_s;
                r.Owner      <= SNmt_c;
                r.AbortSent  <= '0';
                r.AbortPulse <= '0';
                r.Rej        <= (others => '0');
                r.CplDone    <= (others => '0');
                r.CplAbort   <= (others => '0');
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Transmit arbitration (DS-TX-01, DS-TX-06)
    -----------------------------------------------------------------------------------------------
    i_arb : entity olo.olo_base_arb_rr
        generic map (
            Width_g => 7
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => ArbReq,
            Out_Grant => ArbGrant,
            Out_Ready => ArbReady,
            Out_Valid => ArbValid
        );

end architecture;
