## Overview
This project contains shared code for HDL-to-Host registers.  The HDL examples can be instantiated in custom LV FPGA targets and the LabVIEW VI's are used with the NI-RIO host API.

## Project files

### FPGA HDL Code

- `HDL/HdlSharedHostRegister.vhd`
	- Core single-register building block.
	- Implements one 32-bit host-visible register with optional host read-only behavior and optional FPGA acknowledgment/ready gating.

- `HDL/HdlSharedHostRegisterArray.vhd`
	- Multi-register wrapper around `HdlSharedHostRegister`.
	- Creates a register bank with configurable defaults and per-register behavior (`kReadOnly`, `kUseFpgaAck`).

- `HDL/HdlSharedCommonHostRegs.vhd`
	- Standard common register block intended for most designs.
	- Exposes fixed offsets for signature, version, oldest compatible version, and scratch.

- `HDL/tb_HdlSharedHostRegister.vhd`
	- Behavioral testbench covering single-register behavior, array behavior, and common-register behavior.

### Documentation

- `docs/README.md`
	- Quick start for environment setup and simulation flow.

- `docs/RegPort_Theory_of_Operation.md`
	- Detailed explanation of RegPort protocol semantics and timing.

### Host LabVIEW Code 

- `LabVIEW/`
	- Host-side VIs used with the NI-RIO host API to access the FPGA registers

## Simulation

You can use the LabVIEW FPGA HDL Tools to generate a Vivado project for simulation.

Install the LabVIEW FPGA HDL Tools:
pip install -r requirements.txt

Run these nihdl commands:
nihdl install-deps
nihdl create-project
nihdl launch-vivado

Then in Vivado, you can click Run Simulation to simulate the testbench

