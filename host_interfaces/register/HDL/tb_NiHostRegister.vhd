-------------------------------------------------------------------------------
--
-- File: tb_NiHostRegister.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
-- 
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
-- Testbench for NiHostRegister entity to verify:
-- - Host read/write operations
-- - FPGA read/write operations
-- - Default value initialization
-- - Host read-only mode
-- - Priority handling (FPGA write has priority over host write)
-- - Reset behavior
--
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  
library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;

entity tb_NiHostRegister is
end entity tb_NiHostRegister;

architecture sim of tb_NiHostRegister is

  -- Constants
  constant kClkPeriod : time := 10 ns;
  -- Common host registers use fixed offsets: 0x00, 0x04, 0x08, 0x0C
  constant kCommonSignatureValue : std_logic_vector(31 downto 0) := x"5349474E";
  constant kCommonVersionValue : std_logic_vector(31 downto 0) := x"00010002";
  constant kCommonOldestCompatibleValue : std_logic_vector(31 downto 0) := x"00010000";
  constant kCommonSignatureOffset : natural := 16#00#;
  constant kCommonVersionOffset : natural := 16#04#;
  constant kCommonOldestCompatibleOffset : natural := 16#08#;
  constant kCommonScratchOffset : natural := 16#0C#;

  constant kStandardOffset : natural := 16#40#;  -- Byte address 0x40 (64) for standard register
  constant kReadOnlyOffset : natural := 16#44#;  -- Byte address 0x44 (68) for read-only register
  constant kFpgaAckOffset : natural := 16#48#;   -- Byte address 0x48 (72) for FpgaAck register

  constant kArrayNumRegisters : natural := 3;
  constant kArrayBaseOffset : natural := 16#80#; -- Byte addresses 0x80, 0x84, 0x88
  constant kArrayReg0Offset : natural := kArrayBaseOffset + 0;
  constant kArrayReg1Offset : natural := kArrayBaseOffset + 4;
  constant kArrayReg2Offset : natural := kArrayBaseOffset + 8;
  constant kDefaultValue : std_logic_vector(31 downto 0) := x"DEADBEEF";
  constant kArrayDefaultValues : Slv32Ary_t(0 to kArrayNumRegisters-1) := (others => kDefaultValue);
  constant kArrayReadOnly : BooleanVector(0 to kArrayNumRegisters-1) := (others => false);
  constant kArrayUseFpgaAck : BooleanVector(0 to kArrayNumRegisters-1) := (others => false);
  
  -- DUT signals
  signal BusClk : std_logic := '0';
  signal aReset : boolean := true;
  
  -- Host interface
  signal bRegPortIn : RegPortIn_t := kRegPortInZero;
  signal bRegPortOut : RegPortOut_t;
  
  -- FPGA interface
  signal bFpgaHostWrite : boolean;
  signal bFpgaWrite : boolean := false;
  signal bFpgaDataIn : std_logic_vector(31 downto 0) := (others => '0');
  signal bFpgaDataOut : std_logic_vector(31 downto 0);
  
  -- DUT instances for different configurations
  signal bRegPortOut_ReadOnly : RegPortOut_t;
  signal bFpgaDataOut_ReadOnly : std_logic_vector(31 downto 0);
  signal bFpgaHostWrite_ReadOnly : boolean;
  
  signal bRegPortOut_FpgaAck : RegPortOut_t;
  signal bFpgaDataOut_FpgaAck : std_logic_vector(31 downto 0);
  signal bFpgaHostWrite_FpgaAck : boolean;
  signal bFpgaAck : boolean := false;

  signal bRegPortOut_Common : RegPortOut_t;

  signal bRegPortOut_Array : RegPortOut_t;
  signal bFpgaHostWrite_Array : BooleanVector(0 to kArrayNumRegisters-1);
  signal bFpgaAck_Array : BooleanVector(0 to kArrayNumRegisters-1) := (others => false);
  signal bFpgaWrite_Array : BooleanVector(0 to kArrayNumRegisters-1) := (others => false);
  signal bFpgaDataIn_Array : Slv32Ary_t(0 to kArrayNumRegisters-1) := (others => (others => '0'));
  signal bFpgaDataOut_Array : Slv32Ary_t(0 to kArrayNumRegisters-1);
  
  -- Test control
  signal TestDone : boolean := false;
  signal CurrentTest : natural := 0;  -- Indicates which test is currently running

