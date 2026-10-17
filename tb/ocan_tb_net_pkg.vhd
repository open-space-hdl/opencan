---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Control object of the CAN network model: per model node (ocan_tb_can_node) the configuration, the transmit
-- queue, the fault injection and the log of every frame and error the node observed on its bus. The object itself
-- is the shared variable Net_v of ocan_tb_netobj_pkg.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ocan_tb_can_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ocan_tb_net_pkg is

    -- Maximum number of model nodes in one testbench
    constant TbNodes_c : positive := 8;

    -- Configuration of a model node
    type TbNodeCfg_t is record
        BitPeriod  : time;    -- nominal bit time
        Ppm        : integer; -- deviation of the bit time of the node in ppm (positive: longer)
        SamplePct  : natural; -- sample point in percent of the bit time
        Ack        : boolean; -- acknowledge correctly received frames
        Listen     : boolean; -- never drive the bus
        EarlyStart : boolean; -- start a pending frame in the third bit of the intermission
        RecDelay   : time;    -- delay of the dominant-to-recessive edges the node drives
    end record;

    constant TbNodeCfgInit_c : TbNodeCfg_t := (BitPeriod => 1 us, Ppm => 0, SamplePct => 75, Ack => true,
                                               Listen => false, EarlyStart => false, RecDelay => 0 ns);

    -- Log entries
    type TbLogKind_t is (TbFrame, TbError, TbOverload);

    type TbErrKind_t is (
        TbErrNone,
        TbErrBit,     -- bit error (also a dominant bit in the acknowledge slot is not one)
        TbErrStuff,   -- six equal bits in the stuffed part of a frame
        TbErrCrc,     -- CRC sequence does not match
        TbErrForm,    -- dominant bit in a delimiter or in the end of frame
        TbErrAck,     -- transmitter: acknowledge slot recessive
        TbErrInjected -- error flag sent by fault injection
    );

    type TbLog_t is record
        Kind   : TbLogKind_t;
        Frame  : CanFrame_t;  -- decoded frame (TbFrame)
        Own    : boolean;     -- the node sent the frame
        Acked  : boolean;     -- the acknowledge slot was dominant
        Err    : TbErrKind_t; -- error (TbError)
        ErrBit : natural;     -- stuffed bit index from the start of frame at which the error was detected
        T      : time;        -- sample point at which the frame was valid or the error was detected
    end record;

    -- Counters
    type TbCount_t is (TbCntSent, TbCntArbLost, TbCntErrors, TbCntRxFrames, TbCntOverloads);

    type TbNet_t is protected

        -- Configuration
        procedure setCfg (
            idx : natural;
            cfg : TbNodeCfg_t);
        impure function getCfg (idx : natural) return TbNodeCfg_t;

        -- Transmit queue: the head is sent (and retransmitted after a lost arbitration or an error) until it is sent
        procedure txPush (
            idx   : natural;
            frame : CanFrame_t);
        impure function txCount (idx : natural) return natural;
        impure function txPeek (idx : natural) return CanFrame_t;

        procedure txPop (idx : natural);

        procedure txClear (idx : natural);

        -- Fault injection. Error flag: for the next count frames that the node receives (not sends) and whose
        -- identifier is id (-1: any), the node sends an active error flag that starts at stuffed bit index bitIdx.
        procedure setErrFlag (
            idx    : natural;
            bitIdx : natural;
            count  : natural;
            id     : integer := -1);
        impure function errFlagBit (idx : natural) return integer;
        impure function errFlagId (idx : natural) return integer;

        procedure useErrFlag (idx : natural);

        -- Corruption of the node's own frames: stuffed bit bitIdx is sent inverted in the next count frames
        procedure setCorrupt (
            idx    : natural;
            bitIdx : natural;
            count  : natural);
        impure function corruptBit (idx : natural) return integer;

        procedure useCorrupt (idx : natural);

        -- Overload flag in the first bit of the intermission after the next count frames
        procedure setOverload (
            idx   : natural;
            count : natural);
        impure function takeOverload (idx : natural) return boolean;

        -- Log
        procedure logPush (
            idx   : natural;
            entry : TbLog_t);
        impure function logCount (idx : natural) return natural;
        impure function logGet (
            idx : natural;
            n   : natural) return TbLog_t;

        procedure logClear (idx : natural);

        -- Counters
        procedure countUp (
            idx : natural;
            cnt : TbCount_t);
        impure function count (
            idx : natural;
            cnt : TbCount_t) return natural;

    end protected;

    function tbErrImage (err : TbErrKind_t) return string;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ocan_tb_net_pkg is

    function tbErrImage (err : TbErrKind_t) return string is
    begin
        return TbErrKind_t'image(err);
    end function;

    type TbNet_t is protected body

        constant QueueSize_c : positive := 64;
        constant LogSize_c   : positive := 4096;

        type CfgArray_t is array (0 to TbNodes_c - 1) of TbNodeCfg_t;
        type FrameQueue_t is array (0 to QueueSize_c - 1) of CanFrame_t;
        type FrameQueues_t is array (0 to TbNodes_c - 1) of FrameQueue_t;
        type LogArray_t is array (0 to LogSize_c - 1) of TbLog_t;
        type LogArrayPtr_t is access LogArray_t;
        type LogArrays_t is array (0 to TbNodes_c - 1) of LogArrayPtr_t;
        type NatArray_t is array (0 to TbNodes_c - 1) of natural;
        type IntArray_t is array (0 to TbNodes_c - 1) of integer;
        type CountArray_t is array (0 to TbNodes_c - 1, TbCount_t) of natural;

        variable Cfg_v       : CfgArray_t   := (others => TbNodeCfgInit_c);
        variable Queue_v     : FrameQueues_t;
        variable QHead_v     : NatArray_t   := (others => 0);
        variable QCount_v    : NatArray_t   := (others => 0);
        variable Log_v       : LogArrays_t  := (others => null);
        variable LogCount_v  : NatArray_t   := (others => 0);
        variable FlagBit_v   : IntArray_t   := (others => -1);
        variable FlagCount_v : NatArray_t   := (others => 0);
        variable FlagId_v    : IntArray_t   := (others => -1);
        variable CorrBit_v   : IntArray_t   := (others => -1);
        variable CorrCount_v : NatArray_t   := (others => 0);
        variable OvlCount_v  : NatArray_t   := (others => 0);
        variable Count_v     : CountArray_t := (others => (others => 0));

        procedure setCfg (
            idx : natural;
            cfg : TbNodeCfg_t) is
        begin
            Cfg_v(idx) := cfg;
        end procedure;

        impure function getCfg (idx : natural) return TbNodeCfg_t is
        begin
            return Cfg_v(idx);
        end function;

        procedure txPush (
            idx   : natural;
            frame : CanFrame_t) is
        begin
            assert QCount_v(idx) < QueueSize_c
                report "ocan_tb_net_pkg: transmit queue of node " & integer'image(idx) & " full"
                severity failure;
            Queue_v(idx)((QHead_v(idx) + QCount_v(idx)) mod QueueSize_c) := canNormalize(frame);
            QCount_v(idx)                                                := QCount_v(idx) + 1;
        end procedure;

        impure function txCount (idx : natural) return natural is
        begin
            return QCount_v(idx);
        end function;

        impure function txPeek (idx : natural) return CanFrame_t is
        begin
            return Queue_v(idx)(QHead_v(idx));
        end function;

        procedure txPop (idx : natural) is
        begin
            if QCount_v(idx) > 0 then
                QHead_v(idx)  := (QHead_v(idx) + 1) mod QueueSize_c;
                QCount_v(idx) := QCount_v(idx) - 1;
            end if;
        end procedure;

        procedure txClear (idx : natural) is
        begin
            QCount_v(idx) := 0;
        end procedure;

        procedure setErrFlag (
            idx    : natural;
            bitIdx : natural;
            count  : natural;
            id     : integer := -1) is
        begin
            FlagBit_v(idx)   := bitIdx;
            FlagCount_v(idx) := count;
            FlagId_v(idx)    := id;
        end procedure;

        impure function errFlagBit (idx : natural) return integer is
        begin
            if FlagCount_v(idx) > 0 then
                return FlagBit_v(idx);
            else
                return -1;
            end if;
        end function;

        impure function errFlagId (idx : natural) return integer is
        begin
            return FlagId_v(idx);
        end function;

        procedure useErrFlag (idx : natural) is
        begin
            if FlagCount_v(idx) > 0 then
                FlagCount_v(idx) := FlagCount_v(idx) - 1;
            end if;
        end procedure;

        procedure setCorrupt (
            idx    : natural;
            bitIdx : natural;
            count  : natural) is
        begin
            CorrBit_v(idx)   := bitIdx;
            CorrCount_v(idx) := count;
        end procedure;

        impure function corruptBit (idx : natural) return integer is
        begin
            if CorrCount_v(idx) > 0 then
                return CorrBit_v(idx);
            else
                return -1;
            end if;
        end function;

        procedure useCorrupt (idx : natural) is
        begin
            if CorrCount_v(idx) > 0 then
                CorrCount_v(idx) := CorrCount_v(idx) - 1;
            end if;
        end procedure;

        procedure setOverload (
            idx   : natural;
            count : natural) is
        begin
            OvlCount_v(idx) := count;
        end procedure;

        impure function takeOverload (idx : natural) return boolean is
        begin
            if OvlCount_v(idx) > 0 then
                OvlCount_v(idx) := OvlCount_v(idx) - 1;
                return true;
            else
                return false;
            end if;
        end function;

        procedure logPush (
            idx   : natural;
            entry : TbLog_t) is
        begin
            if Log_v(idx) = null then
                Log_v(idx) := new LogArray_t;
            end if;
            assert LogCount_v(idx) < LogSize_c
                report "ocan_tb_net_pkg: log of node " & integer'image(idx) & " full"
                severity failure;
            Log_v(idx)(LogCount_v(idx)) := entry;
            LogCount_v(idx)             := LogCount_v(idx) + 1;
        end procedure;

        impure function logCount (idx : natural) return natural is
        begin
            return LogCount_v(idx);
        end function;

        impure function logGet (
            idx : natural;
            n   : natural) return TbLog_t is
        begin
            assert n < LogCount_v(idx)
                report "ocan_tb_net_pkg: log entry " & integer'image(n) & " of node " & integer'image(idx) &
                       " does not exist"
                severity failure;
            return Log_v(idx)(n);
        end function;

        procedure logClear (idx : natural) is
        begin
            LogCount_v(idx) := 0;
        end procedure;

        procedure countUp (
            idx : natural;
            cnt : TbCount_t) is
        begin
            Count_v(idx, cnt) := Count_v(idx, cnt) + 1;
        end procedure;

        impure function count (
            idx : natural;
            cnt : TbCount_t) return natural is
        begin
            return Count_v(idx, cnt);
        end function;

    end protected body;

end package body;
