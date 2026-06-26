# NiSharedFifo — Interface Descriptions

## NiSharedFifoWriter (Target-to-Host, FPGA → Host)

The Writer FIFO accepts data from user HDL logic and transfers it to the host via DMA.

### User Interface Ports (ViClk Domain)

All user-side signals are synchronous to `ViClk`. They are sampled and driven on the rising edge of `ViClk`.

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
| `vStartStreamRequest` | in | `boolean` | Strobe: assert for one cycle to request Disabled → Enabled |
| `vStopRequestStrobe` | in | `boolean` | Strobe: assert for one cycle to request immediate stop |
| `vFlushTimeoutRequest` | in | `boolean` | Strobe: assert to trigger flush timeout (tie `false` if unused) |
| `vStopWithFlushRequestStrobe` | in | `boolean` | Strobe: assert for one cycle to flush then stop |

### What Is a Strobe Signal?

A **request** signal is asserted (`true`) to trigger a single action such as starting or stopping the stream. Asserting it for one `ViClk` cycle is the recommended usage. These requests are crossed into the BusClk domain through a `HandshakeBool` (and the stop request is also consumed as a level), so holding one asserted for several cycles is also legal and harmless — it is acted on once. The FIFO samples requests on the rising edge of `ViClk`.

```
ViClk:    ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
           └──┘  └──┘  └──┘  └──┘  └──┘
Request:  ─────┐     ┌──────────────────────
                └────┘  (one cycle high — recommended)
```

Writer request signals (assert for one `ViClk` cycle; may also be held):
- `vStartStreamRequest` — requests stream enable
- `vStopRequestStrobe` — requests immediate stream stop
- `vStopWithFlushRequestStrobe` — requests flush-then-stop

`vWriteFifo` is **not** a request: it is a write enable that may be held high
across many cycles while `vInputValid` pulses per sample. A sample is pushed on
every cycle where both `vWriteFifo` and `vInputValid` are asserted and the FIFO
is not full.

**Rule:** Never hold a request signal (start / stop / stop-with-flush) longer
than needed. Asserting for one `ViClk` cycle is the recommended usage, but
holding a request is tolerated because it is crossed through a `HandshakeBool`
and acted on once. Each request triggers exactly one action.

### Writing Data

When writing to the Writer FIFO, `vDataIn` must be **stable and valid on the same clock edge** that `vWriteFifo` is sampled as `true`. Both `vWriteFifo` and `vInputValid` must be asserted on the same cycle.

```
ViClk:       ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──
              └──┘  └──┘  └──┘  └──┘
vDataIn:     ──────╳ VALID DATA ╳──────
vInputValid: ─────┐             ┌─────
                   └─────────────┘
vWriteFifo:  ─────┐             ┌─────
                   └─────────────┘
                   ▲
                   FIFO captures data here
```

**Rules:**
1. Assert `vWriteFifo` together with `vInputValid` to push a sample. `vWriteFifo`
   may be held high across multiple cycles; a sample is pushed on every cycle
   both are asserted and the FIFO is not full.
2. `vDataIn` must be stable (not changing) on each cycle a sample is presented.
3. Do **not** present a sample (`vWriteFifo` and `vInputValid`) when `vFull = true`.
   The sample is dropped (overflow).
4. After a write cycle, `vDataIn` may change freely.
5. Writes are buffered into the FIFO regardless of the stream state. The buffered
   data does not drain to the host until the stream reaches the Enabled state, so
   writing while the stream is still transitioning to Enabled is legal.

### Status Signals

| Signal | Meaning | When to check |
|--------|---------|---------------|
| `vFull` | FIFO cannot accept more data | Check **before** asserting `vWriteFifo` |
| `vCtCount` | Number of elements currently in the FIFO | Informational; can read at any time |

Status signals update every `ViClk` cycle and reflect the current FIFO state. They may change on the cycle immediately after a write operation.

### Handshaking Mode vs. Polling Mode

**Polling mode** (simpler):
- Check `vFull` → if not full, assert both `vWriteFifo` and `vInputValid` for one cycle
- This is the recommended approach for most designs

**Handshaking mode** (back-pressure):
- Assert `vInputValid` when data is available on `vDataIn`
- Wait for `vReadyForInput = true` before asserting `vWriteFifo`
- The FIFO uses `vReadyForInput` to signal it can accept data

### Stream State

The `vStreamStateOut` output reflects the current state of the DMA stream. It updates synchronously to `ViClk`.

| Constant | Value | Meaning |
|----------|-------|---------|
| `kStreamStateUnlinked` | `"00"` | Not connected |
| `kStreamStateDisabled` | `"01"` | Linked but not streaming |
| `kStreamStateEnabled` | `"10"` | Actively streaming — safe to write |
| `kStreamStateFlushing` | `"11"` | Draining buffered data to host |