begin

  -- Clock generation
  BusClk <= not BusClk after kClkPeriod/2 when not TestDone else '0';

  -- DUT: Standard mode
  DUT_Standard: entity work.NiHostRegister
    generic map(
      kOffset => kStandardOffset,
      kDefault => kDefaultValue,
      kReadOnly => false,
      kUseFpgaAck => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOut,
      bFpgaHostWrite => bFpgaHostWrite,
      bFpgaAck       => false,
      bFpgaWrite     => bFpgaWrite,
      bFpgaDataIn    => bFpgaDataIn,
      bFpgaDataOut   => bFpgaDataOut
    );

  -- DUT: Host read-only mode
  DUT_ReadOnly: entity work.NiHostRegister
    generic map(
      kOffset => kReadOnlyOffset,
      kDefault => kDefaultValue,
      kReadOnly => true,
      kUseFpgaAck => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOut_ReadOnly,
      bFpgaHostWrite => bFpgaHostWrite_ReadOnly,
      bFpgaAck       => false,
      bFpgaWrite     => bFpgaWrite,
      bFpgaDataIn    => bFpgaDataIn,
      bFpgaDataOut   => bFpgaDataOut_ReadOnly
    );

  -- DUT: FPGA Acknowledgment mode
  DUT_FpgaAck: entity work.NiHostRegister
    generic map(
      kOffset => kFpgaAckOffset,
      kDefault => kDefaultValue,
      kReadOnly => false,
      kUseFpgaAck => true
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOut_FpgaAck,
      bFpgaHostWrite => bFpgaHostWrite_FpgaAck,
      bFpgaAck       => bFpgaAck,
      bFpgaWrite     => bFpgaWrite,
      bFpgaDataIn    => bFpgaDataIn,
      bFpgaDataOut   => bFpgaDataOut_FpgaAck
    );

  DUT_CommonHostRegs: entity work.NiCommonHostRegs
    generic map(
      kSignature => kCommonSignatureValue,
      kVersion => kCommonVersionValue,
      kOldestCompatibleVersion => kCommonOldestCompatibleValue
    )
    port map(
      BusClk      => BusClk,
      aReset      => aReset,
      bRegPortIn  => bRegPortIn,
      bRegPortOut => bRegPortOut_Common
    );

  DUT_Array: entity work.NiHostRegisterArray
    generic map(
      kNumRegisters => kArrayNumRegisters,
      kBaseAddress => kArrayBaseOffset,
      kDefault => kArrayDefaultValues,
      kReadOnly => kArrayReadOnly,
      kUseFpgaAck => kArrayUseFpgaAck
    )
    port map(
      BusClk       => BusClk,
      aReset       => aReset,
      bRegPortIn   => bRegPortIn,
      bRegPortOut  => bRegPortOut_Array,
      bFpgaHostWrite => bFpgaHostWrite_Array,
      bFpgaAck     => bFpgaAck_Array,
      bFpgaWrite   => bFpgaWrite_Array,
      bFpgaDataIn  => bFpgaDataIn_Array,
      bFpgaDataOut => bFpgaDataOut_Array
    );

  -- Stimulus process
  Stimulus: process
  
    -- Helper procedure for host write
    -- addr parameter is byte address (offset), which gets converted to word address
    procedure HostWrite(
      constant addr : in natural;
      constant data : in std_logic_vector(31 downto 0)
    ) is
    begin
      bRegPortIn.Address <= to_unsigned(addr / 4, bRegPortIn.Address'length);
      bRegPortIn.Data <= data;
      bRegPortIn.Wt <= true;
      wait until rising_edge(BusClk);
      bRegPortIn.Wt <= false;
      bRegPortIn.Data <= (others => '0');
      wait until rising_edge(BusClk);
    end procedure HostWrite;

    -- Helper procedure for host read
    -- addr parameter is byte address (offset), which gets converted to word address
    procedure HostRead(
      constant addr : in natural;
      variable data : out std_logic_vector(31 downto 0);
      variable valid : out boolean
    ) is
    begin
      bRegPortIn.Address <= to_unsigned(addr / 4, bRegPortIn.Address'length);
      bRegPortIn.Rd <= true;
      wait until rising_edge(BusClk);
      wait for 0 ns;
      data := bRegPortOut.Data;
      valid := bRegPortOut.DataValid;
      bRegPortIn.Rd <= false;
      wait until rising_edge(BusClk);
    end procedure HostRead;

    -- Helper procedure for host read from common host regs DUT output
    procedure HostReadCommon(
      constant addr : in natural;
      variable data : out std_logic_vector(31 downto 0);
      variable valid : out boolean
    ) is
    begin
      bRegPortIn.Address <= to_unsigned(addr / 4, bRegPortIn.Address'length);
      bRegPortIn.Rd <= true;
      wait until rising_edge(BusClk);
      wait for 0 ns;
      data := bRegPortOut_Common.Data;
      valid := bRegPortOut_Common.DataValid;
      bRegPortIn.Rd <= false;
      wait until rising_edge(BusClk);
    end procedure HostReadCommon;

    -- Helper procedure for host read from register array DUT output
    procedure HostReadArray(
      constant addr : in natural;
      variable data : out std_logic_vector(31 downto 0);
      variable valid : out boolean
    ) is
    begin
      bRegPortIn.Address <= to_unsigned(addr / 4, bRegPortIn.Address'length);
      bRegPortIn.Rd <= true;
      wait until rising_edge(BusClk);
      wait for 0 ns;
      data := bRegPortOut_Array.Data;
      valid := bRegPortOut_Array.DataValid;
      bRegPortIn.Rd <= false;
      wait until rising_edge(BusClk);
    end procedure HostReadArray;

    -- Helper procedure for FPGA write
    procedure FpgaWrite(
      constant data : in std_logic_vector(31 downto 0)
    ) is
    begin
      bFpgaDataIn <= data;
      bFpgaWrite <= true;
      wait until rising_edge(BusClk);
      bFpgaWrite <= false;
      bFpgaDataIn <= (others => '0');
      wait until rising_edge(BusClk);
    end procedure FpgaWrite;

    -- Helper procedure for FPGA write into array register i
    procedure FpgaWriteArray(
      constant idx : in natural;
      constant data : in std_logic_vector(31 downto 0)
    ) is
    begin
      bFpgaDataIn_Array(idx) <= data;
      bFpgaWrite_Array(idx) <= true;
      wait until rising_edge(BusClk);
      bFpgaWrite_Array(idx) <= false;
      bFpgaDataIn_Array(idx) <= (others => '0');
      wait until rising_edge(BusClk);
    end procedure FpgaWriteArray;
    
    variable vReadData : std_logic_vector(31 downto 0);
    variable vReadValid : boolean;
    
  begin
    -- Initial reset
    aReset <= true;
    wait for kClkPeriod * 5;
    wait until rising_edge(BusClk);
    aReset <= false;
    wait until rising_edge(BusClk);
    
    CurrentTest <= 1;
    report "==== Test 1: Check default value ====";
    HostRead(kStandardOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Read valid should be true" severity error;
    assert vReadData = kDefaultValue 
      report "FAIL: Default value mismatch. Expected: " & 
             to_hstring(to_bitvector(kDefaultValue)) & " Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Default value correct";
    wait for kClkPeriod * 2;

    CurrentTest <= 2;
    report "==== Test 2: Host write and read back ====";
    HostWrite(kStandardOffset, x"12345678");
    wait for kClkPeriod;
    HostRead(kStandardOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Read valid should be true" severity error;
    assert vReadData = x"12345678" 
      report "FAIL: Host write failed. Expected: 12345678 Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Host write and read successful";
    wait for kClkPeriod * 2;

    CurrentTest <= 3;
    report "==== Test 3: FPGA write and read (from FPGA side) ====";
    FpgaWrite(x"ABCD1234");
    wait for kClkPeriod;
    assert bFpgaDataOut = x"ABCD1234" 
      report "FAIL: FPGA write failed. Expected: ABCD1234 Got: " & to_hstring(to_bitvector(bFpgaDataOut)) 
      severity error;
    report "PASS: FPGA write successful";
    wait for kClkPeriod * 2;

    CurrentTest <= 4;
    report "==== Test 4: FPGA write visible to host ====";
    HostRead(kStandardOffset, vReadData, vReadValid);
    assert vReadData = x"ABCD1234" 
      report "FAIL: Host can't see FPGA write. Expected: ABCD1234 Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Host can read FPGA-written data";
    wait for kClkPeriod * 2;

    CurrentTest <= 5;
    report "==== Test 5: Priority test - FPGA write wins ====";
    -- Set up simultaneous write
    bRegPortIn.Address <= to_unsigned(kStandardOffset / 4, bRegPortIn.Address'length);
    bRegPortIn.Data <= x"11111111";
    bRegPortIn.Wt <= true;
    bFpgaDataIn <= x"22222222";
    bFpgaWrite <= true;
    wait until rising_edge(BusClk);
    bRegPortIn.Wt <= false;
    bFpgaWrite <= false;
    wait until rising_edge(BusClk);
    assert bFpgaDataOut = x"22222222" 
      report "FAIL: FPGA priority not respected. Expected: 22222222 Got: " & to_hstring(to_bitvector(bFpgaDataOut)) 
      severity error;
    report "PASS: FPGA write priority correct";
    wait for kClkPeriod * 2;

    CurrentTest <= 6;
    report "==== Test 6: Wrong address should not respond ====";
    HostRead(kStandardOffset + 16#10#, vReadData, vReadValid);
    assert not vReadValid report "FAIL: Wrong address should not give valid response" severity error;
    report "PASS: Wrong address correctly ignored";
    wait for kClkPeriod * 2;

    CurrentTest <= 7;
    report "==== Test 7: Host read-only mode ====";
    -- First write with FPGA
    FpgaWrite(x"FEDCBA98");
    wait for kClkPeriod;
    assert bFpgaDataOut_ReadOnly = x"FEDCBA98" 
      report "FAIL: FPGA write to read-only register failed" severity error;
    -- Try to write from host (should be ignored)
    assert not bFpgaHostWrite_ReadOnly report "FAIL: bFpgaHostWrite should be false before host write attempt" severity error;
    HostWrite(kReadOnlyOffset, x"55555555");
    wait for kClkPeriod;
    -- Verify bFpgaHostWrite did NOT assert
    assert not bFpgaHostWrite_ReadOnly 
      report "FAIL: bFpgaHostWrite should not assert for read-only register" severity error;
    -- Verify value did not change
    assert bFpgaDataOut_ReadOnly = x"FEDCBA98" 
      report "FAIL: Host write should be ignored in read-only mode. Got: " & to_hstring(to_bitvector(bFpgaDataOut_ReadOnly)) 
      severity error;
    -- Verify we can read the value from the read-only register
    HostRead(kReadOnlyOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Read valid should be true for read-only register" severity error;
    assert vReadData = x"FEDCBA98" 
      report "FAIL: Host read from read-only register failed. Expected: FEDCBA98 Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Host read-only mode working correctly";
    wait for kClkPeriod * 2;

    CurrentTest <= 8;
    report "==== Test 8: bFpgaHostWrite pulse detection ====";
    assert not bFpgaHostWrite report "FAIL: bFpgaHostWrite should be false initially" severity error;
    HostWrite(kStandardOffset, x"99999999");
    -- bFpgaHostWrite should have pulsed during the write
    wait for kClkPeriod;
    assert not bFpgaHostWrite report "FAIL: bFpgaHostWrite should return to false" severity error;
    report "PASS: bFpgaHostWrite pulse detected correctly";
    wait for kClkPeriod * 2;

    CurrentTest <= 9;
    report "==== Test 9: Reset behavior ====";
    HostWrite(kStandardOffset, x"FFFFFFFF");
    wait for kClkPeriod;
    aReset <= true;
    wait for kClkPeriod * 3;
    aReset <= false;
    wait for kClkPeriod;
    HostRead(kStandardOffset, vReadData, vReadValid);
    assert vReadData = kDefaultValue 
      report "FAIL: Reset should restore default value. Expected: " & 
             to_hstring(to_bitvector(kDefaultValue)) & " Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Reset restores default value";
    wait for kClkPeriod * 2;

    CurrentTest <= 10;
    report "==== Test 10: FPGA Acknowledgment mode ====";
    -- Initially Ready should be true
    assert bRegPortOut_FpgaAck.Ready report "FAIL: Ready should be true initially" severity error;
    
    -- Address the register with a read - Ready should go false
    bRegPortIn.Address <= to_unsigned(kFpgaAckOffset / 4, bRegPortIn.Address'length);
    bRegPortIn.Rd <= true;
    wait until rising_edge(BusClk);
    bRegPortIn.Rd <= false;
    wait until rising_edge(BusClk);
    -- Ready should be false now
    assert not bRegPortOut_FpgaAck.Ready 
      report "FAIL: Ready should be false after register is addressed" severity error;
    
    -- Wait a few cycles - Ready should stay false
    wait for kClkPeriod * 3;
    assert not bRegPortOut_FpgaAck.Ready 
      report "FAIL: Ready should stay false until acknowledged" severity error;
    
    -- Assert bFpgaAck
    bFpgaAck <= true;
    wait until rising_edge(BusClk);
    bFpgaAck <= false;
    wait until rising_edge(BusClk);
    
    -- Ready should be true again
    assert bRegPortOut_FpgaAck.Ready 
      report "FAIL: Ready should be true after FPGA acknowledgment" severity error;
    
    -- Verify we can write to and read from the FpgaAck register
    bFpgaAck <= true;  -- Acknowledge in advance for next transaction
    wait until rising_edge(BusClk);
    bFpgaAck <= false;
    HostWrite(kFpgaAckOffset, x"AAAA5555");
    wait for kClkPeriod;
    assert bFpgaDataOut_FpgaAck = x"AAAA5555" 
      report "FAIL: FpgaAck register write failed. Expected: AAAA5555 Got: " & to_hstring(to_bitvector(bFpgaDataOut_FpgaAck)) 
      severity error;
    report "PASS: FPGA acknowledgment mode working correctly";
    wait for kClkPeriod * 2;

    CurrentTest <= 11;
    report "==== Test 11: Common host registers ====";
    HostReadCommon(kCommonSignatureOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Common signature read should be valid" severity error;
    assert vReadData = kCommonSignatureValue
      report "FAIL: Common signature mismatch" severity error;

    HostReadCommon(kCommonVersionOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Common version read should be valid" severity error;
    assert vReadData = kCommonVersionValue
      report "FAIL: Common version mismatch" severity error;

    HostReadCommon(kCommonOldestCompatibleOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Common oldest compatible read should be valid" severity error;
    assert vReadData = kCommonOldestCompatibleValue
      report "FAIL: Common oldest compatible mismatch" severity error;

    HostReadCommon(kCommonScratchOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Common scratch default read should be valid" severity error;
    assert vReadData = x"00000000"
      report "FAIL: Common scratch default mismatch" severity error;

    HostWrite(kCommonScratchOffset, x"CAFEBABE");
    wait for kClkPeriod;
    HostReadCommon(kCommonScratchOffset, vReadData, vReadValid);
    assert vReadData = x"CAFEBABE"
      report "FAIL: Common scratch host write/read failed" severity error;

    HostWrite(kCommonSignatureOffset, x"FFFFFFFF");
    wait for kClkPeriod;
    HostReadCommon(kCommonSignatureOffset, vReadData, vReadValid);
    assert vReadData = kCommonSignatureValue
      report "FAIL: Common signature should remain read-only" severity error;
    report "PASS: Common host registers exercised";
    wait for kClkPeriod * 2;

    CurrentTest <= 12;
    report "==== Test 12: Host register array ====";
    HostReadArray(kArrayReg0Offset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Array reg0 default read should be valid" severity error;
    assert vReadData = kArrayDefaultValues(0)
      report "FAIL: Array reg0 default mismatch" severity error;

    HostReadArray(kArrayReg1Offset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Array reg1 default read should be valid" severity error;
    assert vReadData = kArrayDefaultValues(1)
      report "FAIL: Array reg1 default mismatch" severity error;

    HostWrite(kArrayReg1Offset, x"1111AAAA");
    wait for kClkPeriod;
    HostReadArray(kArrayReg1Offset, vReadData, vReadValid);
    assert vReadData = x"1111AAAA"
      report "FAIL: Array host write/read on reg1 failed" severity error;

    CurrentTest <= 13;
    report "==== Test 13: FPGA register array ====";

    FpgaWriteArray(2, x"2222BBBB");
    wait for kClkPeriod;
    assert bFpgaDataOut_Array(2) = x"2222BBBB"
      report "FAIL: Array FPGA write on reg2 failed" severity error;
    HostReadArray(kArrayReg2Offset, vReadData, vReadValid);
    assert vReadData = x"2222BBBB"
      report "FAIL: Host cannot read FPGA-written value on array reg2" severity error;
    report "PASS: Host register array exercised";
    wait for kClkPeriod * 2;

    report "==== All tests completed ====";
    TestDone <= true;
    wait;
  end process Stimulus;

end architecture sim;
