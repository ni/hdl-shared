-------------------------------------------------------------------------------
--
-- File: RegPortProtocolChecker.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
--
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
--   A *simulation-only* protocol monitor for the RegPort interface. It
--   continuously asserts that both sides honor the RegPort contract documented
--   in register/docs/RegPort_Theory_of_Operation.md.
--
--   This checker is embedded directly inside NiSharedHostRegister, fenced by
--   `-- synthesis translate_off` / `-- synthesis translate_on`, so every register
--   (bare, in an array, or via the common-regs block) self-checks its own
--   RegPort traffic in any simulation, with zero synthesis cost.
--
--   Instantiate it yourself only when you lift the RegPort state machine into
--   your own logic: a custom master (a state machine that drives bRegPortIn) or
--   a custom slave (logic that drives bRegPortOut instead of using
--   NiSharedHostRegister). Wire it on the same signals and any protocol
--   violation is reported with an assertion at the cycle it occurs.
--
--   The checker is passive: it only reads the bus signals and never drives them.
--   It is not synthesizable and must only be used in simulation.
--
-- What it checks
--   Master side (the side that drives bRegPortIn), enabled by kCheckMaster:
--     * Rd and Wt are never asserted on the same cycle (one transaction at a time).
--     * Address is not unknown (X/U) on the cycle Rd or Wt is asserted.
--     * Write Data is not unknown (X/U) on the cycle Wt is asserted.
--     * (optional, kCheckStrobePulse) Rd and Wt are each a one-cycle pulse and
--       are not held high across consecutive cycles.
--
--   Slave side (the side that drives bRegPortOut), enabled by kCheckSlave:
--     * Data is driven to all zeros whenever DataValid is false. This is required
--       so that multiple slaves can be OR-combined onto one bus.
--     * Ready is monotonic: once it has settled for a given Address it stays
--       asserted until the Address changes. A slave may de-assert Ready on the
--       single settling cycle right after an Address change to insert wait
--       states (e.g. NiSharedHostRegister with kUseFpgaAck), so a drop on that
--       cycle is allowed; monotonicity is enforced only afterward.
--     * Read Data is not unknown (X/U) on the cycle DataValid is asserted.
--     * (optional, kCheckStrobePulse) DataValid is a one-cycle pulse.
--
-- Usage (standalone -- only needed if you replicate the RegPort state machine
-- outside NiSharedHostRegister; otherwise the embedded instance already does this)
--   library work;
--     use work.PkgCommunicationInterface.all;
--
--   RegPortCheck : entity work.RegPortProtocolChecker
--     generic map (
--       kName => "MyRegPort"   -- prefix used in assertion messages
--     )
--     port map (
--       BusClk         => BusClk,
--       aReset         => aBusReset,      -- checks are suppressed while true
--       bRegPortIn     => bRegPortIn,
--       bRegPortOut    => bRegPortOut,
--       ViolationCount => RegPortViolations
--     );
--
--   -- At the end of the test:
--   assert RegPortViolations = 0
--     report "RegPort protocol violations detected" severity failure;
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgCommunicationInterface.all;

entity RegPortProtocolChecker is
  generic(
    -- Prefix included in every assertion message so multiple checker instances
    -- can be told apart.
    kName : string := "RegPort";

    -- Enable the checks that validate the master (the driver of bRegPortIn).
    kCheckMaster : boolean := true;

    -- Enable the checks that validate the slave (the driver of bRegPortOut).
    kCheckSlave : boolean := true;

    -- Enable the strict "strobes/valids are one-cycle pulses" checks. Disable if
    -- your master legitimately issues back-to-back single-cycle transactions on
    -- consecutive clocks.
    kCheckStrobePulse : boolean := true;

    -- Severity used when a violation is reported. Use 'failure' to halt the
    -- simulation on the first violation, or 'error'/'warning' to keep running.
    kViolationSeverity : severity_level := error
  );
  port(
    BusClk      : in  std_logic;

    -- Active-high reset. While asserted, no checks run (the bus is allowed to be
    -- in an undefined state during reset).
    aReset      : in  boolean;

    -- The RegPort interface to monitor (read only -- never driven by this block).
    bRegPortIn  : in  RegPortIn_t;
    bRegPortOut : in  RegPortOut_t;

    -- Running count of violations seen since reset. Check it is 0 at end of test.
    ViolationCount : out natural
  );
end entity RegPortProtocolChecker;

