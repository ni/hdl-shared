## Overview

This project contains shared HDL building blocks for **DMA FIFOs** plus the host-side
LabVIEW VIs used to stream data through them. The HDL blocks are instantiated in a custom
LabVIEW FPGA target, and the host streams data with the NI-RIO API (directly or through the
supplied VIs).

A DMA FIFO is the high-throughput counterpart to a register: instead of exchanging a single
32-bit value, it streams a continuous flow of elements between host memory and your FPGA
logic over PCIe. Two directional blocks plus a configuration package make up the family:

| Block | Use it for |
|-------|------------|
| `NiSharedFifoWriter` | Target-to-Host streaming (FPGA → Host). User HDL writes; the host reads via DMA. |
| `NiSharedFifoReader` | Host-to-Target streaming (Host → FPGA). The host writes via DMA; user HDL reads. |
| `PkgNiSharedFifo` | Config record (`UserDmaFifoConf_t`), the `FifoDataType_t` enum, and helpers that expand user config into full DMA channel settings. |

See the **[instantiation guide](instantiation-guide.md)** for step-by-step usage, the
**[interface descriptions](interface-descriptions.md)** for the full port lists, and the
**[theory of operation](theory-of-operation.md)** for the streaming model and DMA
architecture.

## Project files

### FPGA HDL Code

- `HDL/NiSharedFifoWriter.vhd`
	- Target-to-Host (FPGA → Host) streaming FIFO.
	- User HDL pushes data on the `ViClk`-domain interface; the host reads it via DMA.

- `HDL/NiSharedFifoReader.vhd`
	- Host-to-Target (Host → FPGA) streaming FIFO.
	- The host writes data via DMA; user HDL pops it on the `ViClk`-domain interface.

- `HDL/PkgNiSharedFifo.vhd`
	- `UserDmaFifoConf_t` configuration record and the `FifoDataType_t` enum.
	- `FifoDataWidth()` / `FifoDataIsSigned()` helpers and the functions that merge user
	  config into the system DMA channel array.

- `HDL/NiSharedFifoWriterCore.vhd`, `HDL/NiSharedFifoReaderCore.vhd`
	- Internal cores wrapped by the Writer/Reader blocks. You instantiate the wrappers, not these.

- `HDL/testbench/`
	- Behavioral testbenches (`tb_FifoWriter.vhd`, `tb_FifoReader.vhd`, `tb_all.vhd`) and
	  their support wrappers.

> **`kNumHdlFifos`** — the number of user DMA FIFO channels is a project-wide setting
> (`set_num_hdl_fifos`, surfaced as `kNumHdlFifos` in the generated `PkgNiHdlSettings`
> package). It must match the size of the `kUserHdlDmaFifoConf` array you declare in
> `PkgUserHdl.vhd`, so the channel count is checked instead of silently mismatching the
> host's DMA configuration.

### Documentation

- `docs/README.md`
	- This overview, the file map, and the simulation quick start.

- `docs/instantiation-guide.md`
	- Step-by-step guide to instantiating and using the FIFO blocks, with a worked example.

- `docs/interface-descriptions.md`
	- Full generic and port reference for the Writer and Reader blocks.

- `docs/theory-of-operation.md`
	- The DMA streaming model, channel configuration, and system architecture.

### Host LabVIEW Code

- `LabVIEW/`
	- Host-side VIs used with the NI-RIO host API to stream data through the FPGA FIFOs.

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

## Built-in protocol checkers

`HDL/verification/` contains passive, simulation-only monitors that assert the user-side
(`ViClk`-domain) interface rules from [interface-descriptions.md](interface-descriptions.md).

**You do not need to instantiate these yourself.** Each checker is embedded directly inside
its endpoint — `NiSharedFifoWriterChecker` in `NiSharedFifoWriter`, `NiSharedFifoReaderChecker`
in `NiSharedFifoReader` — wrapped in `-- synthesis translate_off` / `-- synthesis translate_on`.
So every consumer that instantiates a Writer or Reader gets the check automatically in any
simulation, and the monitor is fenced out of synthesis at zero hardware cost. If your user
logic misuses the interface, the violation is reported at the cycle it happens.

| Checker (embedded in) | Validates |
|-----------------------|-----------|
| `NiSharedFifoWriterChecker` (`NiSharedFifoWriter`) | A sample is not presented (`vWriteFifo`+`vInputValid`) while `vFull` (overflow); `vDataIn` is known on a write; at most one stream request per cycle. Optional: one-cycle request pulses (`kCheckStrobePulse`, **off** by default — requests cross a `HandshakeBool` and may be held). |
| `NiSharedFifoReaderChecker` (`NiSharedFifoReader`) | `vOutputValid` only asserts while Enabled; `vDataOut` is known when `vOutputValid`; at most one stream request per cycle. Optional: FIFO underflow (`kCheckUnderflow`, off) and one-cycle request pulses (`kCheckStrobePulse`, off). |

> `vWriteFifo` and `vReadFifo` are continuous *enables*, not one-cycle strobes — they
> may be held high, and reading while `vEmpty` / writing while not yet Enabled is
> legal (the FIFO buffers/gates internally). The checkers reflect this contract.

The embedded monitors never drive the interface, are excluded from synthesis by the
`translate_off` fence, and report violations at `kViolationSeverity` (default `error`). To
make a simulation hard-fail, run with assertion severity set to stop on `error`. The checker
entities remain available for direct instantiation if you ever replicate the user-side logic
outside these endpoints; see each file header in `HDL/verification/` for the full check list
and generics.
