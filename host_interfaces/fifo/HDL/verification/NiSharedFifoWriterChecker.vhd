-------------------------------------------------------------------------------
--
-- File: NiSharedFifoWriterChecker.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
--
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
--   A *simulation-only* monitor for the user (ViClk-domain) side of a
--   NiSharedFifoWriter instance. It asserts that the logic you hook up to the
--   Writer obeys the rules documented in fifo/docs/interface-descriptions.md.
--
--   This checker is embedded directly inside NiSharedFifoWriter, fenced by
--   `-- synthesis translate_off` / `-- synthesis translate_on`, so it runs
--   automatically in every simulation that instantiates the Writer and is
--   excluded from synthesis at zero hardware cost. You normally do not
--   instantiate it yourself; the standalone Usage example below is only for the
--   rare case where you replicate the Writer's user-side logic outside this
--   endpoint.
--
--   The checker is passive: it only reads the user-side signals and never drives
--   them. It is not synthesizable and must only be used in simulation.
--
--   A write commits to the FIFO on any cycle where vWriteFifo (the read/write
--   enable) and vInputValid (a sample is presented) are both asserted. vWriteFifo
--   is a continuous enable, not a one-cycle strobe: it may be held high across
--   many cycles while vInputValid pulses per sample. Writes are buffered into the
--   FIFO regardless of the stream state - the data simply does not drain to the
--   host until the stream is Enabled - so writing while the stream is not yet
--   Enabled is legal and not flagged here.
--
-- What it checks (all on the rising edge of ViClk, suppressed while aReset)
--     * A write (vWriteFifo and vInputValid) is not presented while vFull is true
--       (the sample would be dropped / overflow).
--     * vDataIn is not unknown (X/U) on a write cycle (vWriteFifo and vInputValid).
--     * Start and stop requests are not asserted on the same cycle, and no two
--       request strobes (start / stop / stop-with-flush) overlap.
--     * (optional, kCheckStrobePulse, OFF by default) the request signals are
--       one-cycle pulses and not held across consecutive cycles. This is a
--       stricter style check, not a protocol requirement: the start / stop /
--       stop-with-flush requests are crossed into the BusClk domain through a
--       HandshakeBool and the stop request is also consumed as a level, so
--       holding a request high for multiple cycles is legal and harmless.
--
-- Usage (standalone -- only needed if you replicate the user-side logic outside
-- NiSharedFifoWriter; otherwise the embedded instance already does this)
--   library work;
--     use work.PkgDmaPortCommIfcStreamStates.all;
--
--   WriterCheck : entity work.NiSharedFifoWriterChecker
--     generic map (
--       kName       => "WriterFifo",
--       kSampleWidth => kDataWidth * kNumOfSamplesPerWrite
--     )
--     port map (
--       ViClk                       => ViClk,
--       aReset                      => aDiagramReset,
--       vFull                       => vFull,
--       vWriteFifo                  => vWriteFifo,
--       vInputValid                 => vInputValid,
--       vDataIn                     => vDataIn,
--       vStreamStateOut             => vStreamStateOut,
--       vStartStreamRequest         => vStartStreamRequest,
--       vStopRequestStrobe          => vStopRequestStrobe,
--       vStopWithFlushRequestStrobe => vStopWithFlushRequestStrobe,
--       ViolationCount              => WriterViolations
--     );
--
--   assert WriterViolations = 0
--     report "Writer FIFO usage violations detected" severity failure;
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgDmaPortCommIfcStreamStates.all;

