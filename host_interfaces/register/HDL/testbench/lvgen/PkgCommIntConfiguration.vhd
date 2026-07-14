-------------------------------------------------------------------------
--
-- LV generated package constants for testbenches
--
-------------------------------------------------------------------------

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.PkgNiUtilities.all;

package PkgCommIntConfiguration is

  constant kAddressWidth          : positive := 22;
  constant kNumberOfDmaChannels   : natural  := 16;
  constant kNumberOfIrqs          : natural  := 1;
  constant kNumberOfMasterPorts   : natural  := 16;
  constant kIrqBaseOffset         : natural  := 16#120018#;

  constant kFifoReadLatency       : natural  := 4;
  constant kDmaDataWidth          : positive := 64;
  constant kDmaAddressWidth       : positive := 32;
  constant kBusBaggageWidth       : natural  := 6;
  constant kInputMaxTransfer      : natural  := 1024;
  constant kOutputMaxTransfer     : natural  := 1024;

  constant kDmaHighSpeedSinkBase     : natural  :=  16#0#;
  constant kDmaHighSpeedSinkSize     : positive  :=  16#1#;

  constant kInputMaxRequests      : natural := 4;
  constant kOutputMaxRequests     : natural := 8;
  constant kInputDataBuffer       : natural := 2;

  constant kDmaRegBase              : natural := 16#4000#;
  constant kDmaRegSize              : positive := 16#4000#;

  constant kEnableByteSwapper       : boolean := false;
  constant kEnableLatchingTtc       : boolean := true;
  constant kTtcWidth                : natural := 64;
  constant kEnableFullScatterGather : boolean := true;
  constant kMaxChunkyLinkSize       : natural := 512;
  constant kLinkFetchMaxRequests    : natural := 1;

  constant kMaxMuxWidth             : natural := 8;

  type MasterPortMode_t is (
    Disabled,
    NiFpgaMasterPortWrite,
    NiFpgaMasterPortRead,
    NiFpgaMasterPortWriteRead
    );

  type MasterPortConfiguration_t is record
    Mode : MasterPortMode_t;
  end record;

  type MasterPortConfArray_t is array (natural range <>)
    of MasterPortConfiguration_t;

  constant kMasterPortConfArray :
    MasterPortConfArray_t(0 to kNumberOfMasterPorts - 1) :=
      ((Mode => NiFpgaMasterPortWriteRead),
       (Mode => NiFpgaMasterPortWrite),
       (Mode => NiFpgaMasterPortRead),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled),
       (Mode => Disabled)
      );

  type DmaChannelMode_t is (
    Disabled,
    NiFpgaTargetToHost,
    NiFpgaHostToTarget,
    NiCoreTargetToHost,
    NiCoreHostToTarget,
    NiFpgaPeerToPeerWriter,
    NiFpgaPeerToPeerReader,
    NiFpgaMemoryBufferWriter,
    NiFpgaMemoryBufferReader
    );

  type DmaChannelConfiguration_t is record
    Mode                      : DmaChannelMode_t;
    FifoDepth                 : natural;
    FifoWidth                 : natural;
    ElementsPerClockCycle     : natural;
    SignedData                : boolean;
    BaseAddress               : natural;
    SCL                       : boolean;
    CountSCL                  : boolean;
    FxpType                   : boolean;
    DisableOnFifoTimeout      : boolean;
    WriteWindowOffset         : natural;
    DmaClkIsDefaultClk        : boolean;
    InterfaceIsHandshaking    : boolean;
  end record;

  type DmaChannelConfArray_t is array (natural range <>)
    of DmaChannelConfiguration_t;

  constant kDmaFifoConfArray : DmaChannelConfArray_t(0 to Larger(kNumberOfDmaChannels,16) - 1) :=