**Rule:** Writes are buffered regardless of stream state; the data only drains to
the host once `vStreamStateOut = kStreamStateEnabled`. The real hazard is
overflow — do not present a sample while `vFull = true`.

### Start/Stop Timing

- `vStartStreamRequest` — Assert for one `ViClk` cycle (may also be held). The stream will not transition instantly; monitor `vStreamStateOut` to confirm the Enabled state before beginning data transfer.
- `vStopRequestStrobe` — Assert for one `ViClk` cycle (may also be held). The stream transitions to Disabled. In-flight data in the FIFO may be lost.
- `vStopWithFlushRequestStrobe` — Assert for one `ViClk` cycle (may also be held). The stream enters Flushing state, drains all buffered data to the host, then transitions to Disabled. Use this for graceful shutdown.

**Rule:** Do not assert start and stop simultaneously. Only assert one request per clock cycle.

### Reset Behavior

| Signal | Type | Effect |
|--------|------|--------|
| `aBusReset` | Asynchronous, active-high boolean | Resets all bus-side logic. FIFO contents are lost. Stream returns to Unlinked. |
| `aDiagramReset` | Asynchronous, active-high boolean | Resets the user-side diagram logic. |

**Rule:** After reset de-asserts, wait for `vStreamStateOut` to reach Disabled before issuing a start request. Do not attempt FIFO operations during or immediately after reset.

### Summary of Writer Timing Rules

| Rule | Description |
|------|-------------|
| Request strobes one cycle (or held) | Asserting a request (start / stop / stop-with-flush) for one `ViClk` cycle is recommended; holding it is tolerated (crossed through a `HandshakeBool`). `vWriteFifo` is a held enable, not a strobe |
| Data with valid | `vDataIn` must be stable when `vWriteFifo` and `vInputValid` are asserted |
| Check full first | Never present a sample when `vFull = true` (the sample is dropped / overflow) |
| Writes are buffered | Writes are accepted regardless of stream state; data drains to the host only once Enabled |
| One request at a time | Do not assert start and stop simultaneously |
| Respect reset | Wait for Disabled state after reset before starting |

---

## NiSharedFifoReader (Host-to-Target, Host → FPGA)

The Reader FIFO receives data from the host via DMA and makes it available to user HDL logic.

### User Interface Ports (ViClk Domain)

All user-side signals are synchronous to `ViClk`. They are sampled and driven on the rising edge of `ViClk`.

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `ViClk` | in | `std_logic` | User logic clock |
| `vDataOut` | out | `std_logic_vector(kSampleWidth*kNumOfSamplesPerRead-1 downto 0)` | Data read from FIFO |
| `vEmpty` | out | `boolean` | FIFO is empty; no data available |
| `vReadFifo` | in | `boolean` | Read enable — assert to request data; may be held to stream continuously |
| `vCtCount` | out | `unsigned(31 downto 0)` | Current number of elements in FIFO |
| `vOutputValid` | out | `boolean` | Data on `vDataOut` is valid this cycle — capture it now |
| `vReadyForOutput` | in | `boolean` | User is ready to accept data; tie `true` if always ready |
| `vStreamStateOut` | out | `StreamStateValue_t` | Current stream state |
| `vStartStreamRequest` | in | `boolean` | Strobe: assert for one cycle to request Disabled → Enabled |
| `vStopRequestStrobe` | in | `boolean` | Strobe: assert for one cycle to request immediate stop |

### What Is a Strobe Signal?

A **request** signal is asserted (`true`) to trigger a single action such as starting or stopping the stream. Asserting it for one `ViClk` cycle is the recommended usage. These requests are crossed into the BusClk domain through a `HandshakeBool` (and the stop request is also consumed as a level), so holding one asserted for several cycles is also legal and harmless — it is acted on once. The FIFO samples requests on the rising edge of `ViClk`.

```
ViClk:    ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
           └──┘  └──┘  └──┘  └──┘  └──┘
Request:  ─────┐     ┌───────────────────────
                └────┘  (one cycle high — recommended)
```

Reader request signals (assert for one `ViClk` cycle; may also be held):
- `vStartStreamRequest` — requests stream enable
- `vStopRequestStrobe` — requests immediate stream stop

`vReadFifo` is **not** a strobe — it is a continuous read *enable*. You may hold it asserted to stream data out on every `ViClk` cycle (see *Reading Data* below).

**Rule:** Asserting a request (`vStartStreamRequest`, `vStopRequestStrobe`) for one `ViClk` cycle is the recommended usage, but holding it is tolerated — each request is crossed through a `HandshakeBool` and acted on once.

### Reading Data

Reading from the Reader FIFO is a request/valid handshake: you assert the read enable, then capture data on the cycles where `vOutputValid` is asserted.