entity NiSharedFifoWriterChecker is
  generic(
    -- Prefix included in every assertion message.
    kName : string := "FifoWriter";

    -- Total width of vDataIn (kSampleWidth * kNumOfSamplesPerWrite). Used to size
    -- the monitored data port.
    kSampleWidth : positive := 32;

    -- Enable the stricter "request signals are one-cycle pulses" checks. OFF by
    -- default: the start / stop / stop-with-flush requests are crossed through a
    -- HandshakeBool CDC and may legally be held for multiple cycles.
    kCheckStrobePulse : boolean := false;

    -- Severity used when a violation is reported.
    kViolationSeverity : severity_level := error
  );
  port(
    ViClk  : in std_logic;

    -- Active-high reset for the user-side logic. While asserted, no checks run.
    aReset : in boolean;

    -- User-side (ViClk-domain) signals to monitor. Mirror the corresponding
    -- ports of the NiSharedFifoWriter instance under test.
    vFull                       : in boolean;
    vWriteFifo                  : in boolean;
    vInputValid                 : in boolean;
    vDataIn                     : in std_logic_vector(kSampleWidth - 1 downto 0);
    vStreamStateOut             : in StreamStateValue_t;
    vStartStreamRequest         : in boolean;
    vStopRequestStrobe          : in boolean;
    vStopWithFlushRequestStrobe : in boolean;

    -- Running count of violations seen since reset. Check it is 0 at end of test.
    ViolationCount : out natural
  );
end entity NiSharedFifoWriterChecker;

architecture sim of NiSharedFifoWriterChecker is

  -- Returns true if any bit is not a firm '0' or '1' (i.e. U/X/Z/W/-).
  function IsUnknown(v : std_logic_vector) return boolean is
  begin
    for i in v'range loop
      if v(i) /= '0' and v(i) /= '1' then
        return true;
      end if;
    end loop;
    return false;
  end function;

  signal PrevStart     : boolean := false;
  signal PrevStop      : boolean := false;
  signal PrevStopFlush : boolean := false;
  signal HaveHistory   : boolean := false;

  signal nViolations : natural := 0;

begin

  ViolationCount <= nViolations;

  Check : process(ViClk)
    variable inc : natural;
  begin
    if rising_edge(ViClk) then
      inc := 0;

      if not aReset then

        -- A write commits when vWriteFifo (enable) and vInputValid (sample
        -- presented) are both asserted. Presenting a sample while the FIFO is
        -- full drops it (overflow); the push hardware is gated by not-full.
        if vWriteFifo and vInputValid and vFull then
          report kName & ": a write (vWriteFifo and vInputValid) was presented "
               & "while vFull is true (the sample is dropped / overflow)."
            severity kViolationSeverity;
          inc := inc + 1;
        end if;

        -- Data must be known on a write cycle.
        if vWriteFifo and vInputValid and IsUnknown(vDataIn) then
          report kName & ": vDataIn is unknown (X/U) on a write cycle "
               & "(vWriteFifo and vInputValid asserted)."
            severity kViolationSeverity;
          inc := inc + 1;
        end if;

        -- At most one stream request per cycle.
        if (vStartStreamRequest and vStopRequestStrobe)
           or (vStartStreamRequest and vStopWithFlushRequestStrobe)
           or (vStopRequestStrobe and vStopWithFlushRequestStrobe) then
          report kName & ": more than one stream request asserted on the same "
               & "cycle (assert only one of start/stop/stop-with-flush)."
            severity kViolationSeverity;
          inc := inc + 1;
        end if;

        -- Request strobes must be one-cycle pulses.
        if kCheckStrobePulse and HaveHistory then
          if PrevStart and vStartStreamRequest then
            report kName & ": vStartStreamRequest held for more than one cycle "
                 & "(it must be a one-cycle strobe)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;
          if PrevStop and vStopRequestStrobe then
            report kName & ": vStopRequestStrobe held for more than one cycle "
                 & "(it must be a one-cycle strobe)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;
          if PrevStopFlush and vStopWithFlushRequestStrobe then
            report kName & ": vStopWithFlushRequestStrobe held for more than one "
                 & "cycle (it must be a one-cycle strobe)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;
        end if;

        nViolations <= nViolations + inc;
        HaveHistory <= true;
      else
        HaveHistory <= false;
      end if;

      PrevStart     <= vStartStreamRequest;
      PrevStop      <= vStopRequestStrobe;
      PrevStopFlush <= vStopWithFlushRequestStrobe;
    end if;
  end process Check;

end architecture sim;
