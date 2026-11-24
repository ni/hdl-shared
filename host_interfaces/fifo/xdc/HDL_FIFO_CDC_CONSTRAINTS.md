# HDL Shared FIFO CDC Constraints

## Overview

When NI FlexRIO FPGAs use HDL Shared FIFOs (`NiSharedFifoWriter` and
`NiSharedFifoReader`), the FIFO logic crosses between two clock
domains:

| Side | FIFO port | Driven by (`UserHdl`) | Frequency | Nominal Period | Effective Period | Tcl variable |
|------|-----------|-----------------------|-----------|----------------|------------------|--------------|
| DMA  | `BusClk`  | `DmaClk`              | 250 MHz   | 4.000 ns       | 3.7496 ns        | `hdl_dmaclk_T` |
| user | `ViClk`   | target `BusClk` (PllClk80) | 80 MHz | 12.500 ns    | 12.2488 ns       | `hdl_userclk_T` |

**Clock naming.** The FIFO's `BusClk` port is driven by the 250 MHz **`DmaClk`**,
*not* by the target's `BusClk`; the FIFO's `ViClk` port is driven by the target's
80 MHz `BusClk` (PllClk80). To avoid that collision, this document and the
generated XDC never use the bare names for a clock. They say **DMA** for the
FIFO `BusClk`-port side and **user** for the FIFO `ViClk`-port side, and the Tcl
period variables are named after the clock (`hdl_dmaclk_T`, `hdl_userclk_T`).
See [Clock Domains](../docs/theory-of-operation.md#clock-domains).

> ⚠️ **REQUIREMENT: every FIFO's `ViClk` port must be driven by an 80 MHz clock**
> (the target's `BusClk` / PllClk80), and its `BusClk` port by the 250 MHz `DmaClk`.
> The periods in `hdl_fifo_cdc_constraints.xdc` are hard-coded and nothing checks them
> against the design. With any other `ViClk` frequency the constraints are **silently
> wrong**: Vivado reports no error, and a faster `ViClk` leaves the FIFO's clock-domain
> crossings under-constrained (second synchronizer stages and multi-bit pointer data are
> allowed more delay than the clock can tolerate). A slower `ViClk` is merely
> over-constrained.
>
> A target that cannot meet this requirement must not use the shared XDC; it would need
> its own copy generated with `USER_FREQ_HZ` set to its real `ViClk` frequency (and only
> works if all of its FIFOs share that frequency).

The FIFO contains multiple CDC (Clock Domain Crossing) synchronizers that
require explicit timing constraints.  Without these constraints, Vivado's
timing analysis treats the CDC paths as regular single-clock paths and may
report false violations or, worse, silently allow unsafe timing.

The constraint generator `gen_constraints.py` produces per-flip-flop
`set_max_delay -datapath_only` constraints that target the exact synchronizer
registers inside each CDC building block.

---

## File Inventory

| File | Purpose |
|------|---------|
| `gen_constraints.py` | Python script that generates the XDC constraint block |
| `hdl_fifo_cdc_constraints.xdc` | The generated CDC constraint file, sourced by the Vivado flow |

---

## How to Use

**In the common case you do nothing.** `hdl_fifo_cdc_constraints.xdc` is
pre-generated and checked in. It targets the CDC synchronizers inside
`NiSharedFifoWriterCore` / `NiSharedFifoReaderCore` with wildcard-prefixed
patterns, so it applies at any hierarchy depth in any target that instantiates
the shared FIFO blocks — **provided every FIFO's `ViClk` is 80 MHz and its
`BusClk` is the 250 MHz `DmaClk`** (see the requirement above).

### Consuming the constraints in a custom target

Reference the checked-in file **in place** (do not copy it) from the target's
`nihdlsettings.py`. For example, in a `flexrio-custom` target:

```python
config.add_custom_constraints(
    "../../deps/hdl-shared/host_interfaces/fifo/xdc/hdl_fifo_cdc_constraints.xdc",
    order=1,
)
```

The tools fold it into the generated constraint set and it is evaluated during
the normal Vivado / LabVIEW FPGA compile. Nothing else is required for the FIFO
CDC paths to be constrained correctly.

### Regenerating (only if you change the FIFO HDL or want custom behavior)

Re-run the generator only when you modify the shared FIFO RTL (adding or renaming
CDC synchronizers) or want to customize the constraints. Write the result back
over the checked-in file and commit it:

```
python gen_constraints.py -o hdl_fifo_cdc_constraints.xdc
```

(The script's default output path points at `../objects/xdc/` for build-time
generation; pass `-o hdl_fifo_cdc_constraints.xdc` to update the committed copy in
this folder.) If your design instantiates the FIFO cores under different instance
names, update `WRITER_FIFOS` / `READER_FIFOS` at the top of the script first.

### Compile

Run the normal Vivado compile flow. The constraints are evaluated during
`link_design` as part of the standard XDC parsing.

---

## Constraint Style

```tcl
set_max_delay -datapath_only $period \
  -from [get_cells -quiet -hierarchical -filter {NAME =~ *pattern* && IS_SEQUENTIAL}] \
  -to   [get_cells -quiet -hierarchical -filter {NAME =~ *pattern* && IS_SEQUENTIAL}]
```

Key aspects:

- **`get_cells -hierarchical -filter {NAME =~ ...}`**: Matches sequential
  cells by full hierarchical name. With `NAME =~`, `*` matches any characters
  **including** the hierarchy separator `/`, so a leading `*` absorbs whatever
  hierarchy wraps the FIFO and trailing `*` reaches synchronizer flops nested
  inside `DFlop` wrappers (e.g. `.../BlkIn.iPushTogglex/DFlopx/GenClr.ClearFDCPEx`).

  > **Do not** use the plain `get_cells {pattern}` form. It only works when
  > the design is synthesized with `-flatten_hierarchy full` (as the LabVIEW
  > FPGA target flow currently does). With hierarchy preserved, its `*` does
  > *not* cross `/`, so a leading `*` cannot match
  > `UserHdl_inst/ReaderFifo_inst/` and nested flops are never reached; with
  > `-quiet`, those constraints then silently match nothing.

- **`-quiet`**: Only suppresses the `get_cells` "no match" warning. An empty
  `-from`/`-to` still produces `CRITICAL WARNING: [Vivado 12-4739]` from
  `set_max_delay`, so unexpected misses remain visible in the build log.

- **`-datapath_only`**: Constrains only the data path delay, not the clock
  path.  This is correct for CDC synchronizers where the source and
  destination clocks are asynchronous.

- **No `set` variables for cell groups**: Each `set_max_delay` uses an inline
  `get_cells` call.  This avoids Tcl variable scoping issues.

---

## CDC Building Blocks

The HDL Shared FIFO contains six types of CDC synchronizer primitives.  Each
has a corresponding emitter function in `gen_constraints.py`.

### HandshakeBool (`emit_HB`)

A toggle-only handshake with **no data payload**.  Used by `StreamStateBlock`
for simple request/acknowledge signaling.

```
  Source (IClk)              Destination (OClk)
  ┌──────────────┐           ┌──────────────────────┐
  │ iPushToggle  │──CDC──>│ oPushToggle0_ms (1st) │
  │              │           │ oPushToggle1    (2nd) │
  │              │           │ oPushToggleToReady    │──CDC──> iRdyPushToggle_ms ──> iRdyPushToggle
  └──────────────┘           └──────────────────────┘
```

**Constraints** (3 per instance):

| # | From | To | Delay |
|---|------|----|-------|
| 1 | `*iPushToggle*` | `BlkOut.oPushToggle0_ms*` | OClk period |
| 2 | `*oPushToggleToReady*` | `*iRdyPushToggle_ms*` | IClk period |
| 3 | `*iRdyPushToggle_ms*` | `*iRdyPushToggle_reg*` | 0.5× IClk period |

**Note**: If a HandshakeBool's request input is tied off in the design (e.g.
`vFlushTimeoutRequest => false`), synthesis removes its `iPushToggle` register
and constraint #1 has an empty `-from`.  Vivado reports this as a
`[Vivado 12-4739]` CRITICAL WARNING; it is expected and harmless.

### HandshakeBaseResetCross (`emit_HBRC`)

A full handshake **with data payload and bidirectional reset synchronizers**.
Used for state transfers (e.g. `HandshakeStateToBusClkDomain`, overflow/underflow
counters, write pointer handshake).

```
  Source (IClk)                    Destination (OClk)
  ┌───────────────────┐            ┌─────────────────────────┐
  │ iPushTogglex      │──CDC──>│ oPushToggle0_msx (1st)  │
  │                   │            │ oPushToggle1x    (2nd)  │
  │ iStoredDatax[N]   │──CDC──>│ oDataFlopx[N]           │
  │                   │            │ oPushToggleToReadyx     │──CDC──> iRdyPushToggle_msx ──> iRdyPushTogglex
  │                   │            │                         │
  │   SyncIReset      │            │   SyncOReset            │
  │   (IClk→OClk)     │            │   (OClk→IClk)           │
  └───────────────────┘            └─────────────────────────┘
```

**Constraints** (14 per instance, 13 when `iData` is open):
- 5 for the toggle/data/ready handshake (the data constraint is omitted for
  instances with no data payload, e.g. the overflow/underflow handshakes)
- 5 for SyncIReset (c1=IClk → c2=OClk, kSpeedUp=true: uses falling-edge resync)
- 4 for SyncOReset (c1=OClk → c2=IClk, kSpeedUp=false: uses rising-edge resync)

The SyncIReset/SyncOReset directions were confirmed by querying the clocks that
drive each matched register in a synthesized netlist.

The SyncIReset also includes a `set_max_delay` (not `-datapath_only`) from
`c1ResetFastLclx` to `iPushTogglex` (both in IClk) to constrain the
reset-to-toggle recovery path.

### DoubleSyncBool (`emit_DSB`)

A classic two-stage double-synchronizer for single-bit asynchronous signals.
Used by the FifoClearController enable chain.

```
  Source (IClk)          Destination (OClk)
  ┌────────────┐          ┌───────────────────────────┐
  │ iDlySigx   │──CDC──>│ DoubleSyncAsyncInBasex/    │
  │            │          │   oSig_msx (1st stage)     │
  │            │          │   oSigx    (2nd stage)     │
  └────────────┘          └───────────────────────────┘
```

**Constraints** (2 per instance):

| # | From | To | Delay |
|---|------|----|-------|
| 1 | `*iDlySigx*` | `*DoubleSyncAsyncInBasex/oSig_msx*` | OClk period |
| 2 | `*oSig_msx*` | `*oSigx*` | 0.5× OClk period |

### PulseSyncBase (`emit_PS`)

A pulse handshake: hold-in → sync → ack-back.  Used by `NiFpgaFifoPortReset`
for reset pulse crossing.

```
  Source (IClk)            Destination (OClk)              Back to Source
  ┌──────────────┐          ┌──────────────────┐            ┌──────────────┐
  │ iHoldSigInx  │──CDC──>│ oHoldSigIn_msx   │            │              │
  │              │          │ oLocalSigOutCEx  │──CDC──>│ iSigOut_msx  │
  │              │          │                  │            │ iSigOutx     │
  └──────────────┘          └──────────────────┘            └──────────────┘
```

**Constraints** (4 per instance):

| # | From | To | Delay |
|---|------|----|-------|
| 1 | `iHoldSigInx*` | `oHoldSigIn_msx*` | OClk period |
| 2 | `oHoldSigIn_msx*` | `oLocalSigOutCEx*` | 0.5× OClk period |
| 3 | `oLocalSigOutCEx*` | `iSigOut_msx*` | IClk period |
| 4 | `iSigOut_msx*` | `iSigOutx*` | 0.5× IClk period |

For `ClearToPush` and `ClearToPop` crossings, an additional constraint covers
the `oRegisteredSigAck` → `iSigOut_msx` path that lies outside the
PulseSyncBase hierarchy.

### DmaPortFifoPtrClockCrossing (`emit_PCC`)

A pointer-transfer handshake used by the streaming FIFO flags logic.  Carries
multi-bit data with a toggle/ack protocol.

```
  Source (IClk)            Destination (OClk)              Back to Source
  ┌──────────────┐          ┌──────────────────┐            ┌──────────────┐
  │ iTogglePush  │──CDC──>│ oPushRcvd_ms     │            │              │
  │ iDataToPush  │──CDC──>│ DataReg           │            │              │
  │              │          │ oAck             │──CDC──>│ iAckRcvd_ms  │
  │              │          │                  │            │ iAckRcvd_reg │
  └──────────────┘          └──────────────────┘            └──────────────┘
```

**Constraints** (5 per instance):

| # | From | To | Delay |
|---|------|----|-------|
| 1 | `iTogglePush*` | `oPushRcvd_ms*` | OClk period |
| 2 | `oPushRcvd_ms*` | `oPushRcvd_reg*` | 0.5× OClk period |
| 3 | `iDataToPush*` | `DataReg*` | 2.0× OClk period |
| 4 | `oAck*` | `iAckRcvd_ms*` | IClk period |
| 5 | `iAckRcvd_ms*` | `iAckRcvd_reg*` | 0.5× IClk period |

### Gray Code Counter Crossing

The streaming FIFO uses gray-coded pointers for the read/write pointer
crossing.  This is a bus-width synchronizer (not a single handshake).

**InputFifo** (Writer; write pointer user → DMA):
- `iWriteSamplePtrUnsGray*` → `GrayPtrClockCrossing.OutputGrayReg_ms*` (DMA period)
- `OutputGrayReg_ms*` → `OutputGrayReg/*` (0.5× DMA period)

**OutputFifo** (Reader; read pointer user → DMA):
- `oReadSamplePtrUnsGray*` → `iReadSamplePtrUnsGray_ms*` (DMA period)
- `iReadSamplePtrUnsGray_ms*` → `iReadSamplePtrUnsGray_reg*` (0.5× DMA period)

---

## Constraint Delay Values — Detailed Analysis

### Clock Periods

The effective CDC periods are derived from the target clock XML definitions
(`MacallanClocks.xml`) using the formula:

```
effective_period = 1 / (freq × (1 + PPM/1e6)) − jitter
```

This computes the **minimum guaranteed inter-edge time**: the shortest possible
period (frequency shifted up by the accuracy tolerance) minus the peak-to-peak
jitter.  The result is the tightest safe CDC window.

For Macallan, both clocks share AccuracyInPPM=100 and JitterInPicoSeconds=250:

| Clock    | Freq    | PPM | Jitter | Effective Period |
|----------|---------|-----|--------|------------------|
| DmaClk   | 250 MHz | 100 | 250 ps | **3.7496000400 ns** |
| PllClk80 |  80 MHz | 100 | 250 ps | **12.2487501250 ns** |

These values now **exactly match** the periods used in the NI-generated
constraints (`TNM_Custom1` through `TNM_Custom573`).

The Tcl variables set at the top of the generated constraints:

```tcl
set hdl_dmaclk_T 3.7496000400
set hdl_userclk_T 12.2487501250
```

### Delay Assignment Rules

Every `set_max_delay` in the generated constraints follows one of four rules,
determined by the role of the path in the synchronizer chain:

| Rule | Expression | Rationale |
|------|-----------|-----------|
| **1× dest** | `$dest_period` | First synchronizer stage.  The source flop launches data that must arrive at the `_ms` capture flop within one destination clock period.  This gives the routing tool a full destination-clock cycle budget, which is the maximum latency the synchronizer protocol can tolerate before the metastability window is violated. |
| **0.5× dest** | `expr {0.5*$dest_period}` | Second synchronizer stage.  The `_ms` flop has already resolved metastability; the path to the second-stage flop (`_reg` or equivalent) is a same-clock-domain transfer.  Half the destination period is sufficient and keeps placement tight, reducing the probability of the second stage seeing a glitch. |
| **2× dest** | `expr {2.0*$dest_period}` | Multi-bit data path.  In toggle-handshake protocols, the data bus (`iStoredData`/`iDataToPush`) is stable for at least two destination-clock cycles before the toggle signal acknowledges.  Two full periods gives a generous budget for multi-bit bus routing skew. |
| **2× source (non-datapath)** | `expr {2.0*$source_period}` | Reset recovery path.  Used only for the SyncIReset `c1ResetFastLclx` → `iPushTogglex` path in HandshakeBaseResetCross (both registers are in IClk).  This is a `set_max_delay` (without `-datapath_only`) that constrains the reset-to-toggle recovery relationship. Two source periods allows the reset synchronizer to settle before the handshake toggle can toggle again. |

A path's "destination period" is the period of the clock that actually drives
the destination register.  Every same-clock synchronizer-stage constraint is
therefore at most half that clock's period, so a `-datapath_only` override can
never relax a path beyond its normal single-cycle requirement.

### Per-Crossing-Type Breakdown

Below is every crossing type, the direction of each constrained path, and the
concrete delay value for the two FIFO clock configurations.

#### HandshakeBool (`emit_HB`) — 3 constraints

Toggle-only handshake with no data payload.  Used by StreamStateBlock request
signals (e.g., start/stop/flush).

All HandshakeBool instances cross **user → DMA** (iT=`hdl_userclk_T`, oT=`hdl_dmaclk_T`).

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 1 | `*iPushToggle*` → `oPushToggle0_ms*` | user → DMA | 1× dest | `$hdl_dmaclk_T` | **3.750 ns** |
| 2 | `*oPushToggleToReady*` → `*iRdyPushToggle_ms*` | DMA → user (return) | 1× dest | `$hdl_userclk_T` | **12.249 ns** |
| 3 | `*iRdyPushToggle_ms*` → `*iRdyPushToggle_reg*` | user (same-domain) | 0.5× dest | `0.5*$hdl_userclk_T` | **6.124 ns** |

**Note:** If a request input is tied off (e.g. `vFlushTimeoutRequest => false`)
its `iPushToggle` register is optimized away and constraint #1 has an empty
`-from`; Vivado reports a `[Vivado 12-4739]` CRITICAL WARNING for it, which is
expected in that case.

#### HandshakeBaseResetCross (`emit_HBRC`) — 14 constraints

Full handshake with data payload and bidirectional reset synchronizers.

All HBRC instances cross **user → DMA** (iT=`hdl_userclk_T`, oT=`hdl_dmaclk_T`).
This includes the Reader's `HandshakeStateToBusClkDomain`, which returns the
user-side stream state to the DMA stream state controller.

**Handshake toggle/data/ready (5 constraints; #3 omitted when `iData` is open):**

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 1 | `iPushTogglex*` → `oPushToggle0_msx*` | user → DMA | 1× dest | `$hdl_dmaclk_T` | **3.750 ns** |
| 2 | `oPushToggle0_msx*` → `*oPushToggle1x*` | DMA (same-domain) | 0.5× dest | `0.5*$hdl_dmaclk_T` | **1.875 ns** |
| 3 | `iStoredDatax*` → `oDataFlopx*` | user → DMA | 2× dest | `2.0*$hdl_dmaclk_T` | **7.499 ns** |
| 4 | `*oPushToggleToReadyx*` → `*iRdyPushToggle_msx*` | DMA → user (return) | 1× dest | `$hdl_userclk_T` | **12.249 ns** |
| 5 | `*iRdyPushToggle_msx*` → `*iRdyPushTogglex*` | user (same-domain) | 0.5× dest | `0.5*$hdl_userclk_T` | **6.124 ns** |

**SyncIReset — c1 = IClk (user) → c2 = OClk (DMA), kSpeedUp=true (5 constraints):**

Uses a falling-edge intermediate flip-flop (kSpeedUp=true reduces latency by
half a cycle).

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 6 | `c1ResetFastLclx*` → `c2ResetFe_msx*` | user → DMA (forward) | 1× dest | `$hdl_dmaclk_T` | **3.750 ns** |
| 7 | `c2ResetFe_msx*` → `SpeedUpWithFeFlopGen.SyncToClk2REfromFE*` | DMA (same-domain) | 0.5× dest | `0.5*$hdl_dmaclk_T` | **1.875 ns** |
| 8 | `SpeedUpWithFeFlopGen.SyncToClk2REfromFE*` → `c1ResetFromClk2_ms*` | DMA → user (return) | 1× dest | `$hdl_userclk_T` | **12.249 ns** |
| 9 | `c1ResetFromClk2_ms*` → `c1ResetFromClk2_reg*` | user (same-domain) | 0.5× dest | `0.5*$hdl_userclk_T` | **6.124 ns** |
| 10 | `c1ResetFastLclx*` → `iPushTogglex*` | user (recovery) | 2× source | `2.0*$hdl_userclk_T` | **24.498 ns** |

Constraint #10 is the only `set_max_delay` **without** `-datapath_only`.
Both ends are in IClk; it bounds the reset-to-toggle recovery path to two
IClk cycles.

**SyncOReset — c1 = OClk (DMA) → c2 = IClk (user), kSpeedUp=false (4 constraints):**

Uses a rising-edge intermediate flip-flop.

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 11 | `c1ResetFastLclx*` → `c2ResetRe_msx*` | DMA → user (forward) | 1× dest | `$hdl_userclk_T` | **12.249 ns** |
| 12 | `c2ResetRe_msx*` → `DontSpeedUpWithFeFlopGen.SyncToClk2REfromRE*` | user (same-domain) | 0.5× dest | `0.5*$hdl_userclk_T` | **6.124 ns** |
| 13 | `DontSpeedUpWithFeFlopGen...` → `c1ResetFromClk2_ms*` | user → DMA (return) | 1× dest | `$hdl_dmaclk_T` | **3.750 ns** |
| 14 | `c1ResetFromClk2_ms*` → `c1ResetFromClk2_reg*` | DMA (same-domain) | 0.5× dest | `0.5*$hdl_dmaclk_T` | **1.875 ns** |

#### DoubleSyncBool (`emit_DSB`) — 2 constraints

Classic two-stage double-synchronizer.  Used in enable chain (FifoClearController).
The FIFO clear runs on the DMA side; ToPush/ToPop cross **DMA → user** and
FromPush/FromPop cross **user → DMA**.

| # | Path | DMA → user | user → DMA |
|---|------|----------------|----------------|
| 1 | `*iDlySigx*` → `*oSig_msx*` (1× dest) | `$hdl_userclk_T` = **12.249 ns** | `$hdl_dmaclk_T` = **3.750 ns** |
| 2 | `*oSig_msx*` → `*oSigx*` (0.5× dest) | `0.5*$hdl_userclk_T` = **6.124 ns** | `0.5*$hdl_dmaclk_T` = **1.875 ns** |

#### PulseSyncBase (`emit_PS`) — 4 constraints

Pulse handshake with hold-in / sync / ack-back.  Used by NiFpgaFifoPortReset.

| Instance | Writer | Reader |
|----------|--------|--------|
| ClearToPush / ClearToPop | DMA → user | DMA → user |
| PopToPush | DMA → user | user → DMA |
| PushToPop | user → DMA | DMA → user |

| # | Path | DMA → user | user → DMA |
|---|------|----------------|----------------|
| 1 | `iHoldSigInx*` → `oHoldSigIn_msx*` (1× dest) | `$hdl_userclk_T` = **12.249 ns** | `$hdl_dmaclk_T` = **3.750 ns** |
| 2 | `oHoldSigIn_msx*` → `oLocalSigOutCEx*` (0.5× dest) | `0.5*$hdl_userclk_T` = **6.124 ns** | `0.5*$hdl_dmaclk_T` = **1.875 ns** |
| 3 | `oLocalSigOutCEx*` → `iSigOut_msx*` (return, 1× dest) | `$hdl_dmaclk_T` = **3.750 ns** | `$hdl_userclk_T` = **12.249 ns** |
| 4 | `iSigOut_msx*` → `iSigOutx*` (return, 0.5× dest) | `0.5*$hdl_dmaclk_T` = **1.875 ns** | `0.5*$hdl_userclk_T` = **6.124 ns** |

For ClearToPush/ClearToPop, an additional path `oRegisteredSigAck*` →
`iSigOut_msx*` is constrained at the return destination period (same as #3).

#### DmaPortFifoPtrClockCrossing (`emit_PCC`) — 5 constraints

Multi-bit pointer transfer with toggle/ack.  In both FIFOs the PCC crosses
**DMA → user** (Writer: read pointer; Reader: write pointer).

| # | Path | DMA → user |
|---|------|----------------|
| 1 | `iTogglePush*` → `oPushRcvd_ms*` (1× dest) | `$hdl_userclk_T` = **12.249 ns** |
| 2 | `oPushRcvd_ms*` → `oPushRcvd_reg*` (0.5× dest) | `0.5*$hdl_userclk_T` = **6.124 ns** |
| 3 | `iDataToPush*` → `DataReg*` (2× dest) | `2.0*$hdl_userclk_T` = **24.498 ns** |
| 4 | `oAck*` → `iAckRcvd_ms*` (return, 1× dest) | `$hdl_dmaclk_T` = **3.750 ns** |
| 5 | `iAckRcvd_ms*` → `iAckRcvd_reg*` (return, 0.5× dest) | `0.5*$hdl_dmaclk_T` = **1.875 ns** |

#### Gray Code Counter — 2 constraints per direction

Bus-width synchronizer for FIFO read/write pointers.  Gray coding guarantees
only one bit changes per clock cycle, making the 1× dest rule safe even for
multi-bit buses.

**InputFifo (Writer) write pointer and disable signal (user → DMA):**

| # | Path | Expression | Value |
|---|------|------------|-------|
| 1 | `iWriteSamplePtrUnsGray*` → `OutputGrayReg_ms*` | `$hdl_dmaclk_T` | **3.750 ns** |
| 2 | `OutputGrayReg_ms*` → `OutputGrayReg/*` | `0.5*$hdl_dmaclk_T` | **1.875 ns** |
| 3 | `iWritesDisabledSampPtrUnsGray*` → `SyncToOClk_ms*` | `$hdl_dmaclk_T` | **3.750 ns** |
| 4 | `SyncToOClk_ms*` → `SyncToOClk*` | `0.5*$hdl_dmaclk_T` | **1.875 ns** |

**OutputFifo (Reader) read pointer (user → DMA):**

| # | Path | Expression | Value |
|---|------|------------|-------|
| 1 | `oReadSamplePtrUnsGray*` → `iReadSamplePtrUnsGray_ms*` | `$hdl_dmaclk_T` | **3.750 ns** |
| 2 | `iReadSamplePtrUnsGray_ms*` → `iReadSamplePtrUnsGray_reg*` | `0.5*$hdl_dmaclk_T` | **1.875 ns** |

### Summary of All Unique Delay Values

| Delay (ns) | Expression | Rule | Where Used |
|-----------|------------|------|------------|
| **1.875** | `0.5*$hdl_dmaclk_T` | 0.5× DmaClk | 2nd sync stage on the DMA side |
| **3.750** | `$hdl_dmaclk_T` | 1× DmaClk | 1st sync stage crossing into the DMA side |
| **6.124** | `0.5*$hdl_userclk_T` | 0.5× PllClk80 | 2nd sync stage on the user side |
| **7.499** | `2.0*$hdl_dmaclk_T` | 2× DmaClk | Multi-bit HBRC data into the DMA side |
| **12.249** | `$hdl_userclk_T` | 1× PllClk80 | 1st sync stage crossing into the user side |
| **24.498** | `2.0*$hdl_userclk_T` | 2× PllClk80 | Multi-bit PCC data into the user side; SyncIReset recovery (user side) |

### Comparison with NI-Generated Constraints

Our constraint periods now use the same formula as NI's constraint generator
(derived from `MacallanClocks.xml`), so the values are identical:

| Clock | Our Period | NI Period | Match |
|-------|-----------|-----------|-------|
| DmaClk (250 MHz) | 3.7496000400 ns | 3.7496000400 ns | ✅ Exact |
| PllClk80 (80 MHz) | 12.2487501250 ns | 12.2487501250 ns | ✅ Exact |

### Async Reset False Paths

Each FIFO also gets `set_false_path` constraints for all asynchronous
clear/preset pins (delay = ∞, i.e., no timing check):

```tcl
set_false_path -to [get_pins -quiet -hier -filter {NAME =~ *Fifo_inst/*/CLR && IS_LEAF}]
set_false_path -to [get_pins -quiet -hier -filter {NAME =~ *Fifo_inst/*/PRE && IS_LEAF}]
```

These prevent Vivado from performing reset recovery/removal timing analysis on the
asynchronous reset paths feeding FDCE/FDPE primitives in HandshakeBaseResetCross,
DFlop, and PulseSync building blocks.

---

## FIFO Internal Structure

### InputFifo (`NiSharedFifoWriterCore` / TargetToHost)

Push = user side (FIFO `ViClk` port, PllClk80 80 MHz), Pop = DMA side (FIFO `BusClk` port, DmaClk 250 MHz)

| CDC Component | Type | Direction | Instance Path |
|--------------|------|-----------|---------------|
| StreamStateBlock.HandshakeStopStreamRequest | HandshakeBool | user → DMA | `StreamStateBlock.HandshakeStopStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStopWithFlushRequest | HandshakeBool | user → DMA | `StreamStateBlock.HandshakeStopWithFlushRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStartStreamRequest | HandshakeBool | user → DMA | `StreamStateBlock.HandshakeStartStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeFlushTimeoutRequest | HandshakeBool | user → DMA | `StreamStateBlock.HandshakeFlushTimeoutRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStateToBusClkDomain | HBRC | user → DMA | `StreamStateBlock.HandshakeStateToBusClkDomain` |
| StreamStateBlock.HandshakeOverflowStopRequest | HBRC (no data) | user → DMA | `StreamStateBlock.HandshakeOverflowStopRequest` |
| BlkOverflow.HandshakeOverflow | HBRC (no data) | user → DMA | `BlkOverflow.HandshakeOverflow` |
| Write pointer gray code | Gray code | user → DMA | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/SyncToOClk` |
| Disable signal | Double-sync | user → DMA | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/SyncToOClk/DisableSignalClockCrossing` |
| Read pointer PCC | PCC | DMA → user | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/OClkToIClkCrossing.SyncToIClk` |
| WritePointerHandshake | HBRC | user → DMA | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/WritePointerHandshake` |
| FifoClear ToPush DoubleSyncBool | DoubleSyncBool | DMA → user | `DmaPortCommIfcComponentEnableChainx/.../PushSynchNeeded.ToPushDblSync` |
| FifoClear FromPush DoubleSyncBool | DoubleSyncBool | user → DMA | `DmaPortCommIfcComponentEnableChainx/.../PushSynchNeeded.FromPushDblSync` |
| ClearToPush PulseSync | PulseSync+ack | DMA → user | `.../NiFpgaFifoPortResetx/Crossing.ClearToPush` |
| PopToPush PulseSync | PulseSync | DMA → user | `.../NiFpgaFifoPortResetx/Crossing.PopToPush/PulseSyncBasex` |
| PushToPop PulseSync | PulseSync | user → DMA | `.../NiFpgaFifoPortResetx/Crossing.PushToPop/PulseSyncBasex` |

### OutputFifo (`NiSharedFifoReaderCore` / HostToTarget)

Push = DMA side (FIFO `BusClk` port, DmaClk 250 MHz), Pop = user side (FIFO `ViClk` port, PllClk80 80 MHz)

| CDC Component | Type | Direction | Instance Path |
|--------------|------|-----------|---------------|
| StreamStateBlock.HandshakeStopStreamRequest | HandshakeBool | user → DMA | `StreamStateBlock.HandshakeStopStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStartStreamRequest | HandshakeBool | user → DMA | `StreamStateBlock.HandshakeStartStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStateToBusClkDomain | HBRC | user → DMA | `StreamStateBlock.HandshakeStateToBusClkDomain` |
| StreamStateBlock.HandshakeUnderflowStopRequest | HBRC (no data) | user → DMA | `StreamStateBlock.HandshakeUnderflowStopRequest` |
| BlkUnderflow.HandshakeUnderflow | HBRC (no data) | user → DMA | `BlkUnderflow.HandshakeUnderflow` |
| HandshakeFullCount | HBRC | user → DMA | `HandshakeFullCount` |
| Read pointer gray code | Gray code | user → DMA | `DmaPortOutStrmFifox/DmaPortOutStrmFifoFlagsx` |
| Write pointer PCC | PCC | DMA → user | `DmaPortOutStrmFifox/DmaPortOutStrmFifoFlagsx/IClkToOClkCrossing.SyncToOClk` |
| FifoClear ToPop DoubleSyncBool | DoubleSyncBool | DMA → user | `DmaPortCommIfcComponentEnableChainx/.../PopSynchNeeded.ToPopDblSync` |
| FifoClear FromPop DoubleSyncBool | DoubleSyncBool | user → DMA | `DmaPortCommIfcComponentEnableChainx/.../PopSynchNeeded.FromPopDblSync` |
| ClearToPop PulseSync | PulseSync+ack | DMA → user | `.../NiFpgaFifoPortResetx/Crossing.ClearToPop` |
| PopToPush PulseSync | PulseSync | user → DMA | `.../NiFpgaFifoPortResetx/Crossing.PopToPush/PulseSyncBasex` |
| PushToPop PulseSync | PulseSync | DMA → user | `.../NiFpgaFifoPortResetx/Crossing.PushToPop/PulseSyncBasex` |

The stream-state crossing in the Reader (`HandshakeStateToBusClkDomain`) must
stay a real handshake: the DMA stream state controller only advances
Disabled↔Enabled and clears the start/stop IRQs once this value reports the
matching state, and the user and DMA clocks are asynchronous.  Do not replace it
with a direct register.

---

## Hierarchy Independence

All cell patterns use a leading `*` wildcard together with `NAME =~`:

```
*NiSharedFifoReaderCorex/StreamStateBlock.HandshakeStopStreamRequest/...
```

so the constraints match regardless of how many levels of hierarchy wrap the
FIFO instance, e.g. `UserHdl_inst/ReaderFifo_inst/NiSharedFifoReaderCorex/...`.

This was verified by synthesizing both FIFOs nested two levels deep (mirroring
`UserHdl_inst/{WriterFifo_inst,ReaderFifo_inst}`) with DmaClk = 4 ns and
PllClk80 = 12.5 ns, both with hierarchy preserved and with
`-flatten_hierarchy full -keep_equivalent_registers` (the LabVIEW FPGA target
synthesis settings). For every generated `set_max_delay`, the matched
registers and the clocks driving them were queried. In both netlists, all
constraints that apply to the configuration resolve to registers whose clocks
agree with the period used, `report_cdc` shows every DmaClk↔PllClk80 endpoint
covered by an exception, and all timing constraints are met.

> **History:** an earlier version of this generator took "BusClk" to mean the
> target's 80 MHz `BusClk`, so it mapped the FIFO `BusClk` port to PllClk80 and
> the FIFO `ViClk` port to DmaClk (backwards). It also swapped the
> SyncIReset/SyncOReset directions and used the wrong period for the
> ClearToPush/ClearToPop ack path. In the fully flattened netlist, 71 of its
> 167 constraints applied the other clock's period. Passing timing does not
> catch this kind of error, because the wrong values were mostly looser than
> the correct ones, so always validate against the netlist clocks as above.

---

## Relationship to Existing NI Constraints

The existing `constraints.xdc` already contains NI-generated CDC constraints
for the standard DMA FIFO endpoints (channels 0 and 1) that live inside the
LabVIEW FPGA window.  These are the `TNM_Custom1` through `TNM_Custom573`
assignments.

The HDL Shared FIFO constraints generated by `gen_constraints.py` cover the
**additional** FIFO endpoints (channels 2+) that are instantiated in user HDL
outside the LabVIEW window.  They use `get_cells -hierarchical -filter
{NAME =~ ...}` so they match at any hierarchy depth (see Constraint Style).

The NI constraints also have some optional paths that produce harmless
`CRITICAL WARNING: No valid object(s)` messages — these are for DMA channels
or features that don't exist in the current design configuration.  The HDL
Shared FIFO constraints behave the same way for tied-off request inputs.

---

## Adding More FIFOs

To add constraints for additional FIFO instances:

1. Add the instance name to `WRITER_FIFOS` or `READER_FIFOS` in
   `gen_constraints.py`
2. Re-run `python gen_constraints.py -o hdl_fifo_cdc_constraints.xdc`
3. Recompile

---

## Troubleshooting

### "No valid object(s)" warnings

If you see `CRITICAL WARNING: [Vivado 12-4739] set_max_delay: No valid
object(s)` for your FIFO constraints:

1. **Check the instance name** — Verify the core instance name matches what
   you put in `WRITER_FIFOS`/`READER_FIFOS`.

2. **Audit cell names** — Open the synth checkpoint and list cells:
   ```tcl
   open_checkpoint FIFO_VI_2.runs/synth_1/MacallanTop.dcp
   get_cells -hierarchical -filter {NAME =~ "*YourFifoInst*" && IS_SEQUENTIAL==true}
   ```

3. **Check for optimized-away cells** — A HandshakeBool whose request input
   is tied off (e.g. `FlushTimeout`) has its push side optimized away by
   synthesis.  A warning for that path alone is expected.

### Timing violations on CDC paths

If you see timing violations specifically on FIFO CDC paths, verify:

1. The constraint delay values match your actual clock periods
2. The `hdl_dmaclk_T` and `hdl_userclk_T` variables are set correctly
3. No other constraints are conflicting (check for duplicate `set_max_delay`
   on the same paths)
