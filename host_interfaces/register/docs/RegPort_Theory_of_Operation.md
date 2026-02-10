# RegPort Interface - Theory of Operation

## Overview

The RegPort interface is a synchronous register access bus used in National Instruments FPGA designs to provide host access to FPGA registers. It supports 32-bit read and write transactions with a simple handshaking protocol.

The interface consists of two record types:
- **RegPortIn_t**: Signals driven by the master (host/initiator)
- **RegPortOut_t**: Signals driven by the slave (register/responder)

## Signal Interface

### RegPortIn_t (Master → Slave)
```vhdl
type RegPortIn_t is record
  Address : unsigned;      -- Word address (not byte address)
  Data    : std_logic_vector(31 downto 0);  -- Write data
  Rd      : boolean;       -- Read strobe (asserted for one cycle)
  Wt      : boolean;       -- Write strobe (asserted for one cycle)
end record;
```

### RegPortOut_t (Slave → Master)
```vhdl
type RegPortOut_t is record
  Data      : std_logic_vector(31 downto 0);  -- Read data
  DataValid : boolean;     -- Read data valid indicator
  Ready     : boolean;     -- Slave ready to accept transactions
end record;
```

## Protocol Description

### Basic Transaction Rules

1. **Address Format**: The Address field is interpreted in 32-bit words, not bytes. A register at byte offset 4 must decode Address = 1. Only aligned 32-bit accesses are supported.

2. **Transaction Initiation**: The master places Address and Data on the bus and strobes either Rd or Wt for exactly one clock cycle to initiate a transaction.

3. **Data Width**: All transactions are 32 bits wide. No byte enables or partial word accesses are supported.

4. **Bus Holding**: Address and Data remain valid on the bus until the transaction completes.

### Write Transactions

```
Cycle:     0    1    2    3
Address:   0x10 0x10 0x10 ---
Data:      0xAB 0xAB 0xAB ---
Wt:        T    F    F    F
Ready:     T    T    T    T
```

The master:
1. Drives Address and Data
2. Asserts Wt for one cycle
3. Holds Address and Data until Ready is seen

The slave:
1. Latches the write data when Wt is asserted
2. Drives Ready based on Address (and internal state if needed)

### Read Transactions

```
Cycle:     0    1    2    3
Address:   0x10 0x10 0x10 ---
Rd:        T    F    F    F
Ready:     T    T    T    T
DataValid: F    T    F    F
Data:      0x00 0xCD 0x00 ---
```

The master:
1. Drives Address
2. Asserts Rd for one cycle
3. Holds Address until DataValid is seen and Ready is asserted

The slave:
1. Must assert DataValid on the exact cycle that valid read data is present
2. Must drive Data to zeros except when DataValid is asserted (for OR-combining)
3. Drives Ready based on Address

## The Ready Signal - Critical Behavior

The Ready signal has subtle but important behavioral requirements:

### Ready Signal Rules

1. **Address-Based**: Ready must be driven as a function of Address and no later than one cycle after Address changes.

2. **Monotonic**: Once Ready asserts, it must stay asserted as long as Address doesn't change.


### Master Behavior Variations

There are two types of RegPort masters in the ecosystem:

**Type 1: Post-Transaction Ready Check**
- Drives Address first
- Strobes Rd/Wt immediately
- Checks Ready before starting the *next* transaction

**Type 2: Pre-Transaction Ready Check**
- Drives Address first
- Waits for Ready before strobing Rd/Wt


### Slave Implementation Requirements

To be compatible with both master types, slaves must:

1. Drive Ready based on Address within one cycle
2. Keep Ready monotonic (no toggling once asserted)
3. If not ready, latch any Rd/Wt strobe until it can be processed
4. Note: Address and Data are held by the master during the entire transaction, so only the strobe needs latching

## OR-Combining Multiple Slaves

Multiple RegPort slaves can be combined by OR-ing their outputs:

```vhdl
bRegPortOut.Data      <= bRegPortOut1.Data or bRegPortOut2.Data or bRegPortOut3.Data;
bRegPortOut.DataValid <= bRegPortOut1.DataValid or bRegPortOut2.DataValid or bRegPortOut3.DataValid;
bRegPortOut.Ready     <= bRegPortOut1.Ready and bRegPortOut2.Ready and bRegPortOut3.Ready;
```

**Key Points**:
- Data is OR-combined (slaves must drive zeros when not responding)
- DataValid is OR-combined (only the addressed slave asserts)
- Ready is AND-combined (all slaves must be ready)


## Transaction Timing Examples

### Simple Write (Always Ready)
```
Cycle:          0      1      2      3
Address:        0x10   0x10   ---    ---
Data:           0xAB   0xAB   ---    ---
Wt:             true   false  false  false
Ready:          true   true   true   true
[Register latches 0xAB at end of cycle 0]
```

### Simple Read (Always Ready)
```
Cycle:          0      1      2      3
Address:        0x10   0x10   ---    ---
Rd:             true   false  false  false
Ready:          true   true   true   true
DataValid:      false  true   false  false
Data:           0x00   0xCD   0x00   0x00
[Master captures 0xCD at end of cycle 1]
```

### Write with Acknowledgment (kUseFpgaAck = true)
```
Cycle:          0      1      2      3      4      5
Address:        0x10   0x10   0x10   0x10   0x10   ---
Data:           0xAB   0xAB   0xAB   0xAB   0xAB   ---
Wt:             true   false  false  false  false  false
Ready:          true   false  false  false  true   true
bFpgaAck:       false  false  false  true   false  false
[Register latches 0xAB at end of cycle 0]
[Ready de-asserts at cycle 1 when register becomes addressed]
[FPGA processes write and asserts bFpgaAck at cycle 3]
[Ready re-asserts at cycle 4]
[Transaction completes, new transaction can begin]
```


## Example

The `HdlSharedHostRegister` implementation demonstrates all these principles with both basic (always-ready) and advanced (acknowledged) operating modes.
