-------------------------------------------------------------------------------
--
-- File: NiSharedCommonHostRegs.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
-- 
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
-- This entity implements a fixed, standard set of four host-visible registers
-- that provide design identity/version metadata plus a writable scratch location.
--
-- Register map (byte offsets):
--   0x00 Signature (read-only)
--     - Identifies the design/target image.
--     - Used by host software to confirm it is communicating with the expected bitfile.
--
--   0x04 Version (read-only)
--     - Current interface/implementation version for this design.
--     - Used by host software to select compatible behavior/features.
--
--   0x08 Oldest Compatible Version (read-only)
--     - Lowest host-side version that is still supported.
--     - Enables forward/backward compatibility checks during startup.
--
--   0x0C Scratch (read/write)
--     - General-purpose software-accessible test/debug register.
--     - Can be used to validate host register access and simple control plumbing.
--
-- This block is intended to give every design a consistent baseline register
-- interface for discovery, version gating, and bring-up diagnostics.
--
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  
library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  
entity NiSharedCommonHostRegs is
  generic (
    kMaxHdlRegOffset : natural;
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
end entity NiSharedCommonHostRegs;

architecture rtl of NiSharedCommonHostRegs is

  constant kNumRegisters : natural := 4;

  -- Registers 0..3 at byte offsets 0x00/0x04/0x08/0x0C:
  --   Signature (RO), Version (RO), Oldest-Compatible-Version (RO), Scratch (RW).
  constant kDefaults : Slv32Ary_t(0 to kNumRegisters-1) :=
    (0 => kSignature, 1 => kVersion, 2 => kOldestCompatibleVersion, 3 => x"00000000");
  constant kReadOnly : BooleanVector(0 to kNumRegisters-1) :=
    (0 => true, 1 => true, 2 => true, 3 => false);
  constant kFalseVec : BooleanVector(0 to kNumRegisters-1) := (others => false);
  constant kZeroData : Slv32Ary_t(0 to kNumRegisters-1)    := (others => (others => '0'));

begin

  -- Built on NiSharedHostRegisterArray at base offset 0. The FPGA-side ports are
  -- unused here: the three identity registers are read-only and Scratch is
  -- host-only, so no FPGA writes/acks are driven.
  CommonRegsArray: entity work.NiSharedHostRegisterArray
    generic map(
      kMaxHdlRegOffset => kMaxHdlRegOffset,
      kNumRegisters    => kNumRegisters,
      kBaseAddress     => 0,
      kDefault         => kDefaults,
      kReadOnly        => kReadOnly,
      kUseFpgaAck      => kFalseVec
    )
    port map(
      BusClk         => BusClk,
      aReset         => aReset,
      bRegPortIn     => bRegPortIn,
      bRegPortOut    => bRegPortOut,
      bFpgaHostWrite => open,
      bFpgaAck       => kFalseVec,
      bFpgaWrite     => kFalseVec,
      bFpgaDataIn    => kZeroData,
      bFpgaDataOut   => open
    );

end rtl;
