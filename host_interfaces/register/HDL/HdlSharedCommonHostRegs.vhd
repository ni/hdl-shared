-------------------------------------------------------------------------------
--
-- File: HdlSharedCommonHostRegs.vhd
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
  
entity HdlSharedCommonHostRegs is
  generic (
    kSignature : std_logic_vector(31 downto 0);
    kVersion : std_logic_vector(31 downto 0);
    kOldestCompatibleVersion : std_logic_vector(31 downto 0)
  );
  port(
    BusClk : in std_logic;
    aReset : in boolean;

    -- Host Register Access
    bRegPortIn  : in RegPortIn_t;
    bRegPortOut : out RegPortOut_t
  );  
end entity HdlSharedCommonHostRegs;

architecture rtl of HdlSharedCommonHostRegs is

  constant kNumRegisters : natural := 4;
  constant kSignatureOffset : natural := 0;
  constant kVersionOffset : natural := 4;
  constant kOldestCompatibleVersionOffset : natural := 8;
  constant kScratchOffset : natural := 12;
  type RegPortOutArray_t is array (natural range <>) of RegPortOut_t;
  signal bRegPortOutArray : RegPortOutArray_t(0 to kNumRegisters-1);

begin


  SignatureReg: entity work.HdlSharedHostRegister
    generic map(
      kOffset => kSignatureOffset,
      kDefault => kSignature,
      kReadOnly => true,
      kUseFpgaAck => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOutArray(0),
      bFpgaHostWrite => open,
      bFpgaAck       => false,
      bFpgaWrite     => false,
      bFpgaDataIn    => (others => '0'),
      bFpgaDataOut   => open
    );


  VersionReg: entity work.HdlSharedHostRegister
    generic map(
      kOffset => kVersionOffset,
      kDefault => kVersion,
      kReadOnly => true,
      kUseFpgaAck => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOutArray(1),
      bFpgaHostWrite => open,
      bFpgaAck       => false,
      bFpgaWrite     => false,
      bFpgaDataIn    => (others => '0'),
      bFpgaDataOut   => open
    );


  OldestCompatibleVersionReg: entity work.HdlSharedHostRegister
    generic map(
      kOffset => kOldestCompatibleVersionOffset,
      kDefault => kOldestCompatibleVersion,
      kReadOnly => true,
      kUseFpgaAck => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOutArray(2),
      bFpgaHostWrite => open,
      bFpgaAck       => false,
      bFpgaWrite     => false,
      bFpgaDataIn    => (others => '0'),
      bFpgaDataOut   => open
    );

  Scratch: entity work.HdlSharedHostRegister
    generic map(
      kOffset => kScratchOffset,
      kDefault => x"00000000",
      kReadOnly => false,
      kUseFpgaAck => false
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOutArray(3),
      bFpgaHostWrite => open,
      bFpgaAck       => false,
      bFpgaWrite     => false,
      bFpgaDataIn    => (others => '0'),
      bFpgaDataOut   => open
    );
   

  -- Combine register outputs using OR reduction for Data/DataValid, AND reduction for Ready
  CombineOutputs: process(bRegPortOutArray)
    variable vCombinedData : std_logic_vector(31 downto 0);
    variable vCombinedValid : boolean;
    variable vCombinedReady : boolean;
  begin
    vCombinedData := (others => '0');
    vCombinedValid := false;
    vCombinedReady := true;
    
    for i in 0 to kNumRegisters-1 loop
      vCombinedData := vCombinedData or bRegPortOutArray(i).Data;
      vCombinedValid := vCombinedValid or bRegPortOutArray(i).DataValid;
      vCombinedReady := vCombinedReady and bRegPortOutArray(i).Ready;
    end loop;
    
    bRegPortOut.Data <= vCombinedData;
    bRegPortOut.DataValid <= vCombinedValid;
    bRegPortOut.Ready <= vCombinedReady;
  end process CombineOutputs;

end rtl;
