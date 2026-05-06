# HDL Shared FIFO CDC Constraints

## Overview

When NI FlexRIO FPGAs use HDL Shared FIFOs (`HdlSharedInputFifoInterface` and
`HdlSharedOutputFifoInterface`), the FIFO logic crosses between two clock
domains:

| Clock     | Frequency | Nominal Period | Effective Period | Role                      |
|-----------|-----------|----------------|-----------------|---------------------------|
| DmaClk    | 250 MHz   | 4.000 ns       | 3.7496 ns       | ViClk / PCIe side         |
| PllClk80  | 80 MHz    | 12.500 ns      | 12.2488 ns      | BusClk / communication side|

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
| `constraints.xdc` | Main Vivado constraint file; the generated block is appended at the end |

---

## How to Use

### 1. Configure FIFO instance names

Edit the `INPUT_FIFOS` and `OUTPUT_FIFOS` lists at the top of
`gen_constraints.py`:

```python
INPUT_FIFOS = [
    "InputFifo_inst",      # ch2 TargetToHost
]

OUTPUT_FIFOS = [
    "OutputFifo_inst",     # ch3 HostToTarget
]
```

Use the **leaf instance name** as declared in the VHDL instantiation.  The
generator prefixes every pattern with `*` so it matches at any hierarchy depth
(e.g. `*InputFifo_inst/...` matches both `InputFifo_inst/...` at the top level
and `Wrapper_inst/InputFifo_inst/...` inside a wrapper).

### 2. Run the generator

```
python gen_constraints.py -o hdl_fifo_constraints.xdc
```

### 3. Append to constraints.xdc

Paste the generated XDC at the **end** of `constraints.xdc`, after all existing
NI-generated constraints.  The generated block starts with:

```tcl
###################################################################################
## HDL Shared FIFO CDC Constraints
```

### 4. Compile

Run the normal Vivado compile flow.  The constraints are evaluated during
`link_design` as part of the standard XDC parsing.

---

## Constraint Style

All constraints follow the same style used by the existing NI-generated CDC
constraints (e.g. `TNM_Custom1` through `TNM_Custom573`):

```tcl
set_max_delay -datapath_only $period \
  -from [get_cells -quiet {*pattern*} -filter {IS_SEQUENTIAL==true}] \
  -to   [get_cells -quiet {*pattern*} -filter {IS_SEQUENTIAL==true}]
```

Key aspects:

- **`get_cells -quiet {pattern} -filter {IS_SEQUENTIAL==true}`**: Matches
  cells by hierarchical name glob.  The `-quiet` flag suppresses warnings if
  the pattern matches nothing (this is intentional — some optional paths may
  not exist in every configuration).

- **`*` wildcard prefix**: Every instance-specific pattern starts with `*` to
  match regardless of where the FIFO is instantiated in the hierarchy.  Vivado
  glob `*` matches zero or more characters including hierarchy separators (`/`).

- **`-datapath_only`**: Constrains only the data path delay, not the clock
  path.  This is correct for CDC synchronizers where the source and
  destination clocks are asynchronous.

- **No `set` variables for cell groups**: Each `set_max_delay` uses an inline
  `get_cells` call.  This avoids Tcl variable scoping issues and matches the
  proven NI constraint style.

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

**Note**: Some HandshakeBool instances (e.g. `HandshakeStopWithFlushRequest`,
`HandshakeFlushTimeoutRequest`) are response-only — they have no `iPushToggle`
register on the source side.  In those cases, constraint #1 resolves to an
empty cell set via `-quiet` and becomes a no-op.

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
  │   (OClk→IClk)     │            │   (IClk→OClk)           │
  └───────────────────┘            └─────────────────────────┘
