# NiSharedFifo — Instantiation and Interface Guide

## Prerequisites

Your design must include the following packages:

```vhdl
library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;
  use work.PkgDmaPortDmaFifos.all;
  use work.PkgDmaPortCommIfcStreamStates.all;
  use work.PkgNiSharedFifo.all;
  use work.PkgUserHdl.all;
```

## Step 1: Define FIFO Channels in PkgUserHdl

Edit `PkgUserHdl.vhd` to declare your FIFO channels using `UserDmaFifoConf_t`:

```vhdl
constant kNumUserHdlDmaChannels : natural := 2;

constant kUserHdlDmaFifoConf : UserDmaFifoConfArray_t(0 to kNumUserHdlDmaChannels - 1) := (
  0 => (FifoDepth => 1029, DataType => kInteger32, ElementsPerClockCycle => 1,
        Mode => NiFpgaHostToTarget),
  1 => (FifoDepth => 1023, DataType => kInteger32, ElementsPerClockCycle => 1,
        Mode => NiFpgaTargetToHost)
);
```

### UserDmaFifoConf_t Fields

| Field | Type | Description |
|-------|------|-------------|
| `FifoDepth` | natural | Number of elements the FIFO can hold. See depth sizing rules below. |
| `DataType` | FifoDataType_t | Host data type. The element width and signedness are derived automatically (see table below). |
| `ElementsPerClockCycle` | natural | Elements transferred per clock. Valid: 1, 2, 4, 8, 16, 32, 64. |
| `Mode` | DmaChannelMode_t | `NiFpgaHostToTarget` (Reader) or `NiFpgaTargetToHost` (Writer). |

### Supported Data Types

These are the only data types the host API supports for DMA FIFOs. Selecting one
sets the FIFO width and signedness automatically — you never specify them directly.

| `DataType` | Host type | Width | Signed |
|------------|-----------|-------|--------|
| `kBoolean` | Boolean | 8 | no (maps to U8) |
| `kUnsigned8` | U8 | 8 | no |
| `kInteger8` | I8 | 8 | yes |
| `kUnsigned16` | U16 | 16 | no |
| `kInteger16` | I16 | 16 | yes |
| `kUnsigned32` | U32 | 32 | no |
| `kInteger32` | I32 | 32 | yes |
| `kUnsigned64` | U64 | 64 | no |
| `kInteger64` | I64 | 64 | yes |
| `kSingle` | SGL | 64 | no (single-precision float) |

### FIFO Depth Rules

**Target-to-Host (Writer):** `2^N - 1` (minimum 63, maximum depends on data width)

**Host-to-Target (Reader):** `(2^N + 6 × ElementsPerClockCycle) - 1`

The extra `6 × ElementsPerClockCycle` elements are required for DMA engine buffering.

Examples for `ElementsPerClockCycle = 1`:
- 1024-element Reader FIFO: depth = `(1024 + 6) - 1 = 1029`
- 1024-element Writer FIFO: depth = `1024 - 1 = 1023`

---

## Step 2: Declare Entity Ports for Stream Interfaces

Your UserHdl entity needs stream interface ports for each FIFO channel. Each channel requires both Input and Output stream interfaces at the entity level (one direction is active, the other is driven to zero):

```vhdl
entity UserHdl is
  port(
    BusClk         : in  std_logic;
    DmaClk         : in  std_logic;
    aBusReset      : in  boolean;
    abDiagramReset : in  boolean;

    bRegPortIn  : in  RegPortIn_t;
    bRegPortOut : out RegPortOut_t;

    -- Writer FIFO (TargetToHost) stream interfaces
    dWriterInputStreamInterfaceToFifo    : in  InputStreamInterfaceToFifo_t;
    dWriterInputStreamInterfaceFromFifo  : out InputStreamInterfaceFromFifo_t;
    dWriterOutputStreamInterfaceToFifo   : in  OutputStreamInterfaceToFifo_t;
    dWriterOutputStreamInterfaceFromFifo : out OutputStreamInterfaceFromFifo_t;

    -- Reader FIFO (HostToTarget) stream interfaces
    dReaderInputStreamInterfaceToFifo    : in  InputStreamInterfaceToFifo_t;
    dReaderInputStreamInterfaceFromFifo  : out InputStreamInterfaceFromFifo_t;
    dReaderOutputStreamInterfaceToFifo   : in  OutputStreamInterfaceToFifo_t;
    dReaderOutputStreamInterfaceFromFifo : out OutputStreamInterfaceFromFifo_t
  );
end entity UserHdl;
```

