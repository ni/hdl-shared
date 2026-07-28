# Host Registers — Instantiation and Interface Guide

This guide shows how to add host-visible registers to a custom target using the three
register blocks in `host_interfaces/register/HDL/`. For the underlying bus protocol and
timing, see [RegPort_Theory_of_Operation.md](RegPort_Theory_of_Operation.md).

The worked example is the `pxie-7912custom` target in `flexrio-custom`
(`targets/pxie-7912custom/rtl-lvfpga/UserHdl.vhd` and `PkgUserHdl.vhd`), which combines a
common-registers block, two register arrays, and DMA FIFOs in one design.

## The three blocks

| Block | What it is |
|-------|------------|
| `NiSharedHostRegister` | One 32-bit register. Host access via `RegPortIn`/`RegPortOut`; FPGA access via `bFpga*` ports. |
| `NiSharedHostRegisterArray` | A bank of N registers at `kBaseAddress + 4·i`, each individually read-only or writable. |
| `NiSharedCommonHostRegs` | A fixed identity block: Signature, Version, Oldest-Compatible-Version, Scratch. |

Most designs use `NiSharedCommonHostRegs` for identity plus one or more
`NiSharedHostRegisterArray` banks for control/status. You rarely instantiate
`NiSharedHostRegister` directly — it is the primitive the other two are built from.

## Prerequisites

Your design must include the register support packages:

```vhdl
library work;
  use work.PkgNiUtilities.all;            -- Slv32Ary_t, BooleanVector
  use work.PkgCommunicationInterface.all; -- RegPortIn_t, RegPortOut_t
  use work.PkgNiHdlSettings.all;          -- kMaxHdlRegOffset (generated)
  use work.PkgUserHdl.all;                -- your register layout constants
```

`PkgNiUtilities` and `PkgCommunicationInterface` come from `flexrio-deps`.
`PkgNiHdlSettings` is generated from your project settings (see `kMaxHdlRegOffset` below).

---

## `kMaxHdlRegOffset` — the register-space bound

Every register block takes a `kMaxHdlRegOffset` generic: the highest byte offset reserved
for HDL registers in this target. Each block asserts at elaboration that its byte offset
is `<= kMaxHdlRegOffset`, so a register placed outside the reserved space fails synthesis
and simulation instead of silently colliding with LabVIEW FPGA's register space.

The value is set once per target with `set_max_hdl_reg_offset` and surfaces as
`kMaxHdlRegOffset` in the generated `PkgNiHdlSettings` package. Pass it straight through to
every register block.

---

## Step 1: Declare your register layout in `PkgUserHdl`

Keep base addresses, register counts, and per-register index names in `PkgUserHdl.vhd` so
the layout lives in one place:

```vhdl
-- Demo register array (4 registers starting at byte offset 0x10)
constant kDemoRegsBaseAddress : natural := 16#10#;
constant kNumDemoRegs         : natural := 4;

constant kLoopbackInAIdx  : natural := 0;  -- offset 0x10: host R/W input A
constant kLoopbackInBIdx  : natural := 1;  -- offset 0x14: host R/W input B
constant kLoopbackOutAIdx : natural := 2;  -- offset 0x18: host RO output (A+1)
constant kLoopbackOutBIdx : natural := 3;  -- offset 0x1C: host RO output (B+1)
```

> **Addressing.** A register at array index `i` lives at byte offset
> `kBaseAddress + 4·i`. Keep banks from overlapping each other or the common-registers
> block (offsets `0x00`–`0x0C`), and keep every offset `<= kMaxHdlRegOffset`.

---

## Step 2: Instantiate `NiSharedCommonHostRegs` (identity)

Give every design the standard identity block. The host reads these to confirm it is
talking to the expected bitfile and a compatible version.

```vhdl
NiSharedCommonHostRegs_inst : entity work.NiSharedCommonHostRegs
  generic map(
    kMaxHdlRegOffset         => kMaxHdlRegOffset,
    kSignature               => x"7912BEEF",
    kVersion                 => x"00000001",
    kOldestCompatibleVersion => x"00000001"
  )
  port map(
    BusClk      => BusClk,
    aReset      => aBusReset,
    bRegPortIn  => bRegPortIn,
    bRegPortOut => bRegPortOutCommonRegs
  );
```

