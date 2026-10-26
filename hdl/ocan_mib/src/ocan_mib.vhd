---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register interface of OpenCAN for a processor system: an AXI4-Lite slave with the identification, the control
-- and the bit timing, the status of the node, sticky event and error flags with an interrupt, the error counters of
-- the controllers, the PDO data, the mailbox of the application objects, the local time and the error injection.
-- The ports towards the core have the names of the ports of ocan_core (ECSS-E-ST-50-15C clauses 5.4.3 and 5.6.2).
--
-- Documentation: hdl/ocan_mib/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ocan_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_mib is
    generic (
        -- Generics of ocan_core, read in GENERICS, DOMINANT_LIMIT and CLK_FREQUENCY
        BusAccess_g           : string                                 := "Selective";
        MinimalSet_g          : boolean                                := false;
        TimePdos_g            : boolean                                := true;
        AutoRecover_g         : boolean                                := true;
        NumRpdo_g             : natural range 0 to 4                   := 4;
        NumTpdo_g             : natural range 0 to 4                   := 4;
        FineBits_g            : natural range 0 to 24                  := 24;
        SyncStages_g          : positive range 2 to 4                  := 2;
        DominantLimit_g       : positive range 13 to 1023              := 32;
        ClkFrequency_g        : positive range 1000000 to integer'high := 100000000;
        -- Reset values of CONTROL.ENABLE and BIT_TIMING
        AutoEnable_g          : boolean                                := true;
        Prescaler_g           : positive range 1 to 1023               := 4;
        Tseg1_g               : natural range 2 to 31                  := 18;
        Tseg2_g               : natural range 2 to 15                  := 6;
        Sjw_g                 : natural range 1 to 4                   := 4;
        -- Error injection registers
        ErrInjRegs_g          : boolean                                := false
    );
    port (
        -- Control
        Clk                   : in    std_logic;
        Rst                   : in    std_logic;
        -- AXI4-Lite slave (9-bit byte addresses)
        S_AxiLite_ArAddr      : in    std_logic_vector(8 downto 0);
        S_AxiLite_ArValid     : in    std_logic;
        S_AxiLite_ArReady     : out   std_logic;
        S_AxiLite_AwAddr      : in    std_logic_vector(8 downto 0);
        S_AxiLite_AwValid     : in    std_logic;
        S_AxiLite_AwReady     : out   std_logic;
        S_AxiLite_WData       : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb       : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid      : in    std_logic;
        S_AxiLite_WReady      : out   std_logic;
        S_AxiLite_BResp       : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid      : out   std_logic;
        S_AxiLite_BReady      : in    std_logic;
        S_AxiLite_RData       : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp       : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid      : out   std_logic;
        S_AxiLite_RReady      : in    std_logic;
        -- Interrupt
        Irq                   : out   std_logic;
        -- Control and bit timing of ocan_core
        Ctrl_Enable           : out   std_logic;
        Ctrl_Recover          : out   std_logic;
        Ctrl_Reenable         : out   std_logic_vector(1 downto 0);
        Cfg_Prescaler         : out   std_logic_vector(9 downto 0);
        Cfg_Tseg1             : out   std_logic_vector(4 downto 0);
        Cfg_Tseg2             : out   std_logic_vector(3 downto 0);
        Cfg_Sjw               : out   std_logic_vector(2 downto 0);
        -- NODE-ID
        Node_Id               : in    std_logic_vector(6 downto 0);
        Node_IdValid          : in    std_logic;
        -- PDOs (PDO n in bit n - 1 and in bits 64 n - 1 downto 64 (n - 1))
        Sync_Valid            : in    std_logic;
        Rpdo_Valid            : in    std_logic_vector(3 downto 0);
        Rpdo_Data             : in    std_logic_vector(255 downto 0);
        Tpdo_Req              : out   std_logic_vector(3 downto 0);
        Tpdo_Data             : out   std_logic_vector(255 downto 0);
        Stat_TpdoBusy         : in    std_logic_vector(3 downto 0);
        Stat_PdoEnabled       : in    std_logic;
        Evt_TpdoSent          : in    std_logic_vector(3 downto 0);
        Evt_TpdoAborted       : in    std_logic_vector(3 downto 0);
        Err_RpdoLength        : in    std_logic_vector(3 downto 0);
        Err_TpdoBusy          : in    std_logic_vector(3 downto 0);
        Err_TpdoTimeout       : in    std_logic_vector(3 downto 0);
        -- Application port
        App_ReqValid          : in    std_logic;
        App_ReqReady          : out   std_logic;
        App_ReqWrite          : in    std_logic;
        App_ReqIndex          : in    std_logic_vector(15 downto 0);
        App_ReqSub            : in    std_logic_vector(7 downto 0);
        App_ReqData           : in    std_logic_vector(63 downto 0);
        App_ReqLen            : in    std_logic_vector(3 downto 0);
        App_RspValid          : out   std_logic;
        App_RspData           : out   std_logic_vector(63 downto 0);
        App_RspLen            : out   std_logic_vector(3 downto 0);
        App_RspAbort          : out   std_logic_vector(31 downto 0);
        -- Local time
        Time_Coarse           : in    std_logic_vector(31 downto 0);
        Time_Fine             : in    std_logic_vector(23 downto 0);
        Time_Req              : out   std_logic;
        Stat_TimeSet          : in    std_logic;
        Evt_TimeSet           : in    std_logic;
        Evt_TimeSync          : in    std_logic;
        Err_TimeTxBusy        : in    std_logic;
        Err_TimeRxDrop        : in    std_logic;
        Err_TimeTxTimeout     : in    std_logic;
        -- Network management
        Stat_NmtState         : in    std_logic_vector(1 downto 0);
        Evt_ResetApp          : in    std_logic;
        Evt_ResetComm         : in    std_logic;
        Err_NmtCs             : in    std_logic;
        Err_NodeId            : in    std_logic;
        Err_NmtTxTimeout      : in    std_logic;
        -- Redundancy management
        Stat_ActiveBus        : in    std_logic;
        Stat_Selecting        : in    std_logic;
        Stat_Ctoggle          : in    std_logic_vector(7 downto 0);
        Stat_MasterHbState    : in    std_logic_vector(7 downto 0);
        Stat_MasterHbPresent  : in    std_logic_vector(1 downto 0);
        Evt_BdefaultUpdate    : in    std_logic;
        Err_MasterHbMissing   : in    std_logic;
        Err_ToggleEnd         : in    std_logic;
        Err_MasterHbDlc       : in    std_logic;
        -- Object dictionary and dispatch
        Stat_ErrReg           : in    std_logic_vector(7 downto 0);
        Err_ParamCopy         : in    std_logic;
        Err_AppTimeout        : in    std_logic;
        Stat_CobIdMismatch    : in    std_logic_vector(11 downto 0);
        Err_Protocol          : in    std_logic;
        Err_CobId             : in    std_logic;
        -- SDO server
        Stat_SdoOpen          : in    std_logic;
        Evt_SdoAbortTx        : in    std_logic;
        Evt_SdoAbortRx        : in    std_logic;
        Err_SdoRxDrop         : in    std_logic;
        Err_SdoTxTimeout      : in    std_logic;
        Err_SdoAccTimeout     : in    std_logic;
        -- Link, per controller (controller A in the low bits)
        Stat_LinkTec          : in    std_logic_vector(17 downto 0);
        Stat_LinkRec          : in    std_logic_vector(15 downto 0);
        Stat_LinkState        : in    std_logic_vector(3 downto 0);
        Stat_LinkBusIdle      : in    std_logic_vector(1 downto 0);
        Stat_LinkDomTimeout   : in    std_logic_vector(1 downto 0);
        Stat_LinkSwitching    : in    std_logic;
        Evt_LinkArbLost       : in    std_logic;
        Err_LinkBit           : in    std_logic_vector(1 downto 0);
        Err_LinkStuff         : in    std_logic_vector(1 downto 0);
        Err_LinkCrc           : in    std_logic_vector(1 downto 0);
        Err_LinkForm          : in    std_logic_vector(1 downto 0);
        Err_LinkAck           : in    std_logic_vector(1 downto 0);
        Err_LinkDomTimeout    : in    std_logic_vector(1 downto 0);
        -- Error injection inputs of ocan_core
        ErrInj_OdBitFlip      : out   std_logic_vector(557 downto 0);
        ErrInj_OdValid        : out   std_logic;
        ErrInj_NmtBitFlip     : out   std_logic_vector(13 downto 0);
        ErrInj_NmtValid       : out   std_logic;
        ErrInj_LinkTxDominant : out   std_logic_vector(1 downto 0);
        ErrInj_LinkStopFlip   : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_mib is

    -- Abort code of a request while the mailbox is off: object does not exist (OD-AP-04)
    constant NoObject_c : std_logic_vector(31 downto 0) := x"06020000";

    -- Widths of the targets of the error injection
    constant OdBits_c  : positive := 558;
    constant NmtBits_c : positive := 14;

    subtype Word_t is std_logic_vector(31 downto 0);

    subtype Data_t is std_logic_vector(63 downto 0);

    type Data_a is array (0 to 3) of Data_t;

    type Word_a is array (0 to 3) of Word_t;

    type Cnt_a is array (0 to 5) of unsigned(7 downto 0);

    type CntCtl_a is array (0 to 1) of Cnt_a;

    -- Register words by word index (address / 4), for the read multiplexer
    type Map_a is array (0 to 127) of Word_t;

    -- *** Two process method ***
    type TwoProcess_r is record
        -- AXI4-Lite read response
        RdData     : Word_t;
        RdValid    : std_logic;
        -- Control and bit timing (MB-1)
        Enable     : std_logic;
        AppEnable  : std_logic;
        Recover    : std_logic;
        Reenable   : std_logic_vector(1 downto 0);
        Prescaler  : std_logic_vector(9 downto 0);
        Tseg1      : std_logic_vector(4 downto 0);
        Tseg2      : std_logic_vector(3 downto 0);
        Sjw        : std_logic_vector(2 downto 0);
        -- Flags and interrupt enables (MB-2)
        Evt        : std_logic_vector(9 downto 0);
        EvtEn      : std_logic_vector(9 downto 0);
        PdoEvt     : std_logic_vector(23 downto 0);
        PdoEn      : std_logic_vector(23 downto 0);
        Err        : std_logic_vector(16 downto 0);
        ErrEn      : std_logic_vector(16 downto 0);
        LinkErr    : std_logic_vector(13 downto 0);
        LinkEn     : std_logic_vector(13 downto 0);
        Irq        : std_logic;
        Cnt        : CntCtl_a;
        -- PDOs (MB-3)
        RpdoLo     : Word_a;
        TpdoNext   : Data_a;
        TpdoData   : Data_a;
        TpdoReq    : std_logic_vector(3 downto 0);
        -- Mailbox of the application port (MB-3)
        Pending    : std_logic;
        ReqWrite   : std_logic;
        ReqIndex   : std_logic_vector(15 downto 0);
        ReqSub     : std_logic_vector(7 downto 0);
        ReqLen     : std_logic_vector(3 downto 0);
        ReqData    : Data_t;
        RspData    : Data_t;
        RspLen     : std_logic_vector(3 downto 0);
        RspAbort   : Word_t;
        RspValid   : std_logic;
        -- Local time (MB-3)
        FineSnap   : std_logic_vector(23 downto 0);
        TimeReq    : std_logic;
        -- Error injection (MB-4)
        InjTarget  : std_logic;
        InjWin0    : unsigned(4 downto 0);
        InjWin1    : unsigned(4 downto 0);
        InjMask0   : Word_t;
        InjMask1   : Word_t;
        InjPulse   : std_logic;
        TxDominant : std_logic_vector(1 downto 0);
        StopFlip   : std_logic_vector(1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- Register bus of olo_axi_lite_slave
    signal RbAddr   : std_logic_vector(8 downto 0);
    signal RbWr     : std_logic;
    signal RbWrData : std_logic_vector(31 downto 0);
    signal RbRd     : std_logic;

    -- One bit of a generic as a register bit
    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    -- A field of a register word
    function field (value : natural; hi : natural; lo : natural) return Word_t is
        variable W_v : Word_t := (others => '0');
    begin
        W_v(hi downto lo) := std_logic_vector(to_unsigned(value, hi - lo + 1));
        return W_v;
    end function;

    -- Bit timing in the ranges of olo_intf_can (MB-CT-04)
    function timingOk (w : Word_t) return boolean is
        variable Tseg1_v : natural range 0 to 31;
        variable Tseg2_v : natural range 0 to 15;
        variable Sjw_v   : natural range 0 to 7;
    begin
        Tseg1_v                                                       := to_integer(unsigned(w(BitTimingTseg1Hi_c downto BitTimingTseg1Lo_c)));
        Tseg2_v                                                       := to_integer(unsigned(w(BitTimingTseg2Hi_c downto BitTimingTseg2Lo_c)));
        Sjw_v                                                         := to_integer(unsigned(w(BitTimingSjwHi_c downto BitTimingSjwLo_c)));
        return Tseg1_v >= 2 and Tseg2_v >= 2 and Sjw_v >= 1 and Sjw_v <= 4 and Sjw_v <= Tseg2_v;
    end function;

    -- The constant registers of the identification
    constant Generics_c      : Word_t := field(SyncStages_g, GenericsSyncStagesHi_c, GenericsSyncStagesLo_c) or
                                    field(FineBits_g, GenericsFineBitsHi_c, GenericsFineBitsLo_c) or
                                    field(NumTpdo_g, GenericsNumTpdoHi_c, GenericsNumTpdoLo_c) or
                                    field(NumRpdo_g, GenericsNumRpdoHi_c, GenericsNumRpdoLo_c);
    constant DominantLimit_c : Word_t := field(DominantLimit_g, DominantLimitLimitHi_c, DominantLimitLimitLo_c);

begin

    assert BusAccess_g = "Selective" or BusAccess_g = "Parallel"
        report "ocan_mib: BusAccess_g must be ""Selective"" or ""Parallel"""
        severity failure;

    assert Sjw_g <= Tseg2_g
        report "ocan_mib: Sjw_g must not exceed Tseg2_g"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Idx_v   : natural range 0 to 127;
        variable Wr_v    : boolean;
        variable W_v     : Word_t;
        variable Map_v   : Map_a;
        variable Rw_v    : Word_t;
        variable EvIn_v  : std_logic_vector(9 downto 0);
        variable PdoIn_v : std_logic_vector(23 downto 0);
        variable ErrIn_v : std_logic_vector(16 downto 0);
        variable LnkIn_v : std_logic_vector(13 downto 0);
        variable CntIn_v : std_logic_vector(5 downto 0);
        variable Taken_v : boolean;
        variable Clr_v   : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.RdValid  := '0';
        v.Recover  := '0';
        v.Reenable := (others => '0');
        v.TpdoReq  := (others => '0');
        v.RspValid := '0';
        v.TimeReq  := '0';
        v.InjPulse := '0';
        v.StopFlip := (others => '0');

        Idx_v := to_integer(unsigned(RbAddr(8 downto 2)));
        Wr_v  := RbWr = '1';
        W_v   := RbWrData;

        -- *** Control and bit timing (MB-CT-01 to MB-CT-04) ***
        ErrIn_v := (others => '0');
        if Wr_v and Idx_v = RegControl_c / 4 then
            v.Enable      := W_v(ControlEnable_c);
            v.AppEnable   := W_v(ControlAppEnable_c);
            v.Recover     := W_v(ControlRecover_c);
            v.Reenable(0) := W_v(ControlReenableA_c);
            v.Reenable(1) := W_v(ControlReenableB_c);
        end if;
        if Wr_v and Idx_v = RegBitTiming_c / 4 then
            if r.Enable = '0' and timingOk(W_v) then
                v.Prescaler := W_v(BitTimingPrescalerHi_c downto BitTimingPrescalerLo_c);
                v.Tseg1     := W_v(BitTimingTseg1Hi_c downto BitTimingTseg1Lo_c);
                v.Tseg2     := W_v(BitTimingTseg2Hi_c downto BitTimingTseg2Lo_c);
                v.Sjw       := W_v(BitTimingSjwHi_c downto BitTimingSjwLo_c);
            else
                ErrIn_v(ErrorsCfgRefused_c) := '1';
            end if;
        end if;

        -- *** Mailbox of the application port (MB-AP-01 to MB-AP-04) ***
        -- A request is taken in the cycle in which App_ReqValid meets App_ReqReady ('1' while no request is pending)
        Taken_v := r.AppEnable = '1' and r.Pending = '0' and App_ReqValid = '1';
        if Taken_v then
            v.Pending  := '1';
            v.ReqWrite := App_ReqWrite;
            v.ReqIndex := App_ReqIndex;
            v.ReqSub   := App_ReqSub;
            v.ReqLen   := App_ReqLen;
            v.ReqData  := App_ReqData;
        end if;
        if Wr_v and Idx_v = RegAppRspControl_c / 4 and W_v(AppRspControlSend_c) = '1' and r.Pending = '1' then
            v.RspValid := '1';
            v.Pending  := '0';
        end if;
        -- The time-out of the request in the core and a mailbox switched off end a pending request
        if Err_AppTimeout = '1' or r.AppEnable = '0' then
            v.Pending := '0';
        end if;
        if Wr_v then
            if Idx_v = RegAppRspHi_c / 4 then
                v.RspData(63 downto 32) := W_v;
            elsif Idx_v = RegAppRspLo_c / 4 then
                v.RspData(31 downto 0) := W_v;
            elsif Idx_v = RegAppRspLen_c / 4 then
                v.RspLen := W_v(AppRspLenLenHi_c downto AppRspLenLenLo_c);
            elsif Idx_v = RegAppRspAbort_c / 4 then
                v.RspAbort := W_v;
            end if;
        end if;

        -- *** Transmit PDOs (MB-PD-02, MB-PD-03) ***
        for n in 0 to NumTpdo_g - 1 loop
            if Wr_v and Idx_v = RegTpdo1Hi_c / 4 + 2 * n then
                v.TpdoNext(n)(63 downto 32) := W_v;
            end if;
            if Wr_v and Idx_v = RegTpdo1Lo_c / 4 + 2 * n then
                v.TpdoNext(n)(31 downto 0) := W_v;
            end if;
            if Wr_v and Idx_v = RegTpdoControl_c / 4 and
               (W_v(TpdoControlUpdateLo_c + n) = '1' or W_v(TpdoControlRequestLo_c + n) = '1') then
                v.TpdoData(n) := r.TpdoNext(n);
                v.TpdoReq(n)  := W_v(TpdoControlRequestLo_c + n);
            end if;
        end loop;

        -- *** Local time request (MB-TM-02) ***
        if Wr_v and Idx_v = RegTimeControl_c / 4 then
            v.TimeReq := W_v(TimeControlRequest_c);
        end if;

        -- *** Error injection (MB-EI-01 to MB-EI-03) ***
        if ErrInjRegs_g and Wr_v then
            if Idx_v = RegErrinjSelect_c / 4 then
                v.InjTarget := W_v(ErrinjSelectTarget_c);
                v.InjWin0   := unsigned(W_v(ErrinjSelectWindow0Hi_c downto ErrinjSelectWindow0Lo_c));
                v.InjWin1   := unsigned(W_v(ErrinjSelectWindow1Hi_c downto ErrinjSelectWindow1Lo_c));
            elsif Idx_v = RegErrinjMask0_c / 4 then
                v.InjMask0 := W_v;
            elsif Idx_v = RegErrinjMask1_c / 4 then
                v.InjMask1 := W_v;
            elsif Idx_v = RegErrinjControl_c / 4 then
                v.InjPulse    := W_v(ErrinjControlInject_c);
                v.StopFlip(0) := W_v(ErrinjControlLinkStopFlipA_c);
                v.StopFlip(1) := W_v(ErrinjControlLinkStopFlipB_c);
                v.TxDominant  := W_v(ErrinjControlLinkTxDominantHi_c downto ErrinjControlLinkTxDominantLo_c);
            end if;
        end if;

        -- *** Flags (MB-FL-01, MB-FL-02): a write of '1' clears, an event of the same cycle sets ***
        EvIn_v                         := (others => '0');
        EvIn_v(EventsSync_c)           := Sync_Valid;
        EvIn_v(EventsResetApp_c)       := Evt_ResetApp;
        EvIn_v(EventsResetComm_c)      := Evt_ResetComm;
        EvIn_v(EventsBdefaultUpdate_c) := Evt_BdefaultUpdate;
        EvIn_v(EventsTimeSet_c)        := Evt_TimeSet;
        EvIn_v(EventsTimeSync_c)       := Evt_TimeSync;
        EvIn_v(EventsSdoAbortTx_c)     := Evt_SdoAbortTx;
        EvIn_v(EventsSdoAbortRx_c)     := Evt_SdoAbortRx;
        EvIn_v(EventsLinkArbLost_c)    := Evt_LinkArbLost;
        EvIn_v(EventsAppRequest_c)     := toSl(Taken_v);

        PdoIn_v := Err_TpdoTimeout & Err_TpdoBusy & Err_RpdoLength & Evt_TpdoAborted & Evt_TpdoSent & Rpdo_Valid;

        ErrIn_v(ErrorsNmtCs_c)           := Err_NmtCs;
        ErrIn_v(ErrorsNodeId_c)          := Err_NodeId;
        ErrIn_v(ErrorsNmtTxTimeout_c)    := Err_NmtTxTimeout;
        ErrIn_v(ErrorsMasterHbMissing_c) := Err_MasterHbMissing;
        ErrIn_v(ErrorsToggleEnd_c)       := Err_ToggleEnd;
        ErrIn_v(ErrorsMasterHbDlc_c)     := Err_MasterHbDlc;
        ErrIn_v(ErrorsParamCopy_c)       := Err_ParamCopy;
        ErrIn_v(ErrorsAppTimeout_c)      := Err_AppTimeout;
        ErrIn_v(ErrorsProtocol_c)        := Err_Protocol;
        ErrIn_v(ErrorsCobId_c)           := Err_CobId;
        ErrIn_v(ErrorsSdoRxDrop_c)       := Err_SdoRxDrop;
        ErrIn_v(ErrorsSdoTxTimeout_c)    := Err_SdoTxTimeout;
        ErrIn_v(ErrorsSdoAccTimeout_c)   := Err_SdoAccTimeout;
        ErrIn_v(ErrorsTimeTxBusy_c)      := Err_TimeTxBusy;
        ErrIn_v(ErrorsTimeRxDrop_c)      := Err_TimeRxDrop;
        ErrIn_v(ErrorsTimeTxTimeout_c)   := Err_TimeTxTimeout;

        LnkIn_v := (others => '0');

        for c in 0 to 1 loop
            LnkIn_v(8 * c + 5 downto 8 * c) := Err_LinkDomTimeout(c) & Err_LinkAck(c) & Err_LinkForm(c) &
                                               Err_LinkCrc(c) & Err_LinkStuff(c) & Err_LinkBit(c);
        end loop;

        if Wr_v and Idx_v = RegEvents_c / 4 then
            v.Evt := r.Evt and not W_v(v.Evt'range);
        end if;
        if Wr_v and Idx_v = RegPdoEvents_c / 4 then
            v.PdoEvt := r.PdoEvt and not W_v(v.PdoEvt'range);
        end if;
        if Wr_v and Idx_v = RegErrors_c / 4 then
            v.Err := r.Err and not W_v(v.Err'range);
        end if;
        if Wr_v and Idx_v = RegLinkErrors_c / 4 then
            v.LinkErr := r.LinkErr and not W_v(v.LinkErr'range);
        end if;
        v.Evt     := v.Evt or EvIn_v;
        v.PdoEvt  := v.PdoEvt or PdoIn_v;
        v.Err     := v.Err or ErrIn_v;
        v.LinkErr := v.LinkErr or LnkIn_v;

        if Wr_v and Idx_v = RegEventsIrqEn_c / 4 then
            v.EvtEn := W_v(v.EvtEn'range);
        end if;
        if Wr_v and Idx_v = RegPdoEventsIrqEn_c / 4 then
            v.PdoEn := W_v(v.PdoEn'range);
        end if;
        if Wr_v and Idx_v = RegErrorsIrqEn_c / 4 then
            v.ErrEn := W_v(v.ErrEn'range);
        end if;
        if Wr_v and Idx_v = RegLinkErrorsIrqEn_c / 4 then
            v.LinkEn := W_v(v.LinkEn'range);
        end if;

        -- *** Interrupt (MB-FL-03): with the flags and enables of the next cycle ***
        v.Irq := (or (v.Evt and v.EvtEn)) or (or (v.PdoEvt and v.PdoEn)) or (or (v.Err and v.ErrEn)) or
                 (or (v.LinkErr and v.LinkEn));

        -- *** Error counters (MB-CN-01): a write clears, an event of the same cycle counts after the clearing ***
        for c in 0 to 1 loop
            CntIn_v := Err_LinkDomTimeout(c) & Err_LinkAck(c) & Err_LinkForm(c) & Err_LinkCrc(c) &
                       Err_LinkStuff(c) & Err_LinkBit(c);

            for k in 0 to 5 loop
                if k < 4 then
                    Clr_v := Wr_v and Idx_v = RegLinkACounts0_c / 4 + 2 * c;
                else
                    Clr_v := Wr_v and Idx_v = RegLinkACounts1_c / 4 + 2 * c;
                end if;
                if Clr_v then
                    v.Cnt(c)(k) := (0 => CntIn_v(k),
                                    others => '0');
                elsif CntIn_v(k) = '1' and r.Cnt(c)(k) /= 255 then
                    v.Cnt(c)(k) := r.Cnt(c)(k) + 1;
                end if;
            end loop;

        end loop;

        -- *** Read multiplexer: the words of the cycle of Rb_Rd ***
        Map_v := (others => (others => '0'));

        Map_v(RegId_c / 4)                              := RegMapId_c;
        Map_v(RegGenerics_c / 4)                        := Generics_c;
        Map_v(RegGenerics_c / 4)(GenericsErrinjRegs_c)  := toSl(ErrInjRegs_g);
        Map_v(RegGenerics_c / 4)(GenericsAutoRecover_c) := toSl(AutoRecover_g);
        Map_v(RegGenerics_c / 4)(GenericsTimePdos_c)    := toSl(TimePdos_g);
        Map_v(RegGenerics_c / 4)(GenericsMinimalSet_c)  := toSl(MinimalSet_g);
        Map_v(RegGenerics_c / 4)(GenericsBusAccess_c)   := toSl(BusAccess_g = "Parallel");
        Map_v(RegDominantLimit_c / 4)                   := DominantLimit_c;
        Map_v(RegClkFrequency_c / 4)                    := std_logic_vector(to_unsigned(ClkFrequency_g, 32));

        Map_v(RegControl_c / 4)(ControlEnable_c)    := r.Enable;
        Map_v(RegControl_c / 4)(ControlAppEnable_c) := r.AppEnable;

        Map_v(RegBitTiming_c / 4)(BitTimingPrescalerHi_c downto BitTimingPrescalerLo_c) := r.Prescaler;
        Map_v(RegBitTiming_c / 4)(BitTimingTseg1Hi_c downto BitTimingTseg1Lo_c)         := r.Tseg1;
        Map_v(RegBitTiming_c / 4)(BitTimingTseg2Hi_c downto BitTimingTseg2Lo_c)         := r.Tseg2;
        Map_v(RegBitTiming_c / 4)(BitTimingSjwHi_c downto BitTimingSjwLo_c)             := r.Sjw;

        Map_v(RegNode_c / 4)(NodeNmtStateHi_c downto NodeNmtStateLo_c) := Stat_NmtState;
        Map_v(RegNode_c / 4)(NodeNodeIdHi_c downto NodeNodeIdLo_c)     := Node_Id;
        Map_v(RegNode_c / 4)(NodeNodeIdValid_c)                        := Node_IdValid;
        Map_v(RegNode_c / 4)(NodeErrRegHi_c downto NodeErrRegLo_c)     := Stat_ErrReg;
        Map_v(RegNode_c / 4)(NodePdoEnabled_c)                         := Stat_PdoEnabled;
        Map_v(RegNode_c / 4)(NodeSdoOpen_c)                            := Stat_SdoOpen;
        Map_v(RegNode_c / 4)(NodeTimeSet_c)                            := Stat_TimeSet;

        Rw_v                                                                     := (others => '0');
        Rw_v(RedundancyActiveBus_c)                                              := Stat_ActiveBus;
        Rw_v(RedundancySelecting_c)                                              := Stat_Selecting;
        Rw_v(RedundancySwitching_c)                                              := Stat_LinkSwitching;
        Rw_v(RedundancyMasterHbPresentHi_c downto RedundancyMasterHbPresentLo_c) := Stat_MasterHbPresent;
        Rw_v(RedundancyCtoggleHi_c downto RedundancyCtoggleLo_c)                 := Stat_Ctoggle;
        Rw_v(RedundancyMasterHbStateHi_c downto RedundancyMasterHbStateLo_c)     := Stat_MasterHbState;
        Map_v(RegRedundancy_c / 4)                                               := Rw_v;

        for c in 0 to 1 loop
            Map_v(RegLinkA_c / 4 + c)(LinkATecHi_c downto LinkATecLo_c)     := Stat_LinkTec(9 * c + 8 downto 9 * c);
            Map_v(RegLinkA_c / 4 + c)(LinkARecHi_c downto LinkARecLo_c)     := Stat_LinkRec(8 * c + 7 downto 8 * c);
            Map_v(RegLinkA_c / 4 + c)(LinkAStateHi_c downto LinkAStateLo_c) := Stat_LinkState(2 * c + 1 downto 2 * c);
            Map_v(RegLinkA_c / 4 + c)(LinkABusIdle_c)                       := Stat_LinkBusIdle(c);
            Map_v(RegLinkA_c / 4 + c)(LinkADomTimeout_c)                    := Stat_LinkDomTimeout(c);
        end loop;

        Map_v(RegCobIdMismatch_c / 4)(CobIdMismatchMismatchHi_c downto CobIdMismatchMismatchLo_c) := Stat_CobIdMismatch;
        Map_v(RegTpdoStatus_c / 4)(TpdoStatusBusyHi_c downto TpdoStatusBusyLo_c)                  := Stat_TpdoBusy;

        Map_v(RegEvents_c / 4)(r.Evt'range)             := r.Evt;
        Map_v(RegEventsIrqEn_c / 4)(r.EvtEn'range)      := r.EvtEn;
        Map_v(RegPdoEvents_c / 4)(r.PdoEvt'range)       := r.PdoEvt;
        Map_v(RegPdoEventsIrqEn_c / 4)(r.PdoEn'range)   := r.PdoEn;
        Map_v(RegErrors_c / 4)(r.Err'range)             := r.Err;
        Map_v(RegErrorsIrqEn_c / 4)(r.ErrEn'range)      := r.ErrEn;
        Map_v(RegLinkErrors_c / 4)(r.LinkErr'range)     := r.LinkErr;
        Map_v(RegLinkErrorsIrqEn_c / 4)(r.LinkEn'range) := r.LinkEn;

        Map_v(RegIrqStatus_c / 4)(IrqStatusEvents_c)     := or (r.Evt and r.EvtEn);
        Map_v(RegIrqStatus_c / 4)(IrqStatusPdoEvents_c)  := or (r.PdoEvt and r.PdoEn);
        Map_v(RegIrqStatus_c / 4)(IrqStatusErrors_c)     := or (r.Err and r.ErrEn);
        Map_v(RegIrqStatus_c / 4)(IrqStatusLinkErrors_c) := or (r.LinkErr and r.LinkEn);

        for c in 0 to 1 loop
            Map_v(RegLinkACounts0_c / 4 + 2 * c)              := std_logic_vector(r.Cnt(c)(3)) & std_logic_vector(r.Cnt(c)(2)) &
                                                                 std_logic_vector(r.Cnt(c)(1)) & std_logic_vector(r.Cnt(c)(0));
            Map_v(RegLinkACounts1_c / 4 + 2 * c)(15 downto 0) := std_logic_vector(r.Cnt(c)(5)) &
                                                                 std_logic_vector(r.Cnt(c)(4));
        end loop;

        for n in 0 to NumRpdo_g - 1 loop
            Map_v(RegRpdo1Hi_c / 4 + 2 * n) := Rpdo_Data(64 * n + 63 downto 64 * n + 32);
            Map_v(RegRpdo1Lo_c / 4 + 2 * n) := r.RpdoLo(n);
        end loop;

        for n in 0 to NumTpdo_g - 1 loop
            Map_v(RegTpdo1Hi_c / 4 + 2 * n) := r.TpdoNext(n)(63 downto 32);
            Map_v(RegTpdo1Lo_c / 4 + 2 * n) := r.TpdoNext(n)(31 downto 0);
        end loop;

        Map_v(RegAppReq_c / 4)(AppReqPending_c)                             := r.Pending;
        Map_v(RegAppReq_c / 4)(AppReqWrite_c)                               := r.ReqWrite;
        Map_v(RegAppReq_c / 4)(AppReqLenHi_c downto AppReqLenLo_c)          := r.ReqLen;
        Map_v(RegAppReq_c / 4)(AppReqSubHi_c downto AppReqSubLo_c)          := r.ReqSub;
        Map_v(RegAppReq_c / 4)(AppReqIndexHi_c downto AppReqIndexLo_c)      := r.ReqIndex;
        Map_v(RegAppReqHi_c / 4)                                            := r.ReqData(63 downto 32);
        Map_v(RegAppReqLo_c / 4)                                            := r.ReqData(31 downto 0);
        Map_v(RegAppRspHi_c / 4)                                            := r.RspData(63 downto 32);
        Map_v(RegAppRspLo_c / 4)                                            := r.RspData(31 downto 0);
        Map_v(RegAppRspLen_c / 4)(AppRspLenLenHi_c downto AppRspLenLenLo_c) := r.RspLen;
        Map_v(RegAppRspAbort_c / 4)                                         := r.RspAbort;

        Map_v(RegTimeCoarse_c / 4)                                                 := Time_Coarse;
        Map_v(RegTimeFine_c / 4)(TimeFineFractionHi_c downto TimeFineFractionLo_c) := r.FineSnap;

        if ErrInjRegs_g then
            Rw_v                                                                         := (others => '0');
            Rw_v(ErrinjSelectTarget_c)                                                   := r.InjTarget;
            Rw_v(ErrinjSelectWindow0Hi_c downto ErrinjSelectWindow0Lo_c)                 := std_logic_vector(r.InjWin0);
            Rw_v(ErrinjSelectWindow1Hi_c downto ErrinjSelectWindow1Lo_c)                 := std_logic_vector(r.InjWin1);
            Map_v(RegErrinjSelect_c / 4)                                                 := Rw_v;
            Map_v(RegErrinjMask0_c / 4)                                                  := r.InjMask0;
            Map_v(RegErrinjMask1_c / 4)                                                  := r.InjMask1;
            Rw_v                                                                         := (others => '0');
            Rw_v(ErrinjControlLinkTxDominantHi_c downto ErrinjControlLinkTxDominantLo_c) := r.TxDominant;
            Map_v(RegErrinjControl_c / 4)                                                := Rw_v;
        end if;

        -- A read answers in the next cycle; the reads of RPDOn_HI and TIME_COARSE take the second word
        -- (MB-PD-01, MB-TM-01)
        if RbRd = '1' then
            v.RdData  := Map_v(Idx_v);
            v.RdValid := '1';

            for n in 0 to NumRpdo_g - 1 loop
                if Idx_v = RegRpdo1Hi_c / 4 + 2 * n then
                    v.RpdoLo(n) := Rpdo_Data(64 * n + 31 downto 64 * n);
                end if;
            end loop;

            if Idx_v = RegTimeCoarse_c / 4 then
                v.FineSnap := Time_Fine;
            end if;
        end if;

        -- *** next state ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.RdValid    <= '0';
                r.Enable     <= toSl(AutoEnable_g);
                r.AppEnable  <= '0';
                r.Recover    <= '0';
                r.Reenable   <= (others => '0');
                r.Prescaler  <= std_logic_vector(to_unsigned(Prescaler_g, 10));
                r.Tseg1      <= std_logic_vector(to_unsigned(Tseg1_g, 5));
                r.Tseg2      <= std_logic_vector(to_unsigned(Tseg2_g, 4));
                r.Sjw        <= std_logic_vector(to_unsigned(Sjw_g, 3));
                r.Evt        <= (others => '0');
                r.EvtEn      <= (others => '0');
                r.PdoEvt     <= (others => '0');
                r.PdoEn      <= (others => '0');
                r.Err        <= (others => '0');
                r.ErrEn      <= (others => '0');
                r.LinkErr    <= (others => '0');
                r.LinkEn     <= (others => '0');
                r.Irq        <= '0';
                r.Cnt        <= (others => (others => (others => '0')));
                r.RpdoLo     <= (others => (others => '0'));
                r.TpdoNext   <= (others => (others => '0'));
                r.TpdoData   <= (others => (others => '0'));
                r.TpdoReq    <= (others => '0');
                r.Pending    <= '0';
                r.ReqWrite   <= '0';
                r.ReqIndex   <= (others => '0');
                r.ReqSub     <= (others => '0');
                r.ReqLen     <= (others => '0');
                r.ReqData    <= (others => '0');
                r.RspData    <= (others => '0');
                r.RspLen     <= (others => '0');
                r.RspAbort   <= (others => '0');
                r.RspValid   <= '0';
                r.FineSnap   <= (others => '0');
                r.TimeReq    <= '0';
                r.InjTarget  <= '0';
                r.InjWin0    <= (others => '0');
                r.InjWin1    <= (others => '0');
                r.InjMask0   <= (others => '0');
                r.InjMask1   <= (others => '0');
                r.InjPulse   <= '0';
                r.TxDominant <= (others => '0');
                r.StopFlip   <= (others => '0');
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    Irq           <= r.Irq;
    Ctrl_Enable   <= r.Enable;
    Ctrl_Recover  <= r.Recover;
    Ctrl_Reenable <= r.Reenable;
    Cfg_Prescaler <= r.Prescaler;
    Cfg_Tseg1     <= r.Tseg1;
    Cfg_Tseg2     <= r.Tseg2;
    Cfg_Sjw       <= r.Sjw;
    Tpdo_Req      <= r.TpdoReq;
    Time_Req      <= r.TimeReq;

    g_tpdo : for n in 0 to 3 generate
        Tpdo_Data(64 * n + 63 downto 64 * n) <= r.TpdoData(n);
    end generate;

    -- The application port: with the mailbox off it answers as its default values do (MB-AP-04)
    App_ReqReady <= not r.AppEnable or not r.Pending;
    App_RspValid <= not r.AppEnable or r.RspValid;
    App_RspData  <= r.RspData when r.AppEnable = '1' else (others => '0');
    App_RspLen   <= r.RspLen when r.AppEnable = '1' else (others => '0');
    App_RspAbort <= r.RspAbort when r.AppEnable = '1' else NoObject_c;

    -- Error injection: the masks in their windows during the cycle of INJECT (MB-EI-01)
    p_inj : process (all) is
        variable Od_v  : std_logic_vector(OdBits_c - 1 downto 0);
        variable Nmt_v : std_logic_vector(NmtBits_c - 1 downto 0);
        variable W_v   : natural range 0 to 31;
    begin
        Od_v  := (others => '0');
        Nmt_v := (others => '0');
        if r.InjPulse = '1' then

            for i in 0 to OdBits_c - 1 loop
                W_v     := i / 32;
                Od_v(i) := ((r.InjMask0(i mod 32) and toSl(r.InjWin0 = W_v)) or
                            (r.InjMask1(i mod 32) and toSl(r.InjWin1 = W_v))) and not r.InjTarget;
            end loop;

            for i in 0 to NmtBits_c - 1 loop
                Nmt_v(i) := ((r.InjMask0(i) and toSl(r.InjWin0 = 0)) or
                             (r.InjMask1(i) and toSl(r.InjWin1 = 0))) and r.InjTarget;
            end loop;

        end if;
        ErrInj_OdBitFlip  <= Od_v;
        ErrInj_NmtBitFlip <= Nmt_v;
        ErrInj_OdValid    <= r.InjPulse and not r.InjTarget;
        ErrInj_NmtValid   <= r.InjPulse and r.InjTarget;
    end process;

    ErrInj_LinkTxDominant <= r.TxDominant;
    ErrInj_LinkStopFlip   <= r.StopFlip;

    -----------------------------------------------------------------------------------------------
    -- AXI4-Lite slave
    -----------------------------------------------------------------------------------------------
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 9,
            AxiDataWidth_g => 32
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Rb_Addr           => RbAddr,
            Rb_Wr             => RbWr,
            Rb_ByteEna        => open,
            Rb_WrData         => RbWrData,
            Rb_Rd             => RbRd,
            Rb_RdData         => r.RdData,
            Rb_RdValid        => r.RdValid
        );

end architecture;
