---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- SDO server of OpenCAN: expedited and segmented transfers of objects of up to 8 bytes between an SDO client and the
-- object dictionary (ECSS-E-ST-50-15C clause 6.1, [CiA301] section 7.2.4).
--
-- Documentation: hdl/ocan_sdo/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_sdo is
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Tick_Ms        : in    std_logic;
        -- SDO request of ocan_dispatch (byte 0 in bits 63 to 56)
        Rx_Valid       : in    std_logic;
        Rx_Dlc         : in    std_logic_vector(3 downto 0);
        Rx_Data        : in    std_logic_vector(63 downto 0);
        -- SDO reply to ocan_dispatch (byte 0 in bits 63 to 56)
        Tx_Valid       : out   std_logic;
        Tx_Ready       : in    std_logic;
        Tx_Dlc         : out   std_logic_vector(3 downto 0);
        Tx_Data        : out   std_logic_vector(63 downto 0);
        Tx_Done        : in    std_logic;
        Tx_Aborted     : in    std_logic;
        -- Access of ocan_od (byte k of the value in bits 8 k + 7 downto 8 k)
        Acc_Valid      : out   std_logic;
        Acc_Ready      : in    std_logic;
        Acc_Write      : out   std_logic;
        Acc_Index      : out   std_logic_vector(15 downto 0);
        Acc_Sub        : out   std_logic_vector(7 downto 0);
        Acc_Data       : out   std_logic_vector(63 downto 0);
        Acc_Len        : out   std_logic_vector(3 downto 0);
        Rsp_Valid      : in    std_logic;
        Rsp_Data       : in    std_logic_vector(63 downto 0);
        Rsp_Len        : in    std_logic_vector(3 downto 0);
        Rsp_Abort      : in    std_logic_vector(31 downto 0);
        -- ocan_nmt
        Nmt_EnaSdo     : in    std_logic;
        Nmt_ResetApp   : in    std_logic;
        Nmt_ResetComm  : in    std_logic;
        -- Status and events
        Stat_Open      : out   std_logic;
        Err_RxDrop     : out   std_logic;
        Err_TxTimeout  : out   std_logic;
        Err_AccTimeout : out   std_logic;
        Evt_AbortTx    : out   std_logic;
        Evt_AbortRx    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ocan_sdo is

    -- *** Constants ***
    -- Abort codes ([CiA301] table 22)
    constant AbortToggle_c  : std_logic_vector(31 downto 0) := x"05030000";
    constant AbortCs_c      : std_logic_vector(31 downto 0) := x"05040001";
    constant AbortMemory_c  : std_logic_vector(31 downto 0) := x"05040005";
    constant AbortMatch_c   : std_logic_vector(31 downto 0) := x"06070010";
    constant AbortHigh_c    : std_logic_vector(31 downto 0) := x"06070012";
    constant AbortGeneral_c : std_logic_vector(31 downto 0) := x"08000000";
    -- Largest object, completion time-out of the reply (SD-TX-02) and answer time-out of the access (SD-TX-04)
    constant MaxBytes_c     : natural := 8;
    constant TxTimeout_c    : natural := 256;
    constant AccTimeout_c   : natural := 512;

    -- *** Types ***
    subtype Byte_t is std_logic_vector(7 downto 0);

    type Xfer_t is (XNone_s, XDown_s, XUp_s);

    type Proc_t is (PIdle_s, PAcc_s, PTx_s, PWait_s);

    -- The request whose access is outstanding
    type Kind_t is (KDownExp_s, KDownLast_s, KUpInit_s);

    -- *** Functions ***
    -- Byte k of a frame (byte 0 in bits 63 to 56)
    function frameByte (d : std_logic_vector(63 downto 0); k : natural) return Byte_t is
    begin
        return d(63 - 8 * k downto 56 - 8 * k);
    end function;

    -- Frame of a command byte, the index and sub-index and 32 bits in bytes 4 to 7, least significant byte first
    function frameMux (
        cmd : Byte_t;
        idx : std_logic_vector(15 downto 0);
        sub : Byte_t;
        val : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable F_v : std_logic_vector(63 downto 0);
    begin
        F_v := cmd & idx(7 downto 0) & idx(15 downto 8) & sub &
               val(7 downto 0) & val(15 downto 8) & val(23 downto 16) & val(31 downto 24);
        return F_v;
    end function;

    -- Value of bytes 4 to 7 of a frame, least significant byte first
    function value32 (d : std_logic_vector(63 downto 0)) return std_logic_vector is
        variable V_v : std_logic_vector(31 downto 0);
    begin
        V_v := frameByte(d, 7) & frameByte(d, 6) & frameByte(d, 5) & frameByte(d, 4);
        return V_v;
    end function;

    -- *** Two process method ***
    type TwoProcess_r is record
        -- Open transfer (architecture, section 2)
        Xfer     : Xfer_t;
        Index    : std_logic_vector(15 downto 0);
        Sub      : Byte_t;
        Tgl      : std_logic;
        Size     : unsigned(3 downto 0);
        Cnt      : unsigned(3 downto 0);
        Buf      : std_logic_vector(63 downto 0);
        -- Processing of a request (architecture, section 3)
        Proc     : Proc_t;
        Kind     : Kind_t;
        LastTgl  : std_logic;
        AccWrite : std_logic;
        AccData  : std_logic_vector(63 downto 0);
        AccLen   : std_logic_vector(3 downto 0);
        AccTaken : std_logic;
        Aborted  : std_logic;
        TxData   : std_logic_vector(63 downto 0);
        TxTmo    : unsigned(8 downto 0);
        -- Events
        ErrDrop  : std_logic;
        ErrTmo   : std_logic;
        ErrAcc   : std_logic;
        EvtAbTx  : std_logic;
        EvtAbRx  : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable B0_v   : Byte_t;
        variable Ccs_v  : natural range 0 to 7;
        variable Idx_v  : std_logic_vector(15 downto 0);
        variable Sub_v  : Byte_t;
        variable K_v    : natural range 0 to 7;
        variable New_v  : natural range 0 to 31;
        variable Rem_v  : natural range 0 to 15;
        variable P_v    : natural range 0 to 7;
        variable Size_v : unsigned(31 downto 0);
        variable Len_v  : natural range 0 to 15;
        variable Val_v  : std_logic_vector(31 downto 0);
        variable Seg_v  : std_logic_vector(63 downto 0);
        variable Stop_v : boolean;
        variable RstE_v : boolean;
        variable AbRq_v : boolean;
        variable Quit_v : boolean;
        variable Take_v : boolean;
    begin
        -- *** hold variables stable ***
        v := r;

        -- *** default values ***
        v.ErrDrop := '0';
        v.ErrTmo  := '0';
        v.ErrAcc  := '0';
        v.EvtAbTx := '0';
        v.EvtAbRx := '0';
        B0_v      := frameByte(Rx_Data, 0);
        Ccs_v     := to_integer(unsigned(B0_v(7 downto 5)));
        Idx_v     := frameByte(Rx_Data, 2) & frameByte(Rx_Data, 1);
        Sub_v     := frameByte(Rx_Data, 3);
        Stop_v    := Nmt_EnaSdo = '0';
        RstE_v    := Nmt_ResetApp = '1' or Nmt_ResetComm = '1';
        AbRq_v    := Rx_Valid = '1' and unsigned(Rx_Dlc) >= 8 and Ccs_v = 4;
        -- The processing ends without a reply (SD-PR-09, SD-RS-01, SD-RS-02)
        Quit_v := AbRq_v or Stop_v or RstE_v;
        Take_v := r.Proc = PAcc_s and r.AccTaken = '0' and Acc_Ready = '1';

        -- *** Processing of the request (architecture, section 3) ***
        case r.Proc is

            when PIdle_s =>
                null;

            when PAcc_s =>
                if Take_v then
                    v.AccTaken := '1';
                end if;
                if r.AccTaken = '1' and Rsp_Valid = '1' then
                    -- The answer of ocan_od
                    if r.Aborted = '1' or Quit_v then
                        -- Not used
                        v.Proc := PIdle_s;
                    elsif Rsp_Abort /= x"00000000" then
                        v.TxData := frameMux(x"80", r.Index, r.Sub, Rsp_Abort);
                        v.Proc   := PTx_s;
                    elsif r.Kind = KDownExp_s then
                        -- Initiate download response
                        v.TxData := frameMux(x"60", r.Index, r.Sub, x"00000000");
                        v.Proc   := PTx_s;
                    elsif r.Kind = KDownLast_s then
                        -- Download segment response
                        v.TxData := "001" & r.LastTgl & "0000" & x"00000000000000";
                        v.Proc   := PTx_s;
                    else
                        -- Initiate upload response (SD-UL-01)
                        Len_v := to_integer(unsigned(Rsp_Len));
                        if Len_v = 0 or Len_v > MaxBytes_c then
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortGeneral_c);
                        elsif Len_v <= 4 then
                            -- Expedited: e = 1, s = 1, n = 4 - the number of bytes
                            Val_v := (others => '0');

                            for J in 0 to 3 loop
                                if J < Len_v then
                                    Val_v(8 * J + 7 downto 8 * J) := Rsp_Data(8 * J + 7 downto 8 * J);
                                end if;
                            end loop;

                            v.TxData := frameMux("0100" & std_logic_vector(to_unsigned(4 - Len_v, 2)) & "11",
                                                 r.Index, r.Sub, Val_v);
                        else
                            -- Segmented: e = 0, s = 1, the size
                            v.TxData := frameMux(x"41", r.Index, r.Sub, std_logic_vector(to_unsigned(Len_v, 32)));
                            v.Xfer   := XUp_s;
                            v.Tgl    := '0';
                            v.Cnt    := (others => '0');
                            v.Size   := to_unsigned(Len_v, 4);
                            v.Buf    := Rsp_Data;
                        end if;
                        v.Proc := PTx_s;
                    end if;
                elsif RstE_v and not Take_v then
                    -- ocan_od ends an outstanding request at a reset event without an answer (OD-RS-02)
                    v.Proc := PIdle_s;
                elsif Quit_v then
                    -- The access is completed and its answer not used
                    v.Aborted := '1';
                end if;
                -- Bounded wait for the answer (SD-TX-04), which also ends the wait after an upset of AccTaken or
                -- Proc
                if v.Proc = PAcc_s and Tick_Ms = '1' then
                    if r.TxTmo >= AccTimeout_c - 1 then
                        v.ErrAcc := '1';
                        if r.Aborted = '1' or Quit_v then
                            v.Proc := PIdle_s;
                        else
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortGeneral_c);
                            v.Proc   := PTx_s;
                        end if;
                    else
                        v.TxTmo := r.TxTmo + 1;
                    end if;
                end if;

            when PTx_s =>
                if Tx_Ready = '1' then
                    if Tx_Aborted = '1' then
                        -- Reject path of ocan_dispatch: the transfer ends (SD-TX-03)
                        v.Proc := PIdle_s;
                        v.Xfer := XNone_s;
                    else
                        v.Proc  := PWait_s;
                        v.TxTmo := (others => '0');
                    end if;
                elsif Quit_v then
                    -- The offered reply is withdrawn
                    v.Proc := PIdle_s;
                end if;

            when PWait_s =>
                if Tx_Done = '1' then
                    v.Proc := PIdle_s;
                    if r.TxData(63 downto 61) = "100" then
                        v.EvtAbTx := '1';
                    end if;
                elsif Tx_Aborted = '1' then
                    -- The transfer ends (SD-TX-03)
                    v.Proc := PIdle_s;
                    v.Xfer := XNone_s;
                elsif Tick_Ms = '1' then
                    -- Bounded wait for the completion (SD-TX-02)
                    if r.TxTmo >= TxTimeout_c - 1 then
                        v.Proc   := PIdle_s;
                        v.ErrTmo := '1';
                    else
                        v.TxTmo := r.TxTmo + 1;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.Proc := PIdle_s;
                v.Xfer := XNone_s;
            -- coverage on

        end case;

        -- *** Request (architecture, section 4) ***
        if Rx_Valid = '1' then
            if unsigned(Rx_Dlc) < 8 then
                -- Not an SDO request (SD-PR-02)
                v.ErrDrop := '1';
            elsif Ccs_v = 4 then
                -- Abort of the client (SD-PR-07, SD-PR-09); ignored without a transfer and a processing
                if r.Xfer /= XNone_s or r.Proc /= PIdle_s then
                    v.EvtAbRx := '1';
                end if;
                v.Xfer := XNone_s;
            elsif r.Proc /= PIdle_s then
                -- One request at a time (SD-PR-09)
                v.ErrDrop := '1';
            else
                v.AccTaken := '0';
                v.Aborted  := '0';
                v.TxTmo    := (others => '0');
                v.Proc     := PTx_s;

                case Ccs_v is

                    when 1 =>
                        -- Initiate download: an open transfer ends (SD-PR-06)
                        v.Xfer  := XNone_s;
                        v.Index := Idx_v;
                        v.Sub   := Sub_v;
                        if B0_v(1) = '1' then
                            -- Expedited (SD-DL-01): 4 - n bytes with s = 1, not indicated with s = 0
                            v.AccWrite := '1';
                            v.AccData  := x"00000000" & value32(Rx_Data);
                            if B0_v(0) = '1' then
                                v.AccLen := std_logic_vector(to_unsigned(4 - to_integer(unsigned(B0_v(3 downto 2))), 4));
                            else
                                v.AccLen := "0000";
                            end if;
                            v.Kind := KDownExp_s;
                            v.Proc := PAcc_s;
                        else
                            -- Segmented (SD-DL-02)
                            Size_v := unsigned(value32(Rx_Data));
                            if B0_v(0) = '0' or Size_v = 0 then
                                v.TxData := frameMux(x"80", Idx_v, Sub_v, AbortMatch_c);
                            elsif Size_v > MaxBytes_c then
                                v.TxData := frameMux(x"80", Idx_v, Sub_v, AbortHigh_c);
                            else
                                v.Xfer   := XDown_s;
                                v.Tgl    := '0';
                                v.Cnt    := (others => '0');
                                v.Size   := Size_v(3 downto 0);
                                v.Buf    := (others => '0');
                                v.TxData := frameMux(x"60", Idx_v, Sub_v, x"00000000");
                            end if;
                        end if;

                    when 0 =>
                        -- Download segment (SD-DL-03, SD-DL-04): 7 - n data bytes
                        K_v   := 7 - to_integer(unsigned(B0_v(3 downto 1)));
                        New_v := to_integer(r.Cnt) + K_v;
                        if r.Xfer = XNone_s then
                            v.TxData := frameMux(x"80", x"0000", x"00", AbortCs_c);
                        elsif r.Xfer /= XDown_s then
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortCs_c);
                            v.Xfer   := XNone_s;
                        elsif B0_v(4) /= r.Tgl then
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortToggle_c);
                            v.Xfer   := XNone_s;
                        elsif New_v > MaxBytes_c then
                            -- Compared with the limit, also for a count above it (architecture, section 4)
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortMemory_c);
                            v.Xfer   := XNone_s;
                        else

                            for J in 0 to 6 loop
                                if J < K_v then
                                    P_v                               := New_v - K_v + J;
                                    v.Buf(8 * P_v + 7 downto 8 * P_v) := frameByte(Rx_Data, J + 1);
                                end if;
                            end loop;

                            v.Cnt := to_unsigned(New_v, 4);
                            v.Tgl := not r.Tgl;
                            if B0_v(0) = '0' then
                                v.TxData := "001" & B0_v(4) & "0000" & x"00000000000000";
                            else
                                -- Last segment: the transfer ends
                                v.Xfer := XNone_s;
                                if New_v /= to_integer(r.Size) then
                                    v.TxData := frameMux(x"80", r.Index, r.Sub, AbortMatch_c);
                                else
                                    v.AccWrite := '1';
                                    v.AccData  := v.Buf;
                                    v.AccLen   := std_logic_vector(to_unsigned(New_v, 4));
                                    v.Kind     := KDownLast_s;
                                    v.LastTgl  := B0_v(4);
                                    v.Proc     := PAcc_s;
                                end if;
                            end if;
                        end if;

                    when 2 =>
                        -- Initiate upload (SD-UL-01): an open transfer ends (SD-PR-06)
                        v.Xfer     := XNone_s;
                        v.Index    := Idx_v;
                        v.Sub      := Sub_v;
                        v.AccWrite := '0';
                        v.AccData  := (others => '0');
                        v.AccLen   := "0000";
                        v.Kind     := KUpInit_s;
                        v.Proc     := PAcc_s;

                    when 3 =>
                        -- Upload segment (SD-UL-02): the next up to 7 bytes
                        if r.Xfer = XNone_s then
                            v.TxData := frameMux(x"80", x"0000", x"00", AbortCs_c);
                        elsif r.Xfer /= XUp_s then
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortCs_c);
                            v.Xfer   := XNone_s;
                        elsif B0_v(4) /= r.Tgl then
                            v.TxData := frameMux(x"80", r.Index, r.Sub, AbortToggle_c);
                            v.Xfer   := XNone_s;
                        else
                            if r.Cnt >= r.Size then
                                Rem_v := 0;
                            else
                                Rem_v := to_integer(r.Size - r.Cnt);
                            end if;
                            if Rem_v >= 7 then
                                K_v := 7;
                            else
                                K_v := Rem_v;
                            end if;
                            Seg_v := (others => '0');

                            for J in 0 to 6 loop
                                if J < K_v and to_integer(r.Cnt) + J < MaxBytes_c then
                                    P_v                                 := to_integer(r.Cnt) + J;
                                    Seg_v(55 - 8 * J downto 48 - 8 * J) := r.Buf(8 * P_v + 7 downto 8 * P_v);
                                end if;
                            end loop;

                            Seg_v(63 downto 61) := "000";
                            Seg_v(60)           := B0_v(4);
                            Seg_v(59 downto 57) := std_logic_vector(to_unsigned(7 - K_v, 3));
                            if Rem_v <= 7 then
                                -- Last segment: the transfer ends
                                Seg_v(56) := '1';
                                v.Xfer    := XNone_s;
                            end if;
                            v.TxData := Seg_v;
                            v.Cnt    := r.Cnt + K_v;
                            v.Tgl    := not r.Tgl;
                        end if;

                    when others =>
                        -- Block transfer (5, 6) and 7 (SD-PR-03)
                        v.TxData := frameMux(x"80", Idx_v, Sub_v, AbortCs_c);
                        v.Xfer   := XNone_s;

                end case;

            end if;
        end if;

        -- *** SDO enable cleared (SD-RS-01) and reset events (SD-RS-02) ***
        if Stop_v or RstE_v then
            v.Xfer := XNone_s;
            if r.Proc /= PAcc_s then
                -- A new request ends here, an offered reply is withdrawn, a taken one is not awaited
                v.Proc := PIdle_s;
            end if;
        end if;

        -- *** assign signal ***
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    Tx_Valid  <= '1' when r.Proc = PTx_s else '0';
    Tx_Dlc    <= "1000";
    Tx_Data   <= r.TxData;
    Acc_Valid <= '1' when r.Proc = PAcc_s and r.AccTaken = '0' else '0';
    Acc_Write <= r.AccWrite;
    Acc_Index <= r.Index;
    Acc_Sub   <= r.Sub;
    Acc_Data  <= r.AccData;
    Acc_Len   <= r.AccLen;

    Stat_Open      <= '0' when r.Xfer = XNone_s else '1';
    Err_RxDrop     <= r.ErrDrop;
    Err_TxTimeout  <= r.ErrTmo;
    Err_AccTimeout <= r.ErrAcc;
    Evt_AbortTx    <= r.EvtAbTx;
    Evt_AbortRx    <= r.EvtAbRx;

    -----------------------------------------------------------------------------------------------
    -- Sequential process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Xfer     <= XNone_s;
                r.Tgl      <= '0';
                r.Cnt      <= (others => '0');
                r.Proc     <= PIdle_s;
                r.AccTaken <= '0';
                r.Aborted  <= '0';
                r.TxTmo    <= (others => '0');
                r.ErrDrop  <= '0';
                r.ErrTmo   <= '0';
                r.ErrAcc   <= '0';
                r.EvtAbTx  <= '0';
                r.EvtAbRx  <= '0';
            end if;
        end if;
    end process;

end architecture;
