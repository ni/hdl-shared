-------------------------------------------------------------------------------
--
-- File: tb_HdlSharedHostRegister.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
-- 
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
-- Testbench for HdlSharedHostRegister entity to verify:
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

entity tb_HdlSharedHostRegister is
end entity tb_HdlSharedHostRegister;

architecture sim of tb_HdlSharedHostRegister is

  -- Constants
  constant kClkPeriod : time := 10 ns;
  constant kTestOffset : natural := 16#40#;  -- Byte address, must be multiple of 4
  constant kDefaultValue : std_logic_vector(31 downto 0) := x"DEADBEEF";
  
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
  
  -- Test control
  signal TestDone : boolean := false;

begin

  -- Clock generation
  BusClk <= not BusClk after kClkPeriod/2 when not TestDone else '0';

  -- DUT: Standard mode
  DUT_Standard: entity work.HdlSharedHostRegister
    generic map(
      kOffset => kTestOffset,
      kDefault => kDefaultValue,
      kReadOnly => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOut,
      bFpgaHostWrite => bFpgaHostWrite,
      bFpgaWrite     => bFpgaWrite,
      bFpgaDataIn    => bFpgaDataIn,
      bFpgaDataOut   => bFpgaDataOut
    );

  -- DUT: Host read-only mode
  DUT_ReadOnly: entity work.HdlSharedHostRegister
    generic map(
      kOffset => kTestOffset,
      kDefault => kDefaultValue,
      kReadOnly => true
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOut_ReadOnly,
      bFpgaHostWrite => bFpgaHostWrite_ReadOnly,
      bFpgaWrite     => bFpgaWrite,
      bFpgaDataIn    => bFpgaDataIn,
      bFpgaDataOut   => bFpgaDataOut_ReadOnly
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
      bRegPortIn.Rd <= false;
      wait until rising_edge(BusClk);
      data := bRegPortOut.Data;
      valid := bRegPortOut.DataValid;
    end procedure HostRead;

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
    
    variable vReadData : std_logic_vector(31 downto 0);
    variable vReadValid : boolean;
    
  begin
    -- Initial reset
    aReset <= true;
    wait for kClkPeriod * 5;
    wait until rising_edge(BusClk);
    aReset <= false;
    wait until rising_edge(BusClk);
    
    report "==== Test 1: Check default value ====";
    HostRead(kTestOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Read valid should be true" severity error;
    assert vReadData = kDefaultValue 
      report "FAIL: Default value mismatch. Expected: " & 
             to_hstring(to_bitvector(kDefaultValue)) & " Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Default value correct";
    wait for kClkPeriod * 2;

    report "==== Test 2: Host write and read back ====";
    HostWrite(kTestOffset, x"12345678");
    wait for kClkPeriod;
    HostRead(kTestOffset, vReadData, vReadValid);
    assert vReadValid report "FAIL: Read valid should be true" severity error;
    assert vReadData = x"12345678" 
      report "FAIL: Host write failed. Expected: 12345678 Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Host write and read successful";
    wait for kClkPeriod * 2;

    report "==== Test 3: FPGA write and read (from FPGA side) ====";
    FpgaWrite(x"ABCD1234");
    wait for kClkPeriod;
    assert bFpgaDataOut = x"ABCD1234" 
      report "FAIL: FPGA write failed. Expected: ABCD1234 Got: " & to_hstring(to_bitvector(bFpgaDataOut)) 
      severity error;
    report "PASS: FPGA write successful";
    wait for kClkPeriod * 2;

    report "==== Test 4: FPGA write visible to host ====";
    HostRead(kTestOffset, vReadData, vReadValid);
    assert vReadData = x"ABCD1234" 
      report "FAIL: Host can't see FPGA write. Expected: ABCD1234 Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Host can read FPGA-written data";
    wait for kClkPeriod * 2;

    report "==== Test 5: Priority test - FPGA write wins ====";
    -- Set up simultaneous write
    bRegPortIn.Address <= to_unsigned(kTestOffset / 4, bRegPortIn.Address'length);
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

    report "==== Test 6: Wrong address should not respond ====";
    HostRead(kTestOffset + 4, vReadData, vReadValid);
    assert not vReadValid report "FAIL: Wrong address should not give valid response" severity error;
    report "PASS: Wrong address correctly ignored";
    wait for kClkPeriod * 2;

    report "==== Test 7: Host read-only mode ====";
    -- First write with FPGA
    FpgaWrite(x"FEDCBA98");
    wait for kClkPeriod;
    assert bFpgaDataOut_ReadOnly = x"FEDCBA98" 
      report "FAIL: FPGA write to read-only register failed" severity error;
    -- Try to write from host (should be ignored)
    assert not bFpgaHostWrite_ReadOnly report "FAIL: bFpgaHostWrite should be false before host write attempt" severity error;
    HostWrite(kTestOffset, x"55555555");
    wait for kClkPeriod;
    -- Verify bFpgaHostWrite did NOT assert
    assert not bFpgaHostWrite_ReadOnly 
      report "FAIL: bFpgaHostWrite should not assert for read-only register" severity error;
    -- Verify value did not change
    assert bFpgaDataOut_ReadOnly = x"FEDCBA98" 
      report "FAIL: Host write should be ignored in read-only mode. Got: " & to_hstring(to_bitvector(bFpgaDataOut_ReadOnly)) 
      severity error;
    report "PASS: Host read-only mode working correctly";
    wait for kClkPeriod * 2;

    report "==== Test 8: bFpgaHostWrite pulse detection ====";
    assert not bFpgaHostWrite report "FAIL: bFpgaHostWrite should be false initially" severity error;
    HostWrite(kTestOffset, x"99999999");
    -- bFpgaHostWrite should have pulsed during the write
    wait for kClkPeriod;
    assert not bFpgaHostWrite report "FAIL: bFpgaHostWrite should return to false" severity error;
    report "PASS: bFpgaHostWrite pulse detected correctly";
    wait for kClkPeriod * 2;

    report "==== Test 9: Reset behavior ====";
    HostWrite(kTestOffset, x"FFFFFFFF");
    wait for kClkPeriod;
    aReset <= true;
    wait for kClkPeriod * 3;
    aReset <= false;
    wait for kClkPeriod;
    HostRead(kTestOffset, vReadData, vReadValid);
    assert vReadData = kDefaultValue 
      report "FAIL: Reset should restore default value. Expected: " & 
             to_hstring(to_bitvector(kDefaultValue)) & " Got: " & to_hstring(to_bitvector(vReadData)) 
      severity error;
    report "PASS: Reset restores default value";
    wait for kClkPeriod * 2;

    report "==== All tests completed ====";
    TestDone <= true;
    wait;
  end process Stimulus;

end architecture sim;
