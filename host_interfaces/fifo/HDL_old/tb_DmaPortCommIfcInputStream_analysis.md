# tb_DmaPortCommIfcInputStream — DUT Analysis

## DUT Configuration Matrix

| DUT | Data Width | Depth | Eviction Timeout | P2P | FxpType | CountScl | Endpoint |
|-----|-----------|-------|-------------------|-----|---------|----------|----------|
| 0 | 8 | 1023 | 16383 | true | false | true | 0 |
| 1 | 16 | 1023 | 511 | false | false | false | 0 |
| 2 | 32 | 1023 | 511 | false | false | false | 0 |
| 3 | 64 | 1023 | 511 | false | false | false | 0 |
| 4 | 17 | 3 | 511 | true | true | true | 1 |
| 5 | 51 | 63 | 511 | true | true | false | 2 |
| 6 | 2 | 4095 | 511 | true | true | true | 0 |
| 7 | 30 | 16383 | 8 | true | true | false | 15 |
| 8 | 6 | 1023 | 511 | false | true | true | 0 |
| 9 | 18 | 1023 | 511 | false | true | false | 0 |

All 10 are instances of `DmaPortCommIfcInputWrapper` with the same port structure but different generic parameters. They share the same `bRegPortIn`, `bNiDmaInputRequestFromDma`, `bNiDmaInputStatusFromDma`, clocks, and resets. Their outputs are OR'd/demuxed by infrastructure processes (`InputRequestToDmaOr`, `InputDataToDmaOr`, `InputDataFromDmaDemux`, `RegPortOutOr`).

## How Each DUT Is Tested

### DUT 0 (8-bit, depth 1023, P2P, long eviction timeout)

The **primary workhorse** for functional verification:

- **Async reset test**: Fill FIFO, trigger arbiter request, disable stream, then async reset — verify all signals/registers return to zero.
- **Sync reset test**: Fill FIFO, start a DMA transfer, assert `bReset` mid-transfer — verify clean recovery.
- **State transition test** (`DoStateTransitionTest`): Exhaustive walk through all state machine transitions (Unlinked→Disabled→Enabled→Flushing→Disabled→Unlinked) from both **host** and **diagram** sides, including flush timeout from diagram with a 10-cycle timeout.
- **Test 28** — Disable during active request: Disables the stream while an arbiter grant is active mid-transfer.
- **Tests 1-10** (within loop DUT 3→0): Normal DMA transfers with varying SATCR, FIFO fill levels, priority levels (normal/emergency/none), and clock wait values (0 and 5).
- **Random tests**: Eligible target (DUTs 0-4).

### DUTs 1-3 (16/32/64-bit, depth 1023, non-P2P, non-FXP)

Test **standard data-width scaling** on the "normal" FIFO depth:

- **Tests 1-10** (shared loop): Same 10 test scenarios as DUT 0 covering SATCR-limited, max-packet-limited, empty FIFO, and zero-SATCR conditions.
- **Tests 23-27** (DUTs 0-2 only): **Additional SATCR writes during active transfers** — SATCR is incremented while data is mid-flight, testing dynamic transfer-size adjustment.
- DUT 1 (`kCountScl=false`) and DUT 0 (`kCountScl=true`) differ in how empty counts are polled (single-cycle handshake for SCL vs multi-cycle strobe/wait/clear for non-SCL in `PollEmptyCounts`).

### DUT 4 (17-bit, depth 3, P2P, FXP)

Tests **minimum FIFO depth** (only 3 entries) and **non-power-of-2 data width**:

- **Tests 11-14**: Targeted tests with 1, 2, and 3 sample fills — boundary cases for the smallest possible FIFO. Includes SATCR-limited vs FIFO-count-limited scenarios on a tiny FIFO.
- **Random tests**: Eligible target.

### DUT 5 (51-bit, depth 63, P2P, FXP)

Tests **odd/large non-power-of-2 data width** with a small-medium FIFO:

- **Tests 15-18**: Targeted tests with progressively increasing fill levels (8, 16, 32, 63 samples) on a 63-deep FIFO — tests normal, emergency, and boundary-full conditions with a wide, non-standard sample width.

### DUT 6 (2-bit, depth 4095, P2P, FXP)

Tests **minimum data width** with a **large FIFO**:

- **Tests 19-22**: Fill levels of 1023×8, 1024×8, 2048×8, and 4094×8 samples — tests large transfer volumes (multiple max-packet-sized transfers in sequence) on the deepest FIFO among the first 7 DUTs.

### DUT 7 (30-bit, depth 16383, eviction timeout 8, P2P, FXP)

Has the **largest FIFO depth** and **shortest eviction timeout**. Notably, **no dedicated test targets DUT 7** — it is only exercised through the shared infrastructure (reset, clock generation, `PollEmptyCounts`, `CheckRespondingPorts`). It could be hit by random tests if `Rand.GetNatural(4)` returns 4... but the random loop uses DUTs 0-4 only. So DUT 7 is effectively **untested** beyond reset behavior.

### DUTs 8-9 (6-bit / 18-bit, depth 1023, non-P2P, FxpType=true)

Test **FXP (fixed-point) data packing** to host:

- **Tests 29-34**: Mirror of Tests 1-6 from the DUT 0-3 loop but specifically for FXP types. The `CheckData` process adjusts expected data based on `kFifoDataWidthArray` per channel, so FXP packing/unpacking is verified byte-by-byte against known input sequences.

## Summary of What Differentiates the Testing

| Dimension | DUTs Exercising It |
|---|---|
| **Data width scaling** (power-of-2: 8→64) | 0, 1, 2, 3 |
| **Non-power-of-2 data widths** (2, 6, 17, 18, 30, 51) | 4, 5, 6, 7, 8, 9 |
| **Minimum FIFO depth** (3) | 4 |
| **Small FIFO depth** (63) | 5 |
| **Large FIFO depth** (4095, 16383) | 6, 7 |
| **FXP data type** | 4, 5, 6, 7, 8, 9 |
| **Peer-to-peer** | 0, 4, 5, 6, 7 |
| **Short eviction timeout** (8) | 7 |
| **CountScl mode** (SCL empty-count polling) | 0, 4, 6, 8 |
| **State machine transitions / flush / flush timeout** | 0 only |
| **Reset (async + sync)** | 0 only |
| **Disable mid-transfer** | 0 only |
| **Dynamic SATCR writes during transfer** | 0, 1, 2 |
| **Random stress testing** | 0-4 |
