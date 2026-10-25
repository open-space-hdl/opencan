---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network testbench of ocan_sdo: the model node M1 of the active bus is the SDO client of the node (NODE-ID 5) and
-- reads and writes objects of ocan_od through ocan_dispatch and ocan_link, on bus A and on bus B. Every reply is
-- compared on the bus with the frame of [CiA301] 7.2.4.3: identifier 580h + NODE-ID, DLC 8 and the data bytes.
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
    use work.ocan_tb_can_pkg.all;
    use work.ocan_tb_net_pkg.all;
    use work.ocan_tb_netobj_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ocan_sdo_net_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ocan_sdo_net_tb is

    -- SDO of NODE-ID 5: requests 600h + NODE-ID, replies 580h + NODE-ID
    constant ReqId_c : natural := 16#605#;
    constant RspId_c : natural := 16#585#;

    -- Bytes 1 to 7 of a segment with the 7 bytes of a SCET, least significant byte first (2001h, 2002h)
    function seg7 (s : std_logic_vector(55 downto 0)) return std_logic_vector is
        variable D_v : std_logic_vector(55 downto 0);
    begin

        for K in 0 to 6 loop
            D_v(55 - 8 * K downto 48 - 8 * K) := s(8 * K + 7 downto 8 * K);
        end loop;

        return D_v;
    end function;

    signal Clk            : std_logic;
    signal Rst            : std_logic := '1';
    signal Bus_Sel        : std_logic := '0';
    signal Stat_Open      : std_logic;
    signal Evt_AbortTx    : std_logic;
    signal Set_Valid      : std_logic;
    signal Set_Scet       : std_logic_vector(55 downto 0);
    signal Stat_ActiveBus : std_logic;

    signal CntSet  : natural                       := 0;
    signal CntAbTx : natural                       := 0;
    signal LastSet : std_logic_vector(55 downto 0) := (others => '0');

begin

    test_runner_watchdog(runner, 100 ms);

    i_th : entity work.ocan_sdo_net_th
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Bus_Sel        => Bus_Sel,
            Stat_Open      => Stat_Open,
            Evt_AbortTx    => Evt_AbortTx,
            Set_Valid      => Set_Valid,
            Set_Scet       => Set_Scet,
            Stat_ActiveBus => Stat_ActiveBus
        );

    p_mon : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Set_Valid = '1' then
                CntSet  <= CntSet + 1;
                LastSet <= Set_Scet;
            end if;
            if Evt_AbortTx = '1' then
                CntAbTx <= CntAbTx + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        -- Received frames with the identifier of the replies in the log of model node n
        impure function replies (n : natural) return natural is
            variable E_v : TbLog_t;
            variable C_v : natural := 0;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = RspId_c then
                    C_v := C_v + 1;
                end if;
            end loop;

            return C_v;
        end function;

        impure function lastReply (n : natural) return CanFrame_t is
            variable E_v : TbLog_t;
            variable F_v : CanFrame_t;
        begin

            for I in 0 to Net_v.logCount(n) - 1 loop
                E_v := Net_v.logGet(n, I);
                if E_v.Kind = TbFrame and not E_v.Own and
                   to_integer(unsigned(E_v.Frame.Id(28 downto 18))) = RspId_c then
                    F_v := E_v.Frame;
                end if;
            end loop;

            return F_v;
        end function;

        -- An SDO request of model node n and its reply, compared with exp
        procedure sdo (
            n   : natural;
            req : std_logic_vector(63 downto 0);
            exp : std_logic_vector(63 downto 0);
            msg : string) is
            variable C_v : natural;
            variable F_v : CanFrame_t;
            variable T_v : natural := 0;
        begin
            C_v := replies(n);
            Net_v.txPush(n, canStd(ReqId_c, 8, req));

            while replies(n) = C_v and T_v < 200 loop
                wait for 10 us;
                T_v := T_v + 1;
            end loop;

            check_value(replies(n), C_v + 1, ERROR, msg & ": one reply");
            F_v := lastReply(n);
            check_value(F_v.Ide, '0', ERROR, msg & ": 11-bit identifier");
            check_value(F_v.Dlc, 8, ERROR, msg & ": DLC");
            check_value(F_v.Data, exp, ERROR, msg & ": data");
        end procedure;

        variable M_v : natural;
        variable S_v : std_logic_vector(55 downto 0);
        variable H_v : std_logic_vector(7 downto 0);
        variable C_v : natural;
        variable A_v : natural;
    begin

        test_runner_setup(runner, runner_cfg);
        set_alert_stop_limit(ERROR, 0);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            -- *** TC-SD-17: SDO transfers on both buses ***
            if run("test_net_sdo") then
                Rst <= '1';
                wait for 250 ns;
                wait until rising_edge(Clk);
                Rst <= '0';

                for B in 0 to 1 loop
                    M_v := 2 * B;
                    if B = 1 then
                        Bus_Sel <= '1';
                    end if;
                    -- Integration of the controller on the bus
                    wait for 1 ms;
                    check_value(Stat_ActiveBus = '1', B = 1, ERROR, "active bus");
                    -- Expedited upload of 1018h sub-index 01h (Vendor-ID 8000 04D8h)
                    sdo(M_v, x"4018100100000000", x"43181001D8040080", "read 1018h sub-index 01h");
                    -- Expedited download and upload of 1017h (2 bytes)
                    H_v := std_logic_vector(to_unsigned(16#E8# + B, 8));
                    sdo(M_v, x"2B171000" & H_v & x"030000", x"6017100000000000", "write 1017h");
                    sdo(M_v, x"4017100000000000", x"4B171000" & H_v & x"030000", "read 1017h");
                    -- Expedited download without the size (s = 0) to 2000h sub-index 02h (1 byte)
                    H_v := std_logic_vector(to_unsigned(16#07# + B, 8));
                    sdo(M_v, x"22002002" & H_v & x"000000", x"6000200200000000", "write 2000h sub-index 02h, s = 0");
                    sdo(M_v, x"4000200200000000", x"4F002002" & H_v & x"000000", "read 2000h sub-index 02h");
                    -- Segmented download of 2001h (7 bytes), segmented upload of 2002h
                    S_v := x"1A2B3C4D5E6F70" xor std_logic_vector(to_unsigned(B, 56));
                    C_v := CntSet;
                    sdo(M_v, x"2101200007000000", x"6001200000000000", "initiate download of 2001h");
                    check_value(Stat_Open, '1', ERROR, "segmented download open");
                    sdo(M_v, x"01" & seg7(S_v), x"2000000000000000", "download segment of 2001h");
                    check_value(CntSet, C_v + 1, ERROR, "one write of Local SCET Set");
                    check_value(LastSet, S_v, ERROR, "value of Local SCET Set");
                    sdo(M_v, x"4002200000000000", x"4102200007000000", "initiate upload of 2002h");
                    sdo(M_v, x"6000000000000000", x"01" & seg7(S_v), "upload segment of 2002h");
                    check_value(Stat_Open, '0', ERROR, "no transfer after the last segment");
                    -- An absent object
                    A_v := CntAbTx;
                    sdo(M_v, x"40FF1F0000000000", x"80FF1F0000000206", "read the absent object 1FFFh");
                    wait for 10 us;
                    check_value(CntAbTx, A_v + 1, ERROR, "Evt_AbortTx of the abort frame sent");
                end loop;

            end if;

        end loop;

        ocanTestEnd(runner);
        wait;
    end process;

end architecture;
