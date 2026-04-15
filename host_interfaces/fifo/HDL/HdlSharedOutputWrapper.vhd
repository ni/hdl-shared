-------------------------------------------------------------------------------
--
-- File: HdlSharedOutputWrapper.vhd
-- Original Project: LabVIEW FPGA
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--
--   This block wraps the DMA output stream controller (DmaPortCommIfcOutputStream)
--   together with the simplified FIFO interface (HdlSharedOutputFifoInterface).
--   Enable chains have been removed; the user-facing signals (read, stream
--   state queries, and state transition requests) are exposed directly.
--
--   Based on DmaPortCommIfcOutputWrapper.
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;
  use work.PkgDmaPortDataPackingFifo.all;
  use work.PkgDmaPortDmaFifos.all;
  use work.PkgDmaPortCommIfcStreamStates.all;
  use work.PkgNiDma.all;

entity HdlSharedOutputWrapper is
    generic(

      -- kFifoDepth      : This is the size of the DMA FIFO in terms of bus
      --                   data width words.
      kFifoDepth         : natural  := 1024;

      -- kDataWidth      : This is the sample size of the data going to the
      --                   user VI.
      kDataWidth         : positive := 32;

      -- kNumOfSamplesPerRead : Number of samples read from the FIFO at one
      --                        time.
      kNumOfSamplesPerRead : positive := 1;

      -- kBaseOffset     : This is the base offset for addressing the DMA
      --                   channel.
      kBaseOffset        : natural  := 0;

      -- kStreamNumber   : This is the stream number associated with the DMA
      --                   channel.
      kStreamNumber      : natural  := 0;

      -- kPeerToPeerStream : This indicates whether the output stream is a
      --                     normal host output stream or a peer-to-peer sink
      --                     stream.
      kPeerToPeerStream  : boolean := false;

      -- kFxpType        : This boolean indicates whether the data type is a
      --                   FXP type.
      kFxpType           : boolean  := false;

      -- kDisableOnFifoTimeout : This sets whether or not the stream disables
      --                         when an underflow occurs.
      kDisableOnFifoTimeout : boolean

    );
    port(

      -- The asynchronous reset for the bus / stream controller side.
      aReset : in boolean;

      -- Synchronous bus reset for the stream controller.
      bReset : in boolean;

      -- The asynchronous reset for the diagram / VI side.
      aDiagramReset : in boolean;

      -------------------------------------------------------------------------
      -- Clocks
      -------------------------------------------------------------------------

      BusClk : in std_logic;
      ViClk  : in std_logic;

      -------------------------------------------------------------------------
      -- NI DMA IP interface
      -------------------------------------------------------------------------

      bNiDmaOutputRequestToDma   : out NiDmaOutputRequestToDma_t;
      bNiDmaOutputRequestFromDma : in  NiDmaOutputRequestFromDma_t;
      bNiDmaOutputDataFromDma    : in  NiDmaOutputDataFromDma_t;

      -------------------------------------------------------------------------
      -- Arbiter signals
      -------------------------------------------------------------------------

      bArbiterNormalReq    : out std_logic;
      bArbiterEmergencyReq : out std_logic;
      bArbiterDone         : out std_logic;
      bArbiterGrant        : in  std_logic;

      -------------------------------------------------------------------------
      -- Register access signals
      -------------------------------------------------------------------------

      bRegPortIn  : in  RegPortIn_t;
      bRegPortOut : out RegPortOut_t;

      -------------------------------------------------------------------------
      -- User VI interface for reading
      -------------------------------------------------------------------------

      vDataOut       : out std_logic_vector(kDataWidth*kNumOfSamplesPerRead-1 downto 0);
      vEmpty         : out boolean;
      vReadFifo      : in  boolean;
      vCtCount       : out unsigned(31 downto 0);

      -- Handshaking signals
      vOutputValid     : out boolean;
      vReadyForOutput  : in  boolean;

      -------------------------------------------------------------------------
      -- User VI interface for stream state info and transitioning
      -------------------------------------------------------------------------

      vStreamStateOut             : out StreamStateValue_t;
      vStartStreamRequest         : in  boolean;
      vStopRequestStrobe          : in  boolean;

      -------------------------------------------------------------------------
      -- IRQ signals
      -------------------------------------------------------------------------

      bIrq : out IrqStatusToInterface_t

    );
