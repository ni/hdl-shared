-------------------------------------------------------------------------------
--
-- File: NiSharedFifoWriterTbWrapper.vhd
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
--   This block wraps the DMA input stream controller (DmaPortCommIfcInputStream)
--   together with the simplified FIFO interface (NiSharedFifoWriterCore).
--   Enable chains have been removed; the user-facing signals (write, flush,
--   stream state queries, and state transition requests) are exposed directly.
--
--   Based on DmaPortCommIfcInputWrapper.
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

  use work.PkgCommIntConfiguration.kInputMaxTransfer;

entity NiSharedFifoWriterTbWrapper is
    generic(

      -- kFifoDepth      : This is the size of the DMA FIFO in terms of bus
      --                   data width words.
      kFifoDepth         : natural  := 1024;

      -- kDataWidth      : This is the sample size of the data coming from the
      --                   user VI.
      kDataWidth         : positive := 32;

      -- kNumOfSamplesPerWrite : Number of samples written to the FIFO at one
      --                        time.
      kNumOfSamplesPerWrite : positive := 1;

      -- kBaseOffset     : This is the base offset for addressing the DMA
      --                   channel.
      kBaseOffset        : natural  := 0;

      -- kStreamNumber   : This is the stream number associated with the DMA
      --                   channel.
      kStreamNumber      : natural  := 0;

      -- kEvictionTimeout: This is the number of BusClk cycles to wait before
      --                   asserting an emergency transmission request to the
      --                   arbiter.
      kEvictionTimeout   : natural  := 0;

      -- kPeerToPeerStream : This indicates whether the input stream is a
      --                     normal host input stream or a peer-to-peer source
      --                     stream.
      kPeerToPeerStream  : boolean := false;

      -- kFxpType        : This boolean indicates whether the data type is a
      --                   FXP type.
      kFxpType           : boolean  := false;

      -- kSignExtend     : This boolean controls whether or not to sign extend
      --                   the data before it is sent to the host.
      kSignExtend        : boolean := false;

      -- kDisableOnFifoTimeout : This sets whether or not the stream disables
      --                         when an overflow/underflow occurs.
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

      bNiDmaInputRequestToDma   : out NiDmaInputRequestToDma_t;
      bNiDmaInputRequestFromDma : in  NiDmaInputRequestFromDma_t;
      bNiDmaInputDataToDma      : out NiDmaInputDataToDma_t;
      bNiDmaInputDataFromDma    : in  NiDmaInputDataFromDma_t;
      bNiDmaInputStatusFromDma  : in  NiDmaInputStatusFromDma_t;

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
      -- User VI interface for writing
      -------------------------------------------------------------------------

      vDataIn        : in  std_logic_vector(kDataWidth*kNumOfSamplesPerWrite-1 downto 0);
      vFull          : out boolean;
      vWriteFifo     : in  boolean;
      vFlush         : in  boolean;
      vCtCount       : out unsigned(31 downto 0);

      -- Handshaking signals
      vInputValid    : in  boolean;
      vReadyForInput : out boolean;

      -------------------------------------------------------------------------
      -- User VI interface for stream state info and transitioning
      -------------------------------------------------------------------------

      vStreamStateOut             : out StreamStateValue_t;
      vStartStreamRequest         : in  boolean;
      vStopRequestStrobe          : in  boolean;
      vFlushTimeoutRequest        : in  boolean;
      vStopWithFlushRequestStrobe : in  boolean;

      -------------------------------------------------------------------------
      -- IRQ signals
      -------------------------------------------------------------------------

      bIrq : out IrqStatusToInterface_t

    );
end NiSharedFifoWriterTbWrapper;


architecture structure of NiSharedFifoWriterTbWrapper is

  signal bInputStreamInterfaceFromFifo : InputStreamInterfaceFromFifo_t;
  signal bInputStreamInterfaceToFifo   : InputStreamInterfaceToFifo_t;

begin

  DmaPortCommIfcInputStreamx: entity work.DmaPortCommIfcInputStream (structure)
    generic map (
      kFifoDepth        => kFifoDepth,
      kSampleWidth      => kDataWidth,
      kBaseOffset       => kBaseOffset,
      kStreamNumber     => kStreamNumber,
      kEvictionTimeout  => kEvictionTimeout,
      kPeerToPeerStream => kPeerToPeerStream,
      kFxpType          => kFxpType)
    port map (
      aReset                        => aReset,
      bReset                        => bReset,
      BusClk                        => BusClk,
      bNiDmaInputRequestToDma       => bNiDmaInputRequestToDma,
      bNiDmaInputRequestFromDma     => bNiDmaInputRequestFromDma,
      bNiDmaInputStatusFromDma      => bNiDmaInputStatusFromDma,
      bInputDataInterfaceFromFifo   => bNiDmaInputDataToDma,
      bInputDataInterfaceToFifo     => bNiDmaInputDataFromDma,
      bArbiterNormalReq             => bArbiterNormalReq,
      bArbiterEmergencyReq          => bArbiterEmergencyReq,
      bArbiterDone                  => bArbiterDone,
      bArbiterGrant                 => bArbiterGrant,
      bRegPortIn                    => bRegPortIn,
      bRegPortOut                   => bRegPortOut,
      bInputStreamInterfaceToFifo   => bInputStreamInterfaceToFifo,
      bInputStreamInterfaceFromFifo => bInputStreamInterfaceFromFifo,
      bIrq                          => bIrq);


  NiSharedFifoWriterx: entity work.NiSharedFifoWriter (structure)
    generic map (
      kFifoDepth            => kFifoDepth,
      kSampleWidth          => kDataWidth,
      kNumOfSamplesPerWrite => kNumOfSamplesPerWrite,
      kSignExtend           => kSignExtend,
      kFxpType              => kFxpType,
      kPeerToPeer           => kPeerToPeerStream,
      kDisableOnFifoTimeout => kDisableOnFifoTimeout)
    port map (
      aDiagramReset                 => aDiagramReset,
      aBusReset                     => aReset,
      BusClk                        => BusClk,
      bInputStreamInterfaceToFifo   => bInputStreamInterfaceToFifo,
      bInputStreamInterfaceFromFifo => bInputStreamInterfaceFromFifo,
      ViClk                         => ViClk,
      vDataIn                       => vDataIn,
      vFull                         => vFull,
      vWriteFifo                    => vWriteFifo,
      vFlush                        => vFlush,
      vCtCount                      => vCtCount,
      vInputValid                   => vInputValid,
      vReadyForInput                => vReadyForInput,
      vStreamStateOut               => vStreamStateOut,
      vStartStreamRequest           => vStartStreamRequest,
      vStopRequestStrobe            => vStopRequestStrobe,
      vFlushTimeoutRequest          => vFlushTimeoutRequest,
      vStopWithFlushRequestStrobe   => vStopWithFlushRequestStrobe);


end structure;