---

## Step 3: Instantiate NiSharedFifoWriter (Target-to-Host)

The Writer FIFO accepts data from your HDL logic and transfers it to the host via DMA.

```vhdl
WriterFifo_inst : entity work.NiSharedFifoWriter
  generic map(
    kFifoDepth            => kUserHdlDmaFifoConf(1).FifoDepth,
    kSampleWidth          => FifoDataWidth(kUserHdlDmaFifoConf(1).DataType),
    kNumOfSamplesPerWrite => kUserHdlDmaFifoConf(1).ElementsPerClockCycle,
    kSignExtend           => FifoDataIsSigned(kUserHdlDmaFifoConf(1).DataType),
    kFxpType              => false,
    kPeerToPeer           => false,
    kDisableOnFifoTimeout => false
  )
  port map(
    aDiagramReset                 => abDiagramReset,
    aBusReset                     => aBusReset,
    BusClk                        => DmaClk,
    bInputStreamInterfaceToFifo   => dWriterInputStreamInterfaceToFifo,
    bInputStreamInterfaceFromFifo => dWriterInputStreamInterfaceFromFifo,
    ViClk                         => BusClk,
    vDataIn                       => bWriterFifoDataIn,
    vFull                         => bWriterFifoFull,
    vWriteFifo                    => bWriterFifoWriteStrobe,
    vFlush                        => false,
    vCtCount                      => bWriterFifoCtCount,
    vInputValid                   => bWriterFifoInputValid,
    vReadyForInput                => bWriterFifoReadyForInput,
    vStreamStateOut               => bWriterFifoStreamState,
    vStartStreamRequest           => bWriterFifoStartReq,
    vStopRequestStrobe            => bWriterFifoStopReq,
    vFlushTimeoutRequest          => false,
    vStopWithFlushRequestStrobe   => false
  );

-- Drive unused Output direction to zero
dWriterOutputStreamInterfaceFromFifo <= kOutputStreamInterfaceFromFifoZero;
```

### Writer Generics

| Generic | Source | Description |
|---------|--------|-------------|
| `kFifoDepth` | `UserDmaFifoConf.FifoDepth` | FIFO depth (`2^N - 1`) |
| `kSampleWidth` | `FifoDataWidth(UserDmaFifoConf.DataType)` | Bit width of one element |
| `kNumOfSamplesPerWrite` | `UserDmaFifoConf.ElementsPerClockCycle` | Elements per write |
| `kSignExtend` | `FifoDataIsSigned(UserDmaFifoConf.DataType)` | Sign-extend data before host transfer |
| `kFxpType` | — | Fixed-point data type flag (tie `false`) |
| `kPeerToPeer` | — | `true` for peer-to-peer source stream |
| `kDisableOnFifoTimeout` | — | `true` to auto-disable on overflow |

