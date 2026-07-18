# NiSharedFifo — Theory of Operation

## Overview

The NiSharedFifo components (`NiSharedFifoWriter` and `NiSharedFifoReader`) provide DMA FIFO channels that transfer data between user HDL on the FPGA and a host application. These are the same DMA FIFO primitives used internally by LabVIEW FPGA, exposed for direct instantiation in custom HDL designs.

- **NiSharedFifoWriter** — Target-to-Host (FPGA → Host). User HDL writes data into the FIFO; the host reads it via DMA.
- **NiSharedFifoReader** — Host-to-Target (Host → FPGA). The host writes data via DMA; user HDL reads it from the FIFO.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Host PC                                     │
│   (NI RIO driver, FPGA Interface C API, or LabVIEW Host VI)         │
└─────────────────────┬───────────────────────────────────────────────┘
                      │  PCIe / DMA
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Communication Interface (CommIfc)                        │
│   Manages DMA channels, stream state machines, and bus arbitration    │
│   Configured by kDmaFifoConfArray in PkgCommIntConfiguration         │
└──────────┬────────────────────────────────┬─────────────────────────┘
           │                                │
           │ InputStreamInterface           │ OutputStreamInterface
           │ (TargetToHost / Writer)        │ (HostToTarget / Reader)
           ▼                                ▼
┌─────────────────────┐          ┌─────────────────────────┐
│  NiSharedFifoWriter │          │   NiSharedFifoReader    │
│  (FPGA → Host)      │          │   (Host → FPGA)         │
│                     │          │                         │
│  User writes data   │          │  User reads data        │
│  via ViClk-domain   │          │  via ViClk-domain       │
│  interface          │          │  interface              │
└─────────────────────┘          └─────────────────────────┘
           ▲                                ▲
           │                                │
           │  User HDL logic                │  User HDL logic
           │  (your design)                 │  (your design)
```

## Configuration Flow

### 1. System-Level Configuration (`PkgCommIntConfiguration`)

The system defines a fixed-size array of DMA channel configurations:

```vhdl
constant kDmaFifoConfArray : DmaChannelConfArray_t(0 to kNumberOfDmaChannels-1);
```

Each entry is a `DmaChannelConfiguration_t` record specifying the mode, depth, width, base address, and other parameters for one DMA channel. The Communication Interface uses this array to configure all DMA hardware.

### 2. User-Level Configuration (`PkgUserHdl` + `PkgNiSharedFifo`)

Users define their FIFOs using the simplified `UserDmaFifoConf_t` record in `PkgUserHdl`:

```vhdl
constant kUserHdlDmaFifoConf : UserDmaFifoConfArray_t(0 to kNumUserHdlDmaChannels - 1) := (
  0 => (FifoDepth => 1029, DataType => kInteger32, ElementsPerClockCycle => 1,
        Mode => NiFpgaHostToTarget),
  1 => (FifoDepth => 1023, DataType => kInteger32, ElementsPerClockCycle => 1,
        Mode => NiFpgaTargetToHost)
);
```

The `DataType` field is a `FifoDataType_t` value (defined in `PkgNiSharedFifo`) that
captures both the element width and signedness in one enum — for example `kInteger32`,
`kUnsigned16`, `kBoolean`, or `kSingle`. The helper functions `FifoDataWidth(DataType)` and
`FifoDataIsSigned(DataType)` derive the bit width and sign behavior from it, so you no
longer specify width and signedness separately.

The `MergeDmaFifoConf` function in `PkgNiSharedFifo` expands these simplified entries into full `DmaChannelConfiguration_t` records and merges them into the system array starting at `kUserHdlDmaStartIndex`, growing downward. That start index is a per-target *derived* constant defined in `PkgUserHdl` (not in the shared `PkgNiSharedFifo`), computed as `kNumberOfDmaChannels - 1 - kNumFixedLogicDmaStreams` from the generated `PkgCommIntConfiguration` and `PkgNiHdlSettings` packages.

### 3. Channel Index Assignment

User FIFO channels are assigned system DMA channel indices as follows:

```
UserConf(0) → System channel kUserHdlDmaStartIndex
UserConf(1) → System channel kUserHdlDmaStartIndex - 1
UserConf(2) → System channel kUserHdlDmaStartIndex - 2
...
```

Each channel's DMA register base address is computed by:

```vhdl
BaseAddress = 0x3FFC0 - ChannelIndex * 0x40
```

## Stream State Machine

Each FIFO channel has a stream state that governs data flow. The state is represented by `StreamStateValue_t` (`std_logic_vector(1 downto 0)`):

| State | Value | Description |
|-------|-------|-------------|
| **Unlinked** | `"00"` | Channel is not connected. No data transfer occurs. Initial state after reset. |
| **Disabled** | `"01"` | Channel is linked but not actively streaming. The host has configured the channel but streaming has not started (or has been stopped). |
| **Enabled** | `"10"` | Channel is actively streaming. Data transfers are occurring between host and FPGA. |
| **Flushing** | `"11"` | Writer FIFO only. The FIFO is draining remaining data to the host before transitioning to Disabled. |

### State Transitions (User Perspective)

```
              StartStreamRequest
  Disabled ──────────────────────► Enabled
     ▲                                │
     │         StopRequestStrobe      │
     └────────────────────────────────┘
     ▲                                │
     │  StopWithFlushRequestStrobe    │
     └──────── Flushing ◄─────────────┘
                              (Writer only)
