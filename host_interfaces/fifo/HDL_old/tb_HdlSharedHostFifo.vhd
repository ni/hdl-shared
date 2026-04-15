library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;
  use work.PkgDmaPortDmaFifos.all;
  use work.PkgDmaPortCommIfcStreamStates.all;

entity tb_HdlSharedHostFifo is
end entity tb_HdlSharedHostFifo;

architecture sim of tb_HdlSharedHostFifo is

  constant cFifoDepth : natural := 1024;
  constant cSampleWidth : positive := 32;
  constant cNumSamplesPerWrite : positive := 1;
  constant cNumSamplesPerRead : positive := 1;

  signal aDiagramReset : boolean := false;
  signal aBusReset : boolean := false;
  signal BusClk : std_logic := '0';
  signal ViClk : std_logic := '0';
  signal DefaultClk : std_logic := '0';

  signal bInputStreamInterfaceToFifo : InputStreamInterfaceToFifo_t;
  signal bInputStreamInterfaceFromFifo : InputStreamInterfaceFromFifo_t;
  signal bOutputStreamInterfaceToFifo : OutputStreamInterfaceToFifo_t;
  signal bOutputStreamInterfaceFromFifo : OutputStreamInterfaceFromFifo_t;

  signal vDataIn : std_logic_vector(cSampleWidth*cNumSamplesPerWrite-1 downto 0) := (others => '0');
  signal vPushPopIn : boolean := false;
  signal vDisableIn : boolean := false;
  signal vResetForFifoIn : boolean := false;
  signal bResetForFifoIn : boolean := false;
  signal bResetDoneIn : boolean := false;
  signal vFlushIn : boolean := false;
  signal vInputValid : std_logic := '0';
  signal bStartStreamRequestIn : boolean := false;
  signal bStopStreamRequestFromDiagramIn : boolean := false;
  signal dStopRequestStrobeIn : boolean := false;
  signal bStopStreamWithFlushRequestIn : boolean := false;
  signal bFlushTimeoutRequestIn : boolean := false;
  signal dStopWithFlushRequestStrobeIn : boolean := false;

  signal vTimeoutOut : std_logic_vector(31 downto 0) := (others => '0');
  signal vEnableInOut : std_logic := '0';
  signal vEnableClearOut : std_logic := '0';
  signal vCtEnableInOut : std_logic := '0';
  signal vCtEnableOutClearOut : std_logic := '0';
  signal vReadyForOutput : std_logic := '0';
  signal vStreamStateEnableInOut : std_logic := '0';
  signal vStreamStateEnableClearOut : std_logic := '0';
  signal dStreamStateEnableInOut : std_logic := '0';
  signal dStreamStateEnableClearOut : std_logic := '0';
  signal dStartRequestEnableInOut : std_logic := '0';
  signal dStartRequestEnableClearOut : std_logic := '0';
  signal dStopRequestEnableInOut : std_logic := '0';
  signal dStopRequestEnableClearOut : std_logic := '0';

begin

  u_input_fifo_ifc: entity work.HdlSharedInputFifoInterface
    generic map (
      kFifoDepth => cFifoDepth,
      kSampleWidth => cSampleWidth,
      kNumOfSamplesPerWrite => cNumSamplesPerWrite,
      kSignExtend => false,
      kFxpType => false,
      kPeerToPeer => false,
      kDisableOnFifoTimeout => false,
      kViClkIsDefaultClk => true,
      kWriteUsingHandshaking => false)
    port map (
      aDiagramReset => aDiagramReset,
      aBusReset => aBusReset,
      BusClk => BusClk,
      bInputStreamInterfaceToFifo => bInputStreamInterfaceToFifo,
      bInputStreamInterfaceFromFifo => bInputStreamInterfaceFromFifo,
      ViClk => ViClk,
      vDataIn => vDataIn,
      vFull => open,
      vPushPop => vPushPopIn,
      vDisable => vDisableIn,
      vResetForFifo => vResetForFifoIn,
      bResetForFifo => bResetForFifoIn,
      bResetDone => bResetDoneIn,
      vFlush => vFlushIn,
      vCtCount => open,
      vInputValid => vInputValid,
      vReadyForInput => open,
      DefaultClk => DefaultClk,
      vStreamStateOut => open,
      dStreamStateOut => open,
      dCurrentStreamState => open,
      bStartStreamRequest => bStartStreamRequestIn,
      bStopStreamRequestFromDiagram => bStopStreamRequestFromDiagramIn,
      dStopRequestStrobe => dStopRequestStrobeIn,
      bStopStreamWithFlushRequest => bStopStreamWithFlushRequestIn,
      bFlushTimeoutRequest => bFlushTimeoutRequestIn,
      dStopWithFlushRequestStrobe => dStopWithFlushRequestStrobeIn);

  u_output_fifo_ifc: entity work.HdlSharedOutputFifoInterface
    generic map (
      kFifoDepth => cFifoDepth,
      kSampleWidth => cSampleWidth,
      kNumOfSamplesPerRead => cNumSamplesPerRead,
      kFxpType => false,
      kScl => false,
      kCountScl => false,
      kPeerToPeer => false,
      kDisableOnFifoTimeout => false,
      kViClkIsDefaultClk => true,
      kReadUsingHandshaking => false)
    port map (
      aDiagramReset => aDiagramReset,
      aBusReset => aBusReset,
      BusClk => BusClk,
      ViClk => ViClk,
      bOutputStreamInterfaceToFifo => bOutputStreamInterfaceToFifo,
      bOutputStreamInterfaceFromFifo => bOutputStreamInterfaceFromFifo,
      vDataOut => open,
      vEmpty => open,
      vTimeout => vTimeoutOut,
      vEnableIn => vEnableInOut,
      vEnableOut => open,
      vEnableClear => vEnableClearOut,
      vCtCount => open,
      vCtEnableIn => vCtEnableInOut,
      vCtEnableOut => open,
      vCtEnableOutClear => vCtEnableOutClearOut,
      vOutputValid => open,
      vReadyForOutput => vReadyForOutput,
      DefaultClk => DefaultClk,
      vStreamStateEnableIn => vStreamStateEnableInOut,
      vStreamStateEnableOut => open,
      vStreamStateEnableClear => vStreamStateEnableClearOut,
      vStreamStateOut => open,
      dStreamStateEnableIn => dStreamStateEnableInOut,
      dStreamStateEnableOut => open,
      dStreamStateEnableClear => dStreamStateEnableClearOut,
      dStreamStateOut => open,
      dCurrentStreamState => open,
      dStartRequestEnableIn => dStartRequestEnableInOut,
      dStartRequestEnableOut => open,
      dStartRequestEnableClear => dStartRequestEnableClearOut,
      dStopRequestEnableIn => dStopRequestEnableInOut,
      dStopRequestEnableOut => open,
      dStopRequestEnableClear => dStopRequestEnableClearOut);

end architecture sim;