architecture sim of RegPortProtocolChecker is

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

  -- Registered history used for monotonic/pulse-duration checks.
  signal PrevAddress   : unsigned(bRegPortIn.Address'range) := (others => '0');
  signal PrevReady     : boolean := true;
  signal PrevRd        : boolean := false;
  signal PrevWt        : boolean := false;
  signal PrevDataValid : boolean := false;
  -- True when the Address was already stable on the previous cycle. Used to skip
  -- the monotonic-Ready check on the single settling cycle after an Address
  -- change (see the Ready check below).
  signal PrevAddressWasStable : boolean := false;
  signal HaveHistory   : boolean := false;

  -- All-zeros constant matching the read-data width, for the OR-combine check.
  constant kZeroData : std_logic_vector(bRegPortOut.Data'range) := (others => '0');

  signal nViolations : natural := 0;

begin

  ViolationCount <= nViolations;

  Check : process(BusClk)
    variable inc : natural;
  begin
    if rising_edge(BusClk) then
      inc := 0;

      if not aReset then

        -------------------------------------------------------------------
        -- Master-side checks (driver of bRegPortIn)
        -------------------------------------------------------------------
        if kCheckMaster then
          -- Rd and Wt are mutually exclusive.
          if bRegPortIn.Rd and bRegPortIn.Wt then
            report kName & ": Rd and Wt asserted on the same cycle "
                 & "(only one transaction at a time)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;

          -- Address must be known when a transaction is started.
          if (bRegPortIn.Rd or bRegPortIn.Wt)
             and IsUnknown(std_logic_vector(bRegPortIn.Address)) then
            report kName & ": Address is unknown (X/U) while Rd/Wt is asserted."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;

          -- Write data must be known when Wt is asserted.
          if bRegPortIn.Wt and IsUnknown(bRegPortIn.Data) then
            report kName & ": Write Data is unknown (X/U) while Wt is asserted."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;

          -- Strobes must be one-cycle pulses.
          if kCheckStrobePulse and HaveHistory then
            if PrevRd and bRegPortIn.Rd then
              report kName & ": Rd held asserted for more than one cycle "
                   & "(Rd must be a one-cycle pulse)."
                severity kViolationSeverity;
              inc := inc + 1;
            end if;
            if PrevWt and bRegPortIn.Wt then
              report kName & ": Wt held asserted for more than one cycle "
                   & "(Wt must be a one-cycle pulse)."
                severity kViolationSeverity;
              inc := inc + 1;
            end if;
          end if;
        end if;

        -------------------------------------------------------------------
        -- Slave-side checks (driver of bRegPortOut)
        -------------------------------------------------------------------
        if kCheckSlave then
          -- Data must be zero unless DataValid, so slaves can be OR-combined.
          if (not bRegPortOut.DataValid)
             and (bRegPortOut.Data /= kZeroData) then
            report kName & ": RegPortOut.Data is non-zero while DataValid is "
                 & "false (slaves must drive zeros for OR-combining)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;

          -- Read data must be known when DataValid is asserted.
          if bRegPortOut.DataValid and IsUnknown(bRegPortOut.Data) then
            report kName & ": Read Data is unknown (X/U) while DataValid is "
                 & "asserted."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;

          -- Ready must be monotonic while the Address is unchanged, but only
          -- after it has settled. The protocol allows Ready to settle up to one
          -- cycle after an Address change (RegPort_Theory_of_Operation.md Ready
          -- rule 1), so a de-assert on the first stable cycle is legal -- e.g. an
          -- FPGA-ack register (kUseFpgaAck) drops Ready the cycle after it is
          -- newly addressed to insert wait states. Enforce monotonicity only
          -- once the Address has been stable for two consecutive cycles, i.e.
          -- after that settling cycle has passed.
          if HaveHistory
             and (bRegPortIn.Address = PrevAddress)
             and PrevAddressWasStable
             and PrevReady and (not bRegPortOut.Ready) then
            report kName & ": Ready de-asserted while Address is stable after it "
                 & "had settled (Ready must stay asserted once settled for a "
                 & "stable Address)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;

          -- DataValid must be a one-cycle pulse.
          if kCheckStrobePulse and HaveHistory
             and PrevDataValid and bRegPortOut.DataValid then
            report kName & ": DataValid held asserted for more than one cycle "
                 & "(DataValid must be a one-cycle pulse)."
              severity kViolationSeverity;
            inc := inc + 1;
          end if;
        end if;

        nViolations <= nViolations + inc;
        HaveHistory <= true;
      else
        -- Hold history invalid across reset so post-reset edges aren't flagged.
        HaveHistory <= false;
      end if;

      -- Update history every clock (even during reset, so the first post-reset
      -- comparison uses a sane previous value once HaveHistory becomes true).
      PrevAddress         <= bRegPortIn.Address;
      PrevReady           <= bRegPortOut.Ready;
      PrevRd              <= bRegPortIn.Rd;
      PrevWt              <= bRegPortIn.Wt;
      PrevDataValid       <= bRegPortOut.DataValid;
      PrevAddressWasStable <= (bRegPortIn.Address = PrevAddress);
    end if;
  end process Check;

end architecture sim;