end HdlSharedOutputWrapper;


architecture structure of HdlSharedOutputWrapper is

  signal bOutputStreamInterfaceFromFifo : OutputStreamInterfaceFromFifo_t;
  signal bOutputStreamInterfaceToFifo   : OutputStreamInterfaceToFifo_t;

  -- The DmaPortCommIfcOutputStream and HdlSharedOutputFifoInterface both
  -- express kFifoDepth in 64-bit bus-width words.  Convert from the
  -- user-visible sample depth to 64-bit-word depth for these components.
  constant kSampleSizeInt  : natural := ActualSampleSize(
    SampleSizeInBits => kDataWidth,
    PeerToPeer       => kPeerToPeerStream,
    FxpType          => kFxpType);
  constant kFifoDataWidthInt : natural := ActualFifoPortWidth(
    kSampleSizeInt * kNumOfSamplesPerRead);
  constant kFifoDepthIn64BitWords : natural :=
    (kFifoDepth + 1) * kSampleSizeInt / 64 - 1;

begin

  DmaPortCommIfcOutputStreamx: entity work.DmaPortCommIfcOutputStream (structure)
    generic map (
      kSampleWidth      => kDataWidth,
      kFifoDepth        => kFifoDepthIn64BitWords,
      kBaseOffset       => kBaseOffset,
      kStreamNumber     => kStreamNumber,
      kFxpType          => kFxpType)
    port map (
      aReset                          => aReset,
      bReset                          => bReset,
      BusClk                          => BusClk,
      bNiDmaOutputRequestToDma        => bNiDmaOutputRequestToDma,
      bNiDmaOutputRequestFromDma      => bNiDmaOutputRequestFromDma,
      bNiDmaOutputDataFromDma         => bNiDmaOutputDataFromDma,
      bArbiterNormalReq               => bArbiterNormalReq,
      bArbiterEmergencyReq            => bArbiterEmergencyReq,
      bArbiterDone                    => bArbiterDone,
      bArbiterGrant                   => bArbiterGrant,
      bRegPortIn                      => bRegPortIn,
      bRegPortOut                     => bRegPortOut,
      bOutputStreamInterfaceToFifo    => bOutputStreamInterfaceToFifo,
      bOutputStreamInterfaceFromFifo  => bOutputStreamInterfaceFromFifo,
      bIrq                            => bIrq);


  HdlSharedOutputFifoInterfacex: entity work.HdlSharedOutputFifoInterface (structure)
    generic map (
      kFifoDepth            => kFifoDepthIn64BitWords,
      kSampleWidth          => kDataWidth,
      kNumOfSamplesPerRead  => kNumOfSamplesPerRead,
      kFxpType              => kFxpType,
      kPeerToPeer           => kPeerToPeerStream,
      kDisableOnFifoTimeout => kDisableOnFifoTimeout)
    port map (
      aDiagramReset                  => aDiagramReset,
      aBusReset                      => aReset,
      BusClk                         => BusClk,
      bOutputStreamInterfaceToFifo   => bOutputStreamInterfaceToFifo,
      bOutputStreamInterfaceFromFifo => bOutputStreamInterfaceFromFifo,
      ViClk                          => ViClk,
      vDataOut                       => vDataOut,
      vEmpty                         => vEmpty,
      vReadFifo                      => vReadFifo,
      vCtCount                       => vCtCount,
      vOutputValid                   => vOutputValid,
      vReadyForOutput                => vReadyForOutput,
      vStreamStateOut                => vStreamStateOut,
      vStartStreamRequest            => vStartStreamRequest,
      vStopRequestStrobe             => vStopRequestStrobe);


end structure;