(   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,

    FifoWidth => 64,
    ElementsPerClockCycle => 1,
    SignedData => False,
    BaseAddress =>16#8000#,

    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 16,
    ElementsPerClockCycle => 1,
    SignedData => False,
    BaseAddress =>16#8200#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 64,
    ElementsPerClockCycle => 2,
    SignedData => False,
    BaseAddress =>16#8400#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 16,
    ElementsPerClockCycle => 2,
    SignedData => False,
    BaseAddress =>16#8600#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 64,
    ElementsPerClockCycle => 4,
    SignedData => False,
    BaseAddress =>16#8800#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 16,
    ElementsPerClockCycle => 4,
    SignedData => False,
    BaseAddress =>16#8A00#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 32,
    ElementsPerClockCycle => 8,
    SignedData => False,
    BaseAddress =>16#8C00#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaTargetToHost,
    FifoDepth => 1023,
    FifoWidth => 8,
    ElementsPerClockCycle => 8,
    SignedData => False,
    BaseAddress =>16#8E00#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
  (Mode => NiFpgaHostToTarget,
    FifoDepth => 1119,
    FifoWidth => 16,
    ElementsPerClockCycle => 16,
    SignedData => False,
    BaseAddress =>16#9000#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => True)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 1071,
    FifoWidth => 16,
    ElementsPerClockCycle => 8,
    SignedData => False,
    BaseAddress =>16#9200#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 21,
    FifoWidth => 8,
    ElementsPerClockCycle => 1,
    SignedData => False,
    BaseAddress =>16#9400#,
    SCL => False,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => False)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 1047,
    FifoWidth => 32,
    ElementsPerClockCycle => 4,
    SignedData => False,
    BaseAddress =>16#9600#,
    SCL => True,
    CountSCL => False,
    FxpType => True,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 21,
    FifoWidth => 8,
    ElementsPerClockCycle => 1,
    SignedData => False,
    BaseAddress =>16#9800#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 1035,
    FifoWidth => 32,
    ElementsPerClockCycle => 2,
    SignedData => False,
    BaseAddress =>16#9A00#,
    SCL => True,
    CountSCL => False,
    FxpType => True,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 1029,
    FifoWidth => 8,
    ElementsPerClockCycle => 1,
    SignedData => False,
    BaseAddress =>16#9C00#,
    SCL => True,
    CountSCL => False,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
,
   (Mode => NiFpgaHostToTarget,
    FifoDepth => 1029,
    FifoWidth => 32,
    ElementsPerClockCycle => 1,
    SignedData => False,
    BaseAddress =>16#9E00#,
    SCL => True,
    CountSCL => True,
    FxpType => False,
    DisableOnFifoTimeout => false,
    WriteWindowOffset => 16#0#,
    DmaClkIsDefaultClk => False,
    InterfaceIsHandshaking => true)
);

  function DmaMaxWidth(DmaChannelConfArray : DmaChannelConfArray_t) return natural;
  function DmaMaxWidth(unused : boolean) return natural;
  function DmaMaxDepth(DmaChannelConfArray : DmaChannelConfArray_t) return positive;
  function DmaMaxDepth(unused : boolean) return positive;

  function NumOfInStrms(Arg : DmaChannelConfArray_t) return natural;
  function NumOfOutStrms(Arg : DmaChannelConfArray_t) return natural;

  function NumOfWriteMasterPorts(Arg : MasterPortConfArray_t) return natural;
  function NumOfReadMasterPorts(Arg : MasterPortConfArray_t) return natural;

end PkgCommIntConfiguration;

package body PkgCommIntConfiguration is

  function DmaMaxWidth(DmaChannelConfArray : DmaChannelConfArray_t) return natural is
    variable maxWidth : natural := 1;
  begin
    for i in DmaChannelConfArray'range loop
      maxWidth := Larger(maxWidth,
                    DmaChannelConfArray(i).FifoWidth*DmaChannelConfArray(i).ElementsPerClockCycle);
    end loop;
    return maxWidth;
  end DmaMaxWidth;

  function DmaMaxWidth(unused : boolean) return natural is
  begin
    return DmaMaxWidth(kDmaFifoConfArray);
  end DmaMaxWidth;

  function DmaMaxDepth(DmaChannelConfArray : DmaChannelConfArray_t) return positive is
    variable maxDepth : positive := 1;
  begin
    for i in DmaChannelConfArray'range loop
      maxDepth := Larger(maxDepth, DmaChannelConfArray(i).FifoDepth);
    end loop;
    return maxDepth;
  end DmaMaxDepth;

  function DmaMaxDepth(unused : boolean) return positive is
  begin
    return DmaMaxDepth(kDmaFifoConfArray);
  end DmaMaxDepth;

  function NumOfInStrms(Arg : DmaChannelConfArray_t)
  return natural is
    variable ReturnVal : natural;
  begin
    ReturnVal := 0;
    for i in arg'range loop
      if Arg(i).Mode = NiFpgaTargetToHost or Arg(i).Mode = NiFpgaPeerToPeerWriter or Arg(i).Mode = NiFpgaMemoryBufferWriter then
        ReturnVal := ReturnVal + 1;
      end if;
    end loop;
    return ReturnVal;
  end NumOfInStrms;

  function NumOfOutStrms(Arg : DmaChannelConfArray_t)
  return natural is
    variable ReturnVal : natural;
  begin
    ReturnVal := 0;
    for i in arg'range loop
      if Arg(i).Mode = NiFpgaHostToTarget or Arg(i).Mode = NiFpgaMemoryBufferReader then
        ReturnVal := ReturnVal + 1;
      end if;
    end loop;
    return ReturnVal;
  end NumOfOutStrms;

  function NumOfWriteMasterPorts(Arg : MasterPortConfArray_t)
  return natural is
    variable ReturnVal : natural;
  begin
    ReturnVal := 0;
    for i in arg'range loop
      if Arg(i).Mode = NiFpgaMasterPortWriteRead or Arg(i).Mode = NiFpgaMasterPortWrite then
        ReturnVal := ReturnVal + 1;
      end if;
    end loop;
    return ReturnVal;
  end NumOfWriteMasterPorts;

  function NumOfReadMasterPorts(Arg : MasterPortConfArray_t)
  return natural is
    variable ReturnVal : natural;
  begin
    ReturnVal := 0;
    for i in arg'range loop
      if Arg(i).Mode = NiFpgaMasterPortWriteRead or Arg(i).Mode = NiFpgaMasterPortRead then
        ReturnVal := ReturnVal + 1;
      end if;
    end loop;
    return ReturnVal;
  end NumOfReadMasterPorts;

end PkgCommIntConfiguration;