Fixed register map (byte offsets):

| Offset | Register | Access |
|--------|----------|--------|
| `0x00` | Signature | host read-only |
| `0x04` | Version | host read-only |
| `0x08` | Oldest Compatible Version | host read-only |
| `0x0C` | Scratch | host read/write |

| Generic | Description |
|---------|-------------|
| `kMaxHdlRegOffset` | Register-space bound (see above). |
| `kSignature` | 32-bit design/target identifier the host checks at startup. |
| `kVersion` | Current interface/implementation version. |
| `kOldestCompatibleVersion` | Lowest host version still supported, for compatibility gating. |

---

## Step 3: Instantiate `NiSharedHostRegisterArray` (control/status bank)

A register array is the workhorse. Each register is independently read-only or writable,
and each exposes an FPGA-side port so your logic can drive status values or react to host
writes.

```vhdl
NiDemoRegisterArray_inst : entity work.NiSharedHostRegisterArray
  generic map(
    kMaxHdlRegOffset => kMaxHdlRegOffset,
    kNumRegisters    => kNumDemoRegs,
    kBaseAddress     => kDemoRegsBaseAddress,
    kDefault         => (0 to kNumDemoRegs-1 => x"00000000"),
    kReadOnly        => (kLoopbackInAIdx  => false,   -- host-writable inputs
                         kLoopbackInBIdx  => false,
                         kLoopbackOutAIdx => true,    -- FPGA-driven outputs
                         kLoopbackOutBIdx => true),
    kUseFpgaAck      => (0 to kNumDemoRegs-1 => false)
  )
  port map(
    BusClk         => BusClk,
    aReset         => aBusReset,
    bRegPortIn     => bRegPortIn,
    bRegPortOut    => bRegPortOutDemoRegs,
    bFpgaHostWrite => bDemoRegFpgaHostWrite,
    bFpgaAck       => bDemoRegFpgaAck,
    bFpgaWrite     => bDemoRegFpgaWrite,
    bFpgaDataIn    => bDemoRegFpgaDataIn,
    bFpgaDataOut   => bDemoRegFpgaDataOut
  );
```

### Array generics

| Generic | Type | Description |
|---------|------|-------------|
| `kMaxHdlRegOffset` | natural | Register-space bound. |
| `kNumRegisters` | natural | Number of registers in the bank. |
| `kBaseAddress` | natural | Byte offset of register 0. Register `i` is at `kBaseAddress + 4·i`. |
| `kDefault` | `Slv32Ary_t(0 to N-1)` | Reset value of each register. |
| `kReadOnly` | `BooleanVector(0 to N-1)` | `true` blocks host writes to that register (FPGA-driven status). |
| `kUseFpgaAck` | `BooleanVector(0 to N-1)` | `true` enables the Ready/ack handshake for that register (see Step 6). |

> The `kDefault`/`kReadOnly`/`kUseFpgaAck` aggregates **must** be indexed `0 to
> kNumRegisters-1`; the block asserts this at elaboration.

### Array FPGA-side ports (BusClk domain, one element per register)

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `bFpgaHostWrite` | out | `BooleanVector` | Pulses for one cycle when the host writes register `i`. |
| `bFpgaWrite` | in | `BooleanVector` | Assert to write `bFpgaDataIn(i)` into register `i`. |
| `bFpgaDataIn` | in | `Slv32Ary_t` | Value the FPGA writes into register `i`. |
| `bFpgaDataOut` | out | `Slv32Ary_t` | Current contents of register `i` (continuously valid). |
| `bFpgaAck` | in | `BooleanVector` | Completes an acknowledged transaction (only when `kUseFpgaAck(i)`). |

> **Write priority.** If the FPGA (`bFpgaWrite`) and the host write the same register on
> the same clock edge, the FPGA write wins.

---

## Step 4: Drive and observe registers from FPGA logic

**FPGA-driven status (read-only to host).** Continuously write the status value:

```vhdl
bFifoRegFpgaWrite(kWriterCountIdx)  <= true;
bFifoRegFpgaDataIn(kWriterCountIdx) <= std_logic_vector(bWriterFifoCtCount);
```