### Writer User Interface Ports (ViClk domain)

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `ViClk` | in | `std_logic` | User logic clock |
| `vDataIn` | in | `std_logic_vector(kSampleWidth*kNumOfSamplesPerWrite-1 downto 0)` | Data to write into FIFO |
| `vFull` | out | `boolean` | FIFO is full; do not write |
| `vWriteFifo` | in | `boolean` | Write enable — assert together with `vInputValid` to push a sample; may be held to write continuously |
| `vFlush` | in | `boolean` | Flush partial data to host (tie `false` if unused) |
| `vCtCount` | out | `unsigned(31 downto 0)` | Current number of elements in FIFO |
| `vInputValid` | in | `boolean` | Handshaking: data on `vDataIn` is valid |
| `vReadyForInput` | out | `boolean` | Handshaking: FIFO is ready to accept data |
| `vStreamStateOut` | out | `StreamStateValue_t` | Current stream state |
| `vStartStreamRequest` | in | `boolean` | Assert to request Disabled → Enabled transition |
| `vStopRequestStrobe` | in | `boolean` | Assert to request immediate stop |
| `vFlushTimeoutRequest` | in | `boolean` | Assert to trigger flush timeout (tie `false` if unused) |
| `vStopWithFlushRequestStrobe` | in | `boolean` | Assert to flush then stop (tie `false` if unused) |

### Writer Bus Interface Ports (BusClk/DmaClk domain)

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `aDiagramReset` | in | `boolean` | Asynchronous diagram reset |
| `aBusReset` | in | `boolean` | Asynchronous bus reset |
| `BusClk` | in | `std_logic` | DMA bus clock (connect to `DmaClk`) |
| `bInputStreamInterfaceToFifo` | in | `InputStreamInterfaceToFifo_t` | From Communication Interface |
| `bInputStreamInterfaceFromFifo` | out | `InputStreamInterfaceFromFifo_t` | To Communication Interface |

---

## Step 4: Instantiate NiSharedFifoReader (Host-to-Target)

The Reader FIFO receives data from the host via DMA and makes it available to your HDL logic.

```vhdl
ReaderFifo_inst : entity work.NiSharedFifoReader
  generic map(
    kFifoDepth            => kUserHdlDmaFifoConf(0).FifoDepth,
    kSampleWidth          => FifoDataWidth(kUserHdlDmaFifoConf(0).DataType),
    kNumOfSamplesPerRead  => kUserHdlDmaFifoConf(0).ElementsPerClockCycle,
    kFxpType              => false,
    kPeerToPeer           => false,
    kDisableOnFifoTimeout => false
  )
  port map(
    aDiagramReset                  => abDiagramReset,
    aBusReset                      => aBusReset,
    BusClk                         => DmaClk,
    bOutputStreamInterfaceToFifo   => dReaderOutputStreamInterfaceToFifo,
    bOutputStreamInterfaceFromFifo => dReaderOutputStreamInterfaceFromFifo,
    ViClk                          => BusClk,
    vDataOut                       => bReaderFifoDataOut,
    vEmpty                         => bReaderFifoEmpty,
    vReadFifo                      => bReaderFifoReadStrobe,
    vCtCount                       => bReaderFifoCtCount,
    vOutputValid                   => bReaderFifoOutputValid,
    vReadyForOutput                => true,
    vStreamStateOut                => bReaderFifoStreamState,
    vStartStreamRequest            => bReaderFifoStartReq,
    vStopRequestStrobe             => bReaderFifoStopReq
  );

-- Drive unused Input direction to zero
dReaderInputStreamInterfaceFromFifo <= kInputStreamInterfaceFromFifoZero;
```

### Reader Generics

| Generic | Source | Description |
|---------|--------|-------------|
| `kFifoDepth` | `UserDmaFifoConf.FifoDepth` | FIFO depth (`(2^N + 6*EPC) - 1`) |
| `kSampleWidth` | `FifoDataWidth(UserDmaFifoConf.DataType)` | Bit width of one element |
| `kNumOfSamplesPerRead` | `UserDmaFifoConf.ElementsPerClockCycle` | Elements per read |
| `kFxpType` | — | Fixed-point data type flag (tie `false`) |
| `kPeerToPeer` | — | `true` for peer-to-peer sink stream |
| `kDisableOnFifoTimeout` | — | `true` to auto-disable on underflow |

