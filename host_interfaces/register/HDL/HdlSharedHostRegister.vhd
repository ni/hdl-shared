-------------------------------------------------------------------------------
--
-- File: HdlSharedHostRegister.vhd

--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
-- 
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
-- This entity implements a shared register that can be accessed by both the FPGA
-- and the host. It supports independent read and write operations from both sides.
--
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  
library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  
entity HdlSharedHostRegister is
  generic(
    kOffset  : natural := 0;
    kDefault  : std_logic_vector(31 downto 0);
    kReadOnly : boolean := false
  );
  port(
    BusClk      : in std_logic;
    aReset      : in boolean;

    -- Host Register Access
    bRegPortIn  : in RegPortIn_t;
    bRegPortOut : out RegPortOut_t;    

    -- FPGA Register Access
    bFpgaHostWrite    : out boolean;
    bFpgaWrite        : in boolean;
    bFpgaDataIn       : in std_logic_vector(31 downto 0);
    bFpgaDataOut      : out std_logic_vector(31 downto 0)

  );  
end entity HdlSharedHostRegister;

architecture rtl of HdlSharedHostRegister is

  signal bRegData : std_logic_vector(31 downto 0);
  signal bRegAddressed : boolean;
  
begin

  -- Address from RegPortIn is in 32 bit words so we need to multiply by 4 (shift left by 2) to get
  -- byte address and compare with our offset
  bRegAddressed  <= (unsigned(bRegPortIn.Address & "00") = kOffset);

  -- Write process: we always grant the priority to the FPGA write
  -- so if both write signal are high at the same time, only the 
  -- FpgaWrite makes it
  Writing:process (aReset, BusClk)
  begin
    if aReset then
      bRegData <= kDefault;
    elsif rising_edge(BusClk) then
      if bFpgaWrite then
        bRegData <= bFpgaDataIn;
      elsif bRegAddressed and bRegPortIn.Wt and not kReadOnly then
        bRegData <= bRegPortIn.Data;
      end if;
    end if;
  end process Writing;

  -- Read process: output data to the host must be valid for one clock cycle
  -- after a read request 
  Reading:process (BusClk)
  begin
    if aReset then
      bRegPortOut.Data <= (others => '0');
      bRegPortOut.DataValid <= false;
    elsif rising_edge(BusClk) then
      -- Host read response - assert data and valid for one clock cycle
      if bRegAddressed and bRegPortIn.Rd then
        bRegPortOut.Data <= bRegData;
        bRegPortOut.DataValid <= true;
      else
        bRegPortOut.Data <= (others => '0');
        bRegPortOut.DataValid <= false;
      end if;

      -- Assert FPGA host write for one cycle
      if bRegAddressed and bRegPortIn.Wt then
        bFpgaHostWrite <= true;
      else
        bFpgaHostWrite <= false;
      end if;

    end if;
  end process Reading;

  -- Register is always ready to accept host requests
  bRegPortOut.Ready <= true;

  -- Data is always available on the FPGA side when requested
  bFpgaDataOut <= bRegData;
  
end rtl;