```

**Constraints** (14 per instance):
- 5 for the toggle/data/ready handshake
- 5 for SyncIReset (OClk→IClk, with kSpeedUp=true: uses falling-edge resync)
- 4 for SyncOReset (IClk→OClk, with kSpeedUp=false: uses rising-edge resync)

The SyncIReset also includes a `set_max_delay` (not `-datapath_only`) from
`c1ResetFastLclx` to `iPushTogglex` to constrain the reset-to-toggle recovery
path.

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

**InputFifo** (write pointer DmaClk → BusClk):
- `iWriteSamplePtrUnsGray*` → `GrayPtrClockCrossing.OutputGrayReg_ms*` (BusClk period)
- `OutputGrayReg_ms*` → `OutputGrayReg/*` (0.5× BusClk period)

**OutputFifo** (read pointer DmaClk → BusClk):
- `oReadSamplePtrUnsGray*` → `iReadSamplePtrUnsGray_ms*` (BusClk period)
- `iReadSamplePtrUnsGray_ms*` → `iReadSamplePtrUnsGray_reg*` (0.5× BusClk period)

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
set hdl_dma_T 3.7496000400
set hdl_bus_T 12.2487501250
```

### Delay Assignment Rules

Every `set_max_delay` in the generated constraints follows one of four rules,
determined by the role of the path in the synchronizer chain:

| Rule | Expression | Rationale |
|------|-----------|-----------|
| **1× dest** | `$dest_period` | First synchronizer stage.  The source flop launches data that must arrive at the `_ms` capture flop within one destination clock period.  This gives the routing tool a full destination-clock cycle budget, which is the maximum latency the synchronizer protocol can tolerate before the metastability window is violated. |
| **0.5× dest** | `expr {0.5*$dest_period}` | Second synchronizer stage.  The `_ms` flop has already resolved metastability; the path to the second-stage flop (`_reg` or equivalent) is a same-clock-domain transfer.  Half the destination period is sufficient and keeps placement tight, reducing the probability of the second stage seeing a glitch. |
| **2× dest** | `expr {2.0*$dest_period}` | Multi-bit data path.  In toggle-handshake protocols, the data bus (`iStoredData`/`iDataToPush`) is stable for at least two destination-clock cycles before the toggle signal acknowledges.  Two full periods gives a generous budget for multi-bit bus routing skew. |
| **2× source (non-datapath)** | `expr {2.0*$source_period}` | Reset recovery path.  Used only for the SyncIReset `c1ResetFastLclx` → `iPushTogglex` path in HandshakeBaseResetCross.  This is a `set_max_delay` (without `-datapath_only`) that constrains the reset-to-toggle recovery relationship. Two source periods allows the reset synchronizer to settle before the handshake toggle can toggle again. |

### Per-Crossing-Type Breakdown

Below is every crossing type, the direction of each constrained path, and the
concrete delay value for the two FIFO clock configurations.

#### HandshakeBool (`emit_HB`) — 3 constraints

Toggle-only handshake with no data payload.  Used by StreamStateBlock request
signals (e.g., start/stop/flush).

All HandshakeBool instances in this design cross **DmaClk → BusClk** (iT=`hdl_dma_T`, oT=`hdl_bus_T`).

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 1 | `*iPushToggle*` → `oPushToggle0_ms*` | DmaClk → BusClk | 1× dest | `$hdl_bus_T` | **12.249 ns** |
| 2 | `*oPushToggleToReady*` → `*iRdyPushToggle_ms*` | BusClk → DmaClk (return) | 1× dest | `$hdl_dma_T` | **3.750 ns** |
| 3 | `*iRdyPushToggle_ms*` → `*iRdyPushToggle_reg*` | DmaClk (same-domain) | 0.5× dest | `0.5*$hdl_dma_T` | **1.875 ns** |

**Note:** Some HandshakeBool instances are response-only (no `iPushToggle`
register); constraint #1 becomes a no-op via `-quiet`.

#### HandshakeBaseResetCross (`emit_HBRC`) — 14 constraints

Full handshake with data payload and bidirectional reset synchronizers.

All HBRC instances in this design cross **DmaClk → BusClk** (iT=`hdl_dma_T`, oT=`hdl_bus_T`).

**Handshake toggle/data/ready (5 constraints):**

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 1 | `iPushTogglex*` → `oPushToggle0_msx*` | DmaClk → BusClk | 1× dest | `$hdl_bus_T` | **12.249 ns** |
| 2 | `oPushToggle0_msx*` → `*oPushToggle1x*` | BusClk (same-domain) | 0.5× dest | `0.5*$hdl_bus_T` | **6.124 ns** |
| 3 | `iStoredDatax*` → `oDataFlopx*` | DmaClk → BusClk | 2× dest | `2.0*$hdl_bus_T` | **24.498 ns** |
| 4 | `*oPushToggleToReadyx*` → `*iRdyPushToggle_msx*` | BusClk → DmaClk (return) | 1× dest | `$hdl_dma_T` | **3.750 ns** |
| 5 | `*iRdyPushToggle_msx*` → `*iRdyPushTogglex*` | DmaClk (same-domain) | 0.5× dest | `0.5*$hdl_dma_T` | **1.875 ns** |

**SyncIReset — OClk(BusClk) → IClk(DmaClk), kSpeedUp=true (5 constraints):**

The SyncIReset synchronizes the output-clock reset into the input-clock domain
using a falling-edge intermediate flip-flop (kSpeedUp=true reduces latency by
half a cycle).

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 6 | `c1ResetFastLclx*` → `c2ResetFe_msx*` | BusClk → DmaClk (forward) | 1× dest | `$hdl_dma_T` | **3.750 ns** |
| 7 | `c2ResetFe_msx*` → `SpeedUpWithFeFlopGen.SyncToClk2REfromFE*` | DmaClk (same-domain) | 0.5× dest | `0.5*$hdl_dma_T` | **1.875 ns** |
| 8 | `SpeedUpWithFeFlopGen.SyncToClk2REfromFE*` → `c1ResetFromClk2_ms*` | DmaClk → BusClk (return) | 1× dest | `$hdl_bus_T` | **12.249 ns** |
| 9 | `c1ResetFromClk2_ms*` → `c1ResetFromClk2_reg*` | BusClk (same-domain) | 0.5× dest | `0.5*$hdl_bus_T` | **6.124 ns** |
| 10 | `c1ResetFastLclx*` → `iPushTogglex*` | BusClk → DmaClk (recovery) | 2× source | `2.0*$hdl_dma_T` | **7.499 ns** |

Constraint #10 is the only `set_max_delay` **without** `-datapath_only`.
It constrains the relationship between when the reset is asserted (in the
BusClk domain) and when the handshake toggle can toggle (in the DmaClk domain).
Omitting `-datapath_only` means Vivado includes clock-path pessimism, making
this a true timing check rather than just a routing budget.

**SyncOReset — IClk(DmaClk) → OClk(BusClk), kSpeedUp=false (4 constraints):**

The SyncOReset synchronizes the input-clock reset into the output-clock domain
using a rising-edge intermediate flip-flop.

| # | Path | Direction | Rule | Expression | Value |
|---|------|-----------|------|------------|-------|
| 11 | `c1ResetFastLclx*` → `c2ResetRe_msx*` | DmaClk → BusClk (forward) | 1× dest | `$hdl_bus_T` | **12.249 ns** |
| 12 | `c2ResetRe_msx*` → `DontSpeedUpWithFeFlopGen.SyncToClk2REfromRE*` | BusClk (same-domain) | 0.5× dest | `0.5*$hdl_bus_T` | **6.124 ns** |
| 13 | `DontSpeedUpWithFeFlopGen...` → `c1ResetFromClk2_ms*` | BusClk → DmaClk (return) | 1× dest | `$hdl_dma_T` | **3.750 ns** |
| 14 | `c1ResetFromClk2_ms*` → `c1ResetFromClk2_reg*` | DmaClk (same-domain) | 0.5× dest | `0.5*$hdl_dma_T` | **1.875 ns** |

#### DoubleSyncBool (`emit_DSB`) — 2 constraints

Classic two-stage double-synchronizer.  Used in enable chain (FifoClearController).

Instances in this design cross either **BusClk → DmaClk** (ToPush/ToPop) or
**DmaClk → BusClk** (FromPush/FromPop).

| # | Path | BusClk → DmaClk | DmaClk → BusClk |
|---|------|-----------------|-----------------|
| 1 | `*iDlySigx*` → `*oSig_msx*` (1× dest) | `$hdl_dma_T` = **3.750 ns** | `$hdl_bus_T` = **12.249 ns** |
| 2 | `*oSig_msx*` → `*oSigx*` (0.5× dest) | `0.5*$hdl_dma_T` = **1.875 ns** | `0.5*$hdl_bus_T` = **6.124 ns** |

#### PulseSyncBase (`emit_PS`) — 4 constraints

Pulse handshake with hold-in / sync / ack-back.  Used by NiFpgaFifoPortReset.

Instances in this design cross either **BusClk → DmaClk** (ClearToPush,
PopToPush) or **DmaClk → BusClk** (PushToPop).

| # | Path | BusClk → DmaClk | DmaClk → BusClk |
|---|------|-----------------|-----------------|
| 1 | `iHoldSigInx*` → `oHoldSigIn_msx*` (1× dest) | `$hdl_dma_T` = **3.750 ns** | `$hdl_bus_T` = **12.249 ns** |
| 2 | `oHoldSigIn_msx*` → `oLocalSigOutCEx*` (0.5× dest) | `0.5*$hdl_dma_T` = **1.875 ns** | `0.5*$hdl_bus_T` = **6.124 ns** |
| 3 | `oLocalSigOutCEx*` → `iSigOut_msx*` (return, 1× dest) | `$hdl_bus_T` = **12.249 ns** | `$hdl_dma_T` = **3.750 ns** |
| 4 | `iSigOut_msx*` → `iSigOutx*` (return, 0.5× dest) | `0.5*$hdl_bus_T` = **6.124 ns** | `0.5*$hdl_dma_T` = **1.875 ns** |

For ClearToPush/ClearToPop, an additional path `oRegisteredSigAck*` →
`iSigOut_msx*` is constrained at the return destination period (same as #3).

#### DmaPortFifoPtrClockCrossing (`emit_PCC`) — 5 constraints

Multi-bit pointer transfer with toggle/ack.

In InputFifo, the PCC crosses **BusClk → DmaClk** (read pointer).
In OutputFifo, the PCC crosses **BusClk → DmaClk** (write pointer).

| # | Path | BusClk → DmaClk |
|---|------|-----------------|
| 1 | `iTogglePush*` → `oPushRcvd_ms*` (1× dest) | `$hdl_dma_T` = **3.750 ns** |
| 2 | `oPushRcvd_ms*` → `oPushRcvd_reg*` (0.5× dest) | `0.5*$hdl_dma_T` = **1.875 ns** |
| 3 | `iDataToPush*` → `DataReg*` (2× dest) | `2.0*$hdl_dma_T` = **7.499 ns** |
| 4 | `oAck*` → `iAckRcvd_ms*` (return, 1× dest) | `$hdl_bus_T` = **12.249 ns** |
| 5 | `iAckRcvd_ms*` → `iAckRcvd_reg*` (return, 0.5× dest) | `0.5*$hdl_bus_T` = **6.124 ns** |

#### Gray Code Counter — 2 constraints per direction

Bus-width synchronizer for FIFO read/write pointers.  Gray coding guarantees
only one bit changes per clock cycle, making the 1× dest rule safe even for
multi-bit buses.

**InputFifo write pointer (DmaClk → BusClk):**

| # | Path | Expression | Value |
|---|------|------------|-------|
| 1 | `iWriteSamplePtrUnsGray*` → `OutputGrayReg_ms*` | `$hdl_bus_T` | **12.249 ns** |
| 2 | `OutputGrayReg_ms*` → `OutputGrayReg/*` | `0.5*$hdl_bus_T` | **6.124 ns** |

**InputFifo disable signal (BusClk → DmaClk):**

| # | Path | Expression | Value |
|---|------|------------|-------|
| 1 | `iWritesDisabledSampPtrUnsGray*` → `SyncToOClk_ms*` | `$hdl_dma_T` | **3.750 ns** |
| 2 | `SyncToOClk_ms*` → `SyncToOClk*` | `0.5*$hdl_dma_T` | **1.875 ns** |

**OutputFifo read pointer (DmaClk → BusClk):**

| # | Path | Expression | Value |
|---|------|------------|-------|
| 1 | `oReadSamplePtrUnsGray*` → `iReadSamplePtrUnsGray_ms*` | `$hdl_bus_T` | **12.249 ns** |
| 2 | `iReadSamplePtrUnsGray_ms*` → `iReadSamplePtrUnsGray_reg*` | `0.5*$hdl_bus_T` | **6.124 ns** |

**OutputFifo PCC DataReg → bStateInDefaultClkDomainClean (BusClk → DmaClk):**

| # | Path | Expression | Value |
|---|------|------------|-------|
| 1 | `DataReg*` → `bStateInDefaultClkDomainClean_reg*` | `$hdl_dma_T` | **3.750 ns** |

### Summary of All Unique Delay Values

| Delay (ns) | Expression | Rule | Where Used |
|-----------|------------|------|------------|
| **1.875** | `0.5*$hdl_dma_T` | 0.5× DmaClk | 2nd sync stage in DmaClk domain |
| **3.750** | `$hdl_dma_T` | 1× DmaClk | 1st sync stage crossing into DmaClk |
| **6.124** | `0.5*$hdl_bus_T` | 0.5× BusClk | 2nd sync stage in BusClk domain |
| **7.499** | `2.0*$hdl_dma_T` | 2× DmaClk | Multi-bit data into DmaClk; reset recovery |
| **12.249** | `$hdl_bus_T` | 1× BusClk | 1st sync stage crossing into BusClk |
| **24.498** | `2.0*$hdl_bus_T` | 2× BusClk | Multi-bit data into BusClk (HBRC iStoredData) |

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

### InputFifo (`HdlSharedInputFifoInterface` / TargetToHost)

Push = DmaClk (250 MHz), Pop = PllClk80 (80 MHz)

| CDC Component | Type | Direction | Instance Path |
|--------------|------|-----------|---------------|
| StreamStateBlock.HandshakeStopStreamRequest | HandshakeBool | DmaClk → BusClk | `StreamStateBlock.HandshakeStopStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStopWithFlushRequest | HandshakeBool (response-only) | DmaClk → BusClk | `StreamStateBlock.HandshakeStopWithFlushRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStartStreamRequest | HandshakeBool | DmaClk → BusClk | `StreamStateBlock.HandshakeStartStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeFlushTimeoutRequest | HandshakeBool (response-only) | DmaClk → BusClk | `StreamStateBlock.HandshakeFlushTimeoutRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStateToBusClkDomain | HBRC | DmaClk → BusClk | `StreamStateBlock.HandshakeStateToBusClkDomain` |
| StreamStateBlock.HandshakeOverflowStopRequest | HBRC | DmaClk → BusClk | `StreamStateBlock.HandshakeOverflowStopRequest` |
| BlkOverflow.HandshakeOverflow | HBRC | DmaClk → BusClk | `BlkOverflow.HandshakeOverflow` |
| Write pointer gray code | Gray code | DmaClk → BusClk | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/SyncToOClk` |
| Disable signal | Double-sync | BusClk → DmaClk | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/SyncToOClk/DisableSignalClockCrossing` |
| Read pointer PCC | PCC | BusClk → DmaClk | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/OClkToIClkCrossing.SyncToIClk` |
| WritePointerHandshake | HBRC | DmaClk → BusClk | `DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx/WritePointerHandshake` |
| FifoClear ToPush DoubleSyncBool | DoubleSyncBool | BusClk → DmaClk | `DmaPortCommIfcComponentEnableChainx/.../PushSynchNeeded.ToPushDblSync` |
| FifoClear FromPush DoubleSyncBool | DoubleSyncBool | DmaClk → BusClk | `DmaPortCommIfcComponentEnableChainx/.../PushSynchNeeded.FromPushDblSync` |
| ClearToPush PulseSync | PulseSync+ack | BusClk → DmaClk | `.../NiFpgaFifoPortResetx/Crossing.ClearToPush` |
| PopToPush PulseSync | PulseSync | BusClk → DmaClk | `.../NiFpgaFifoPortResetx/Crossing.PopToPush/PulseSyncBasex` |
| PushToPop PulseSync | PulseSync | DmaClk → BusClk | `.../NiFpgaFifoPortResetx/Crossing.PushToPop/PulseSyncBasex` |

### OutputFifo (`HdlSharedOutputFifoInterface` / HostToTarget)

Push = PllClk80 (80 MHz), Pop = DmaClk (250 MHz)

| CDC Component | Type | Direction | Instance Path |
|--------------|------|-----------|---------------|
| StreamStateBlock.HandshakeStopStreamRequest | HandshakeBool | DmaClk → BusClk | `StreamStateBlock.HandshakeStopStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeStartStreamRequest | HandshakeBool | DmaClk → BusClk | `StreamStateBlock.HandshakeStartStreamRequest/HandshakeBasex` |
| StreamStateBlock.HandshakeUnderflowStopRequest | HBRC | DmaClk → BusClk | `StreamStateBlock.HandshakeUnderflowStopRequest` |
| BlkUnderflow.HandshakeUnderflow | HBRC | DmaClk → BusClk | `BlkUnderflow.HandshakeUnderflow` |
| HandshakeFullCount | HBRC | DmaClk → BusClk | `HandshakeFullCount` |
| Read pointer gray code | Gray code | DmaClk → BusClk | `DmaPortOutStrmFifox/DmaPortOutStrmFifoFlagsx` |
| Write pointer PCC | PCC | BusClk → DmaClk | `DmaPortOutStrmFifox/DmaPortOutStrmFifoFlagsx/IClkToOClkCrossing.SyncToOClk` |
| FifoClear ToPop DoubleSyncBool | DoubleSyncBool | BusClk → DmaClk | `DmaPortCommIfcComponentEnableChainx/.../PopSynchNeeded.ToPopDblSync` |
| FifoClear FromPop DoubleSyncBool | DoubleSyncBool | DmaClk → BusClk | `DmaPortCommIfcComponentEnableChainx/.../PopSynchNeeded.FromPopDblSync` |
| ClearToPop PulseSync | PulseSync+ack | BusClk → DmaClk | `.../NiFpgaFifoPortResetx/Crossing.ClearToPop` |
| PopToPush PulseSync | PulseSync | DmaClk → BusClk | `.../NiFpgaFifoPortResetx/Crossing.PopToPush/PulseSyncBasex` |
| PushToPop PulseSync | PulseSync | BusClk → DmaClk | `.../NiFpgaFifoPortResetx/Crossing.PushToPop/PulseSyncBasex` |

---

## Hierarchy Independence

All cell patterns use a leading `*` wildcard:

```
*InputFifo_inst/StreamStateBlock.HandshakeStopStreamRequest/...
```

This means the constraints work regardless of how many levels of hierarchy
wrap the FIFO instance.  For example, all of these match:

- `InputFifo_inst/StreamStateBlock...` (direct at top level)
- `InputFifoWrapper_inst/InputFifo_inst/StreamStateBlock...` (one wrapper)
- `MyDesign/SubBlock/InputFifo_inst/StreamStateBlock...` (deeply nested)

This was verified by adding an `InputFifoWrapper` entity around the
InputFifo and confirming the constraints still matched and timing was clean
(WNS = +0.118 ns).

---

## Relationship to Existing NI Constraints

The existing `constraints.xdc` already contains NI-generated CDC constraints
for the standard DMA FIFO endpoints (channels 0 and 1) that live inside the
LabVIEW FPGA window.  These are the `TNM_Custom1` through `TNM_Custom573`
assignments.

The HDL Shared FIFO constraints generated by `gen_constraints.py` cover the
**additional** FIFO endpoints (channels 2+) that are instantiated in user HDL
outside the LabVIEW window.  They use the exact same `get_cells` / `set_max_delay`
style as the NI constraints.

The NI constraints also have some optional paths that produce harmless
`CRITICAL WARNING: No valid object(s)` messages — these are for DMA channels
or features that don't exist in the current design configuration.  Our
constraints use `-quiet` to suppress these warnings for optional paths.

---

## Adding More FIFOs

To add constraints for additional FIFO instances:

1. Add the instance name to `INPUT_FIFOS` or `OUTPUT_FIFOS` in
   `gen_constraints.py`
2. Re-run `python gen_constraints.py`
3. Replace the HDL Shared FIFO CDC section at the end of `constraints.xdc`
   with the new output
4. Recompile

---

## Troubleshooting

### "No valid object(s)" warnings

If you see `CRITICAL WARNING: [Vivado 12-4739] set_max_delay: No valid
object(s)` for your FIFO constraints:

1. **Check the instance name** — Verify the VHDL instance name matches what
   you put in `INPUT_FIFOS`/`OUTPUT_FIFOS`.

2. **Audit cell names** — Open the synth checkpoint and list cells:
   ```tcl
   open_checkpoint FIFO_VI_2.runs/synth_1/MacallanTop.dcp
   get_cells -hierarchical -filter {NAME =~ "*YourFifoInst*" && IS_SEQUENTIAL==true}
   ```

3. **Check for optimized-away cells** — Some HandshakeBool instances
   (like `StopWithFlush`, `FlushTimeout`) have the push side optimized away
   by synthesis.  This is normal — the `-quiet` flag makes these no-ops.

### Timing violations on CDC paths

If you see timing violations specifically on FIFO CDC paths, verify:

1. The constraint delay values match your actual clock periods
2. The `hdl_dma_T` and `hdl_bus_T` variables are set correctly
3. No other constraints are conflicting (check for duplicate `set_max_delay`
   on the same paths)
