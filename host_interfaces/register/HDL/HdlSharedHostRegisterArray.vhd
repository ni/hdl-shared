-------------------------------------------------------------------------------
--
-- File: HdlSharedHostRegisterArray.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
-- 
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
-- This entity instantiates an array of HdlSharedHostRegister entities
-- using a for-generate loop.
--
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  
library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  
entity HdlSharedHostRegisterArray is
  generic(
    kNumRegisters : natural := 10;
    kBaseAddress : natural := 0;
    kDefault : std_logic_vector(31 downto 0) := (others => '0')
  );
  port(
    BusClk : in std_logic;
    aReset : in boolean;

    -- Host Register Access
    bRegPortIn  : in RegPortIn_t;
    bRegPortOut : out RegPortOut_t;    

    -- FPGA Register Access (array for kNumRegisters)
    bFpgaWrite  : in boolean_vector(0 to kNumRegisters-1);
    bFpgaDataIn : in slv32_array(0 to kNumRegisters-1);
    bFpgaDataOut : out slv32_array(0 to kNumRegisters-1)
  );  
end entity HdlSharedHostRegisterArray;

architecture rtl of HdlSharedHostRegisterArray is

  type RegPortOutArray_t is array (natural range <>) of RegPortOut_t;
  signal bRegPortOutArray : RegPortOutArray_t(0 to kNumRegisters-1);

begin

  -- Generate instances of HdlSharedHostRegister
  GenRegisters: for i in 0 to kNumRegisters-1 generate
    RegInst: entity work.HdlSharedHostRegister
      generic map(
        kAddress => kBaseAddress + i,
        kDefault => kDefault
      )
      port map(
        BusClk       => BusClk,
        aReset       => aReset,
        bRegPortIn   => bRegPortIn,
        bRegPortOut  => bRegPortOutArray(i),
        bFpgaWrite   => bFpgaWrite(i),
        bFpgaDataIn  => bFpgaDataIn(i),
        bFpgaDataOut => bFpgaDataOut(i)
      );
  end generate GenRegisters;

  -- Combine register outputs using OR reduction
  CombineOutputs: process(bRegPortOutArray)
    variable vCombinedData : std_logic_vector(31 downto 0);
    variable vCombinedValid : boolean;
  begin
    vCombinedData := (others => '0');
    vCombinedValid := false;
    
    for i in 0 to kNumRegisters-1 loop
      vCombinedData := vCombinedData or bRegPortOutArray(i).Data;
      vCombinedValid := vCombinedValid or bRegPortOutArray(i).DataValid;
    end loop;
    
    bRegPortOut.Data <= vCombinedData;
    bRegPortOut.DataValid <= vCombinedValid;
  end process CombineOutputs;

end rtl;



  HdlSharedHostRegisterArray_inst : entity work.HdlSharedHostRegisterArray
    generic map(
      kNumRegisters => 8,
      kBaseAddress  => 13,
      kDefault      => (others => '0')
    )
    port map(
      BusClk       => BusClk,
      aReset       => aBusReset,
      bRegPortIn   => bRegPortIn,
      bRegPortOut  => bRegPortOutHdlRegArray,
      bFpgaWrite   => bHdlRegArrayFpgaWrite,
      bFpgaDataIn  => bHdlRegArrayFpgaDataIn,
      bFpgaDataOut => bHdlRegArrayFpgaDataOut
    );