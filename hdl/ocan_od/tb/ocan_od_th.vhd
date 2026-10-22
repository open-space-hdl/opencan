---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Harness of ocan_od: the clock (40 MHz) and the device under test. With AppPort_g = false the inputs of the
-- application port keep their default values (TC-OD-18).

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_od_th is
    generic (
        MinimalSet_g     : boolean;
        NumRpdo_g        : natural;
        NumTpdo_g        : natural;
        TimePdos_g       : boolean;
        DeviceType_g     : std_logic_vector(31 downto 0);
        VendorId_g       : std_logic_vector(31 downto 0);
        ProductCode_g    : std_logic_vector(31 downto 0);
        Revision_g       : std_logic_vector(31 downto 0);
        SerialNumber_g   : std_logic_vector(31 downto 0);
        ProducerHbTime_g : natural;
        MasterNodeId_g   : natural;
        MasterHbTime_g   : natural;
        Bdefault_g       : natural;
        Ttoggle_g        : natural;
        Ntoggle_g        : natural;
        RpdoType_g       : natural;
        TpdoType_g       : natural;
        SctCobId_g       : natural;
        SctType_g        : natural;
        LtpCobId_g       : natural;
        LtpType_g        : natural;
        AppPort_g        : boolean
    );
    port (
        Clk              : out   std_logic;
        Rst              : in    std_logic;
        Tick_Ms          : in    std_logic;
        Acc_Valid        : in    std_logic;
        Acc_Ready        : out   std_logic;
        Acc_Write        : in    std_logic;
        Acc_Index        : in    std_logic_vector(15 downto 0);
        Acc_Sub          : in    std_logic_vector(7 downto 0);
        Acc_Data         : in    std_logic_vector(63 downto 0);
        Acc_Len          : in    std_logic_vector(3 downto 0);
        Rsp_Valid        : out   std_logic;
        Rsp_Data         : out   std_logic_vector(63 downto 0);
        Rsp_Len          : out   std_logic_vector(3 downto 0);
        Rsp_Abort        : out   std_logic_vector(31 downto 0);
        Nmt_State        : in    std_logic_vector(1 downto 0);
        Nmt_NodeId       : in    std_logic_vector(6 downto 0);
        Nmt_ResetApp     : in    std_logic;
        Nmt_ResetComm    : in    std_logic;
        Cfg_CobId        : out   std_logic_vector(143 downto 0);
        Cfg_CobIdCopy    : out   std_logic_vector(143 downto 0);
        Cfg_HbTime       : out   std_logic_vector(15 downto 0);
        Cfg_MasterHbTime : out   std_logic_vector(15 downto 0);
        Cfg_Bdefault     : out   std_logic;
        Cfg_Ttoggle      : out   std_logic_vector(7 downto 0);
        Cfg_Ntoggle      : out   std_logic_vector(7 downto 0);
        Cfg_Ctoggle      : out   std_logic_vector(7 downto 0);
        Cfg_CtoggleValid : out   std_logic;
        Stat_Ctoggle     : in    std_logic_vector(7 downto 0);
        Upd_Valid        : in    std_logic;
        Upd_Bdefault     : in    std_logic;
        Cfg_SctType      : out   std_logic_vector(7 downto 0);
        Cfg_LtpType      : out   std_logic_vector(7 downto 0);
        Cfg_SetValid     : out   std_logic;
        Cfg_SetScet      : out   std_logic_vector(55 downto 0);
        Stat_Scet        : in    std_logic_vector(55 downto 0);
        Cfg_RpdoType     : out   std_logic_vector(31 downto 0);
        Cfg_TpdoType     : out   std_logic_vector(31 downto 0);
        Link_State       : in    std_logic_vector(1 downto 0);
        App_ReqValid     : out   std_logic;
        App_ReqReady     : in    std_logic;
        App_ReqWrite     : out   std_logic;
        App_ReqIndex     : out   std_logic_vector(15 downto 0);
        App_ReqSub       : out   std_logic_vector(7 downto 0);
        App_ReqData      : out   std_logic_vector(63 downto 0);
        App_ReqLen       : out   std_logic_vector(3 downto 0);
        App_RspValid     : in    std_logic;
        App_RspData      : in    std_logic_vector(63 downto 0);
        App_RspLen       : in    std_logic_vector(3 downto 0);
        App_RspAbort     : in    std_logic_vector(31 downto 0);
        Stat_ErrReg      : out   std_logic_vector(7 downto 0);
        Err_ParamCopy    : out   std_logic;
        Err_AppTimeout   : out   std_logic;
        ErrInj_BitFlip   : in    std_logic_vector(557 downto 0);
        ErrInj_Valid     : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_od_th is

    constant ClkPeriod_c : time := 25 ns;

    signal ClkInt : std_logic := '0';

begin

    ClkInt <= not ClkInt after ClkPeriod_c / 2;
    Clk    <= ClkInt;

    g_app : if AppPort_g generate

        i_dut : entity work.ocan_od
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
                LtpType_g        => LtpType_g
            )
            port map (
                Clk              => ClkInt,
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

    end generate;

    g_noapp : if not AppPort_g generate

        i_dut : entity work.ocan_od
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
                LtpType_g        => LtpType_g
            )
            port map (
                Clk              => ClkInt,
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
                App_ReqWrite     => App_ReqWrite,
                App_ReqIndex     => App_ReqIndex,
                App_ReqSub       => App_ReqSub,
                App_ReqData      => App_ReqData,
                App_ReqLen       => App_ReqLen,
                Stat_ErrReg      => Stat_ErrReg,
                Err_ParamCopy    => Err_ParamCopy,
                Err_AppTimeout   => Err_AppTimeout,
                ErrInj_BitFlip   => ErrInj_BitFlip,
                ErrInj_Valid     => ErrInj_Valid
            );

    end generate;

end architecture;
