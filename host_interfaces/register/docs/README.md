## Overview

This project contains shared HDL building blocks for **host-visible registers** plus the
host-side LabVIEW VIs used to access them. The HDL blocks are instantiated in a custom
LabVIEW FPGA target, and the host reads/writes the registers with the NI-RIO API (directly
or through the supplied VIs).

A register is the simplest way for a host and your FPGA logic to exchange small amounts of
control and status: the host writes a 32-bit value at an address, your logic reacts; your
logic updates a 32-bit value, the host reads it back. Three blocks build on each other:

| Block | Use it for |
|-------|------------|
| `NiSharedHostRegister` | A single 32-bit register. The fundamental building block. |
| `NiSharedHostRegisterArray` | A contiguous bank of N registers, each individually read-only/writable. |
| `NiSharedCommonHostRegs` | A standard identity block (Signature/Version/OldestCompatible/Scratch) every design should include. |

See the **[instantiation guide](instantiation-guide.md)** for step-by-step usage and the
**[RegPort theory of operation](RegPort_Theory_of_Operation.md)** for the bus protocol and
timing.

## Project files

### FPGA HDL Code

- `HDL/NiSharedHostRegister.vhd`
	- Core single-register building block.
	- Implements one 32-bit host-visible register with optional host read-only behavior and optional FPGA acknowledgment/ready gating.
	- Host access is via `RegPortIn`/`RegPortOut`; FPGA-side access is via the `bFpga*` ports.

- `HDL/NiSharedHostRegisterArray.vhd`
	- Multi-register wrapper around `NiSharedHostRegister`.
	- Creates a register bank at `kBaseAddress + 4·i` with configurable defaults and per-register behavior (`kReadOnly`, `kUseFpgaAck`).

- `HDL/NiSharedCommonHostRegs.vhd`
	- Standard common register block intended for most designs.
	- Exposes fixed offsets for signature, version, oldest compatible version, and scratch.

- `HDL/tb_NiSharedHostRegister.vhd`
	- Behavioral testbench covering single-register behavior, array behavior, and common-register behavior.

> **`kMaxHdlRegOffset`** — every register block takes a `kMaxHdlRegOffset` generic and
> asserts at elaboration that its byte offset fits within the HDL register space the
> LabVIEW FPGA target reserves. This value comes from the project's
> `set_max_hdl_reg_offset` setting (surfaced as `kMaxHdlRegOffset` in the generated
> `PkgNiHdlSettings` package). An out-of-range register fails the build instead of silently
> colliding with LabVIEW FPGA register space.

### Documentation

- `docs/README.md`
	- This overview, the file map, and the simulation quick start.

- `docs/instantiation-guide.md`
	- Step-by-step guide to instantiating and using the register blocks, with a worked example.

- `docs/RegPort_Theory_of_Operation.md`
	- Detailed explanation of RegPort protocol semantics and timing.

### Host LabVIEW Code

- `LabVIEW/`
	- Host-side VIs used with the NI-RIO host API to access the FPGA registers.

## Simulation

You can use the LabVIEW FPGA HDL Tools to generate a ModelSim project for simulation.

Install the LabVIEW FPGA HDL Tools (bootstraps a Python venv, installs the tools, and
activates the environment):
* nisetup.bat

Run these nihdl commands:
* nihdl install-deps    — clone GitHub dependencies into deps/
* nihdl gen-modelsim    — create the ModelSim project (add -o to recreate it)
* nihdl launch-modelsim — launch ModelSim and run the testbench (add --batch for headless)

Run `nihdl --help` for the full command list.

## Built-in protocol checker

`HDL/verification/RegPortProtocolChecker.vhd` is a passive, simulation-only monitor that
continuously asserts that both sides honor the RegPort contract.

It is **embedded directly inside `NiSharedHostRegister`**, wrapped in `-- synthesis
translate_off` / `-- synthesis translate_on`. So every register you instantiate — bare, in
an array, or via the common-regs block — self-checks its own RegPort traffic in any
simulation, and the monitor is fenced out of synthesis at zero hardware cost. No testbench
wiring is required.

It flags, at the cycle they occur: `Rd`/`Wt` asserted together, unknown Address/Data during
a strobe, non-zero `Data` while `DataValid` is false (the OR-combine rule), non-monotonic
`Ready` (after it has settled — a one-cycle settle after an Address change is allowed, e.g.
the `kUseFpgaAck` wait-state), and over-long strobe/valid pulses.

**If you lift the RegPort state machine into your own logic** (a custom master driving
`bRegPortIn`, or a custom slave driving `bRegPortOut` instead of using `NiSharedHostRegister`),
the embedded checker can't follow you — instantiate it yourself on those signals:

```vhdl
RegPortCheck : entity work.RegPortProtocolChecker
  generic map ( kName => "MyRegPort" )
  port map (
    BusClk         => BusClk,
    aReset         => aBusReset,
    bRegPortIn     => bRegPortIn,
    bRegPortOut    => bRegPortOut,
    ViolationCount => RegPortViolations
  );

-- At the end of the test:
assert RegPortViolations = 0
  report "RegPort protocol violations detected" severity failure;
```

The block never drives the bus, is excluded from synthesis by the `translate_off` fence, and
reports violations at `kViolationSeverity` (default `error`). See the file header for the full
check list and generics (`kCheckMaster`, `kCheckSlave`, `kCheckStrobePulse`).

