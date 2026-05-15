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
| `vWriteFifo` | in | `boolean` | Write strobe — assert for exactly one ViClk cycle to push data |
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

A **strobe** is a signal that is asserted (`true`) for exactly **one `ViClk` cycle** to trigger a single action. The FIFO samples strobe inputs on the rising edge of `ViClk`. After the active cycle, the strobe must return to `false`.

```
ViClk:    ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
           └──┘  └──┘  └──┘  └──┘  └──┘
Strobe:   ─────┐     ┌─────────────────────
                └─────┘  (one cycle high)
```

Writer strobe signals:
- `vWriteFifo` — triggers a single write into the FIFO
- `vStartStreamRequest` — requests stream enable
- `vStopRequestStrobe` — requests immediate stream stop
- `vStopWithFlushRequestStrobe` — requests flush-then-stop

**Rule:** Never hold a strobe asserted for more than one `ViClk` cycle. Each assertion triggers exactly one action.

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
1. Assert `vWriteFifo` and `vInputValid` together for exactly one `ViClk` cycle.
2. `vDataIn` must be stable (not changing) during that cycle.
3. Do **not** assert `vWriteFifo` when `vFull = true`. The write will be lost.
4. After the write cycle, `vDataIn` may change freely.
5. The stream must be in the Enabled state (`vStreamStateOut = kStreamStateEnabled`) for writes to succeed.

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

**Rule:** Do not write data unless `vStreamStateOut = kStreamStateEnabled`.

### Start/Stop Timing

- `vStartStreamRequest` — Assert for one `ViClk` cycle. The stream will not transition instantly; monitor `vStreamStateOut` to confirm the Enabled state before beginning data transfer.
- `vStopRequestStrobe` — Assert for one `ViClk` cycle. The stream transitions to Disabled. In-flight data in the FIFO may be lost.
- `vStopWithFlushRequestStrobe` — Assert for one `ViClk` cycle. The stream enters Flushing state, drains all buffered data to the host, then transitions to Disabled. Use this for graceful shutdown.

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
| Strobes are one cycle | Never hold `vWriteFifo` or request signals for more than one `ViClk` cycle |
| Data before strobe | `vDataIn` must be stable when `vWriteFifo` is asserted |
| Check full first | Never write when `vFull = true` |
| Stream must be enabled | Only write in Enabled state |
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
| `vReadFifo` | in | `boolean` | Read strobe — assert for exactly one ViClk cycle to pop data |
| `vCtCount` | out | `unsigned(31 downto 0)` | Current number of elements in FIFO |
| `vOutputValid` | out | `boolean` | Data on `vDataOut` is valid this cycle — capture it now |
| `vReadyForOutput` | in | `boolean` | User is ready to accept data; tie `true` if always ready |
| `vStreamStateOut` | out | `StreamStateValue_t` | Current stream state |
| `vStartStreamRequest` | in | `boolean` | Strobe: assert for one cycle to request Disabled → Enabled |
| `vStopRequestStrobe` | in | `boolean` | Strobe: assert for one cycle to request immediate stop |

### What Is a Strobe Signal?

A **strobe** is a signal that is asserted (`true`) for exactly **one `ViClk` cycle** to trigger a single action. The FIFO samples strobe inputs on the rising edge of `ViClk`. After the active cycle, the strobe must return to `false`.

```
ViClk:    ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
           └──┘  └──┘  └──┘  └──┘  └──┘
Strobe:   ─────┐     ┌─────────────────────
                └─────┘  (one cycle high)
```

Reader strobe signals:
- `vReadFifo` — triggers a single read from the FIFO
- `vStartStreamRequest` — requests stream enable
- `vStopRequestStrobe` — requests immediate stream stop

**Rule:** Never hold a strobe asserted for more than one `ViClk` cycle. Each assertion triggers exactly one action.

### Reading Data

Reading from the Reader FIFO is a two-phase operation: you request a read with a strobe, then wait for valid data to appear.

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
1. Assert `vReadFifo` for exactly one `ViClk` cycle to request a pop.
2. Do **not** assert `vReadFifo` when `vEmpty = true`. There is no data to read.
3. After the read strobe, wait for `vOutputValid = true` before sampling `vDataOut`.
4. `vDataOut` is only guaranteed valid on the cycle where `vOutputValid` is asserted.
5. Data appears one or more cycles after the read strobe (latency depends on internal clock-domain crossing).
6. If `vReadyForOutput = false`, the FIFO will hold data on `vDataOut` until you assert `vReadyForOutput`. Tie to `true` if you always consume data immediately.
7. The stream must be in the Enabled state (`vStreamStateOut = kStreamStateEnabled`) for reads to succeed.

### Status Signals

| Signal | Meaning | When to check |
|--------|---------|---------------|
| `vEmpty` | FIFO has no data available | Check **before** asserting `vReadFifo` |
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

**Rule:** Do not read data unless `vStreamStateOut = kStreamStateEnabled`.

### Start/Stop Timing

- `vStartStreamRequest` — Assert for one `ViClk` cycle. The stream will not transition instantly; monitor `vStreamStateOut` to confirm the Enabled state before beginning data transfer.
- `vStopRequestStrobe` — Assert for one `ViClk` cycle. The stream transitions to Disabled. Unread data in the FIFO may be lost.

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
| Strobes are one cycle | Never hold `vReadFifo` or request signals for more than one `ViClk` cycle |
| Wait for valid | Sample `vDataOut` only when `vOutputValid = true` |
| Check empty first | Never read when `vEmpty = true` |
| Stream must be enabled | Only read in Enabled state |
| One request at a time | Do not assert start and stop simultaneously |
| Respect reset | Wait for Disabled state after reset before starting |