```
ViClk:        ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
               └──┘  └──┘  └──┘  └──┘  └──┘
vReadFifo:    ─────┐     ┌──────────────────────
                    └─────┘
                    ▲ read request

vOutputValid: ─────────────────┐     ┌──────────
                               └─────┘
vDataOut:     ─────────────────╳VALID╳──────────
                               ▲
                               capture data here
```

**Rules:**
1. Assert `vReadFifo` to request data. It is an enable, not a one-cycle strobe — you may pulse it for a single read or hold it asserted to stream continuously.
2. Asserting `vReadFifo` while `vEmpty = true` is harmless: the pop is suppressed internally, so no data is lost. The common idiom is to assert `vReadFifo` and simply wait for `vOutputValid`.
3. Capture `vDataOut` only on cycles where `vOutputValid = true`; it is not guaranteed valid otherwise.
4. Data appears one or more cycles after the request (latency depends on the internal clock-domain crossing).
5. If `vReadyForOutput = false`, the FIFO holds data on `vDataOut` until you assert `vReadyForOutput`. Tie to `true` if you always consume data immediately.
6. **Underflow caution:** asserting `vReadyForOutput` (claiming you will consume a sample) while `vEmpty = true` flags a FIFO underflow. When the FIFO is built with `kDisableOnFifoTimeout`, that underflow disables the stream.
7. Data only flows while the stream is Enabled (`vStreamStateOut = kStreamStateEnabled`); `vOutputValid` never asserts outside the Enabled state.

### Status Signals

| Signal | Meaning | When to check |
|--------|---------|---------------|
| `vEmpty` | FIFO has no data available | Wait for `vOutputValid` rather than gating `vReadFifo` on this |
| `vCtCount` | Number of elements currently in the FIFO | Informational; can read at any time |

Status signals update every `ViClk` cycle and reflect the current FIFO state. They may change on the cycle immediately after a read operation.

### Handshaking Mode vs. Polling Mode

**Polling mode** (simpler):
- Check `vEmpty` → if not empty, assert `vReadFifo` for one cycle
- Tie `vReadyForOutput => true` (always ready to accept data)
- Wait for `vOutputValid` to capture `vDataOut`
- This is the recommended approach for most designs

**Handshaking mode** (back-pressure):
- Assert `vReadyForOutput` only when you can accept data
- The FIFO holds `vDataOut` stable until `vReadyForOutput` is asserted
- Use this when your downstream logic may not always be ready to consume data

### Stream State

The `vStreamStateOut` output reflects the current state of the DMA stream. It updates synchronously to `ViClk`.

| Constant | Value | Meaning |
|----------|-------|---------|
| `kStreamStateUnlinked` | `"00"` | Not connected |
| `kStreamStateDisabled` | `"01"` | Linked but not streaming |
| `kStreamStateEnabled` | `"10"` | Actively streaming — safe to read |
| `kStreamStateFlushing` | `"11"` | Not applicable to Reader |

**Rule:** Data only emerges from the FIFO (`vOutputValid = true`) while
`vStreamStateOut = kStreamStateEnabled`. Asserting `vReadFifo` while the stream
is not Enabled is harmless; simply wait for `vOutputValid` before capturing data.

### Start/Stop Timing

- `vStartStreamRequest` — Assert for one `ViClk` cycle (may also be held). The stream will not transition instantly; monitor `vStreamStateOut` to confirm the Enabled state before beginning data transfer.
- `vStopRequestStrobe` — Assert for one `ViClk` cycle (may also be held). The stream transitions to Disabled. Unread data in the FIFO may be lost.

**Rule:** Do not assert start and stop simultaneously. Only assert one request per clock cycle.

### Reset Behavior

| Signal | Type | Effect |
|--------|------|--------|
| `aBusReset` | Asynchronous, active-high boolean | Resets all bus-side logic. FIFO contents are lost. Stream returns to Unlinked. |
| `aDiagramReset` | Asynchronous, active-high boolean | Resets the user-side diagram logic. |

**Rule:** After reset de-asserts, wait for `vStreamStateOut` to reach Disabled before issuing a start request. Do not attempt FIFO operations during or immediately after reset.

### Summary of Reader Timing Rules

| Rule | Description |
|------|-------------|
| Requests: one cycle (or held) | Asserting a request (start / stop) for one `ViClk` cycle is recommended; holding it is tolerated (crossed through a `HandshakeBool`). `vReadFifo` is a held enable, not a strobe |
| Wait for valid | Sample `vDataOut` only when `vOutputValid = true` |
| Reading while empty is safe | Asserting `vReadFifo` while `vEmpty` is harmless (the pop is gated internally); just wait for `vOutputValid` |
| Underflow caution | Asserting `vReadyForOutput` while `vEmpty` flags an underflow (disables the stream when `kDisableOnFifoTimeout`) |
| One request at a time | Do not assert start and stop simultaneously |
| Respect reset | Wait for Disabled state after reset before starting |