**React to a host write.** Use the `bFpgaHostWrite` pulse as a "host wrote me" event and
read the new value from `bFpgaDataOut`:

```vhdl
if bDemoRegFpgaHostWrite(kLoopbackInAIdx) then
  bDemoRegFpgaDataIn(kLoopbackOutAIdx) <=
      std_logic_vector(unsigned(bDemoRegFpgaDataOut(kLoopbackInAIdx)) + 1);
  bDemoRegFpgaWrite(kLoopbackOutAIdx) <= true;
end if;
```

**Command register (host write triggers an action).** A host write pulse can drive a
one-cycle strobe into other logic — for example, a FIFO start/stop bit:

```vhdl
if bFifoRegFpgaHostWrite(kWriterStartStopIdx) then
  if bFifoRegFpgaDataOut(kWriterStartStopIdx)(0) = '1' then
    bWriterFifoStartReq <= true;   -- one-cycle pulse
  end if;
end if;
```

---

## Step 5: Merge register outputs

Combine every block's `RegPortOut` into the single `bRegPortOut` your entity exposes:
**OR** the `Data` and `DataValid` fields (only the addressed register drives non-zero),
and **AND** the `Ready` fields (all blocks must be ready).

```vhdl
bRegPortOut.Data      <= bRegPortOutCommonRegs.Data or
                         bRegPortOutDemoRegs.Data or
                         bRegPortOutFifoRegs.Data;

bRegPortOut.DataValid <= bRegPortOutCommonRegs.DataValid or
                         bRegPortOutDemoRegs.DataValid or
                         bRegPortOutFifoRegs.DataValid;

bRegPortOut.Ready     <= bRegPortOutCommonRegs.Ready and
                         bRegPortOutDemoRegs.Ready and
                         bRegPortOutFifoRegs.Ready;
```

This works because each register drives its `Data`/`DataValid` to zero unless it is the
addressed register being read. See
[RegPort_Theory_of_Operation.md](RegPort_Theory_of_Operation.md#or-combining-multiple-slaves)
for details.

---

## Step 6: Acknowledged registers (`kUseFpgaAck`) — optional

By default a register is always Ready and host transactions complete immediately. Set
`kUseFpgaAck(i) => true` when the host must block until FPGA logic has processed a
transaction.

- When the register is newly addressed, `Ready` de-asserts and stays low.
- The host transaction stalls until your logic asserts the corresponding `bFpgaAck(i)`.
- `Ready` then re-asserts and the transaction completes.

> **Deadlock warning.** In acknowledged mode your logic **must** eventually assert
> `bFpgaAck(i)` for every host access, or all subsequent host transactions stall. Use this
> mode only when you genuinely need host/FPGA synchronization.

---

## Step 7: Access registers from the host

After building the bitfile, read/write the registers from the host with the NI-RIO API.
Ready-made LabVIEW host VIs are in `host_interfaces/register/LabVIEW/` (available in a
target at `deps/hdl-shared/host_interfaces/register/LabVIEW/`).

When opening the bitfile from LabVIEW, use **Open Dynamic Bitfile Reference** (not the
normal Open FPGA VI Reference), then use the read/write register VIs to access registers by
byte offset.

---

## Signal naming conventions

| Prefix | Meaning |
|--------|---------|
| `a` | Asynchronous signal (not clocked) |
| `b` | BusClk domain signal |
| `k` | Constant/generic |

---

## Checklist

- [ ] Define base addresses, counts, and index names in `PkgUserHdl.vhd`
- [ ] Pass `kMaxHdlRegOffset` to every register block
- [ ] Keep every register offset within `kMaxHdlRegOffset` and non-overlapping
- [ ] Instantiate `NiSharedCommonHostRegs` with a unique `kSignature`
- [ ] Size `kDefault`/`kReadOnly`/`kUseFpgaAck` to `0 to kNumRegisters-1`
- [ ] Mark FPGA-driven status registers `kReadOnly => true`
- [ ] Drive status with `bFpgaWrite`/`bFpgaDataIn`; react to writes with `bFpgaHostWrite`
- [ ] OR-combine `Data`/`DataValid` and AND-combine `Ready` across all blocks
- [ ] If using `kUseFpgaAck`, guarantee `bFpgaAck` is always eventually asserted
