# HDL Shared

Reusable, host-facing HDL building blocks for custom NI FPGA designs, for use with the
[LabVIEW FPGA HDL Tools](https://github.com/ni/labview-fpga-hdl-tools).

> **Pre-release** — this code is not yet supported by NI. Use the
> [Issues](https://github.com/ni/flexrio-custom/issues) and
> [Discussions](https://github.com/ni/flexrio-custom/discussions) sections of the
> `flexrio-custom` repository to collaborate with the developers and other lead users.

---

## What is this?

`hdl-shared` is a library of HDL components that let a host PC communicate with custom
FPGA logic through the standard NI-RIO driver, **without** requiring LabVIEW FPGA. It
provides the two communication primitives most designs need:

- **Host registers** — 32-bit control/status registers that the host can read and write.
- **DMA FIFOs** — high-throughput streaming channels between host memory and the FPGA.

These are the same building blocks NI uses internally, packaged for direct instantiation
in your own VHDL. You drop them into a custom target's top-level HDL, wire them to your
logic, and access them from the host with the NI-RIO API (or the supplied LabVIEW host
VIs).

## How this relates to `flexrio-custom` (and other custom-target repos)

`hdl-shared` is a **dependency**, not a standalone project. You consume it from a
*custom-target* repository such as
[`flexrio-custom`](https://github.com/ni/flexrio-custom):

```
┌──────────────────────────────────────────────────────────────┐
│  flexrio-custom  (custom-target repo — start here)            │
│                                                              │
│   targets/pxie-7912custom/        ← a buildable FPGA target  │
│     rtl-lvfpga/UserHdl.vhd        ← YOUR logic + shared HDL  │
│     rtl-lvfpga/PkgUserHdl.vhd     ← YOUR FIFO/register config│
│     projectsettings.ini                                       │
│   dependencies.toml               ← declares the deps below  │
│   deps/                           ← populated by the tools   │
│     ├── hdl-shared/   ◄───────────┐  cloned from THIS repo   │
│     ├── flexrio/                  │                          │
│     └── flexrio-deps/  (support HDL the shared blocks need)  │
└──────────────────────────────────┼──────────────────────────┘
                                    │
              ┌─────────────────────┴──────────────────────────┐
              │  hdl-shared  (THIS repo)                        │
              │    host_interfaces/register/HDL/                │
              │    host_interfaces/fifo/HDL/                    │
              │    host_interfaces/register/LabVIEW/  (host VIs)│
              └────────────────────────────────────────────────┘
```

Any future custom-target repository integrates `hdl-shared` the same way: declare it in
`dependencies.toml`, let the tools clone it into `deps/`, and reference its HDL from the
target's file lists. **If you are just getting started, begin in `flexrio-custom`** and
follow its README — it walks you through installing the tools, cloning dependencies, and
building a bitfile.

---

## Repository layout

| Path | Contents |
|------|----------|
| `host_interfaces/register/` | Host register building blocks, testbench, host LabVIEW VIs, and docs. |
| `host_interfaces/fifo/` | DMA FIFO building blocks (`NiSharedFifoWriter`/`Reader`), config package, and docs. |
| `host_interfaces/common/` | Shared TCL helper scripts used by the simulation projects. |
| `dependencies.toml` | Declares this repo's own dependencies (support HDL + the HDL tools). |
| `deps/` | Dependencies cloned by the tools (e.g. `flexrio-deps`). Not checked in. |
| `nisetup.py` / `nisetup.bat` | Bootstrap a Python environment and install the HDL tools. |
| `docs/` | Repo-wide process docs (test & release). |

### What's inside — the building blocks

**Registers** (`host_interfaces/register/HDL/`)

| File | Role |
|------|------|
| `NiSharedHostRegister.vhd` | Core single 32-bit host-visible register, with optional read-only and FPGA acknowledge/ready gating. |
| `NiSharedHostRegisterArray.vhd` | A bank of N independent registers placed at `kBaseAddress + 4·i`, each individually configurable. |
| `NiSharedCommonHostRegs.vhd` | A standard 4-register block (Signature, Version, Oldest-Compatible-Version, Scratch) for design identity and bring-up. |
| `tb_NiSharedHostRegister.vhd` | Behavioral testbench for all three blocks. |

> See [host_interfaces/register/docs/README.md](host_interfaces/register/docs/README.md)
> for an overview, the [instantiation guide](host_interfaces/register/docs/instantiation-guide.md)
> for step-by-step usage, and
> [RegPort_Theory_of_Operation.md](host_interfaces/register/docs/RegPort_Theory_of_Operation.md)
> for the bus protocol.

**DMA FIFOs** (`host_interfaces/fifo/HDL/`)

| File | Role |
|------|------|
| `NiSharedFifoWriter.vhd` | Target-to-Host (FPGA → Host) streaming FIFO. |
| `NiSharedFifoReader.vhd` | Host-to-Target (Host → FPGA) streaming FIFO. |
| `PkgNiSharedFifo.vhd` | `UserDmaFifoConf_t` config record, `FifoDataType_t`, and the helpers that expand user config into full DMA channel settings. |

> See [host_interfaces/fifo/docs/README.md](host_interfaces/fifo/docs/README.md)
> for an overview, the [instantiation guide](host_interfaces/fifo/docs/instantiation-guide.md)
> for step-by-step usage, the
> [interface descriptions](host_interfaces/fifo/docs/interface-descriptions.md) for the
> port reference, and the
> [theory of operation](host_interfaces/fifo/docs/theory-of-operation.md) for the
> streaming model.

A complete worked example that combines registers **and** FIFOs in one design is the
`pxie-7912custom` target in `flexrio-custom`
(`targets/pxie-7912custom/rtl-lvfpga/UserHdl.vhd` and `PkgUserHdl.vhd`). The register and
FIFO guides above teach from that example.

---

## How the shared dependencies work

Dependencies are declared in [`dependencies.toml`](dependencies.toml) using PEP 440
version specifiers (the same syntax `pip install` uses):

```toml
github_dependencies = [
    "ni/flexrio-deps~=26.3.0.dev0",   # support HDL the shared blocks compile against
]

python_dependencies = [
    "labview-fpga-hdl-tools~=0.4.0",  # the `nihdl` CLI used to build/simulate
]
```

There are two kinds of dependency:

- **`python_dependencies`** — Python packages installed with `pip` (run `nisetup.py`, or
  `pip install -r requirements.txt` in a target). The key package is
  `labview-fpga-hdl-tools`, which provides the `nihdl` command used everywhere below.
- **`github_dependencies`** — other Git repositories cloned into `deps/` by
  `nihdl install-deps`. The shared HDL here does not implement everything from scratch; it
  compiles against support packages (`PkgNiUtilities`, `PkgCommunicationInterface`,
  `PkgCommIntConfiguration`, `PkgNiDma`, the DMA-port FIFO cores, …) that come from
  **`flexrio-deps`**. That is why `flexrio-deps` is a dependency even though it contains no
  user-facing components.

Version specifiers keep a custom target pinned to a compatible set of repositories:
`~=26.3.0` means "≥ 26.3.0 and < 26.4.0". When you check out a tagged release of a
custom-target repo, its `dependencies.toml` selects the matching shared HDL.

---

## Integrating `hdl-shared` into a custom target

When you build a target in `flexrio-custom`, the tools resolve and wire in `hdl-shared`
for you. The mechanics, so you can reproduce them in your own target:

1. **Declare the dependency.** The custom-target repo's top-level `dependencies.toml`
   lists `hdl-shared` alongside the other repos:

   ```toml
   dependencies = [
       "ni/flexrio~=26.2.0",
       "ni/flexrio-deps~=26.2.0",
       "ni/flexrio-clips~=26.2.2",
       "ni/hdl-shared~=0.2.0",
   ]
   ```

2. **Clone dependencies.** From inside a target folder, run:

   ```
   pip install -r requirements.txt   # installs the pinned labview-fpga-hdl-tools
   nihdl install-deps                # clones the repos above into ../../deps/
   ```

   This populates `deps/hdl-shared/`, `deps/flexrio/`, and `deps/flexrio-deps/`.

3. **Add the shared HDL to the project.** The target's HDL file lists reference the
   shared sources so the tools add them to the generated Vivado/ModelSim project. For
   `pxie-7912custom`, `vivadoprojectsources.txt` lists the register and FIFO sources:

   ```
   .../hdl-shared/host_interfaces/register/HDL/NiSharedHostRegister.vhd
   .../hdl-shared/host_interfaces/register/HDL/NiSharedCommonHostRegs.vhd
   .../hdl-shared/host_interfaces/register/HDL/NiSharedHostRegisterArray.vhd
   .../hdl-shared/host_interfaces/fifo/HDL/NiSharedFifoWriter.vhd
   .../hdl-shared/host_interfaces/fifo/HDL/NiSharedFifoReader.vhd
   .../hdl-shared/host_interfaces/fifo/HDL/PkgNiSharedFifo.vhd
   ...
   ```

   The FIFO blocks also need the encrypted DMA-port support cores from `flexrio-deps`;
   those are supplied by a separate FIFO-deps file list (e.g.
   `vivadoprojectfifodeps.txt`). You only need the FIFO deps if your design instantiates
   FIFOs; registers require only the `flexrio-deps` support packages.

4. **Provide the generated settings package.** Some shared blocks read project-wide
   settings from a generated `PkgNiHdlSettings` package:

   - `set_max_hdl_reg_offset` → `kMaxHdlRegOffset`: the highest byte offset reserved for
     HDL registers. Every register block self-checks its offset against this at
     elaboration, so an out-of-range register fails the build instead of silently
     colliding with LabVIEW FPGA's register space.
   - `set_num_hdl_fifos` → `kNumHdlFifos`: the number of user DMA FIFO channels, which
     must match the size of the `kUserHdlDmaFifoConf` array in `PkgUserHdl.vhd`.

   The tools generate `PkgNiHdlSettings.vhd` from these settings and add it to the project;
   your `PkgUserHdl.vhd` consumes it via `use work.PkgNiHdlSettings.all;`.

5. **Instantiate and configure.** Edit your target's `PkgUserHdl.vhd` to declare your
   registers and FIFOs, and `UserHdl.vhd` to instantiate the shared blocks. Follow the
   [register instantiation guide](host_interfaces/register/docs/instantiation-guide.md)
   and the [FIFO instantiation guide](host_interfaces/fifo/docs/instantiation-guide.md).

6. **Access from the host.** Build the bitfile in Vivado, then talk to your registers and
   FIFOs from the host with the NI-RIO API. Ready-made host VIs for register access live in
   `host_interfaces/register/LabVIEW/` (available in a target at
   `deps/hdl-shared/host_interfaces/register/LabVIEW/`).

---

## Simulating the shared HDL on its own

Each component family is also a self-contained simulation project so you can exercise the
blocks against their testbench without a full target build. From a component folder (for
example `host_interfaces/register/`):

```
nisetup.bat            # bootstrap the Python venv, install the HDL tools, activate the venv
nihdl install-deps     # clone GitHub dependencies into deps/
nihdl gen-modelsim     # create the ModelSim simulation project (add -o to recreate it)
nihdl launch-modelsim  # launch ModelSim and run the testbench (add --batch for headless)
```

Project settings (top entity, source file lists) live in that folder's `nihdlsettings.py`.
Run `nihdl --help` for the full command list.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). This project follows a fork-and-pull-request model
and requires signed-off commits (DCO).
