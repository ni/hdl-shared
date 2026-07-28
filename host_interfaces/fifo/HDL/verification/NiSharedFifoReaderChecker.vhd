-------------------------------------------------------------------------------
--
-- File: NiSharedFifoReaderChecker.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
--
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
--   A *simulation-only* monitor for the user (ViClk-domain) side of a
--   NiSharedFifoReader instance. It asserts that the logic you hook up to the
--   Reader obeys the rules documented in fifo/docs/interface-descriptions.md.
--
--   This checker is embedded directly inside NiSharedFifoReader, fenced by
--   `-- synthesis translate_off` / `-- synthesis translate_on`, so it runs
--   automatically in every simulation that instantiates the Reader and is
--   excluded from synthesis at zero hardware cost. You normally do not
--   instantiate it yourself; the standalone Usage example below is only for the
--   rare case where you replicate the Reader's user-side logic outside this
--   endpoint.
--
--   The checker is passive: it only reads the user-side signals and never drives
--   them. It is not synthesizable and must only be used in simulation.
--
-- What it checks (all on the rising edge of ViClk, suppressed while aReset)
--     * vOutputValid is only asserted while the stream is Enabled (data must
--       not emerge from the FIFO outside the Enabled state).
--     * Start and stop requests are not asserted on the same cycle.
--     * (optional, kCheckStrobePulse, OFF by default) the request signals are
--       one-cycle pulses and not held across consecutive cycles. This is a
--       stricter style check, not a protocol requirement: vStartStreamRequest
--       and vStopRequestStrobe are crossed into the BusClk domain through a
--       HandshakeBool and the stop request is also consumed as a level, so
--       holding a request high for multiple cycles is legal and harmless.
--     * (optional, kCheckOutputData) vDataOut is not unknown (X/U) on the cycle
--       vOutputValid is asserted. This validates that captured data is well
--       defined when the consumer samples it.
--     * (optional, kCheckUnderflow) vReadyForOutput is not asserted while the
--       FIFO is empty. The reader is a request/valid interface: asserting the
--       read enable while empty is harmless (the pop is internally gated), but
--       claiming you will *consume* data (vReadyForOutput) while empty flags a
--       FIFO underflow, which disables the stream when kDisableOnFifoTimeout is
--       set. This check is off by default because continuously-ready consumers
--       legitimately tie vReadyForOutput high.
--
-- Note on vReadFifo: it is a continuous read *enable*, not a one-cycle strobe.
--   You may hold it asserted to stream data out every cycle, and you may assert
--   it while vEmpty is true (no data is lost; the pop is suppressed internally).
--   Wait for vOutputValid to know when vDataOut is valid. The checker therefore
--   does NOT flag read-while-empty or a held vReadFifo.
--
-- Usage (standalone -- only needed if you replicate the user-side logic outside
-- NiSharedFifoReader; otherwise the embedded instance already does this)
--   library work;
--     use work.PkgDmaPortCommIfcStreamStates.all;
--
--   ReaderCheck : entity work.NiSharedFifoReaderChecker
--     generic map (
--       kName        => "ReaderFifo",
--       kSampleWidth => kDataWidth * kNumOfSamplesPerRead
--     )
--     port map (
--       ViClk               => ViClk,
--       aReset              => aDiagramReset,
--       vEmpty              => vEmpty,
--       vReadFifo           => vReadFifo,
--       vOutputValid        => vOutputValid,
--       vReadyForOutput     => vReadyForOutput,
--       vDataOut            => vDataOut,
--       vStreamStateOut     => vStreamStateOut,
--       vStartStreamRequest => vStartStreamRequest,
--       vStopRequestStrobe  => vStopRequestStrobe,
--       ViolationCount      => ReaderViolations
--     );
--
--   assert ReaderViolations = 0
--     report "Reader FIFO usage violations detected" severity failure;
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgDmaPortCommIfcStreamStates.all;

entity NiSharedFifoReaderChecker is
  generic(
    -- Prefix included in every assertion message.
    kName : string := "FifoReader";

    -- Total width of vDataOut (kSampleWidth * kNumOfSamplesPerRead).
    kSampleWidth : positive := 32;

    -- Enable the stricter "request signals are one-cycle pulses" checks. OFF by
    -- default: vStartStreamRequest / vStopRequestStrobe are crossed through a
    -- HandshakeBool CDC and may legally be held for multiple cycles.
    kCheckStrobePulse : boolean := false;

    -- Enable checking that vDataOut is known when vOutputValid is asserted.
    kCheckOutputData : boolean := true;

    -- Enable the opt-in underflow check (vReadyForOutput asserted while empty).
    -- Off by default: consumers that are always ready tie vReadyForOutput high.
    kCheckUnderflow : boolean := false;

    -- Severity used when a violation is reported.
    kViolationSeverity : severity_level := error
  );
  port(
    ViClk  : in std_logic;

    -- Active-high reset for the user-side logic. While asserted, no checks run.
    aReset : in boolean;

    -- User-side (ViClk-domain) signals to monitor. Mirror the corresponding
    -- ports of the NiSharedFifoReader instance under test.
    vEmpty              : in boolean;
    vReadFifo           : in boolean;
    vOutputValid        : in boolean;
    vReadyForOutput     : in boolean;
    vDataOut            : in std_logic_vector(kSampleWidth - 1 downto 0);
    vStreamStateOut     : in StreamStateValue_t;
    vStartStreamRequest : in boolean;
    vStopRequestStrobe  : in boolean;

    -- Running count of violations seen since reset. Check it is 0 at end of test.
    ViolationCount : out natural
  );
end entity NiSharedFifoReaderChecker;

architecture sim of NiSharedFifoReaderChecker is

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

  signal PrevStart   : boolean := false;
  signal PrevStop    : boolean := false;
  signal HaveHistory : boolean := false;

  signal nViolations : natural := 0;

begin

  ViolationCount <= nViolations;

  Check : process(ViClk)
    variable inc : natural;
  begin
    if rising_edge(ViClk) then
      inc := 0;

      if not aReset then

        -- Data must only emerge while the stream is Enabled.
        if vOutputValid and (vStreamStateOut /= kStreamStateEnabled) then
          report kName & ": vOutputValid asserted while the stream is not Enabled "
               & "(vStreamStateOut /= kStreamStateEnabled)."
            severity kViolationSeverity;
          inc := inc + 1;
        end if;

        -- At most one stream request per cycle.
        if vStartStreamRequest and vStopRequestStrobe then
          report kName & ": vStartStreamRequest and vStopRequestStrobe asserted "
               & "on the same cycle (assert only one)."
            severity kViolationSeverity;
          inc := inc + 1;
        end if;

        -- Captured data must be known on the valid cycle.
        if kCheckOutputData and vOutputValid and IsUnknown(vDataOut) then
          report kName & ": vDataOut is unknown (X/U) while vOutputValid is "
               & "asserted."
            severity kViolationSeverity;
          inc := inc + 1;
        end if;

        -- Opt-in: claiming readiness to consume while empty flags an underflow.
        if kCheckUnderflow and vReadyForOutput and vEmpty then
          report kName & ": vReadyForOutput asserted while vEmpty is true "
               & "(this flags a FIFO underflow; with kDisableOnFifoTimeout the "
               & "stream will disable)."
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
        end if;

        nViolations <= nViolations + inc;
        HaveHistory <= true;
      else
        HaveHistory <= false;
      end if;

      PrevStart <= vStartStreamRequest;
      PrevStop  <= vStopRequestStrobe;
    end if;
  end process Check;

end architecture sim;
