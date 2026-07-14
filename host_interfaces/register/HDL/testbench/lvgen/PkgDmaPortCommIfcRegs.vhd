-------------------------------------------------------------------------
--
-- LV generated package constants for testbenches
--
-------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package PkgDmaPortCommIfcRegs is

  subtype DmaRegOffset_t is natural;

  type DmaRegInfo_t is
    record
      offset     : DmaRegOffset_t;
    end record;

  type DmaReg_t is
    (Control,
     Status,
     Satcr,
     InterruptStatus,
     InterruptMask,
     FifoCount,
     PeerAddressLow,
     PeerAddressHigh,
     TransferLimit,
     PacketAlignment);

  type DmaRegArray_t is array (DmaReg_t) of DmaRegInfo_t;
  constant kDmaRegArray : DmaRegArray_t :=
    (Control           => (offset=>16#0#),
     Status            => (offset=>16#4#),
     Satcr             => (offset=>16#8#),
     InterruptStatus   => (offset=>16#C#),
     InterruptMask     => (offset=>16#10#),
     FifoCount         => (offset=>16#14#),
     PeerAddressLow    => (offset=>16#18#),
     PeerAddressHigh   => (offset=>16#1C#),
     TransferLimit     => (offset=>16#24#),
     PacketAlignment   => (offset=>16#28#));

  type DmaBitFields_t is
    (

     Reset,
     StartChannel,
     StopChannel,
     StopChannelWithFlush,
     LinkStream,
     UnlinkStream,
     ResetSatcr,
     ClearOverflowStatus,
     ClearUnderflowStatus,
     EnableSatcrUpdates,
     DisableSatcrUpdates,
     ClearFlushingStatus,
     ClearFlushingFailedStatus,
     ClearStreamErrorStatus,

     ResetStatus,
     DisableStatus,
     State,
     OverflowStatus,
     UnderflowStatus,
     SatcrUpdateStatus,
     FlushingStatus,
     FlushingFailedStatus,
     StreamErrorStatus,

     OverflowIrq,
     UnderflowIrq,
     StartStreamIrq,
     StopStreamIrq,
     FlushingIrq,
     StreamErrorIrq,

     EnableOverflowIrq,
     DisableOverflowIrq,
     OverflowIrqMaskStatus,
     EnableUnderflowIrq,
     DisableUnderflowIrq,
     UnderflowIrqMaskStatus,
     EnableStartStreamIrq,
     DisableStartStreamIrq,
     StartStreamIrqMaskStatus,
     EnableStopStreamIrq,
     DisableStopStreamIrq,
     StopStreamIrqMaskStatus,
     EnableFlushingIrq,
     DisableFlushingIrq,
     FlushingIrqMaskStatus,
     EnableStreamErrorIrq,
     DisableStreamErrorIrq,
     StreamErrorIrqMaskStatus,

     MaxPayloadSize,

     EnableAlignment,
     NextBoundary

    );

  type DmaBitFieldInfo_t is
    record
      index   : integer;
      defaultValue : boolean;
      size    : integer;
    end record;

  type DmaBitFieldArray is array (DmaBitFields_t) of DmaBitFieldInfo_t;
  constant kDmaBitFieldArray : DmaBitFieldArray :=
    (

     Reset                     => (index=>0,  defaultValue=>false, size=> 1),
     StartChannel              => (index=>1,  defaultValue=>false, size=> 1),
     StopChannel               => (index=>2,  defaultValue=>false, size=> 1),
     StopChannelWithFlush      => (index=>3,  defaultValue=>false, size=> 1),
     ResetSatcr                => (index=>4,  defaultValue=>false, size=> 1),
     LinkStream                => (index=>5,  defaultValue=>false, size=> 1),
     UnlinkStream              => (index=>6,  defaultValue=>false, size=> 1),
     ClearOverflowStatus       => (index=>7,  defaultValue=>false, size=> 1),
     ClearUnderflowStatus      => (index=>8,  defaultValue=>false, size=> 1),
     EnableSatcrUpdates        => (index=>9,  defaultValue=>false, size=> 1),
     DisableSatcrUpdates       => (index=>10, defaultValue=>false, size=> 1),
     ClearFlushingStatus       => (index=>11, defaultValue=>false, size=> 1),
     ClearFlushingFailedStatus => (index=>12, defaultValue=>false, size=> 1),
     ClearStreamErrorStatus    => (index=>13, defaultValue=>false, size=> 1),

     ResetStatus              => (index=>0, defaultValue=>false, size=> 1),

     DisableStatus            => (index=>1, defaultValue=>false, size=> 1),

     State                    => (index=>2, defaultValue=>false, size=> 2),

     OverflowStatus           => (index=>4, defaultValue=>false, size=> 1),
     UnderflowStatus          => (index=>5, defaultValue=>false, size=> 1),

     SatcrUpdateStatus        => (index=>6, defaultValue=>true, size=> 1),

     FlushingStatus           => (index=>7, defaultValue=>false, size=> 1),
     FlushingFailedStatus     => (index=>8, defaultValue=>false, size=> 1),

     StreamErrorStatus        => (index=>9, defaultValue=>false, size=> 1),

     OverflowIrq              => (index=>0,  defaultValue=>false, size=> 1),
     UnderflowIrq             => (index=>2,  defaultValue=>false, size=> 1),
     StartStreamIrq           => (index=>4,  defaultValue=>false, size=> 1),
     StopStreamIrq            => (index=>6,  defaultValue=>false, size=> 1),
     FlushingIrq              => (index=>8,  defaultValue=>false, size=> 1),
     StreamErrorIrq           => (index=>10, defaultValue=>false, size=> 1),

     EnableOverflowIrq        => (index=>0,  defaultValue=>false, size=> 1),
     DisableOverflowIrq       => (index=>1,  defaultValue=>false, size=> 1),
     EnableUnderflowIrq       => (index=>2,  defaultValue=>false, size=> 1),
     DisableUnderflowIrq      => (index=>3,  defaultValue=>false, size=> 1),
     EnableStartStreamIrq     => (index=>4,  defaultValue=>false, size=> 1),
     DisableStartStreamIrq    => (index=>5,  defaultValue=>false, size=> 1),
     EnableStopStreamIrq      => (index=>6,  defaultValue=>false, size=> 1),
     DisableStopStreamIrq     => (index=>7,  defaultValue=>false, size=> 1),
     EnableFlushingIrq        => (index=>8,  defaultValue=>false, size=> 1),
     DisableFlushingIrq       => (index=>9,  defaultValue=>false, size=> 1),
     EnableStreamErrorIrq     => (index=>10, defaultValue=>false, size=> 1),
     DisableStreamErrorIrq    => (index=>11, defaultValue=>false, size=> 1),

     OverflowIrqMaskStatus    => (index=>0,  defaultValue=>false, size=> 1),
     UnderflowIrqMaskStatus   => (index=>2,  defaultValue=>false, size=> 1),
     StartStreamIrqMaskStatus => (index=>4,  defaultValue=>false, size=> 1),
     StopStreamIrqMaskStatus  => (index=>6,  defaultValue=>false, size=> 1),
     FlushingIrqMaskStatus    => (index=>8,  defaultValue=>false, size=> 1),
     StreamErrorIrqMaskStatus => (index=>10, defaultValue=>false, size=> 1),

     MaxPayloadSize           => (index=>16,  defaultValue=>false, size=> 16),

     EnableAlignment          => (index=>31, defaultValue=>true,  size=> 1),
     NextBoundary             => (index=>0,  defaultValue=>false, size=> 16)

  );

  function OffsetValue(Reg : DmaReg_t) return DmaRegOffset_t;

  function BitFieldIndex(RegBit :  DmaBitFields_t) return integer;
  function BitFieldInitValue(RegBit : DmaBitFields_t) return boolean;
  function BitFieldSize(RegBit : DmaBitFields_t) return integer;
  function BitFieldUpperIndex(RegBit : DmaBitFields_t) return integer;

end PkgDmaPortCommIfcRegs;

package body PkgDmaPortCommIfcRegs is

  function OffsetValue(Reg : DmaReg_t) return DmaRegOffset_t is
  begin
    return kDmaRegArray(Reg).offset;
  end OffsetValue;

  function BitFieldIndex(RegBit : DmaBitFields_t) return integer is
  begin
    return kDmaBitFieldArray(RegBit).index;
  end BitFieldIndex;

  function BitFieldInitValue(RegBit : DmaBitFields_t) return boolean is
  begin
    return kDmaBitFieldArray(RegBit).defaultValue;
  end BitFieldInitValue;

  function BitFieldSize(RegBit : DmaBitFields_t) return integer is
  begin
    return kDmaBitFieldArray(RegBit).size;
  end BitFieldSize;

  function BitFieldUpperIndex(RegBit : DmaBitFields_t) return integer is
  begin
    return BitFieldIndex(RegBit) + BitFieldSize(RegBit) - 1;
  end BitFieldUpperIndex;

end PkgDmaPortCommIfcRegs;
