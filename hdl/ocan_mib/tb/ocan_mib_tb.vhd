---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Direct testbench of ocan_mib: the AXI-Lite VVC of UVVM accesses the registers, the test drives the inputs from the
-- core, a model of the application port of ocan_od answers the mailbox, and a reference model of the register file
-- written from the specification predicts every output in every clock cycle and every read word.
--
-- Documentation: hdl/ocan_mib/docs/verification_plan.md

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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_mib_tb is
    generic (
        runner_cfg      : string;
        BusAccess_g     : string                                 := "Selective";
        MinimalSet_g    : boolean                                := false;
        TimePdos_g      : boolean                                := true;
        AutoRecover_g   : boolean                                := true;
        NumRpdo_g       : natural range 0 to 4                   := 4;
        NumTpdo_g       : natural range 0 to 4                   := 4;
        FineBits_g      : natural range 0 to 24                  := 24;
        SyncStages_g    : positive range 2 to 4                  := 2;
        DominantLimit_g : positive range 13 to 1023              := 32;
        ClkFrequency_g  : positive range 1000000 to integer'high := 100000000;
        AutoEnable_g    : boolean                                := true;
        Prescaler_g     : positive range 1 to 1023               := 4;
        Tseg1_g         : natural range 2 to 31                  := 18;
        Tseg2_g         : natural range 2 to 15                  := 6;
        Sjw_g           : natural range 1 to 4                   := 4;
        ErrInjRegs_g    : boolean                                := false;
        Seed_g          : positive                               := 7
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_mib_tb is

    constant Axi_c : natural := 0;

    constant Zero_c     : std_logic_vector(31 downto 0) := (others => '0');
    constant NoObject_c : std_logic_vector(31 downto 0) := x"06020000";

    subtype Word_t is std_logic_vector(31 downto 0);

    type Word_a is array (natural range <>) of Word_t;

    type Data_a is array (0 to 3) of std_logic_vector(63 downto 0);

    type Cnt_a is array (0 to 1, 0 to 5) of natural range 0 to 255;

    -- *** Reference model of the register file (written from the specification) ***
    type Model_r is record
        Enable     : std_logic;
        AppEnable  : std_logic;
        Recover    : std_logic;
        Reenable   : std_logic_vector(1 downto 0);
        Prescaler  : natural range 0 to 1023;
        Tseg1      : natural range 0 to 31;
        Tseg2      : natural range 0 to 15;
        Sjw        : natural range 0 to 7;
        Evt        : std_logic_vector(9 downto 0);
        EvtEn      : std_logic_vector(9 downto 0);
        PdoEvt     : std_logic_vector(23 downto 0);
        PdoEn      : std_logic_vector(23 downto 0);
        Err        : std_logic_vector(16 downto 0);
        ErrEn      : std_logic_vector(16 downto 0);
        LinkErr    : std_logic_vector(13 downto 0);
        LinkEn     : std_logic_vector(13 downto 0);
        Irq        : std_logic;
        Cnt        : Cnt_a;
        RpdoLo     : Word_a(0 to 3);
        TpdoNext   : Data_a;
        TpdoData   : Data_a;
        TpdoReq    : std_logic_vector(3 downto 0);
        Pending    : std_logic;
        ReqWrite   : std_logic;
        ReqIndex   : std_logic_vector(15 downto 0);
        ReqSub     : std_logic_vector(7 downto 0);
        ReqLen     : std_logic_vector(3 downto 0);
        ReqData    : std_logic_vector(63 downto 0);
        RspData    : std_logic_vector(63 downto 0);
        RspLen     : std_logic_vector(3 downto 0);
        RspAbort   : Word_t;
        RspValid   : std_logic;
        FineSnap   : std_logic_vector(23 downto 0);
        TimeReq    : std_logic;
        InjTarget  : std_logic;
        InjWin0    : natural range 0 to 31;
        InjWin1    : natural range 0 to 31;
        InjMask0   : Word_t;
        InjMask1   : Word_t;
        InjPulse   : std_logic;
        TxDominant : std_logic_vector(1 downto 0);
        StopFlip   : std_logic_vector(1 downto 0);
    end record;

    function b2sl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    function resetModel return Model_r is
        variable M_v : Model_r;
    begin
        M_v.Enable     := b2sl(AutoEnable_g);
        M_v.AppEnable  := '0';
        M_v.Recover    := '0';
        M_v.Reenable   := "00";
        M_v.Prescaler  := Prescaler_g;
        M_v.Tseg1      := Tseg1_g;
        M_v.Tseg2      := Tseg2_g;
        M_v.Sjw        := Sjw_g;
        M_v.Evt        := (others => '0');
        M_v.EvtEn      := (others => '0');
        M_v.PdoEvt     := (others => '0');
        M_v.PdoEn      := (others => '0');
        M_v.Err        := (others => '0');
        M_v.ErrEn      := (others => '0');
        M_v.LinkErr    := (others => '0');
        M_v.LinkEn     := (others => '0');
        M_v.Irq        := '0';
        M_v.Cnt        := (others => (others => 0));
        M_v.RpdoLo     := (others => Zero_c);
        M_v.TpdoNext   := (others => (others => '0'));
        M_v.TpdoData   := (others => (others => '0'));
        M_v.TpdoReq    := "0000";
        M_v.Pending    := '0';
        M_v.ReqWrite   := '0';
        M_v.ReqIndex   := (others => '0');
        M_v.ReqSub     := (others => '0');
        M_v.ReqLen     := (others => '0');
        M_v.ReqData    := (others => '0');
        M_v.RspData    := (others => '0');
        M_v.RspLen     := (others => '0');
        M_v.RspAbort   := Zero_c;
        M_v.RspValid   := '0';
        M_v.FineSnap   := (others => '0');
        M_v.TimeReq    := '0';
        M_v.InjTarget  := '0';
        M_v.InjWin0    := 0;
        M_v.InjWin1    := 0;
        M_v.InjMask0   := Zero_c;
        M_v.InjMask1   := Zero_c;
        M_v.InjPulse   := '0';
        M_v.TxDominant := "00";
        M_v.StopFlip   := "00";
        return M_v;
    end function;

    -- Harness ports
    signal Clk                   : std_logic;
    signal Rst                   : std_logic                      := '1';
    signal Irq                   : std_logic;
    signal Ctrl_Enable           : std_logic;
    signal Ctrl_Recover          : std_logic;
    signal Ctrl_Reenable         : std_logic_vector(1 downto 0);
    signal Cfg_Prescaler         : std_logic_vector(9 downto 0);
    signal Cfg_Tseg1             : std_logic_vector(4 downto 0);
    signal Cfg_Tseg2             : std_logic_vector(3 downto 0);
    signal Cfg_Sjw               : std_logic_vector(2 downto 0);
    signal Node_Id               : std_logic_vector(6 downto 0)   := (others => '0');
    signal Node_IdValid          : std_logic                      := '0';
    signal Sync_Valid            : std_logic                      := '0';
    signal Rpdo_Valid            : std_logic_vector(3 downto 0)   := (others => '0');
    signal Rpdo_Data             : std_logic_vector(255 downto 0) := (others => '0');
    signal Tpdo_Req              : std_logic_vector(3 downto 0);
    signal Tpdo_Data             : std_logic_vector(255 downto 0);
    signal Stat_TpdoBusy         : std_logic_vector(3 downto 0)   := (others => '0');
    signal Stat_PdoEnabled       : std_logic                      := '0';
    signal Evt_TpdoSent          : std_logic_vector(3 downto 0)   := (others => '0');
    signal Evt_TpdoAborted       : std_logic_vector(3 downto 0)   := (others => '0');
    signal Err_RpdoLength        : std_logic_vector(3 downto 0)   := (others => '0');
    signal Err_TpdoBusy          : std_logic_vector(3 downto 0)   := (others => '0');
    signal Err_TpdoTimeout       : std_logic_vector(3 downto 0)   := (others => '0');
    signal App_ReqValid          : std_logic                      := '0';
    signal App_ReqReady          : std_logic;
    signal App_ReqWrite          : std_logic                      := '0';
    signal App_ReqIndex          : std_logic_vector(15 downto 0)  := (others => '0');
    signal App_ReqSub            : std_logic_vector(7 downto 0)   := (others => '0');
    signal App_ReqData           : std_logic_vector(63 downto 0)  := (others => '0');
    signal App_ReqLen            : std_logic_vector(3 downto 0)   := (others => '0');
    signal App_RspValid          : std_logic;
    signal App_RspData           : std_logic_vector(63 downto 0);
    signal App_RspLen            : std_logic_vector(3 downto 0);
    signal App_RspAbort          : std_logic_vector(31 downto 0);
    signal Time_Coarse           : std_logic_vector(31 downto 0)  := (others => '0');
    signal Time_Fine             : std_logic_vector(23 downto 0)  := (others => '0');
    signal Time_Req              : std_logic;
    signal Stat_TimeSet          : std_logic                      := '0';
    signal Evt_TimeSet           : std_logic                      := '0';
    signal Evt_TimeSync          : std_logic                      := '0';
    signal Err_TimeTxBusy        : std_logic                      := '0';
    signal Err_TimeRxDrop        : std_logic                      := '0';
    signal Err_TimeTxTimeout     : std_logic                      := '0';
    signal Stat_NmtState         : std_logic_vector(1 downto 0)   := (others => '0');
    signal Evt_ResetApp          : std_logic                      := '0';
    signal Evt_ResetComm         : std_logic                      := '0';
    signal Err_NmtCs             : std_logic                      := '0';
    signal Err_NodeId            : std_logic                      := '0';
    signal Err_NmtTxTimeout      : std_logic                      := '0';
    signal Stat_ActiveBus        : std_logic                      := '0';
    signal Stat_Selecting        : std_logic                      := '0';
    signal Stat_Ctoggle          : std_logic_vector(7 downto 0)   := (others => '0');
    signal Stat_MasterHbState    : std_logic_vector(7 downto 0)   := (others => '0');
    signal Stat_MasterHbPresent  : std_logic_vector(1 downto 0)   := (others => '0');
    signal Evt_BdefaultUpdate    : std_logic                      := '0';
    signal Err_MasterHbMissing   : std_logic                      := '0';
    signal Err_ToggleEnd         : std_logic                      := '0';
    signal Err_MasterHbDlc       : std_logic                      := '0';
    signal Stat_ErrReg           : std_logic_vector(7 downto 0)   := (others => '0');
    signal Err_ParamCopy         : std_logic                      := '0';
    signal Err_AppTimeout        : std_logic                      := '0';
    signal Stat_CobIdMismatch    : std_logic_vector(11 downto 0)  := (others => '0');
    signal Err_Protocol          : std_logic                      := '0';
    signal Err_CobId             : std_logic                      := '0';
    signal Stat_SdoOpen          : std_logic                      := '0';
    signal Evt_SdoAbortTx        : std_logic                      := '0';
    signal Evt_SdoAbortRx        : std_logic                      := '0';
    signal Err_SdoRxDrop         : std_logic                      := '0';
    signal Err_SdoTxTimeout      : std_logic                      := '0';
    signal Err_SdoAccTimeout     : std_logic                      := '0';
    signal Stat_LinkTec          : std_logic_vector(17 downto 0)  := (others => '0');
    signal Stat_LinkRec          : std_logic_vector(15 downto 0)  := (others => '0');
    signal Stat_LinkState        : std_logic_vector(3 downto 0)   := (others => '0');
    signal Stat_LinkBusIdle      : std_logic_vector(1 downto 0)   := (others => '0');
    signal Stat_LinkDomTimeout   : std_logic_vector(1 downto 0)   := (others => '0');
    signal Stat_LinkSwitching    : std_logic                      := '0';
    signal Evt_LinkArbLost       : std_logic                      := '0';
    signal Err_LinkBit           : std_logic_vector(1 downto 0)   := (others => '0');
    signal Err_LinkStuff         : std_logic_vector(1 downto 0)   := (others => '0');
    signal Err_LinkCrc           : std_logic_vector(1 downto 0)   := (others => '0');
    signal Err_LinkForm          : std_logic_vector(1 downto 0)   := (others => '0');
    signal Err_LinkAck           : std_logic_vector(1 downto 0)   := (others => '0');
    signal Err_LinkDomTimeout    : std_logic_vector(1 downto 0)   := (others => '0');
    signal ErrInj_OdBitFlip      : std_logic_vector(557 downto 0);
    signal ErrInj_OdValid        : std_logic;
    signal ErrInj_NmtBitFlip     : std_logic_vector(13 downto 0);
    signal ErrInj_NmtValid       : std_logic;
    signal ErrInj_LinkTxDominant : std_logic_vector(1 downto 0);
    signal ErrInj_LinkStopFlip   : std_logic_vector(1 downto 0);
    signal Axi_ArAddr            : std_logic_vector(8 downto 0);
    signal Axi_ArValid           : std_logic;
    signal Axi_ArReady           : std_logic;
    signal Axi_AwAddr            : std_logic_vector(8 downto 0);
    signal Axi_AwValid           : std_logic;
    signal Axi_AwReady           : std_logic;
    signal Axi_WData             : std_logic_vector(31 downto 0);
    signal Axi_WStrb             : std_logic_vector(3 downto 0);
    signal Axi_WValid            : std_logic;
    signal Axi_WReady            : std_logic;
    signal Axi_BResp             : std_logic_vector(1 downto 0);
    signal Axi_BValid            : std_logic;
    signal Axi_BReady            : std_logic;
    signal Axi_RData             : std_logic_vector(31 downto 0);
    signal Axi_RResp             : std_logic_vector(1 downto 0);
    signal Axi_RValid            : std_logic;
    signal Axi_RReady            : std_logic;

    -- Model of the application port of ocan_od: a request per increment of AppGo, a time-out after AppTmo cycles
    signal AppGo     : natural                       := 0;
    signal AppDone   : natural                       := 0;
    signal AppTmo    : natural                       := 1000;
    signal AppWr     : std_logic                     := '0';
    signal AppIdx    : std_logic_vector(15 downto 0) := (others => '0');
    signal AppSub    : std_logic_vector(7 downto 0)  := (others => '0');
    signal AppDat    : std_logic_vector(63 downto 0) := (others => '0');
    signal AppLen    : std_logic_vector(3 downto 0)  := (others => '0');
    signal AppRspOk  : boolean                       := false;
    signal AppRspDat : std_logic_vector(63 downto 0) := (others => '0');
    signal AppRspLn  : std_logic_vector(3 downto 0)  := (others => '0');
    signal AppRspAb  : std_logic_vector(31 downto 0) := (others => '0');
    signal AppTmoCnt : natural                       := 0;

    -- Number of read words checked by the model (to confirm that the model ran)
    signal ModelReads : natural := 0;

    -- An output or a read word that differs from the model
    procedure mismatch (name : string) is
    begin
        alert(ERROR, "model: " & name & " differs from the reference model");
    end procedure;

    impure function word (m : Model_r; idx : natural) return Word_t is
        variable R_v : Word_t := (others => '0');
        variable N_v : natural;
    begin
        if idx = RegId_c / 4 then
            R_v := x"4F434101";
        elsif idx = RegGenerics_c / 4 then
            R_v(26 downto 24) := std_logic_vector(to_unsigned(SyncStages_g, 3));
            R_v(20 downto 16) := std_logic_vector(to_unsigned(FineBits_g, 5));
            R_v(14 downto 12) := std_logic_vector(to_unsigned(NumTpdo_g, 3));
            R_v(10 downto 8)  := std_logic_vector(to_unsigned(NumRpdo_g, 3));
            R_v(4)            := b2sl(ErrInjRegs_g);
            R_v(3)            := b2sl(AutoRecover_g);
            R_v(2)            := b2sl(TimePdos_g);
            R_v(1)            := b2sl(MinimalSet_g);
            R_v(0)            := b2sl(BusAccess_g = "Parallel");
        elsif idx = RegDominantLimit_c / 4 then
            R_v(9 downto 0) := std_logic_vector(to_unsigned(DominantLimit_g, 10));
        elsif idx = RegClkFrequency_c / 4 then
            R_v := std_logic_vector(to_unsigned(ClkFrequency_g, 32));
        elsif idx = RegControl_c / 4 then
            R_v(0) := m.Enable;
            R_v(1) := m.AppEnable;
        elsif idx = RegBitTiming_c / 4 then
            R_v(9 downto 0)   := std_logic_vector(to_unsigned(m.Prescaler, 10));
            R_v(20 downto 16) := std_logic_vector(to_unsigned(m.Tseg1, 5));
            R_v(27 downto 24) := std_logic_vector(to_unsigned(m.Tseg2, 4));
            R_v(30 downto 28) := std_logic_vector(to_unsigned(m.Sjw, 3));
        elsif idx = RegNode_c / 4 then
            R_v(1 downto 0)   := Stat_NmtState;
            R_v(14 downto 8)  := Node_Id;
            R_v(15)           := Node_IdValid;
            R_v(23 downto 16) := Stat_ErrReg;
            R_v(24)           := Stat_PdoEnabled;
            R_v(25)           := Stat_SdoOpen;
            R_v(26)           := Stat_TimeSet;
        elsif idx = RegRedundancy_c / 4 then
            R_v(0)            := Stat_ActiveBus;
            R_v(1)            := Stat_Selecting;
            R_v(2)            := Stat_LinkSwitching;
            R_v(5 downto 4)   := Stat_MasterHbPresent;
            R_v(15 downto 8)  := Stat_Ctoggle;
            R_v(23 downto 16) := Stat_MasterHbState;
        elsif idx = RegLinkA_c / 4 or idx = RegLinkB_c / 4 then
            N_v               := idx - RegLinkA_c / 4;
            R_v(8 downto 0)   := Stat_LinkTec(9 * N_v + 8 downto 9 * N_v);
            R_v(23 downto 16) := Stat_LinkRec(8 * N_v + 7 downto 8 * N_v);
            R_v(25 downto 24) := Stat_LinkState(2 * N_v + 1 downto 2 * N_v);
            R_v(28)           := Stat_LinkBusIdle(N_v);
            R_v(29)           := Stat_LinkDomTimeout(N_v);
        elsif idx = RegCobIdMismatch_c / 4 then
            R_v(11 downto 0) := Stat_CobIdMismatch;
        elsif idx = RegTpdoStatus_c / 4 then
            R_v(3 downto 0) := Stat_TpdoBusy;
        elsif idx = RegEvents_c / 4 then
            R_v(9 downto 0) := m.Evt;
        elsif idx = RegEventsIrqEn_c / 4 then
            R_v(9 downto 0) := m.EvtEn;
        elsif idx = RegPdoEvents_c / 4 then
            R_v(23 downto 0) := m.PdoEvt;
        elsif idx = RegPdoEventsIrqEn_c / 4 then
            R_v(23 downto 0) := m.PdoEn;
        elsif idx = RegErrors_c / 4 then
            R_v(16 downto 0) := m.Err;
        elsif idx = RegErrorsIrqEn_c / 4 then
            R_v(16 downto 0) := m.ErrEn;
        elsif idx = RegLinkErrors_c / 4 then
            R_v(13 downto 0) := m.LinkErr;
        elsif idx = RegLinkErrorsIrqEn_c / 4 then
            R_v(13 downto 0) := m.LinkEn;
        elsif idx = RegIrqStatus_c / 4 then
            R_v(0) := b2sl((m.Evt and m.EvtEn) /= (m.Evt'range => '0'));
            R_v(1) := b2sl((m.PdoEvt and m.PdoEn) /= (m.PdoEvt'range => '0'));
            R_v(2) := b2sl((m.Err and m.ErrEn) /= (m.Err'range => '0'));
            R_v(3) := b2sl((m.LinkErr and m.LinkEn) /= (m.LinkErr'range => '0'));
        elsif idx >= RegLinkACounts0_c / 4 and idx <= RegLinkBCounts1_c / 4 then
            N_v := (idx - RegLinkACounts0_c / 4) / 2;
            if (idx - RegLinkACounts0_c / 4) mod 2 = 0 then
                R_v := std_logic_vector(to_unsigned(m.Cnt(N_v, 3), 8)) &
                       std_logic_vector(to_unsigned(m.Cnt(N_v, 2), 8)) &
                       std_logic_vector(to_unsigned(m.Cnt(N_v, 1), 8)) &
                       std_logic_vector(to_unsigned(m.Cnt(N_v, 0), 8));
            else
                R_v(15 downto 0) := std_logic_vector(to_unsigned(m.Cnt(N_v, 5), 8)) &
                                    std_logic_vector(to_unsigned(m.Cnt(N_v, 4), 8));
            end if;
        elsif idx >= RegRpdo1Hi_c / 4 and idx <= RegRpdo4Lo_c / 4 then
            N_v := (idx - RegRpdo1Hi_c / 4) / 2;
            if N_v < NumRpdo_g then
                if (idx - RegRpdo1Hi_c / 4) mod 2 = 0 then
                    R_v := Rpdo_Data(64 * N_v + 63 downto 64 * N_v + 32);
                else
                    R_v := m.RpdoLo(N_v);
                end if;
            end if;
        elsif idx >= RegTpdo1Hi_c / 4 and idx <= RegTpdo4Lo_c / 4 then
            N_v := (idx - RegTpdo1Hi_c / 4) / 2;
            if N_v < NumTpdo_g then
                if (idx - RegTpdo1Hi_c / 4) mod 2 = 0 then
                    R_v := m.TpdoNext(N_v)(63 downto 32);
                else
                    R_v := m.TpdoNext(N_v)(31 downto 0);
                end if;
            end if;
        elsif idx = RegAppReq_c / 4 then
            R_v(31)           := m.Pending;
            R_v(28)           := m.ReqWrite;
            R_v(27 downto 24) := m.ReqLen;
            R_v(23 downto 16) := m.ReqSub;
            R_v(15 downto 0)  := m.ReqIndex;
        elsif idx = RegAppReqHi_c / 4 then
            R_v := m.ReqData(63 downto 32);
        elsif idx = RegAppReqLo_c / 4 then
            R_v := m.ReqData(31 downto 0);
        elsif idx = RegAppRspHi_c / 4 then
            R_v := m.RspData(63 downto 32);
        elsif idx = RegAppRspLo_c / 4 then
            R_v := m.RspData(31 downto 0);
        elsif idx = RegAppRspLen_c / 4 then
            R_v(3 downto 0) := m.RspLen;
        elsif idx = RegAppRspAbort_c / 4 then
            R_v := m.RspAbort;
        elsif idx = RegTimeCoarse_c / 4 then
            R_v := Time_Coarse;
        elsif idx = RegTimeFine_c / 4 then
            R_v(23 downto 0) := m.FineSnap;
        elsif ErrInjRegs_g and idx = RegErrinjSelect_c / 4 then
            R_v(8)            := m.InjTarget;
            R_v(4 downto 0)   := std_logic_vector(to_unsigned(m.InjWin0, 5));
            R_v(20 downto 16) := std_logic_vector(to_unsigned(m.InjWin1, 5));
        elsif ErrInjRegs_g and idx = RegErrinjMask0_c / 4 then
            R_v := m.InjMask0;
        elsif ErrInjRegs_g and idx = RegErrinjMask1_c / 4 then
            R_v := m.InjMask1;
        elsif ErrInjRegs_g and idx = RegErrinjControl_c / 4 then
            R_v(9 downto 8) := m.TxDominant;
        end if;
        return R_v;
    end function;

    function timingOk (w : Word_t) return boolean is
        variable T1_v : natural;
        variable T2_v : natural;
        variable S_v  : natural;
    begin
        T1_v                      := to_integer(unsigned(w(20 downto 16)));
        T2_v                      := to_integer(unsigned(w(27 downto 24)));
        S_v                       := to_integer(unsigned(w(30 downto 28)));
        return T1_v >= 2 and T1_v <= 31 and T2_v >= 2 and T2_v <= 15 and S_v >= 1 and S_v <= 4 and S_v <= T2_v;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- UVVM engine and harness
    -----------------------------------------------------------------------------------------------
    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    i_th : entity work.ocan_mib_th
        generic map (
            BusAccess_g     => BusAccess_g,
            MinimalSet_g    => MinimalSet_g,
            TimePdos_g      => TimePdos_g,
            AutoRecover_g   => AutoRecover_g,
            NumRpdo_g       => NumRpdo_g,
            NumTpdo_g       => NumTpdo_g,
            FineBits_g      => FineBits_g,
            SyncStages_g    => SyncStages_g,
            DominantLimit_g => DominantLimit_g,
            ClkFrequency_g  => ClkFrequency_g,
            AutoEnable_g    => AutoEnable_g,
            Prescaler_g     => Prescaler_g,
            Tseg1_g         => Tseg1_g,
            Tseg2_g         => Tseg2_g,
            Sjw_g           => Sjw_g,
            ErrInjRegs_g    => ErrInjRegs_g
        )
        port map (
            Clk                   => Clk,
            Rst                   => Rst,
            Irq                   => Irq,
            Ctrl_Enable           => Ctrl_Enable,
            Ctrl_Recover          => Ctrl_Recover,
            Ctrl_Reenable         => Ctrl_Reenable,
            Cfg_Prescaler         => Cfg_Prescaler,
            Cfg_Tseg1             => Cfg_Tseg1,
            Cfg_Tseg2             => Cfg_Tseg2,
            Cfg_Sjw               => Cfg_Sjw,
            Node_Id               => Node_Id,
            Node_IdValid          => Node_IdValid,
            Sync_Valid            => Sync_Valid,
            Rpdo_Valid            => Rpdo_Valid,
            Rpdo_Data             => Rpdo_Data,
            Tpdo_Req              => Tpdo_Req,
            Tpdo_Data             => Tpdo_Data,
            Stat_TpdoBusy         => Stat_TpdoBusy,
            Stat_PdoEnabled       => Stat_PdoEnabled,
            Evt_TpdoSent          => Evt_TpdoSent,
            Evt_TpdoAborted       => Evt_TpdoAborted,
            Err_RpdoLength        => Err_RpdoLength,
            Err_TpdoBusy          => Err_TpdoBusy,
            Err_TpdoTimeout       => Err_TpdoTimeout,
            App_ReqValid          => App_ReqValid,
            App_ReqReady          => App_ReqReady,
            App_ReqWrite          => App_ReqWrite,
            App_ReqIndex          => App_ReqIndex,
            App_ReqSub            => App_ReqSub,
            App_ReqData           => App_ReqData,
            App_ReqLen            => App_ReqLen,
            App_RspValid          => App_RspValid,
            App_RspData           => App_RspData,
            App_RspLen            => App_RspLen,
            App_RspAbort          => App_RspAbort,
            Time_Coarse           => Time_Coarse,
            Time_Fine             => Time_Fine,
            Time_Req              => Time_Req,
            Stat_TimeSet          => Stat_TimeSet,
            Evt_TimeSet           => Evt_TimeSet,
            Evt_TimeSync          => Evt_TimeSync,
            Err_TimeTxBusy        => Err_TimeTxBusy,
            Err_TimeRxDrop        => Err_TimeRxDrop,
            Err_TimeTxTimeout     => Err_TimeTxTimeout,
            Stat_NmtState         => Stat_NmtState,
            Evt_ResetApp          => Evt_ResetApp,
            Evt_ResetComm         => Evt_ResetComm,
            Err_NmtCs             => Err_NmtCs,
            Err_NodeId            => Err_NodeId,
            Err_NmtTxTimeout      => Err_NmtTxTimeout,
            Stat_ActiveBus        => Stat_ActiveBus,
            Stat_Selecting        => Stat_Selecting,
            Stat_Ctoggle          => Stat_Ctoggle,
            Stat_MasterHbState    => Stat_MasterHbState,
            Stat_MasterHbPresent  => Stat_MasterHbPresent,
            Evt_BdefaultUpdate    => Evt_BdefaultUpdate,
            Err_MasterHbMissing   => Err_MasterHbMissing,
            Err_ToggleEnd         => Err_ToggleEnd,
            Err_MasterHbDlc       => Err_MasterHbDlc,
            Stat_ErrReg           => Stat_ErrReg,
            Err_ParamCopy         => Err_ParamCopy,
            Err_AppTimeout        => Err_AppTimeout,
            Stat_CobIdMismatch    => Stat_CobIdMismatch,
            Err_Protocol          => Err_Protocol,
            Err_CobId             => Err_CobId,
            Stat_SdoOpen          => Stat_SdoOpen,
            Evt_SdoAbortTx        => Evt_SdoAbortTx,
            Evt_SdoAbortRx        => Evt_SdoAbortRx,
            Err_SdoRxDrop         => Err_SdoRxDrop,
            Err_SdoTxTimeout      => Err_SdoTxTimeout,
            Err_SdoAccTimeout     => Err_SdoAccTimeout,
            Stat_LinkTec          => Stat_LinkTec,
            Stat_LinkRec          => Stat_LinkRec,
            Stat_LinkState        => Stat_LinkState,
            Stat_LinkBusIdle      => Stat_LinkBusIdle,
            Stat_LinkDomTimeout   => Stat_LinkDomTimeout,
            Stat_LinkSwitching    => Stat_LinkSwitching,
            Evt_LinkArbLost       => Evt_LinkArbLost,
            Err_LinkBit           => Err_LinkBit,
            Err_LinkStuff         => Err_LinkStuff,
            Err_LinkCrc           => Err_LinkCrc,
            Err_LinkForm          => Err_LinkForm,
            Err_LinkAck           => Err_LinkAck,
            Err_LinkDomTimeout    => Err_LinkDomTimeout,
            ErrInj_OdBitFlip      => ErrInj_OdBitFlip,
            ErrInj_OdValid        => ErrInj_OdValid,
            ErrInj_NmtBitFlip     => ErrInj_NmtBitFlip,
            ErrInj_NmtValid       => ErrInj_NmtValid,
            ErrInj_LinkTxDominant => ErrInj_LinkTxDominant,
            ErrInj_LinkStopFlip   => ErrInj_LinkStopFlip,
            Axi_ArAddr            => Axi_ArAddr,
            Axi_ArValid           => Axi_ArValid,
            Axi_ArReady           => Axi_ArReady,
            Axi_AwAddr            => Axi_AwAddr,
            Axi_AwValid           => Axi_AwValid,
            Axi_AwReady           => Axi_AwReady,
            Axi_WData             => Axi_WData,
            Axi_WStrb             => Axi_WStrb,
            Axi_WValid            => Axi_WValid,
            Axi_WReady            => Axi_WReady,
            Axi_BResp             => Axi_BResp,
            Axi_BValid            => Axi_BValid,
            Axi_BReady            => Axi_BReady,
            Axi_RData             => Axi_RData,
            Axi_RResp             => Axi_RResp,
            Axi_RValid            => Axi_RValid,
            Axi_RReady            => Axi_RReady
        );

    -----------------------------------------------------------------------------------------------
    -- Model of the application port of ocan_od (OD-AP-01 to OD-AP-03): one request at a time, taken at
    -- App_ReqReady, answered at App_RspValid; a request or a wait longer than AppTmo cycles ends with
    -- Err_AppTimeout and a later response is ignored
    -----------------------------------------------------------------------------------------------
    p_app : process is
        variable Cnt_v : natural;
        variable Got_v : boolean;
    begin
        wait until rising_edge(Clk);
        if AppGo /= AppDone then
            App_ReqValid <= '1';
            App_ReqWrite <= AppWr;
            App_ReqIndex <= AppIdx;
            App_ReqSub   <= AppSub;
            App_ReqData  <= AppDat;
            App_ReqLen   <= AppLen;
            AppRspOk     <= false;
            Cnt_v        := 0;
            Got_v        := false;

            -- Request until taken
            loop
                wait until rising_edge(Clk);
                exit when App_ReqReady = '1';
                Cnt_v := Cnt_v + 1;
                exit when Cnt_v >= AppTmo;
            end loop;

            App_ReqValid <= '0';
            if Cnt_v < AppTmo then

                -- Wait for the response
                loop
                    wait until rising_edge(Clk);
                    if App_RspValid = '1' then
                        Got_v     := true;
                        AppRspDat <= App_RspData;
                        AppRspLn  <= App_RspLen;
                        AppRspAb  <= App_RspAbort;
                        exit;
                    end if;
                    Cnt_v := Cnt_v + 1;
                    exit when Cnt_v >= AppTmo;
                end loop;

            end if;
            if not Got_v then
                Err_AppTimeout <= '1';
                AppTmoCnt      <= AppTmoCnt + 1;
                wait until rising_edge(Clk);
                Err_AppTimeout <= '0';
            end if;
            AppRspOk <= Got_v;
            AppDone  <= AppDone + 1;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Reference model: the outputs of the cycle are compared with the model, then the model takes the cycle
    -----------------------------------------------------------------------------------------------
    p_model : process is
        variable M_v      : Model_r;
        variable N_v      : Model_r;
        variable WrAddr_v : natural range 0 to 511;
        variable WrData_v : Word_t;
        variable BPrev_v  : std_logic := '0';
        variable RdNow_v  : boolean   := false;
        variable RdAddr_v : natural range 0 to 511;
        variable ArAddr_v : natural range 0 to 511;
        variable Exp_v    : Word_a(0 to 15);
        variable Head_v   : natural   := 0;
        variable Tail_v   : natural   := 0;
        variable Wr_v     : boolean;
        variable Idx_v    : natural;
        variable W_v      : Word_t;
        variable Taken_v  : boolean;
        variable EvIn_v   : std_logic_vector(9 downto 0);
        variable PdoIn_v  : std_logic_vector(23 downto 0);
        variable ErrIn_v  : std_logic_vector(16 downto 0);
        variable LnkIn_v  : std_logic_vector(13 downto 0);
        variable CntIn_v  : std_logic_vector(5 downto 0);
        variable Od_v     : std_logic_vector(557 downto 0);
        variable Nmt_v    : std_logic_vector(13 downto 0);
        variable Reads_v  : natural   := 0;
        variable Armed_v  : boolean   := false;
    begin
        M_v := resetModel;

        loop
            wait until rising_edge(Clk);

            -- *** Outputs of the cycle against the model, from the first clock edge in reset on ***
            if Armed_v then
                if Ctrl_Enable /= M_v.Enable then
                    mismatch("Ctrl_Enable");
                end if;
                if Ctrl_Recover /= M_v.Recover then
                    mismatch("Ctrl_Recover");
                end if;
                if Ctrl_Reenable /= M_v.Reenable then
                    mismatch("Ctrl_Reenable");
                end if;
                if to_integer(unsigned(Cfg_Prescaler)) /= M_v.Prescaler or to_integer(unsigned(Cfg_Tseg1)) /= M_v.Tseg1 or
                   to_integer(unsigned(Cfg_Tseg2)) /= M_v.Tseg2 or to_integer(unsigned(Cfg_Sjw)) /= M_v.Sjw then
                    mismatch("Cfg_*");
                end if;
                if Tpdo_Req /= M_v.TpdoReq then
                    mismatch("Tpdo_Req");
                end if;

                for n in 0 to 3 loop
                    if Tpdo_Data(64 * n + 63 downto 64 * n) /= M_v.TpdoData(n) then
                        mismatch("Tpdo_Data of PDO " & integer'image(n + 1));
                    end if;
                end loop;

                if App_ReqReady /= (not M_v.AppEnable or not M_v.Pending) then
                    mismatch("App_ReqReady");
                end if;
                if App_RspValid /= (not M_v.AppEnable or M_v.RspValid) then
                    mismatch("App_RspValid");
                end if;
                if M_v.AppEnable = '1' then
                    if App_RspData /= M_v.RspData or App_RspLen /= M_v.RspLen or App_RspAbort /= M_v.RspAbort then
                        mismatch("App_Rsp*");
                    end if;
                elsif App_RspData /= (App_RspData'range => '0') or App_RspLen /= "0000" or App_RspAbort /= NoObject_c then
                    mismatch("App_Rsp* with the mailbox off");
                end if;
                if Time_Req /= M_v.TimeReq then
                    mismatch("Time_Req");
                end if;
                if Irq /= M_v.Irq then
                    mismatch("Irq");
                end if;
                Od_v  := (others => '0');
                Nmt_v := (others => '0');
                if M_v.InjPulse = '1' then

                    for i in 0 to 557 loop
                        if M_v.InjTarget = '0' and ((i / 32 = M_v.InjWin0 and M_v.InjMask0(i mod 32) = '1') or
                                                    (i / 32 = M_v.InjWin1 and M_v.InjMask1(i mod 32) = '1')) then
                            Od_v(i) := '1';
                        end if;
                    end loop;

                    for i in 0 to 13 loop
                        if M_v.InjTarget = '1' and ((M_v.InjWin0 = 0 and M_v.InjMask0(i) = '1') or
                                                    (M_v.InjWin1 = 0 and M_v.InjMask1(i) = '1')) then
                            Nmt_v(i) := '1';
                        end if;
                    end loop;

                end if;
                if ErrInj_OdBitFlip /= Od_v or ErrInj_NmtBitFlip /= Nmt_v or
                   ErrInj_OdValid /= (M_v.InjPulse and not M_v.InjTarget) or
                   ErrInj_NmtValid /= (M_v.InjPulse and M_v.InjTarget) then
                    mismatch("ErrInj_Od*, ErrInj_Nmt*");
                end if;
                if ErrInj_LinkTxDominant /= M_v.TxDominant or ErrInj_LinkStopFlip /= M_v.StopFlip then
                    mismatch("ErrInj_Link*");
                end if;
            end if;

            -- *** Read words: the word of the cycle after the read address, compared at the response ***
            if Axi_RValid = '1' and Axi_RReady = '1' then
                if Head_v = Tail_v then
                    alert(ERROR, "model: read response without a read");
                else
                    if Axi_RData /= Exp_v(Head_v mod 16) then
                        alert(ERROR, "model: read of 0x" & to_hstring(to_unsigned(RdAddr_v, 12)) & ": 0x" &
                                     to_hstring(Axi_RData) & ", expected 0x" & to_hstring(Exp_v(Head_v mod 16)));
                    end if;
                    if Axi_RResp /= "00" then
                        alert(ERROR, "model: read response not OKAY");
                    end if;
                    Head_v     := Head_v + 1;
                    Reads_v    := Reads_v + 1;
                    ModelReads <= Reads_v;
                end if;
            end if;
            if Axi_BValid = '1' and Axi_BReady = '1' and Axi_BResp /= "00" then
                alert(ERROR, "model: write response not OKAY");
            end if;

            -- *** The model takes the cycle ***
            N_v          := M_v;
            N_v.Recover  := '0';
            N_v.Reenable := "00";
            N_v.TpdoReq  := "0000";
            N_v.RspValid := '0';
            N_v.TimeReq  := '0';
            N_v.InjPulse := '0';
            N_v.StopFlip := "00";

            -- The write of the slave happens in the cycle in which BValid rises
            Wr_v  := Axi_BValid = '1' and BPrev_v = '0';
            Idx_v := WrAddr_v / 4;
            W_v   := WrData_v;

            ErrIn_v := (others => '0');
            if Wr_v then
                if Idx_v = RegControl_c / 4 then
                    N_v.Enable      := W_v(0);
                    N_v.AppEnable   := W_v(1);
                    N_v.Recover     := W_v(8);
                    N_v.Reenable(0) := W_v(9);
                    N_v.Reenable(1) := W_v(10);
                elsif Idx_v = RegBitTiming_c / 4 then
                    if M_v.Enable = '0' and timingOk(W_v) then
                        N_v.Prescaler := to_integer(unsigned(W_v(9 downto 0)));
                        N_v.Tseg1     := to_integer(unsigned(W_v(20 downto 16)));
                        N_v.Tseg2     := to_integer(unsigned(W_v(27 downto 24)));
                        N_v.Sjw       := to_integer(unsigned(W_v(30 downto 28)));
                    else
                        ErrIn_v(16) := '1';
                    end if;
                elsif Idx_v = RegEventsIrqEn_c / 4 then
                    N_v.EvtEn := W_v(9 downto 0);
                elsif Idx_v = RegPdoEventsIrqEn_c / 4 then
                    N_v.PdoEn := W_v(23 downto 0);
                elsif Idx_v = RegErrorsIrqEn_c / 4 then
                    N_v.ErrEn := W_v(16 downto 0);
                elsif Idx_v = RegLinkErrorsIrqEn_c / 4 then
                    N_v.LinkEn := W_v(13 downto 0);
                elsif Idx_v >= RegTpdo1Hi_c / 4 and Idx_v <= RegTpdo4Lo_c / 4 then
                    if (Idx_v - RegTpdo1Hi_c / 4) / 2 < NumTpdo_g then
                        if (Idx_v - RegTpdo1Hi_c / 4) mod 2 = 0 then
                            N_v.TpdoNext((Idx_v - RegTpdo1Hi_c / 4) / 2)(63 downto 32) := W_v;
                        else
                            N_v.TpdoNext((Idx_v - RegTpdo1Hi_c / 4) / 2)(31 downto 0) := W_v;
                        end if;
                    end if;
                elsif Idx_v = RegTpdoControl_c / 4 then

                    for n in 0 to NumTpdo_g - 1 loop
                        if W_v(n) = '1' or W_v(8 + n) = '1' then
                            N_v.TpdoData(n) := M_v.TpdoNext(n);
                        end if;
                        N_v.TpdoReq(n) := W_v(8 + n);
                    end loop;

                elsif Idx_v = RegAppRspHi_c / 4 then
                    N_v.RspData(63 downto 32) := W_v;
                elsif Idx_v = RegAppRspLo_c / 4 then
                    N_v.RspData(31 downto 0) := W_v;
                elsif Idx_v = RegAppRspLen_c / 4 then
                    N_v.RspLen := W_v(3 downto 0);
                elsif Idx_v = RegAppRspAbort_c / 4 then
                    N_v.RspAbort := W_v;
                elsif Idx_v = RegTimeControl_c / 4 then
                    N_v.TimeReq := W_v(0);
                elsif ErrInjRegs_g and Idx_v = RegErrinjSelect_c / 4 then
                    N_v.InjTarget := W_v(8);
                    N_v.InjWin0   := to_integer(unsigned(W_v(4 downto 0)));
                    N_v.InjWin1   := to_integer(unsigned(W_v(20 downto 16)));
                elsif ErrInjRegs_g and Idx_v = RegErrinjMask0_c / 4 then
                    N_v.InjMask0 := W_v;
                elsif ErrInjRegs_g and Idx_v = RegErrinjMask1_c / 4 then
                    N_v.InjMask1 := W_v;
                elsif ErrInjRegs_g and Idx_v = RegErrinjControl_c / 4 then
                    N_v.InjPulse   := W_v(0);
                    N_v.StopFlip   := W_v(5 downto 4);
                    N_v.TxDominant := W_v(9 downto 8);
                end if;
            end if;

            -- Mailbox
            Taken_v := M_v.AppEnable = '1' and M_v.Pending = '0' and App_ReqValid = '1';
            if Taken_v then
                N_v.Pending  := '1';
                N_v.ReqWrite := App_ReqWrite;
                N_v.ReqIndex := App_ReqIndex;
                N_v.ReqSub   := App_ReqSub;
                N_v.ReqLen   := App_ReqLen;
                N_v.ReqData  := App_ReqData;
            end if;
            if Wr_v and Idx_v = RegAppRspControl_c / 4 and W_v(0) = '1' and M_v.Pending = '1' then
                N_v.RspValid := '1';
                N_v.Pending  := '0';
            end if;
            if Err_AppTimeout = '1' or M_v.AppEnable = '0' then
                N_v.Pending := '0';
            end if;

            -- Flags
            EvIn_v               := b2sl(Taken_v) & Evt_LinkArbLost & Evt_SdoAbortRx & Evt_SdoAbortTx & Evt_TimeSync & Evt_TimeSet &
                                    Evt_BdefaultUpdate & Evt_ResetComm & Evt_ResetApp & Sync_Valid;
            PdoIn_v              := Err_TpdoTimeout & Err_TpdoBusy & Err_RpdoLength & Evt_TpdoAborted & Evt_TpdoSent & Rpdo_Valid;
            ErrIn_v(15 downto 0) := Err_TimeTxTimeout & Err_TimeRxDrop & Err_TimeTxBusy & Err_SdoAccTimeout &
                                    Err_SdoTxTimeout & Err_SdoRxDrop & Err_CobId & Err_Protocol & Err_AppTimeout &
                                    Err_ParamCopy & Err_MasterHbDlc & Err_ToggleEnd & Err_MasterHbMissing &
                                    Err_NmtTxTimeout & Err_NodeId & Err_NmtCs;
            LnkIn_v              := Err_LinkDomTimeout(1) & Err_LinkAck(1) & Err_LinkForm(1) & Err_LinkCrc(1) &
                                    Err_LinkStuff(1) & Err_LinkBit(1) & "00" & Err_LinkDomTimeout(0) & Err_LinkAck(0) &
                                    Err_LinkForm(0) & Err_LinkCrc(0) & Err_LinkStuff(0) & Err_LinkBit(0);
            if Wr_v and Idx_v = RegEvents_c / 4 then
                N_v.Evt := M_v.Evt and not W_v(9 downto 0);
            end if;
            if Wr_v and Idx_v = RegPdoEvents_c / 4 then
                N_v.PdoEvt := M_v.PdoEvt and not W_v(23 downto 0);
            end if;
            if Wr_v and Idx_v = RegErrors_c / 4 then
                N_v.Err := M_v.Err and not W_v(16 downto 0);
            end if;
            if Wr_v and Idx_v = RegLinkErrors_c / 4 then
                N_v.LinkErr := M_v.LinkErr and not W_v(13 downto 0);
            end if;
            N_v.Evt     := N_v.Evt or EvIn_v;
            N_v.PdoEvt  := N_v.PdoEvt or PdoIn_v;
            N_v.Err     := N_v.Err or ErrIn_v;
            N_v.LinkErr := N_v.LinkErr or LnkIn_v;
            N_v.Irq     := b2sl((N_v.Evt and N_v.EvtEn) /= (N_v.Evt'range => '0') or
                                (N_v.PdoEvt and N_v.PdoEn) /= (N_v.PdoEvt'range => '0') or
                                (N_v.Err and N_v.ErrEn) /= (N_v.Err'range => '0') or
                                (N_v.LinkErr and N_v.LinkEn) /= (N_v.LinkErr'range => '0'));

            -- Counters
            for c in 0 to 1 loop
                CntIn_v := LnkIn_v(8 * c + 5 downto 8 * c);

                for k in 0 to 5 loop
                    if Wr_v and ((k < 4 and Idx_v = RegLinkACounts0_c / 4 + 2 * c) or
                                 (k >= 4 and Idx_v = RegLinkACounts1_c / 4 + 2 * c)) then
                        if CntIn_v(k) = '1' then
                            N_v.Cnt(c, k) := 1;
                        else
                            N_v.Cnt(c, k) := 0;
                        end if;
                    elsif CntIn_v(k) = '1' and M_v.Cnt(c, k) < 255 then
                        N_v.Cnt(c, k) := M_v.Cnt(c, k) + 1;
                    end if;
                end loop;

            end loop;

            -- The read of the slave samples the cycle after the read address
            if RdNow_v then
                Exp_v(Tail_v mod 16) := word(M_v, RdAddr_v / 4);
                Tail_v               := Tail_v + 1;

                for n in 0 to NumRpdo_g - 1 loop
                    if RdAddr_v / 4 = RegRpdo1Hi_c / 4 + 2 * n then
                        N_v.RpdoLo(n) := Rpdo_Data(64 * n + 31 downto 64 * n);
                    end if;
                end loop;

                if RdAddr_v / 4 = RegTimeCoarse_c / 4 then
                    N_v.FineSnap := Time_Fine;
                end if;
            end if;
            RdNow_v := false;
            if Axi_ArValid = '1' and Axi_ArReady = '1' then
                RdNow_v  := true;
                RdAddr_v := to_integer(unsigned(Axi_ArAddr));
            end if;

            -- AXI capture
            if Axi_AwValid = '1' and Axi_AwReady = '1' then
                WrAddr_v := to_integer(unsigned(Axi_AwAddr));
            end if;
            if Axi_WValid = '1' and Axi_WReady = '1' then
                WrData_v := Axi_WData;
            end if;
            BPrev_v := Axi_BValid;

            if Rst = '1' then
                N_v     := resetModel;
                Head_v  := 0;
                Tail_v  := 0;
                Armed_v := true;
            end if;
            M_v := N_v;
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable D_v   : Word_t;
        variable E_v   : Word_t;
        variable N_v   : natural;
        variable Lim_v : natural;

        procedure syncClk (n : natural := 1) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

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

        -- A write without waiting; the bench waits for the cycle of the write itself
        procedure wrStart (addr : natural; data : Word_t) is
        begin
            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(addr, AxiAddrBits_c), data, "write");
        end procedure;

        procedure wrAwait is
        begin
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        -- Waits for the rising edge after which the slave writes (the edge that ends the cycle of the W handshake)
        procedure waitWriteCycle is
        begin

            loop
                wait until rising_edge(Clk);
                exit when Axi_WValid = '1' and Axi_WReady = '1';
            end loop;

        end procedure;

        -- Waits for the edge that ends the cycle in which the slave sees the write address while idle: the cycle of
        -- the write is the third cycle after that edge (address, data, write)
        procedure waitWriteAddress is
        begin

            loop
                wait until rising_edge(Clk);
                exit when Axi_AwValid = '1' and Axi_AwReady = '0';
            end loop;

        end procedure;

        procedure reset is
        begin
            Rst <= '1';
            syncClk(4);
            Rst <= '0';
            syncClk(2);
        end procedure;

        -- Drives the event inputs: EVENTS bits 8:0 (bit 9 is the mailbox), PDO_EVENTS, ERRORS bits 15:0 without
        -- bit 7 (Err_AppTimeout belongs to the application port model) and LINK_ERRORS
        procedure setEvents (
            ev  : std_logic_vector(9 downto 0);
            pdo : std_logic_vector(23 downto 0);
            er  : std_logic_vector(16 downto 0);
            lnk : std_logic_vector(13 downto 0)) is
        begin
            Sync_Valid          <= ev(0);
            Evt_ResetApp        <= ev(1);
            Evt_ResetComm       <= ev(2);
            Evt_BdefaultUpdate  <= ev(3);
            Evt_TimeSet         <= ev(4);
            Evt_TimeSync        <= ev(5);
            Evt_SdoAbortTx      <= ev(6);
            Evt_SdoAbortRx      <= ev(7);
            Evt_LinkArbLost     <= ev(8);
            Rpdo_Valid          <= pdo(3 downto 0);
            Evt_TpdoSent        <= pdo(7 downto 4);
            Evt_TpdoAborted     <= pdo(11 downto 8);
            Err_RpdoLength      <= pdo(15 downto 12);
            Err_TpdoBusy        <= pdo(19 downto 16);
            Err_TpdoTimeout     <= pdo(23 downto 20);
            Err_NmtCs           <= er(0);
            Err_NodeId          <= er(1);
            Err_NmtTxTimeout    <= er(2);
            Err_MasterHbMissing <= er(3);
            Err_ToggleEnd       <= er(4);
            Err_MasterHbDlc     <= er(5);
            Err_ParamCopy       <= er(6);
            Err_Protocol        <= er(8);
            Err_CobId           <= er(9);
            Err_SdoRxDrop       <= er(10);
            Err_SdoTxTimeout    <= er(11);
            Err_SdoAccTimeout   <= er(12);
            Err_TimeTxBusy      <= er(13);
            Err_TimeRxDrop      <= er(14);
            Err_TimeTxTimeout   <= er(15);

            for c in 0 to 1 loop
                Err_LinkBit(c)        <= lnk(8 * c);
                Err_LinkStuff(c)      <= lnk(8 * c + 1);
                Err_LinkCrc(c)        <= lnk(8 * c + 2);
                Err_LinkForm(c)       <= lnk(8 * c + 3);
                Err_LinkAck(c)        <= lnk(8 * c + 4);
                Err_LinkDomTimeout(c) <= lnk(8 * c + 5);
            end loop;

        end procedure;

        procedure quiet is
        begin
            setEvents((others => '0'), (others => '0'), (others => '0'), (others => '0'));
        end procedure;

        -- One-cycle pulse of the event inputs
        procedure pulse (
            ev  : std_logic_vector(9 downto 0);
            pdo : std_logic_vector(23 downto 0);
            er  : std_logic_vector(16 downto 0);
            lnk : std_logic_vector(13 downto 0)) is
        begin
            setEvents(ev, pdo, er, lnk);
            syncClk;
            quiet;
        end procedure;

        -- Random events, each input with probability 1 / p
        procedure randomEvents (p : positive) is
            variable Ev_v  : std_logic_vector(9 downto 0);
            variable Pdo_v : std_logic_vector(23 downto 0);
            variable Er_v  : std_logic_vector(16 downto 0);
            variable Lnk_v : std_logic_vector(13 downto 0);
        begin

            for i in Ev_v'range loop
                Ev_v(i) := b2sl(random(1, p) = 1);
            end loop;

            for i in Pdo_v'range loop
                Pdo_v(i) := b2sl(random(1, p) = 1);
            end loop;

            for i in Er_v'range loop
                Er_v(i) := b2sl(random(1, p) = 1);
            end loop;

            for i in Lnk_v'range loop
                Lnk_v(i) := b2sl(random(1, p) = 1);
            end loop;

            setEvents(Ev_v, Pdo_v, Er_v, Lnk_v);
        end procedure;

        -- Random status, PDO data and time
        procedure randomStatus is
        begin
            Node_Id              <= random(7);
            Node_IdValid         <= random(1)(0);
            Stat_NmtState        <= random(2);
            Stat_ErrReg          <= random(8);
            Stat_PdoEnabled      <= random(1)(0);
            Stat_SdoOpen         <= random(1)(0);
            Stat_TimeSet         <= random(1)(0);
            Stat_ActiveBus       <= random(1)(0);
            Stat_Selecting       <= random(1)(0);
            Stat_LinkSwitching   <= random(1)(0);
            Stat_MasterHbPresent <= random(2);
            Stat_Ctoggle         <= random(8);
            Stat_MasterHbState   <= random(8);
            Stat_LinkTec         <= random(18);
            Stat_LinkRec         <= random(16);
            Stat_LinkState       <= random(4);
            Stat_LinkBusIdle     <= random(2);
            Stat_LinkDomTimeout  <= random(2);
            Stat_CobIdMismatch   <= random(12);
            Stat_TpdoBusy        <= random(4);

            for n in 0 to 7 loop
                Rpdo_Data(32 * n + 31 downto 32 * n) <= random(32);
            end loop;

            Time_Coarse <= random(32);
            Time_Fine   <= random(24);
        end procedure;

        procedure appRequest (
            write : std_logic;
            index : natural;
            sub   : natural;
            data  : std_logic_vector(63 downto 0);
            len   : natural) is
        begin
            AppWr  <= write;
            AppIdx <= std_logic_vector(to_unsigned(index, 16));
            AppSub <= std_logic_vector(to_unsigned(sub, 8));
            AppDat <= data;
            AppLen <= std_logic_vector(to_unsigned(len, 4));
            AppGo  <= AppGo + 1;
            syncClk;
        end procedure;

        procedure appWait is
        begin

            while AppDone /= AppGo loop
                syncClk;
            end loop;

        end procedure;

        -- A word whose bits depend on the address, so that no two registers carry the same test data. The result
        -- is returned through a local variable: QuestaSim can give two calls of one function in one procedure call
        -- the same value when a function returns the result of another function directly
        function pattern (addr : natural; k : natural) return Word_t is
            variable W_v : unsigned(31 downto 0);
            variable R_v : Word_t;
        begin
            W_v := to_unsigned((addr * 40503 + k * 9973 + 12345) mod 65536, 16) &
                   to_unsigned((addr * 9973 + k * 40503 + 54321) mod 65536, 16);
            R_v := std_logic_vector(W_v) xor x"A5C3_3C5A";
            return R_v;
        end function;

        -- Expected value of a read-only constant or zero word, as the register map defines it
        variable Gen_v : Word_t;
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        shared_axilite_vvc_config(Axi_c).bfm_config.max_wait_cycles := 1000;
        randomize(Seed_g, Seed_g + 17, "seeds of the test");
        quiet;
        reset;

        while test_suite loop

            -- *** TC-MB-01: identification, unused addresses, read-only registers ***
            if run("test_registers") then
                log(ID_LOG_HDR, "ID, GENERICS, DOMINANT_LIMIT, CLK_FREQUENCY; unused addresses; writes to read-only registers");
                chk(RegId_c, RegMapId_c, "ID");
                check_value(RegMapId_c, std_logic_vector'(x"4F434101"), ERROR, "ID of the register map package");
                Gen_v               := (others => '0');
                Gen_v(26 downto 24) := std_logic_vector(to_unsigned(SyncStages_g, 3));
                Gen_v(20 downto 16) := std_logic_vector(to_unsigned(FineBits_g, 5));
                Gen_v(14 downto 12) := std_logic_vector(to_unsigned(NumTpdo_g, 3));
                Gen_v(10 downto 8)  := std_logic_vector(to_unsigned(NumRpdo_g, 3));
                Gen_v(4)            := b2sl(ErrInjRegs_g);
                Gen_v(3)            := b2sl(AutoRecover_g);
                Gen_v(2)            := b2sl(TimePdos_g);
                Gen_v(1)            := b2sl(MinimalSet_g);
                Gen_v(0)            := b2sl(BusAccess_g = "Parallel");
                chk(RegGenerics_c, Gen_v, "GENERICS");
                chk(RegDominantLimit_c, std_logic_vector(to_unsigned(DominantLimit_g, 32)), "DOMINANT_LIMIT");
                chk(RegClkFrequency_c, std_logic_vector(to_unsigned(ClkFrequency_g, 32)), "CLK_FREQUENCY");

                -- Every address of the 9-bit space is read; the model knows the word of every register
                for a in 0 to 127 loop
                    rd(4 * a, D_v);
                end loop;

                -- Writes of patterns to the constant and status registers and to every unused address change nothing
                for a in 0 to 127 loop
                    if a = RegId_c / 4 or a = RegGenerics_c / 4 or a = RegDominantLimit_c / 4 or
                       a = RegClkFrequency_c / 4 or (a >= RegNode_c / 4 and a <= RegTpdoStatus_c / 4) or
                       a = RegIrqStatus_c / 4 or (a >= RegRpdo1Hi_c / 4 and a <= RegRpdo4Lo_c / 4) or
                       (a >= RegAppReq_c / 4 and a <= RegAppReqLo_c / 4) or a = RegTimeCoarse_c / 4 or
                       a = RegTimeFine_c / 4 or (a > RegDominantLimit_c / 4 + 3 and a < RegNode_c / 4) or
                       (a > RegTpdoStatus_c / 4 and a < RegEvents_c / 4) or (a > RegIrqStatus_c / 4 and a < RegLinkACounts0_c / 4) or
                       (a > RegLinkBCounts1_c / 4 and a < RegRpdo1Hi_c / 4) or
                       (a > RegTpdoControl_c / 4 and a < RegAppReq_c / 4) or
                       (a > RegTimeControl_c / 4 and a < RegErrinjSelect_c / 4) or a > RegErrinjControl_c / 4 then
                        wr(4 * a, pattern(4 * a, 1));
                    end if;
                end loop;

                for a in 0 to 127 loop
                    rd(4 * a, D_v);
                end loop;

                chk(RegId_c, RegMapId_c, "ID after the writes");
                chk(RegGenerics_c, Gen_v, "GENERICS after the writes");
                -- Byte strobes are ignored: a write with no strobe set writes the whole word
                wr(RegEventsIrqEn_c, x"00000000");
                axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(RegEventsIrqEn_c, AxiAddrBits_c), x"000003FF", std_logic_vector'("0000"),
                              "write with byte strobes 0000");
                wrAwait;
                chk(RegEventsIrqEn_c, x"000003FF", "EVENTS_IRQ_EN written with the byte strobes 0000");

            -- *** TC-MB-02: reset values ***
            elsif run("test_reset_values") then
                log(ID_LOG_HDR, "Reset values of every register and of the outputs");
                check_value(Ctrl_Enable, b2sl(AutoEnable_g), ERROR, "Ctrl_Enable after the reset");
                check_value(to_integer(unsigned(Cfg_Prescaler)), Prescaler_g, ERROR, "Cfg_Prescaler after the reset");
                check_value(to_integer(unsigned(Cfg_Tseg1)), Tseg1_g, ERROR, "Cfg_Tseg1 after the reset");
                check_value(to_integer(unsigned(Cfg_Tseg2)), Tseg2_g, ERROR, "Cfg_Tseg2 after the reset");
                check_value(to_integer(unsigned(Cfg_Sjw)), Sjw_g, ERROR, "Cfg_Sjw after the reset");
                check_value(App_ReqReady, '1', ERROR, "App_ReqReady after the reset");
                check_value(App_RspValid, '1', ERROR, "App_RspValid after the reset (mailbox off)");
                check_value(App_RspAbort, NoObject_c, ERROR, "App_RspAbort after the reset");

                for a in 0 to 127 loop
                    rd(4 * a, D_v);
                end loop;

                E_v               := (others => '0');
                E_v(0)            := b2sl(AutoEnable_g);
                chk(RegControl_c, E_v, "CONTROL after the reset");
                E_v               := (others => '0');
                E_v(9 downto 0)   := std_logic_vector(to_unsigned(Prescaler_g, 10));
                E_v(20 downto 16) := std_logic_vector(to_unsigned(Tseg1_g, 5));
                E_v(27 downto 24) := std_logic_vector(to_unsigned(Tseg2_g, 4));
                E_v(30 downto 28) := std_logic_vector(to_unsigned(Sjw_g, 3));
                chk(RegBitTiming_c, E_v, "BIT_TIMING after the reset");

                for a in RegEvents_c / 4 to RegErrinjControl_c / 4 loop
                    if not (a >= RegRpdo1Hi_c / 4 and a <= RegRpdo4Lo_c / 4) and a /= RegTimeCoarse_c / 4 then
                        chk(4 * a, Zero_c, "register at 0x" & to_hstring(to_unsigned(4 * a, 12)) & " after the reset");
                    end if;
                end loop;

            -- *** TC-MB-03: control ***
            elsif run("test_control") then
                log(ID_LOG_HDR, "CONTROL: ENABLE and APP_ENABLE read back, RECOVER and REENABLE pulse for one cycle");

                for i in 0 to 3 loop
                    wr(RegControl_c, std_logic_vector(to_unsigned(i, 32)));
                    chk(RegControl_c, std_logic_vector(to_unsigned(i, 32)), "CONTROL read back");
                    check_value(Ctrl_Enable, b2sl(i mod 2 = 1), ERROR, "Ctrl_Enable");
                end loop;

                for b in 8 to 10 loop
                    wrStart(RegControl_c, std_logic_vector(to_unsigned(2 ** b + 1, 32)));
                    waitWriteCycle;
                    syncClk(2);

                    -- The pulse is in the cycle after the write
                    case b is
                        when 8 => check_value(Ctrl_Recover, '1', ERROR, "Ctrl_Recover pulse");
                        when 9 => check_value(Ctrl_Reenable, "01", ERROR, "Ctrl_Reenable(0) pulse");
                        when others => check_value(Ctrl_Reenable, "10", ERROR, "Ctrl_Reenable(1) pulse");
                    end case;

                    syncClk;
                    check_value(Ctrl_Recover, '0', ERROR, "Ctrl_Recover after one cycle");
                    check_value(Ctrl_Reenable, "00", ERROR, "Ctrl_Reenable after one cycle");
                    wrAwait;
                    chk(RegControl_c, x"00000001", "CONTROL: the commands read zero");
                end loop;

                -- Writes to the other bits change nothing
                wr(RegControl_c, x"FFFFF8FC");
                chk(RegControl_c, x"00000000", "CONTROL with the undefined bits set");

            -- *** TC-MB-04: bit timing ***
            elsif run("test_bit_timing") then
                log(ID_LOG_HDR, "BIT_TIMING: writes while disabled and in range; refused writes set CFG_REFUSED");
                wr(RegControl_c, x"00000000");

                -- Values in range: the bounds of every field
                for t1 in 2 to 31 loop

                    for t2 in 2 to 15 loop
                        if (t1 = 2 or t1 = 31 or t1 = 17) and (t2 = 2 or t2 = 15 or t2 = 3) then

                            for s in 1 to 4 loop
                                if s <= t2 then
                                    E_v               := (others => '0');
                                    E_v(9 downto 0)   := std_logic_vector(to_unsigned((t1 * 37 + t2 * 5 + s) mod 1024, 10));
                                    E_v(20 downto 16) := std_logic_vector(to_unsigned(t1, 5));
                                    E_v(27 downto 24) := std_logic_vector(to_unsigned(t2, 4));
                                    E_v(30 downto 28) := std_logic_vector(to_unsigned(s, 3));
                                    wr(RegBitTiming_c, E_v or x"80E0FC00");
                                    chk(RegBitTiming_c, E_v, "BIT_TIMING in range");
                                end if;
                            end loop;

                        end if;
                    end loop;

                end loop;

                wr(RegBitTiming_c, x"40000000" or x"0F000000" or x"001F0000" or x"000003FF");
                chk(RegBitTiming_c, x"4F1F03FF", "BIT_TIMING: prescaler 1023, Tseg1 31, Tseg2 15, Sjw 4");
                wr(RegBitTiming_c, x"10020000" or x"02000000");
                chk(RegBitTiming_c, x"12020000", "BIT_TIMING: prescaler 0, Tseg1 2, Tseg2 2, Sjw 1");
                chk(RegErrors_c, Zero_c, "no CFG_REFUSED for values in range");

                -- Values out of range: Tseg1 0 and 1, Tseg2 0 and 1, Sjw 0, 5 to 7 and above Tseg2
                for k in 0 to 8 loop

                    case k is
                        when 0 => E_v := x"40030000" or x"06000000";  -- Tseg1 3, Tseg2 6, Sjw 4 (valid base)
                        when 1 => E_v := x"40000000" or x"06000000";  -- Tseg1 0
                        when 2 => E_v := x"40010000" or x"06000000";  -- Tseg1 1
                        when 3 => E_v := x"10030000";                 -- Tseg2 0
                        when 4 => E_v := x"10030000" or x"01000000";  -- Tseg2 1
                        when 5 => E_v := x"00030000" or x"06000000";  -- Sjw 0
                        when 6 => E_v := x"50030000" or x"0F000000";  -- Sjw 5
                        when 7 => E_v := x"70030000" or x"0F000000";  -- Sjw 7
                        when others => E_v := x"30030000" or x"02000000";  -- Sjw 3 above Tseg2 2
                    end case;

                    wr(RegBitTiming_c, E_v);
                    if k = 0 then
                        chk(RegBitTiming_c, E_v, "BIT_TIMING: the valid base value");
                    else
                        chk(RegBitTiming_c, x"46030000", "BIT_TIMING unchanged after a refused value");
                        D_v                     := (others => '0');
                        D_v(ErrorsCfgRefused_c) := '1';
                        chk(RegErrors_c, D_v, "CFG_REFUSED after a refused value");
                        wr(RegErrors_c, D_v);
                        chk(RegErrors_c, Zero_c, "CFG_REFUSED cleared");
                    end if;
                end loop;

                -- A valid value while enabled is refused
                wr(RegControl_c, x"00000001");
                wr(RegBitTiming_c, x"20050000" or x"04000000" or x"00000011");
                chk(RegBitTiming_c, x"46030000", "BIT_TIMING unchanged while enabled");
                chk(RegErrors_c, x"00010000", "CFG_REFUSED after a write while enabled");

            -- *** TC-MB-05: status ***
            elsif run("test_status") then
                log(ID_LOG_HDR, "NODE, REDUNDANCY, LINK_A, LINK_B, COB_ID_MISMATCH, TPDO_STATUS with random inputs");

                for i in 1 to 200 loop
                    randomStatus;
                    syncClk;

                    for a in RegNode_c / 4 to RegTpdoStatus_c / 4 loop
                        rd(4 * a, D_v);
                    end loop;

                end loop;

                -- A status that changes in every cycle: the read takes the value of one cycle (the model checks it)
                for i in 1 to 40 loop
                    wrStart(RegControl_c, x"0000000" & "000" & b2sl(AutoEnable_g));
                    axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(RegLinkA_c + 4 * (i mod 2), AxiAddrBits_c), "read");

                    for k in 1 to 20 loop
                        randomStatus;
                        syncClk;
                    end loop;

                    wrAwait;
                end loop;

            -- *** TC-MB-06: flags ***
            elsif run("test_flags") then
                log(ID_LOG_HDR, "Every flag is set by its input and cleared by a write of one; an event in the cycle of the clear keeps it");

                -- One flag at a time
                for i in 0 to 8 loop
                    D_v    := (others => '0');
                    D_v(i) := '1';
                    pulse(D_v(9 downto 0), (others => '0'), (others => '0'), (others => '0'));
                    chk(RegEvents_c, D_v, "EVENTS bit " & integer'image(i));
                    wr(RegEvents_c, not D_v);
                    chk(RegEvents_c, D_v, "EVENTS: a write of zero does not clear");
                    wr(RegEvents_c, D_v);
                    chk(RegEvents_c, Zero_c, "EVENTS cleared");
                end loop;

                for i in 0 to 23 loop
                    D_v    := (others => '0');
                    D_v(i) := '1';
                    pulse((others => '0'), D_v(23 downto 0), (others => '0'), (others => '0'));
                    chk(RegPdoEvents_c, D_v, "PDO_EVENTS bit " & integer'image(i));
                    wr(RegPdoEvents_c, not D_v);
                    chk(RegPdoEvents_c, D_v, "PDO_EVENTS: a write of zero does not clear");
                    wr(RegPdoEvents_c, D_v);
                    chk(RegPdoEvents_c, Zero_c, "PDO_EVENTS cleared");
                end loop;

                for i in 0 to 15 loop
                    if i /= ErrorsAppTimeout_c then
                        D_v    := (others => '0');
                        D_v(i) := '1';
                        pulse((others => '0'), (others => '0'), D_v(16 downto 0), (others => '0'));
                        chk(RegErrors_c, D_v, "ERRORS bit " & integer'image(i));
                        wr(RegErrors_c, not D_v);
                        chk(RegErrors_c, D_v, "ERRORS: a write of zero does not clear");
                        wr(RegErrors_c, D_v);
                        chk(RegErrors_c, Zero_c, "ERRORS cleared");
                    end if;
                end loop;

                for i in 0 to 13 loop
                    if i mod 8 < 6 then
                        D_v    := (others => '0');
                        D_v(i) := '1';
                        pulse((others => '0'), (others => '0'), (others => '0'), D_v(13 downto 0));
                        chk(RegLinkErrors_c, D_v, "LINK_ERRORS bit " & integer'image(i));
                        wr(RegLinkErrors_c, not D_v);
                        chk(RegLinkErrors_c, D_v, "LINK_ERRORS: a write of zero does not clear");
                        wr(RegLinkErrors_c, D_v);
                        chk(RegLinkErrors_c, Zero_c, "LINK_ERRORS cleared");
                    end if;
                end loop;

                -- An event two cycles before to two cycles after the cycle of the clearing write
                for d in -2 to 2 loop
                    pulse("0000000001", (0 => '1', others => '0'), (0 => '1', others => '0'), (0 => '1', others => '0'));

                    for r in 0 to 3 loop

                        case r is
                            when 0 => N_v := RegEvents_c;
                            when 1 => N_v := RegPdoEvents_c;
                            when 2 => N_v := RegErrors_c;
                            when others => N_v := RegLinkErrors_c;
                        end case;

                        wrStart(N_v, x"00000001");
                        -- the event d cycles after the cycle of the write (d < 0: before it)
                        waitWriteAddress;
                        syncClk(d + 2);
                        if r = 0 then
                            pulse("0000000001", (others => '0'), (others => '0'), (others => '0'));
                        elsif r = 1 then
                            pulse((others => '0'), (0 => '1', others => '0'), (others => '0'), (others => '0'));
                        elsif r = 2 then
                            pulse((others => '0'), (others => '0'), (0 => '1', others => '0'), (others => '0'));
                        else
                            pulse((others => '0'), (others => '0'), (others => '0'), (0 => '1', others => '0'));
                        end if;
                        wrAwait;
                        syncClk(4);
                        rd(N_v, D_v);
                        wr(N_v, x"00000001");
                    end loop;

                end loop;

                -- Clearing a flag in the cycle of the write: offset 0 relative to the write cycle
                pulse("0000000001", (others => '0'), (others => '0'), (others => '0'));
                wrStart(RegEvents_c, x"00000001");

                loop
                    wait until rising_edge(Clk);
                    exit when Axi_WValid = '1' and Axi_WReady = '1';
                end loop;

                -- The next cycle is the cycle of the write: the event of that cycle keeps the flag set
                pulse("0000000001", (others => '0'), (others => '0'), (others => '0'));
                wrAwait;
                chk(RegEvents_c, x"00000001", "SYNC flag set by an event in the cycle of its clearing write");

            -- *** TC-MB-07: interrupt ***
            elsif run("test_irq") then
                log(ID_LOG_HDR, "Interrupt enables, Irq and IRQ_STATUS");

                for r in 0 to 3 loop

                    case r is
                        when 0 => N_v := 10;
                        when 1 => N_v := 24;
                        when 2 => N_v := 17;
                        when others => N_v := 14;
                    end case;

                    for i in 0 to N_v - 1 loop
                        if not (r = 0 and i = 9) and not (r = 2 and (i = ErrorsAppTimeout_c or i = 16)) and
                           not (r = 3 and i mod 8 >= 6) then
                            D_v    := (others => '0');
                            D_v(i) := '1';

                            -- The flag without its enable: no interrupt
                            case r is
                                when 0 => pulse(D_v(9 downto 0), (others => '0'), (others => '0'), (others => '0'));
                                when 1 => pulse((others => '0'), D_v(23 downto 0), (others => '0'), (others => '0'));
                                when 2 => pulse((others => '0'), (others => '0'), D_v(16 downto 0), (others => '0'));
                                when others => pulse((others => '0'), (others => '0'), (others => '0'), D_v(13 downto 0));
                            end case;

                            syncClk;
                            check_value(Irq, '0', ERROR, "Irq without the enable");
                            -- Every other enable set: still no interrupt
                            wr(RegEventsIrqEn_c + 8 * r, not D_v);
                            check_value(Irq, '0', ERROR, "Irq with the other enables");
                            chk(RegIrqStatus_c, Zero_c, "IRQ_STATUS with the other enables");
                            -- Its enable set: interrupt
                            wr(RegEventsIrqEn_c + 8 * r, D_v);
                            check_value(Irq, '1', ERROR, "Irq with the enable");
                            E_v    := (others => '0');
                            E_v(r) := '1';
                            chk(RegIrqStatus_c, E_v, "IRQ_STATUS with the enable");
                            -- The flag cleared: no interrupt
                            wr(RegEvents_c + 8 * r, D_v);
                            check_value(Irq, '0', ERROR, "Irq after the clear");
                            wr(RegEventsIrqEn_c + 8 * r, Zero_c);
                        end if;
                    end loop;

                end loop;

                -- The refused bit timing and the mailbox request raise the interrupt as well
                wr(RegErrorsIrqEn_c, x"00010000");
                wr(RegControl_c, x"00000001");
                wr(RegBitTiming_c, x"46030000");
                check_value(Irq, '1', ERROR, "Irq by CFG_REFUSED");
                wr(RegErrors_c, x"00010000");
                wr(RegEventsIrqEn_c, x"00000200");
                wr(RegControl_c, x"00000003");
                appRequest('0', 16#2100#, 1, (others => '0'), 0);
                syncClk(4);
                check_value(Irq, '1', ERROR, "Irq by APP_REQUEST");
                wr(RegAppRspControl_c, x"00000001");
                appWait;
                wr(RegEvents_c, x"00000200");
                check_value(Irq, '0', ERROR, "Irq after the clear of APP_REQUEST");
                -- Several flags: the interrupt stays until the last enabled flag is cleared
                wr(RegEventsIrqEn_c, x"000003FF");
                wr(RegLinkErrorsIrqEn_c, x"00003F3F");
                pulse("0000000011", (others => '0'), (others => '0'), (8 => '1', others => '0'));
                wr(RegEvents_c, x"00000001");
                check_value(Irq, '1', ERROR, "Irq with two flags left");
                wr(RegEvents_c, x"00000002");
                check_value(Irq, '1', ERROR, "Irq with one flag left");
                wr(RegLinkErrors_c, x"00000100");
                check_value(Irq, '0', ERROR, "Irq with no flag left");

            -- *** TC-MB-08: counters ***
            elsif run("test_counters") then
                log(ID_LOG_HDR, "Error counters: count, saturate at 255, clear by write; an event of the clearing cycle counts");

                for c in 0 to 1 loop

                    for k in 0 to 5 loop

                        -- k + 1 + 3 c errors of this kind
                        for e in 1 to k + 1 + 3 * c loop
                            D_v            := (others => '0');
                            D_v(8 * c + k) := '1';
                            pulse((others => '0'), (others => '0'), (others => '0'), D_v(13 downto 0));
                            syncClk(e mod 3);
                        end loop;

                    end loop;

                end loop;

                for a in RegLinkACounts0_c / 4 to RegLinkBCounts1_c / 4 loop
                    rd(4 * a, D_v);
                    rd(4 * a, E_v);
                    check_value(D_v, E_v, ERROR, "a read does not clear the counters");
                end loop;

                chk(RegLinkACounts0_c, x"04030201", "LINK_A_COUNTS0");
                chk(RegLinkACounts1_c, x"00000605", "LINK_A_COUNTS1");
                chk(RegLinkBCounts0_c, x"07060504", "LINK_B_COUNTS0");
                chk(RegLinkBCounts1_c, x"00000908", "LINK_B_COUNTS1");
                -- A write clears the counters of its register only
                wr(RegLinkACounts1_c, x"FFFFFFFF");
                chk(RegLinkACounts1_c, Zero_c, "LINK_A_COUNTS1 cleared");
                chk(RegLinkACounts0_c, x"04030201", "LINK_A_COUNTS0 kept");
                wr(RegLinkBCounts0_c, x"00000000");
                chk(RegLinkBCounts0_c, Zero_c, "LINK_B_COUNTS0 cleared by a write of zero");
                chk(RegLinkBCounts1_c, x"00000908", "LINK_B_COUNTS1 kept");
                -- Saturation: 300 events in back-to-back cycles on every input
                setEvents((others => '0'), (others => '0'), (others => '0'), "11111100111111");
                syncClk(300);
                quiet;

                for a in RegLinkACounts0_c / 4 to RegLinkBCounts1_c / 4 loop
                    rd(4 * a, D_v);
                end loop;

                chk(RegLinkACounts0_c, x"FFFFFFFF", "LINK_A_COUNTS0 saturated");
                chk(RegLinkBCounts1_c, x"0000FFFF", "LINK_B_COUNTS1 saturated");
                -- Events in every cycle around the clearing write: the event of the write cycle is counted
                setEvents((others => '0'), (others => '0'), (others => '0'), "00000000000001");
                wrStart(RegLinkACounts0_c, Zero_c);
                waitWriteCycle;
                syncClk;
                quiet;
                wrAwait;
                chk(RegLinkACounts0_c, x"00000001", "LINK_A_COUNTS0: the bit error of the write cycle counts after the clear");

            -- *** TC-MB-09: receive PDOs ***
            elsif run("test_rpdo") then
                log(ID_LOG_HDR, "RPDOn_HI and RPDOn_LO: one PDO in both words, also when the data change between the reads");

                for i in 1 to 30 loop
                    randomStatus;
                    syncClk;

                    for n in 0 to 3 loop
                        rd(RegRpdo1Hi_c + 8 * n, D_v);
                        if i mod 2 = 0 then
                            randomStatus;
                        end if;
                        rd(RegRpdo1Lo_c + 8 * n, D_v);
                    end loop;

                end loop;

                -- Data that change in every cycle during the reads
                for n in 0 to 3 loop
                    axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(RegRpdo1Hi_c + 8 * n, AxiAddrBits_c), "read HI");
                    axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(RegRpdo1Lo_c + 8 * n, AxiAddrBits_c), "read LO");

                    for k in 1 to 30 loop
                        randomStatus;
                        syncClk;
                    end loop;

                    await_completion(AXILITE_VVCT, Axi_c, 100 us);
                end loop;

                -- A read of LO without a read of HI returns the last taken word
                rd(RegRpdo2Lo_c, D_v);
                rd(RegRpdo2Lo_c, E_v);
                check_value(D_v, E_v, ERROR, "RPDO2_LO repeated");

            -- *** TC-MB-10: transmit PDOs ***
            elsif run("test_tpdo") then
                log(ID_LOG_HDR, "TPDOn_HI and TPDOn_LO staging, UPDATE and REQUEST copy both words in one cycle");

                for n in 0 to NumTpdo_g - 1 loop
                    wr(RegTpdo1Hi_c + 8 * n, pattern(RegTpdo1Hi_c + 8 * n, 3));
                    wr(RegTpdo1Lo_c + 8 * n, pattern(RegTpdo1Lo_c + 8 * n, 3));
                end loop;

                for n in 0 to NumTpdo_g - 1 loop
                    chk(RegTpdo1Hi_c + 8 * n, pattern(RegTpdo1Hi_c + 8 * n, 3), "TPDO HI read back");
                    chk(RegTpdo1Lo_c + 8 * n, pattern(RegTpdo1Lo_c + 8 * n, 3), "TPDO LO read back");
                    check_value(Tpdo_Data(64 * n + 63 downto 64 * n), x"0000000000000000", ERROR,
                                "Tpdo_Data unchanged before UPDATE");
                end loop;

                -- UPDATE of one PDO at a time
                for n in 0 to NumTpdo_g - 1 loop
                    wr(RegTpdoControl_c, std_logic_vector(to_unsigned(2 ** n, 32)));
                    check_value(Tpdo_Data(64 * n + 63 downto 64 * n),
                                pattern(RegTpdo1Hi_c + 8 * n, 3) & pattern(RegTpdo1Lo_c + 8 * n, 3), ERROR,
                                "Tpdo_Data after UPDATE");
                    check_value(Tpdo_Req, "0000", ERROR, "no request by UPDATE");
                end loop;

                -- New next data, then REQUEST: data and request in the same cycle
                for n in 0 to NumTpdo_g - 1 loop
                    wr(RegTpdo1Hi_c + 8 * n, pattern(RegTpdo1Hi_c + 8 * n, 4));
                    wr(RegTpdo1Lo_c + 8 * n, pattern(RegTpdo1Lo_c + 8 * n, 4));
                    wrStart(RegTpdoControl_c, std_logic_vector(to_unsigned(2 ** (8 + n), 32)));
                    waitWriteCycle;
                    syncClk(2);
                    check_value(Tpdo_Req(n), '1', ERROR, "Tpdo_Req pulse");
                    check_value(Tpdo_Data(64 * n + 63 downto 64 * n),
                                pattern(RegTpdo1Hi_c + 8 * n, 4) & pattern(RegTpdo1Lo_c + 8 * n, 4), ERROR,
                                "Tpdo_Data in the cycle of the request");
                    syncClk;
                    check_value(Tpdo_Req, "0000", ERROR, "Tpdo_Req for one cycle");
                    wrAwait;
                end loop;

                -- Several PDOs in one write
                wr(RegTpdoControl_c, x"00000F0F");
                wr(RegTpdoControl_c, x"FFFFF0F0");
                chk(RegTpdoControl_c, Zero_c, "TPDO_CONTROL reads zero");

            -- *** TC-MB-11: absent PDOs ***
            elsif run("test_absent_pdos") then
                log(ID_LOG_HDR, "The registers of the PDOs above NumRpdo_g and NumTpdo_g read zero and ignore writes");

                for n in 0 to 3 loop
                    wr(RegTpdo1Hi_c + 8 * n, pattern(RegTpdo1Hi_c + 8 * n, 5));
                    wr(RegTpdo1Lo_c + 8 * n, pattern(RegTpdo1Lo_c + 8 * n, 5));
                    wr(RegRpdo1Hi_c + 8 * n, pattern(RegRpdo1Hi_c + 8 * n, 5));
                end loop;

                randomStatus;
                syncClk;

                for a in RegRpdo1Hi_c / 4 to RegTpdo4Lo_c / 4 loop
                    rd(4 * a, D_v);
                end loop;

                wr(RegTpdoControl_c, x"00000F0F");

                for n in 0 to 3 loop
                    if n >= NumTpdo_g then
                        check_value(Tpdo_Data(64 * n + 63 downto 64 * n), x"0000000000000000", ERROR,
                                    "Tpdo_Data of an absent PDO");
                    end if;
                end loop;

            -- *** TC-MB-12: mailbox ***
            elsif run("test_mailbox") then
                log(ID_LOG_HDR, "Mailbox: request taken, PENDING and APP_REQUEST, SEND answers with the response registers");
                wr(RegControl_c, x"00000002" or (x"0000000" & "000" & b2sl(AutoEnable_g)));

                for i in 0 to 7 loop
                    appRequest(b2sl(i mod 2 = 0), 16#2003# + 997 * i, 17 * i mod 256, pattern(16#180#, i) & pattern(16#184#, i),
                               (i + 1) mod 9);
                    syncClk(3);
                    D_v               := (others => '0');
                    D_v(31)           := '1';
                    D_v(28)           := b2sl(i mod 2 = 0);
                    D_v(27 downto 24) := std_logic_vector(to_unsigned((i + 1) mod 9, 4));
                    D_v(23 downto 16) := std_logic_vector(to_unsigned(17 * i mod 256, 8));
                    D_v(15 downto 0)  := std_logic_vector(to_unsigned(16#2003# + 997 * i, 16));
                    chk(RegAppReq_c, D_v, "APP_REQ");
                    chk(RegAppReqHi_c, pattern(16#180#, i), "APP_REQ_HI");
                    chk(RegAppReqLo_c, pattern(16#184#, i), "APP_REQ_LO");
                    chk(RegEvents_c, x"00000200", "APP_REQUEST");
                    check_value(App_ReqReady, '0', ERROR, "App_ReqReady while pending");
                    wr(RegAppRspHi_c, pattern(16#18C#, i));
                    wr(RegAppRspLo_c, pattern(16#190#, i));
                    wr(RegAppRspLen_c, std_logic_vector(to_unsigned(8 - i, 32)));
                    if i mod 3 = 0 then
                        wr(RegAppRspAbort_c, x"06010002");
                    else
                        wr(RegAppRspAbort_c, Zero_c);
                    end if;
                    chk(RegAppRspLen_c, std_logic_vector(to_unsigned(8 - i, 32)), "APP_RSP_LEN read back");
                    wr(RegAppRspControl_c, x"00000001");
                    appWait;
                    check_value(AppRspOk, true, ERROR, "response received");
                    check_value(AppRspDat, pattern(16#18C#, i) & pattern(16#190#, i), ERROR, "response data");
                    check_value(AppRspLn, std_logic_vector(to_unsigned(8 - i, 4)), ERROR, "response length");
                    if i mod 3 = 0 then
                        check_value(AppRspAb, std_logic_vector'(x"06010002"), ERROR, "response abort code");
                    else
                        check_value(AppRspAb, Zero_c, ERROR, "response abort code 0");
                    end if;
                    chk(RegAppReq_c, D_v and x"7FFFFFFF", "APP_REQ after SEND: PENDING cleared");
                    wr(RegEvents_c, x"00000200");
                end loop;

                -- SEND without a pending request has no effect
                wr(RegAppRspControl_c, x"00000001");
                syncClk(4);
                check_value(App_RspValid, '0', ERROR, "no App_RspValid by SEND without a request");
                chk(RegAppRspControl_c, Zero_c, "APP_RSP_CONTROL reads zero");

            -- *** TC-MB-13: mailbox time-out and mailbox switched off while pending ***
            elsif run("test_mailbox_timeout") then
                log(ID_LOG_HDR, "Err_AppTimeout ends a pending request; a late SEND has no effect; APP_ENABLE cleared while pending");
                wr(RegControl_c, x"00000002" or (x"0000000" & "000" & b2sl(AutoEnable_g)));
                AppTmo <= 60;
                appRequest('1', 16#2200#, 3, pattern(1, 1) & pattern(2, 1), 4);
                appWait;
                check_value(AppRspOk, false, ERROR, "no response before the time-out");
                syncClk(2);
                chk(RegErrors_c, x"00000080", "APP_TIMEOUT flag");
                chk(RegAppReq_c, x"14032200", "PENDING cleared by the time-out");
                check_value(App_ReqReady, '1', ERROR, "App_ReqReady after the time-out");
                wr(RegAppRspControl_c, x"00000001");
                syncClk(3);
                check_value(App_RspValid, '0', ERROR, "a late SEND has no effect");

                -- The time-out in the cycle of the SEND: the sweep puts SEND before, in and after the time-out cycle
                for d in -3 to 3 loop
                    AppTmo <= 80;
                    appRequest('0', 16#3000#, d + 3, (others => '0'), 0);
                    -- the request is taken in the first cycle; the time-out comes 80 cycles later
                    syncClk(70 + d);
                    wrStart(RegAppRspControl_c, x"00000001");
                    appWait;
                    wrAwait;
                    syncClk(4);
                    rd(RegAppReq_c, D_v);
                    check_value(D_v(31), '0', ERROR, "no request pending after the sweep");
                    wr(RegErrors_c, x"00000080");
                    wr(RegEvents_c, x"00000200");
                end loop;

                -- APP_ENABLE cleared while a request is pending: the port answers 0602 0000h
                AppTmo <= 1000;
                appRequest('0', 16#2101#, 1, (others => '0'), 0);
                syncClk(4);
                chk(RegAppReq_c, x"80012101", "pending");
                wr(RegControl_c, x"0000000" & "000" & b2sl(AutoEnable_g));
                appWait;
                check_value(AppRspOk, true, ERROR, "response after APP_ENABLE cleared");
                check_value(AppRspAb, NoObject_c, ERROR, "0602 0000h after APP_ENABLE cleared");
                chk(RegAppReq_c, x"00012101", "PENDING cleared by APP_ENABLE");

            -- *** TC-MB-14: mailbox off ***
            elsif run("test_mailbox_off") then
                log(ID_LOG_HDR, "APP_ENABLE = 0: every request ends with 0602 0000h as with the default values of the port");
                wr(RegAppRspHi_c, x"FFFFFFFF");
                wr(RegAppRspLo_c, x"FFFFFFFF");
                wr(RegAppRspLen_c, x"00000008");
                wr(RegAppRspAbort_c, x"12345678");

                for i in 0 to 4 loop
                    appRequest(b2sl(i mod 2 = 1), 16#2003# + i, i, pattern(i, 7) & pattern(i, 8), i);
                    appWait;
                    check_value(AppRspOk, true, ERROR, "answered");
                    check_value(AppRspAb, NoObject_c, ERROR, "0602 0000h");
                    check_value(AppRspDat, x"0000000000000000", ERROR, "no data");
                    check_value(AppRspLn, "0000", ERROR, "no length");
                end loop;

                chk(RegAppReq_c, Zero_c, "nothing in the mailbox");
                chk(RegEvents_c, Zero_c, "no APP_REQUEST");

            -- *** TC-MB-15: local time ***
            elsif run("test_time") then
                log(ID_LOG_HDR, "TIME_COARSE takes TIME_FINE for the next read; TIME_CONTROL.REQUEST pulses Time_Req");

                for i in 1 to 40 loop
                    randomStatus;
                    syncClk;
                    rd(RegTimeCoarse_c, D_v);
                    randomStatus;
                    rd(RegTimeFine_c, E_v);
                end loop;

                for i in 1 to 10 loop
                    axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(RegTimeCoarse_c, AxiAddrBits_c), "read coarse");
                    axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(RegTimeFine_c, AxiAddrBits_c), "read fine");

                    for k in 1 to 30 loop
                        randomStatus;
                        syncClk;
                    end loop;

                    await_completion(AXILITE_VVCT, Axi_c, 100 us);
                end loop;

                -- Only the read of TIME_COARSE takes the fine time: a read of another register in between and a repeated
                -- read of TIME_FINE return the fine time of the read of TIME_COARSE
                for i in 1 to 10 loop
                    randomStatus;
                    syncClk;
                    rd(RegTimeCoarse_c, D_v);
                    randomStatus;
                    syncClk;
                    rd(RegNode_c, E_v);
                    randomStatus;
                    syncClk;
                    rd(RegTimeFine_c, D_v);
                    randomStatus;
                    syncClk;
                    rd(RegTimeFine_c, E_v);
                    check_value(E_v, D_v, ERROR, "TIME_FINE repeated");
                end loop;

                wrStart(RegTimeControl_c, x"FFFFFFFF");
                waitWriteCycle;
                syncClk(2);
                check_value(Time_Req, '1', ERROR, "Time_Req pulse");
                syncClk;
                check_value(Time_Req, '0', ERROR, "Time_Req for one cycle");
                wrAwait;
                chk(RegTimeControl_c, Zero_c, "TIME_CONTROL reads zero");
                wr(RegTimeControl_c, x"FFFFFFFE");
                check_value(Time_Req, '0', ERROR, "no Time_Req without bit 0");

            -- *** TC-MB-16: error injection ***
            elsif run("test_errinj") then
                log(ID_LOG_HDR, "Error injection: target, two windows, masks, link injections");

                -- Every window of both targets with both masks
                for t in 0 to 1 loop

                    for w0 in 0 to 31 loop
                        Lim_v             := (w0 * 7 + 3) mod 32;
                        E_v               := (others => '0');
                        E_v(8)            := b2sl(t = 1);
                        E_v(4 downto 0)   := std_logic_vector(to_unsigned(w0, 5));
                        E_v(20 downto 16) := std_logic_vector(to_unsigned(Lim_v, 5));
                        wr(RegErrinjSelect_c, E_v or x"FFE0FEE0");
                        chk(RegErrinjSelect_c, E_v, "ERRINJ_SELECT read back");
                        wr(RegErrinjMask0_c, pattern(w0, t));
                        wr(RegErrinjMask1_c, pattern(Lim_v, t + 2));
                        chk(RegErrinjMask0_c, pattern(w0, t), "ERRINJ_MASK0 read back");
                        chk(RegErrinjMask1_c, pattern(Lim_v, t + 2), "ERRINJ_MASK1 read back");
                        wrStart(RegErrinjControl_c, x"00000001");
                        waitWriteCycle;
                        syncClk(2);
                        if t = 0 then
                            check_value(ErrInj_OdValid, '1', ERROR, "ErrInj_OdValid");
                        else
                            check_value(ErrInj_NmtValid, '1', ERROR, "ErrInj_NmtValid");
                        end if;
                        syncClk;
                        check_value(ErrInj_OdValid, '0', ERROR, "ErrInj_OdValid for one cycle");
                        check_value(ErrInj_NmtValid, '0', ERROR, "ErrInj_NmtValid for one cycle");
                        wrAwait;
                    end loop;

                end loop;

                -- Common mode: copy A and copy B of the first COB-ID entry (bits 0 and 279) in one command
                wr(RegErrinjSelect_c, x"00080000");   -- target 0, window 0 and window 8
                wr(RegErrinjMask0_c, x"00000001");     -- bit 0
                wr(RegErrinjMask1_c, x"00800000");     -- bit 8 * 32 + 23 = 279
                wrStart(RegErrinjControl_c, x"00000001");
                waitWriteCycle;
                syncClk(2);
                check_value(ErrInj_OdBitFlip(0), '1', ERROR, "copy A, bit 0");
                check_value(ErrInj_OdBitFlip(279), '1', ERROR, "copy B, bit 279");
                wrAwait;
                -- The same window in both: the OR of the masks
                wr(RegErrinjSelect_c, x"00110011");
                wr(RegErrinjMask0_c, x"0000FFFF");
                wr(RegErrinjMask1_c, x"FF0000FF");
                wr(RegErrinjControl_c, x"00000001");
                -- Link injections
                wr(RegErrinjControl_c, x"00000100");
                check_value(ErrInj_LinkTxDominant, "01", ERROR, "LINK_TX_DOMINANT of controller A");
                chk(RegErrinjControl_c, x"00000100", "ERRINJ_CONTROL reads the level");
                wr(RegErrinjControl_c, x"00000200");
                check_value(ErrInj_LinkTxDominant, "10", ERROR, "LINK_TX_DOMINANT of controller B");

                for b in 4 to 5 loop
                    wrStart(RegErrinjControl_c, std_logic_vector(to_unsigned(2 ** b, 32)));
                    waitWriteCycle;
                    syncClk(2);
                    check_value(ErrInj_LinkStopFlip, std_logic_vector(to_unsigned(2 ** (b - 4), 2)), ERROR,
                                "LINK_STOP_FLIP pulse");
                    syncClk;
                    check_value(ErrInj_LinkStopFlip, "00", ERROR, "LINK_STOP_FLIP for one cycle");
                    wrAwait;
                end loop;

                check_value(ErrInj_LinkTxDominant, "00", ERROR, "LINK_TX_DOMINANT cleared by the last writes");

            -- *** TC-MB-17: error injection off ***
            elsif run("test_errinj_off") then
                log(ID_LOG_HDR, "ErrInjRegs_g false: the injection registers read zero and the injection inputs stay 0");
                wr(RegErrinjSelect_c, x"FFFFFFFF");
                wr(RegErrinjMask0_c, x"FFFFFFFF");
                wr(RegErrinjMask1_c, x"FFFFFFFF");
                wr(RegErrinjControl_c, x"FFFFFFFF");

                for a in RegErrinjSelect_c / 4 to RegErrinjControl_c / 4 loop
                    chk(4 * a, Zero_c, "error injection register");
                end loop;

                check_value(ErrInj_OdValid, '0', ERROR, "ErrInj_OdValid");
                check_value(ErrInj_LinkTxDominant, "00", ERROR, "ErrInj_LinkTxDominant");

            -- *** TC-MB-18: reset ***
            elsif run("test_reset") then
                log(ID_LOG_HDR, "A reset clears flags, counters, snapshots, enables, the mailbox and the pulses");
                wr(RegControl_c, x"00000002");
                wr(RegBitTiming_c, x"21050007");
                wr(RegEventsIrqEn_c, x"000003FF");
                wr(RegTpdo1Hi_c, x"11223344");
                wr(RegTpdoControl_c, x"00000001");
                setEvents((others => '1'), (others => '1'), "01111111101111111", "11111100111111");
                syncClk(3);
                quiet;
                randomStatus;
                rd(RegTimeCoarse_c, D_v);
                rd(RegRpdo1Hi_c, D_v);
                appRequest('1', 16#2003#, 0, (others => '1'), 8);
                syncClk(4);
                if ErrInjRegs_g then
                    wr(RegErrinjControl_c, x"00000300");
                end if;
                reset;
                appWait;

                for a in 0 to 127 loop
                    rd(4 * a, D_v);
                end loop;

                check_value(Irq, '0', ERROR, "Irq after the reset");
                check_value(Tpdo_Data, (Tpdo_Data'range => '0'), ERROR, "Tpdo_Data after the reset");
                check_value(ErrInj_LinkTxDominant, "00", ERROR, "ErrInj_LinkTxDominant after the reset");

            -- *** TC-MB-19: random accesses and events ***
            elsif run("test_random") then
                log(ID_LOG_HDR, "Random accesses to every address with random events, status and mailbox requests");
                AppTmo <= 300;

                for i in 1 to 600 loop
                    N_v := random(0, 127);

                    case random(0, 9) is
                        when 0 to 3 =>
                            axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(4 * N_v, AxiAddrBits_c), "random read");
                        when 4 to 7 =>
                            D_v := random(32);
                            -- Mostly enable the mailbox and keep the controllers off, so the bit timing is writable
                            if N_v = RegControl_c / 4 then
                                D_v(1) := b2sl(random(0, 3) /= 0);
                                D_v(0) := b2sl(random(0, 3) = 0);
                            end if;
                            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(4 * N_v, AxiAddrBits_c), D_v, "random write");
                        when 8 =>
                            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(RegAppRspControl_c, AxiAddrBits_c),
                                          x"00000001", "SEND");
                        when others =>
                            if AppGo = AppDone then
                                AppWr  <= random(1)(0);
                                AppIdx <= random(16);
                                AppSub <= random(8);
                                AppDat <= random(32) & random(32);
                                AppLen <= random(4);
                                AppGo  <= AppGo + 1;
                            end if;
                    end case;

                    for k in 0 to random(0, 6) loop
                        randomEvents(6);
                        if random(0, 2) = 0 then
                            randomStatus;
                        end if;
                        syncClk;
                    end loop;

                    quiet;
                    if i mod 20 = 0 then
                        await_completion(AXILITE_VVCT, Axi_c, 1 ms);
                    end if;
                end loop;

                await_completion(AXILITE_VVCT, Axi_c, 1 ms);
                appWait;

                for a in 0 to 127 loop
                    rd(4 * a, D_v);
                end loop;

                check_value(ModelReads > 200, ERROR, "the model checked the read words");
            end if;

            -- *** End of every test: all accesses done, the model checked the last cycles ***
            await_completion(AXILITE_VVCT, Axi_c, 1 ms);
            syncClk(10);
        end loop;

        ocanTestEnd(runner);
    end process;

end architecture;
