---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Access of OpenCAN to the nominal and the redundant bus (ECSS-E-ST-50-15C clauses 5.4, 5.6 and 8.2): one or two
-- olo_intf_can, the bus switch, the received frames as events, the transmit path and a dominant monitor per
-- controller.
--
-- Documentation: hdl/ocan_link/docs/architecture.md

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
entity ocan_link is
    generic (
        BusAccess_g     : string                    := "Selective";
        SyncStages_g    : positive range 2 to 4     := 2;
        AutoRecover_g   : boolean                   := true;
        DominantLimit_g : positive range 13 to 1023 := 32
    );
    port (
        -- Control
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        Ctrl_Enable       : in    std_logic;
        Ctrl_Bus          : in    std_logic;
        Ctrl_Recover      : in    std_logic                     := '0';
        Ctrl_Reenable     : in    std_logic_vector(1 downto 0)  := "00";
        -- Bit timing (static while Ctrl_Enable = '1')
        Cfg_Prescaler     : in    std_logic_vector(9 downto 0);
        Cfg_Tseg1         : in    std_logic_vector(4 downto 0);
        Cfg_Tseg2         : in    std_logic_vector(3 downto 0);
        Cfg_Sjw           : in    std_logic_vector(2 downto 0);
        -- Frame to send
        Tx_Valid          : in    std_logic                     := '0';
        Tx_Ready          : out   std_logic;
        Tx_Id             : in    std_logic_vector(28 downto 0) := (others => '0');
        Tx_Ide            : in    std_logic                     := '0';
        Tx_Rtr            : in    std_logic                     := '0';
        Tx_Dlc            : in    std_logic_vector(3 downto 0)  := (others => '0');
        Tx_Data           : in    std_logic_vector(63 downto 0) := (others => '0');
        Tx_Abort          : in    std_logic                     := '0';
        Tx_Done           : out   std_logic;
        Tx_Aborted        : out   std_logic;
        Tx_ArbLost        : out   std_logic;
        -- Received frames, per bus (bus b in slice b)
        Rx_Valid          : out   std_logic_vector(1 downto 0);
        Rx_Id             : out   std_logic_vector(57 downto 0);
        Rx_Ide            : out   std_logic_vector(1 downto 0);
        Rx_Rtr            : out   std_logic_vector(1 downto 0);
        Rx_Dlc            : out   std_logic_vector(7 downto 0);
        Rx_Data           : out   std_logic_vector(127 downto 0);
        -- Status
        Stat_ActiveBus    : out   std_logic;
        Stat_Switching    : out   std_logic;
        -- Status and error events, per controller (controller c in slice c)
        Stat_Tec          : out   std_logic_vector(17 downto 0);
        Stat_Rec          : out   std_logic_vector(15 downto 0);
        Stat_State        : out   std_logic_vector(3 downto 0);
        Stat_BusIdle      : out   std_logic_vector(1 downto 0);
        Stat_DomTimeout   : out   std_logic_vector(1 downto 0);
        Err_Bit           : out   std_logic_vector(1 downto 0);
        Err_Stuff         : out   std_logic_vector(1 downto 0);
        Err_Crc           : out   std_logic_vector(1 downto 0);
        Err_Form          : out   std_logic_vector(1 downto 0);
        Err_Ack           : out   std_logic_vector(1 downto 0);
        Err_DomTimeout    : out   std_logic_vector(1 downto 0);
        -- Test input: forces the transmit bit of a controller dominant (tie to "00" in a system)
        ErrInj_TxDominant : in    std_logic_vector(1 downto 0)  := "00";
        -- Transceivers, per bus (bus A in index 0, bus B in index 1)
        Can_Tx            : out   std_logic_vector(1 downto 0);
        Can_TxEn          : out   std_logic_vector(1 downto 0);
        Can_Rx            : in    std_logic_vector(1 downto 0)  := "11"
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_link is

    -- *** Constants ***
    constant Parallel_c : boolean := BusAccess_g = "Parallel";

    function numControllers return positive is
    begin
        if Parallel_c then
            return 2;
        else
            return 1;
        end if;
    end function;

    constant NumCtl_c : positive := numControllers;

    -- Bus or controller index as the value of the active bus signal
    function indexBit (idx : natural) return std_logic is
    begin
        if idx = 1 then
            return '1';
        else
            return '0';
        end if;
    end function;

    -- *** Types ***
    type State_t is (Disabled_s, Run_s, Abort_s, Switch_s);

    type Id_a is array (0 to 1) of std_logic_vector(28 downto 0);
    type Dlc_a is array (0 to 1) of std_logic_vector(3 downto 0);
    type Data_a is array (0 to 1) of std_logic_vector(63 downto 0);
    type Tq_a is array (0 to 1) of unsigned(9 downto 0);
    type Quanta_a is array (0 to 1) of unsigned(5 downto 0);
    type Bits_a is array (0 to 1) of unsigned(9 downto 0);
    type Tec_a is array (0 to 1) of std_logic_vector(8 downto 0);
    type Rec_a is array (0 to 1) of std_logic_vector(7 downto 0);
    type CtlState_a is array (0 to 1) of std_logic_vector(1 downto 0);

    -- *** Two process method ***
    type TwoProcess_r is record
        State   : State_t;
        Active  : std_logic;                    -- active bus: '0' bus A, '1' bus B
        Stopped : std_logic_vector(1 downto 0); -- controller stopped by its dominant monitor
        TqCnt   : Tq_a;
        QCnt    : Quanta_a;
        BitCnt  : Bits_a;
        DomErr  : std_logic_vector(1 downto 0);
        RxValid : std_logic_vector(1 downto 0);
        RxId    : Id_a;
        RxIde   : std_logic_vector(1 downto 0);
        RxRtr   : std_logic_vector(1 downto 0);
        RxDlc   : Dlc_a;
        RxData  : Data_a;
    end record;

    signal r, r_next : TwoProcess_r;

    -- *** Controller signals (index = controller) ***
    signal CtlEnable    : std_logic_vector(1 downto 0);
    signal CtlListen    : std_logic_vector(1 downto 0);
    signal CtlCanRx     : std_logic_vector(1 downto 0);
    signal CtlCanTx     : std_logic_vector(1 downto 0) := "11";
    signal CtlTxValid   : std_logic_vector(1 downto 0);
    signal CtlTxReady   : std_logic_vector(1 downto 0) := "11";
    signal CtlTxAbort   : std_logic_vector(1 downto 0);
    signal CtlTxDone    : std_logic_vector(1 downto 0) := "00";
    signal CtlTxAborted : std_logic_vector(1 downto 0) := "00";
    signal CtlTxArbLost : std_logic_vector(1 downto 0) := "00";
    signal CtlRxValid   : std_logic_vector(1 downto 0) := "00";
    signal CtlRxId      : Id_a                         := (others => (others => '0'));
    signal CtlRxIde     : std_logic_vector(1 downto 0) := "00";
    signal CtlRxRtr     : std_logic_vector(1 downto 0) := "00";
    signal CtlRxDlc     : Dlc_a                        := (others => (others => '0'));
    signal CtlRxData    : Data_a                       := (others => (others => '0'));
    signal CtlTec       : Tec_a                        := (others => (others => '0'));
    signal CtlRec       : Rec_a                        := (others => (others => '0'));
    signal CtlState     : CtlState_a                   := (others => (others => '0'));
    signal CtlBusIdle   : std_logic_vector(1 downto 0) := "00";
    signal CtlErrBit    : std_logic_vector(1 downto 0) := "00";
    signal CtlErrStuff  : std_logic_vector(1 downto 0) := "00";
    signal CtlErrCrc    : std_logic_vector(1 downto 0) := "00";
    signal CtlErrForm   : std_logic_vector(1 downto 0) := "00";
    signal CtlErrAck    : std_logic_vector(1 downto 0) := "00";

    -- Transmit bit of each controller after the fault injection ('0' dominant)
    signal TxInt  : std_logic_vector(1 downto 0);
    -- Controller of the active bus
    signal ActCtl : natural range 0 to 1;
    -- Controller takes part in the bus
    signal Live   : std_logic_vector(1 downto 0);

begin

    assert BusAccess_g = "Selective" or BusAccess_g = "Parallel"
        report "ocan_link: BusAccess_g must be ""Selective"" or ""Parallel"""
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Combinational signals of the bus side
    -----------------------------------------------------------------------------------------------
    p_bus : process (all) is
        variable Run_v   : boolean;
        variable C_v     : natural range 0 to 1;
        variable Live_v  : std_logic_vector(1 downto 0);
        variable TxInt_v : std_logic_vector(1 downto 0);
    begin
        Run_v := r.State = Run_s or r.State = Abort_s;

        -- Controller of the active bus
        if Parallel_c and r.Active = '1' then
            ActCtl <= 1;
        else
            ActCtl <= 0;
        end if;

        for C in 0 to 1 loop
            TxInt_v(C) := CtlCanTx(C) and not ErrInj_TxDominant(C);
            if C < NumCtl_c and Run_v and r.Stopped(C) = '0' then
                Live_v(C) := '1';
            else
                Live_v(C) := '0';
            end if;
        end loop;

        TxInt <= TxInt_v;
        Live  <= Live_v;

        -- Controller enables and modes (LK-BA-01, LK-BA-02); they change only while the controllers are disabled
        for C in 0 to 1 loop
            CtlEnable(C) <= Live_v(C);
            if Parallel_c and indexBit(C) /= r.Active then
                CtlListen(C) <= '1';
            else
                CtlListen(C) <= '0';
            end if;
        end loop;

        -- Receive bits: selector of the selective bus access, or one bus per controller
        if Parallel_c then
            CtlCanRx <= Can_Rx;
        elsif r.Active = '1' then
            CtlCanRx <= '1' & Can_Rx(1);
        else
            CtlCanRx <= '1' & Can_Rx(0);
        end if;

        -- Bus outputs: only the active bus is driven, and only by a live controller (LK-BA-03, D4)
        for B in 0 to 1 loop
            if Parallel_c then
                C_v := B;
            else
                C_v := 0;
            end if;
            if indexBit(B) = r.Active and Live_v(C_v) = '1' then
                Can_Tx(B)   <= TxInt_v(C_v);
                Can_TxEn(B) <= '1';
            else
                Can_Tx(B)   <= '1';
                Can_TxEn(B) <= '0';
            end if;
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Transmit path (LK-5)
    -----------------------------------------------------------------------------------------------
    p_tx : process (all) is
    begin

        for C in 0 to 1 loop
            CtlTxValid(C) <= '0';
            CtlTxAbort(C) <= '0';
            if C = ActCtl and r.State = Run_s and r.Stopped(C) = '0' then
                CtlTxValid(C) <= Tx_Valid;
                CtlTxAbort(C) <= Tx_Abort;
            end if;
            -- Abort before a switch, while disabled and while stopped (LK-BS-02, LK-BA-04, LK-DT-01)
            if (C = ActCtl and r.State = Abort_s) or r.State = Disabled_s or r.Stopped(C) = '1' then
                CtlTxAbort(C) <= '1';
            end if;
        end loop;

        if r.State = Run_s and r.Stopped(ActCtl) = '0' then
            Tx_Ready <= CtlTxReady(ActCtl);
        else
            Tx_Ready <= '0';
        end if;
        Tx_Done    <= CtlTxDone(0) or CtlTxDone(1);
        Tx_Aborted <= CtlTxAborted(0) or CtlTxAborted(1);
        Tx_ArbLost <= CtlTxArbLost(0) or CtlTxArbLost(1);
    end process;

    -----------------------------------------------------------------------------------------------
    -- Sequencer, monitors and receive registers
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable B_v     : natural range 0 to 1;
        variable Presc_v : unsigned(9 downto 0);
        variable Quant_v : unsigned(5 downto 0);
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.RxValid := "00";
        v.DomErr  := "00";

        -- *** Bus switch sequencer (LK-3) ***
        case r.State is

            when Disabled_s =>
                if Ctrl_Enable = '1' then
                    v.Active := Ctrl_Bus; -- LK-BS-01
                    v.State  := Run_s;
                end if;

            when Run_s =>
                if Ctrl_Bus /= r.Active then
                    v.State := Abort_s;
                end if;

            when Abort_s =>
                -- No frame pending in the controller of the active bus: change the bus (LK-BS-02)
                if CtlTxReady(ActCtl) = '1' then
                    v.Active := not r.Active;
                    v.State  := Switch_s;
                end if;

            when Switch_s =>
                v.State := Run_s;

            -- coverage off
            when others =>
                v.State := Disabled_s;
            -- coverage on

        end case;

        -- *** Dominant monitors (LK-6) ***
        Presc_v := unsigned(Cfg_Prescaler);
        if Presc_v = 0 then
            Presc_v := to_unsigned(1, Presc_v'length);
        end if;
        Quant_v := 1 + resize(unsigned(Cfg_Tseg1), Quant_v'length) + resize(unsigned(Cfg_Tseg2), Quant_v'length);

        for C in 0 to NumCtl_c - 1 loop
            if TxInt(C) = '1' then
                v.TqCnt(C)  := (others => '0');
                v.QCnt(C)   := (others => '0');
                v.BitCnt(C) := (others => '0');
            elsif r.BitCnt(C) < DominantLimit_g then
                if r.TqCnt(C) + 1 >= Presc_v then
                    v.TqCnt(C) := (others => '0');
                    if r.QCnt(C) + 1 >= Quant_v then
                        v.QCnt(C)   := (others => '0');
                        v.BitCnt(C) := r.BitCnt(C) + 1;
                    else
                        v.QCnt(C) := r.QCnt(C) + 1;
                    end if;
                else
                    v.TqCnt(C) := r.TqCnt(C) + 1;
                end if;
            end if;
            -- Timeout: release the bus and stop the controller (LK-DT-01)
            if v.BitCnt(C) = DominantLimit_g and r.BitCnt(C) /= DominantLimit_g and r.Stopped(C) = '0' then
                v.Stopped(C) := '1';
                v.DomErr(C)  := '1';
            end if;
            -- Re-enable (LK-DT-02)
            if Ctrl_Reenable(C) = '1' then
                v.Stopped(C) := '0';
            end if;
        end loop;

        -- *** Received frames: one register, the event of the bus of the controller (LK-RX-01, LK-RX-02) ***
        for C in 0 to NumCtl_c - 1 loop
            if Parallel_c then
                B_v := C;
            elsif r.Active = '1' then
                B_v := 1;
            else
                B_v := 0;
            end if;
            if CtlRxValid(C) = '1' then
                v.RxValid(B_v) := '1';
                v.RxId(B_v)    := CtlRxId(C);
                v.RxIde(B_v)   := CtlRxIde(C);
                v.RxRtr(B_v)   := CtlRxRtr(C);
                v.RxDlc(B_v)   := CtlRxDlc(C);
                v.RxData(B_v)  := CtlRxData(C);
            end if;
        end loop;

        -- *** Disable (LK-BA-04, LK-DT-02) ***
        if Ctrl_Enable = '0' then
            v.State   := Disabled_s;
            v.Stopped := "00";
        end if;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -- *** Outputs ***
    Rx_Valid        <= r.RxValid;
    Stat_ActiveBus  <= r.Active;
    Stat_Switching  <= '1' when r.State = Abort_s or r.State = Switch_s else '0';
    Stat_DomTimeout <= r.Stopped;
    Err_DomTimeout  <= r.DomErr;

    g_out : for B in 0 to 1 generate
        Rx_Id(29 * B + 28 downto 29 * B)   <= r.RxId(B);
        Rx_Ide(B)                          <= r.RxIde(B);
        Rx_Rtr(B)                          <= r.RxRtr(B);
        Rx_Dlc(4 * B + 3 downto 4 * B)     <= r.RxDlc(B);
        Rx_Data(64 * B + 63 downto 64 * B) <= r.RxData(B);
        Stat_Tec(9 * B + 8 downto 9 * B)   <= CtlTec(B);
        Stat_Rec(8 * B + 7 downto 8 * B)   <= CtlRec(B);
        Stat_State(2 * B + 1 downto 2 * B) <= CtlState(B);
    end generate;

    Stat_BusIdle <= CtlBusIdle;
    Err_Bit      <= CtlErrBit;
    Err_Stuff    <= CtlErrStuff;
    Err_Crc      <= CtlErrCrc;
    Err_Form     <= CtlErrForm;
    Err_Ack      <= CtlErrAck;

    -- *** Sequential process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State   <= Disabled_s;
                r.Active  <= '0';
                r.Stopped <= "00";
                r.TqCnt   <= (others => (others => '0'));
                r.QCnt    <= (others => (others => '0'));
                r.BitCnt  <= (others => (others => '0'));
                r.DomErr  <= "00";
                r.RxValid <= "00";
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Controllers (LK-1)
    -----------------------------------------------------------------------------------------------
    g_ctl : for C in 0 to NumCtl_c - 1 generate

        i_can : entity olo.olo_intf_can
            generic map (
                SyncStages_g  => SyncStages_g,
                SyncTmr_g     => true,
                AutoRecover_g => AutoRecover_g
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                Cfg_Enable     => CtlEnable(C),
                Cfg_Prescaler  => Cfg_Prescaler,
                Cfg_Tseg1      => Cfg_Tseg1,
                Cfg_Tseg2      => Cfg_Tseg2,
                Cfg_Sjw        => Cfg_Sjw,
                Cfg_ListenOnly => CtlListen(C),
                Cfg_Loopback   => '0',
                Ctrl_Recover   => Ctrl_Recover,
                Tx_Valid       => CtlTxValid(C),
                Tx_Ready       => CtlTxReady(C),
                Tx_Id          => Tx_Id,
                Tx_Ide         => Tx_Ide,
                Tx_Rtr         => Tx_Rtr,
                Tx_Dlc         => Tx_Dlc,
                Tx_Data        => Tx_Data,
                Tx_Abort       => CtlTxAbort(C),
                Tx_Done        => CtlTxDone(C),
                Tx_Aborted     => CtlTxAborted(C),
                Tx_ArbLost     => CtlTxArbLost(C),
                Rx_Valid       => CtlRxValid(C),
                Rx_Id          => CtlRxId(C),
                Rx_Ide         => CtlRxIde(C),
                Rx_Rtr         => CtlRxRtr(C),
                Rx_Dlc         => CtlRxDlc(C),
                Rx_Data        => CtlRxData(C),
                Stat_Tec       => CtlTec(C),
                Stat_Rec       => CtlRec(C),
                Stat_State     => CtlState(C),
                Stat_BusIdle   => CtlBusIdle(C),
                Err_Bit        => CtlErrBit(C),
                Err_Stuff      => CtlErrStuff(C),
                Err_Crc        => CtlErrCrc(C),
                Err_Form       => CtlErrForm(C),
                Err_Ack        => CtlErrAck(C),
                Can_Tx         => CtlCanTx(C),
                Can_Rx         => CtlCanRx(C)
            );

    end generate;

end architecture;