### Reader User Interface Ports (ViClk domain)

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `ViClk` | in | `std_logic` | User logic clock |
| `vDataOut` | out | `std_logic_vector(kSampleWidth*kNumOfSamplesPerRead-1 downto 0)` | Data read from FIFO |
| `vEmpty` | out | `boolean` | FIFO is empty; no data available |
| `vReadFifo` | in | `boolean` | Read enable — assert to request data; may be held to stream continuously. Wait for `vOutputValid` before capturing `vDataOut` |
| `vCtCount` | out | `unsigned(31 downto 0)` | Current number of elements in FIFO |
| `vOutputValid` | out | `boolean` | Handshaking: data on `vDataOut` is valid |
| `vReadyForOutput` | in | `boolean` | Handshaking: user is ready to accept data (tie `true` if always ready) |
| `vStreamStateOut` | out | `StreamStateValue_t` | Current stream state |
| `vStartStreamRequest` | in | `boolean` | Assert to request Disabled → Enabled transition |
| `vStopRequestStrobe` | in | `boolean` | Assert to request immediate stop |

### Reader Bus Interface Ports (BusClk/DmaClk domain)

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `aDiagramReset` | in | `boolean` | Asynchronous diagram reset |
| `aBusReset` | in | `boolean` | Asynchronous bus reset |
| `BusClk` | in | `std_logic` | DMA bus clock (connect to `DmaClk`) |
| `bOutputStreamInterfaceToFifo` | in | `OutputStreamInterfaceToFifo_t` | From Communication Interface |
| `bOutputStreamInterfaceFromFifo` | out | `OutputStreamInterfaceFromFifo_t` | To Communication Interface |

---

## Interface Rules and Timing

See [interface-descriptions.md](interface-descriptions.md) for complete signal timing rules, strobe definitions, data validity contracts, and handshaking protocols for both the Writer and Reader interfaces.

---

## Step 5: Stream Start/Stop Control

Before data can flow through a FIFO, you must transition the stream from Disabled to Enabled. This is done by asserting `vStartStreamRequest` for one clock cycle.

### Typical Start/Stop Pattern

```vhdl
StartStopGlue : process(BusClk)
begin
  if aBusReset then
    bFifoStartReq <= false;
    bFifoStopReq  <= false;
  elsif rising_edge(BusClk) then
    bFifoStartReq <= false;
    bFifoStopReq  <= false;

    -- Start stream (one-cycle pulse)
    if start_condition then
      bFifoStartReq <= true;
    end if;

    -- Stop stream (one-cycle pulse)
    if stop_condition then
      bFifoStopReq <= true;
    end if;
  end if;
end process StartStopGlue;
```

### Stream State Monitoring

```vhdl
signal bStreamState : StreamStateValue_t;
-- ...
-- Check if stream is enabled before writing/reading:
if bStreamState = kStreamStateEnabled then
  -- Safe to write/read
end if;
```

Stream state constants from `PkgDmaPortCommIfcStreamStates`:

| Constant | Value | Meaning |
|----------|-------|---------|
| `kStreamStateUnlinked` | `"00"` | Not connected |
| `kStreamStateDisabled` | `"01"` | Linked but not streaming |
| `kStreamStateEnabled` | `"10"` | Actively streaming |
| `kStreamStateFlushing` | `"11"` | Draining (Writer only) |

---

## Step 6: Writing Data (Writer FIFO)

### Simple Write (Polling)

```vhdl
WriteLogic : process(ViClk)
begin
  if rising_edge(ViClk) then
    bWriteStrobe <= false;
    bInputValid  <= false;

    if not bFifoFull and data_ready then
      bDataIn      <= my_data;
      bInputValid  <= true;
      bWriteStrobe <= true;
    end if;
  end if;
end process WriteLogic;
```

### Key Rules for Writing