```

The stream state is managed by the Communication Interface. User HDL controls transitions by asserting:
- `vStartStreamRequest` — Request transition from Disabled → Enabled
- `vStopRequestStrobe` — Request immediate stop (Enabled → Disabled)
- `vStopWithFlushRequestStrobe` — Writer only: flush remaining data before stopping (Enabled → Flushing → Disabled)

## Clock Domains

Each FIFO has two clock domains:

| Clock | Purpose |
|-------|---------|
| **BusClk** | The DMA bus clock. Connects to the Communication Interface stream ports. This is the DMA engine's clock domain. |
| **ViClk** | The user logic clock. All user-facing data, control, and status ports operate in this domain. Can be the same as BusClk or a different clock. |

The FIFO internally handles clock-domain crossing between BusClk and ViClk.

## FIFO Depth Sizing

### Target-to-Host (Writer) FIFOs

Depth must be `2^N - 1`, with:
- Minimum: 63
- Maximum: 1,048,575 (2^20 - 1)

### Host-to-Target (Reader) FIFOs

Depth must be `(2^N + 6 × ElementsPerClockCycle) - 1`. The extra `6 × ElementsPerClockCycle` elements provide buffering required for the NI DMA engine to achieve maximum throughput.

- Minimum: 63 + 6 × ElementsPerClockCycle
- Maximum: 1,048,575 + 6 × ElementsPerClockCycle

### Maximum Depth by Data Width

| Data Width | Maximum Depth |
|-----------|---------------|
| Boolean (1-bit) | 2,097,151 (2^21 - 1) |
| 16-bit | 1,048,575 (2^20 - 1) |
| 32-bit | 524,287 (2^19 - 1) |
| 64-bit | 262,143 (2^18 - 1) |

For fixed-point data types, round up to the nearest standard width (16/32/64) and use the corresponding maximum.

## Data Width and Packing

- `DataType` (a `FifoDataType_t` enum) determines the width and signedness of a single data element. `FifoDataWidth(DataType)` maps it to the `kSampleWidth` generic (8–64 bits) and `FifoDataIsSigned(DataType)` maps it to the `kSignExtend` generic.
- `ElementsPerClockCycle` (mapped to `kNumOfSamplesPerRead`/`kNumOfSamplesPerWrite`) specifies how many elements are transferred per clock cycle. Valid values: 1, 2, 4, 8, 16, 32, or 64.
- The total user data port width is `FifoDataWidth(DataType) × ElementsPerClockCycle` bits.

## DMA Channel Modes

The `DmaChannelMode_t` enumeration defines the channel's transfer direction:

| Mode | Direction | Entity |
|------|-----------|--------|
| `NiFpgaTargetToHost` | FPGA → Host | `NiSharedFifoWriter` |
| `NiFpgaHostToTarget` | Host → FPGA | `NiSharedFifoReader` |
| `NiFpgaPeerToPeerWriter` | P2P source | `NiSharedFifoWriter` (with `kPeerToPeer => true`) |
| `NiFpgaPeerToPeerReader` | P2P sink | `NiSharedFifoReader` (with `kPeerToPeer => true`) |
| `Disabled` | None | No FIFO instantiated |

## Stream Interface Records

The Communication Interface connects to each FIFO through paired record types. Each direction (Writer/Reader) uses a different pair:

### Writer (Target-to-Host) — `InputStreamInterface`

| Record | Direction | Purpose |
|--------|-----------|---------|
| `InputStreamInterfaceToFifo_t` | CommIfc → Writer FIFO | DMA pop commands, reset, stream state |
| `InputStreamInterfaceFromFifo_t` | Writer FIFO → CommIfc | Data output, flow control, stream requests |

### Reader (Host-to-Target) — `OutputStreamInterface`

| Record | Direction | Purpose |
|--------|-----------|---------|
| `OutputStreamInterfaceToFifo_t` | CommIfc → Reader FIFO | DMA write commands, data input, stream state |
| `OutputStreamInterfaceFromFifo_t` | Reader FIFO → CommIfc | Flow control, underflow status, stream requests |

These interfaces are managed entirely by the Communication Interface and the FIFO cores. User HDL does **not** interact with these records directly—they are simply wired through from the top-level entity ports to the FIFO instances.

### Unused Direction Handling

Each FIFO entity port pair has both an Input and Output stream interface at the top level. Only one direction is active per channel:
- A Writer (TargetToHost) channel uses the **Input** stream interface; the **Output** interface must be driven to zero.
- A Reader (HostToTarget) channel uses the **Output** stream interface; the **Input** interface must be driven to zero.

Use the provided zero constants:
```vhdl
dWriterOutputStreamInterfaceFromFifo <= kOutputStreamInterfaceFromFifoZero;
dReaderInputStreamInterfaceFromFifo  <= kInputStreamInterfaceFromFifoZero;
```
