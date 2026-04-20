-------------------------------------------------------------------------------
--
-- File: NiFifoReader.vhd
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--
--   User-facing DMA output (host-to-target) FIFO entity.
--
--   This is the top-level entity that users instantiate to read data from
--   a DMA FIFO sent by the host.  Internally it wraps NiFifoReaderCore.
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

entity NiFifoReader is
    generic(

      -- kFifoDepth      : This is the size of the DMA FIFO in bus data width
      --                   words.
      kFifoDepth         : natural  := 1024;

      -- kSampleWidth    : This is the sample size of the data going to the
      --                   user VI.
      kSampleWidth       : positive := 32;

      -- kNumOfSamplesPerRead : Number of samples read from the FIFO at one
      --                        time.
      kNumOfSamplesPerRead : positive := 1;

      -- kFxpType        : This boolean indicates whether the data type is a
      --                   FXP type.
      kFxpType           : boolean  := false;

      -- kPeerToPeer     : This boolean indicates whether the stream is a
      --                   normal host to target stream or a peer-to-peer sink
      --                   stream.
      kPeerToPeer        : boolean := false;

      -- kDisableOnFifoTimeout : This sets whether or not the stream disables
      --                         when an underflow occurs.
      kDisableOnFifoTimeout : boolean

    );
    port(

      -- The asynchronous reset for the stream circuit
      aDiagramReset : in boolean;

      aBusReset : in boolean;

      -------------------------------------------------------------------------
      -- Clocks
      -------------------------------------------------------------------------

      BusClk : in std_logic;

      -------------------------------------------------------------------------
      -- Communication Interface interface
      -------------------------------------------------------------------------

      bOutputStreamInterfaceToFifo   : in  OutputStreamInterfaceToFifo_t;
      bOutputStreamInterfaceFromFifo : out OutputStreamInterfaceFromFifo_t;

      -------------------------------------------------------------------------
      -- User VI interface for reading
      -------------------------------------------------------------------------

      ViClk          : in std_logic;
      vDataOut       : out std_logic_vector(kSampleWidth*kNumOfSamplesPerRead-1 downto 0);
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
      vStopRequestStrobe          : in  boolean

    );
end NiFifoReader;


architecture structure of NiFifoReader is
begin

  NiFifoReaderCorex: entity work.NiFifoReaderCore (structure)
    generic map (
      kFifoDepth            => kFifoDepth,
      kSampleWidth          => kSampleWidth,
      kNumOfSamplesPerRead  => kNumOfSamplesPerRead,
      kFxpType              => kFxpType,
      kPeerToPeer           => kPeerToPeer,
      kDisableOnFifoTimeout => kDisableOnFifoTimeout)
    port map (
      aDiagramReset                  => aDiagramReset,
      aBusReset                      => aBusReset,
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