1. Do not present a sample (`vWriteFifo` + `vInputValid`) when `vFull = true` — the sample is dropped (overflow). Check `vFull` (or use `vReadyForInput` handshaking) first.
2. A sample is pushed on every `ViClk` cycle where both `vWriteFifo` and `vInputValid` are asserted. `vWriteFifo` is an enable and may be held across multiple cycles.
3. `vDataIn` must be stable on each cycle a sample is presented.
4. Writes are buffered regardless of stream state; the data drains to the host once the stream reaches Enabled. There is no need to gate writes on the stream state.

---

## Step 7: Reading Data (Reader FIFO)

### Simple Read (Polling)

```vhdl
ReadLogic : process(ViClk)
begin
  if rising_edge(ViClk) then
    bReadStrobe <= false;

    if not bFifoEmpty then
      bReadStrobe <= true;
    end if;

    -- Capture data when valid
    if bOutputValid then
      captured_data <= bDataOut;
    end if;
  end if;
end process ReadLogic;
```

### Key Rules for Reading

1. Asserting `vReadFifo` while `vEmpty = true` is harmless — the pop is gated internally, so no data is lost. The common idiom is to assert `vReadFifo` and wait for `vOutputValid`.
2. `vReadFifo` is a read *enable*: pulse it for a single read or hold it asserted to stream continuously.
3. Data appears on `vDataOut` with `vOutputValid` asserted one or more cycles after the read request. Capture `vDataOut` only when `vOutputValid = true`.
4. If using handshaking, assert `vReadyForOutput` when you can accept data. Tie to `true` if always ready. Asserting `vReadyForOutput` while `vEmpty` flags an underflow (disables the stream when `kDisableOnFifoTimeout`).
5. Data only emerges (`vOutputValid`) while the stream is Enabled; you do not need to gate `vReadFifo` on the stream state.

---

## Complete Example: Register-Controlled FIFOs

The `UserHdl.vhd` reference design demonstrates a complete implementation where host register writes trigger FIFO operations:

### Writer Flow (FPGA → Host)
1. Host writes data to the WriterData register
2. The register write event triggers a one-cycle pulse on `vWriteFifo`
3. Data is pushed into NiSharedFifoWriter
4. The Communication Interface DMA engine transfers data to host memory

### Reader Flow (Host → FPGA)
1. Host sends data via DMA into NiSharedFifoReader
2. Host writes to the ReaderStrobe register to trigger a pop
3. The register write event triggers a one-cycle pulse on `vReadFifo`
4. When `vOutputValid` asserts, the data is latched into the ReaderData register
5. Host reads the ReaderData register to retrieve the value

### Start/Stop Flow
1. Host writes bit 0 = 1 to the StartStop register → `vStartStreamRequest` pulse
2. Stream transitions Disabled → Enabled; data can now flow
3. Host writes bit 1 = 1 to the StartStop register → `vStopRequestStrobe` pulse
4. Stream transitions Enabled → Disabled; data flow stops

---

## Signal Naming Conventions

| Prefix | Meaning |
|--------|---------|
| `a` | Asynchronous signal (not clocked) |
| `b` | BusClk domain signal |
| `d` | DmaClk domain signal |
| `v` | ViClk (user clock) domain signal |
| `k` | Constant/generic |

---

## Checklist

- [ ] Define `kUserHdlDmaFifoConf` in `PkgUserHdl.vhd` with correct Mode, Depth, and DataType
- [ ] Verify depth follows sizing rules (Reader adds `6 × ElementsPerClockCycle`)
- [ ] Instantiate `NiSharedFifoWriter` for each TargetToHost channel
- [ ] Instantiate `NiSharedFifoReader` for each HostToTarget channel
- [ ] Connect stream interfaces from entity ports to FIFO instances
- [ ] Drive unused stream direction outputs to zero constants
- [ ] Implement start/stop control logic (one-cycle pulses)
- [ ] Check `vFull` before presenting a sample (writing while full drops it); wait for `vOutputValid` when reading
- [ ] Connect `BusClk` port to `DmaClk` (not the user logic clock)
- [ ] Connect `ViClk` port to your user logic clock
