-------------------------------------------------------------------------------
--
-- File: NiSharedFifoWriter.vhd
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--
--   User-facing DMA input (target-to-host) FIFO entity.
--
--   This is the top-level entity that users instantiate to write data from
--   FPGA logic into a DMA FIFO for transfer to the host.  Internally it
--   wraps NiSharedFifoWriterCore.
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

entity NiSharedFifoWriter is
    generic(

      -- kFifoDepth      : This is the size of the DMA FIFO in terms of bus
      --                   data width words.
      kFifoDepth         : natural  := 1024;

      -- kSampleWidth    : This is the width of one sample coming from the
      --                   user VI.
      kSampleWidth       : positive := 32;

      -- kNumOfSamplesPerWrite : Number of samples written to the FIFO at one
      --                        time.
      kNumOfSamplesPerWrite : positive := 1;

      -- kSignExtend     : This boolean controls whether or not to sign extend
      --                   the data before it is sent to the host.
      kSignExtend        : boolean := false;

      -- kFxpType        : This boolean indicates whether the data type is a
      --                   FXP type.
      kFxpType           : boolean  := false;

      -- kPeerToPeer     : This boolean indicates whether the stream is a
      --                   normal target to host stream or a peer-to-peer
      --                   source stream.
      kPeerToPeer        : boolean := false;

      -- kDisableOnFifoTimeout : This sets whether or not the stream disables
      --                         when an overflow/underflow occurs.
      kDisableOnFifoTimeout : boolean

    );
    port(

      -- The asynchronous reset for the stream circuit
      aDiagramReset : in boolean;

      aBusReset : in boolean;

      -- The IO Port 2 transmit clock
      BusClk : in std_logic;

      -------------------------------------------------------------------------
      -- Communication Interface interface
      -------------------------------------------------------------------------

      bInputStreamInterfaceToFifo   : in  InputStreamInterfaceToFifo_t;
      bInputStreamInterfaceFromFifo : out InputStreamInterfaceFromFifo_t;

      -------------------------------------------------------------------------
      -- User VI interface for writing
      -------------------------------------------------------------------------

      ViClk          : in std_logic;
      vDataIn        : in  std_logic_vector(kSampleWidth*kNumOfSamplesPerWrite-1 downto 0);
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
      vStopWithFlushRequestStrobe : in  boolean

    );
end NiSharedFifoWriter;


architecture structure of NiSharedFifoWriter is
begin

  NiSharedFifoWriterCorex: entity work.NiSharedFifoWriterCore (structure)
    generic map (
      kFifoDepth            => kFifoDepth,
      kSampleWidth          => kSampleWidth,
      kNumOfSamplesPerWrite => kNumOfSamplesPerWrite,
      kSignExtend           => kSignExtend,
      kFxpType              => kFxpType,
      kPeerToPeer           => kPeerToPeer,
      kDisableOnFifoTimeout => kDisableOnFifoTimeout)
    port map (
      aDiagramReset                 => aDiagramReset,
      aBusReset                     => aBusReset,
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
