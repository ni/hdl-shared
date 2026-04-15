-------------------------------------------------------------------------------
--
-- File: DmaPortCommIfcInputWrapper.vhd
-- Author: Matthew Koenn
-- Original Project: LabVIEW FPGA
-- Date: 7 July 2008
--
-------------------------------------------------------------------------------
-- (c) 2008 Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--
--   This block implements an entire LvFpga input DMA channel.  It wraps up the
-- controller portion of the DMA channel in the top level communication 
-- interface with the FIFO portion of the channel located within TheWindow.
-- This is used primarily for testing purposes so that the DMA channel as 
-- a whole can be tested without having the instantiate both individual
-- components.
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  
library work;
  use work.PkgNiUtilities.all;

  -- This package contains the definitions for the LabVIEW FPGA register 
  -- framework signals 
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;
  
  -- This package contains the information for the max packet size for the
  -- Ni Dma implementation
  use work.PkgNiDmaConfig.all;
  
  -- This package contains some useful functions for determining the width of
  -- the empty count from the data packing FIFO.
  use work.PkgDmaPortDataPackingFifo.all; 
  
  -- The pkg containing the definitions for the FIFO interface signals.
  use work.PkgDmaPortDmaFifos.all;
  
  -- The pkg containing stream state definitions.
  use work.PkgDmaPortCommIfcStreamStates.all;

  -- This package contains the definitions for the interface between the NI DMA IP and
  -- the application specific logic
  use work.PkgNiDma.all;

entity DmaPortCommIfcInputWrapper is
    generic(

      
      -- kFifoDepth      : This is the size of the DMA FIFO in 64 bit words.
      kFifoDepth         : natural  := 1024;
      
      -- kDataWidth      : This is the sample size of the data coming from the
      --                   user VI.  This is used to set the FIFO data width
      --                   and the data width of corresponding signals.
      kDataWidth         : positive := 32;
      
      -- kBaseOffset     : This is the base offset for addressing the DMA
      --                   channel.  The full address for the DMA channel is
      --                   CHInChBaseAddress + LvFpgaWindowBaseOffset +
      --                   DMAChannelBaseOffset.
      kBaseOffset        : natural  := 0;
      
      kScl               : boolean := false;
      
      -- kCountScl       : This boolean controls whether or not the query FIFO
      --                   count method is in a single cycle loop.
      kCountScl          : boolean  := false;
      
      kSignExtend        : boolean := false;
      
      -- kStreamNumber   : This is the stream number associated with the DMA
      --                   channel.
      kStreamNumber      : natural  := 0;
      
      -- kEvictionTimeout: This is the number of BusClk cycles to wait before
      --                   asserting an emergency transmission request to the
      --                   arbiter.
      kEvictionTimeout   : natural  := 0;
      
      -- kPeerToPeerStream : This indicates whether the input stream is a normal
      --                     host input stream or a peer-to-peer source stream.
      kPeerToPeerStream    : boolean := false;
      
      -- kFxpType          : This boolean indicates whether the data type is a 
      --                     FXP type.
      kFxpType             : boolean  := false;
      
      -- kDisableOnFifoTimeout  : This sets whether or not the stream disables when an
      --                          overflow/underflow occurs.
      kDisableOnFifoTimeout     : boolean;
      
      -- kViClkIsDefaultClk     : This bit is set when the DMA clock (or VI clock) is
      --                          the same clock as the default clock.
      kViClkIsDefaultClk       : boolean
      
    );
    port(

      -- The asynchronous reset for the stream circuit
      aReset : in boolean;
      
      -- This is a synchronous reset for the stream circuit.
      bReset : in boolean;
      
      -------------------------------------------------------------------------
      -- Clocks
      -------------------------------------------------------------------------
      
      -- The IO Port 2 transmit clock
      BusClk : in std_logic;
      
      -- The user VI clock to which writes are synchronous.
      ViClk  : in std_logic;
      
      -- The top level clock to which the state transitions and stream state 
      -- info is synchronous to.
      DefaultClk : in std_logic;
    
      -------------------------------------------------------------------------
      -- NI DMA IP interface
      -------------------------------------------------------------------------

      -- The DMA IN send request access to the DMA channel. This bus carry the
      -- information details about the requested transaction.
      bNiDmaInputRequestToDma : out NiDmaInputRequestToDma_t;

      -- The Acknowledge from the NI DMA IP indicating that the request was received.
      bNiDmaInputRequestFromDma : in NiDmaInputRequestFromDma_t;

      bNiDmaInputDataToDma : out NiDmaInputDataToDma_t;
      bNiDmaInputDataFromDma : in NiDmaInputDataFromDma_t;

      bNiDmaInputStatusFromDma: in NiDmaInputStatusFromDma_t;

      -------------------------------------------------------------------------
      -- Arbiter signals
      -------------------------------------------------------------------------
      
      -- bArbiterNormalReq   : This is the signal to the arbiter indicating 
      --                       that normal access is requested to the IOPort2.
      bArbiterNormalReq      : out std_logic;
      
      -- bArbiterEmergencyReq: This is the signal to the arbiter indicating 
      --                       that emergency access is requested to the 
      --                       IOPort2.
      bArbiterEmergencyReq   : out std_logic;
      
      -- bArbiterDone        : This is the signal to the arbiter indicating
      --                       that the current access to IOPort2 has completed
      --                       on this clock cycle.  This is a strobe bit.
      bArbiterDone           : out boolean;
      
      -- bArbiterGrant       : This is the signal from the arbiter indicating
      --                       the DMA channel has access to IOPort2.  This
      --                       stays asserted while the channel has access.
      bArbiterGrant          : in  std_logic;
      
      -------------------------------------------------------------------------
      -- Register access signals from register access component
      -------------------------------------------------------------------------
      
      -- bRegPortIn          : These are the register access signals coming 
      --                       from the register access component to issue
      --                       read and write requests.
      bRegPortIn             : in  RegPortIn_t;
      
      -- bRegPortOut         : These are the register access signals going back
      --                       to the register access component to provide
      --                       write responses.
      bRegPortOut            : out RegPortOut_t;
      
      -------------------------------------------------------------------------
      -- User VI interface
      -------------------------------------------------------------------------
      
      -- vDataIn             : The data coming from the user VI to push into 
      --                       the FIFO.
      vDataIn                : in  std_logic_vector(kDataWidth-1 downto 0);
      
      -- vFull               : This indicates to the user VI when the FIFO is
      --                       full.
      vFull                  : out std_logic;
      
      -- vTimeout            : This is the number of ViClk cycles to wait to
      --                       push data into the FIFO in the case that the
      --                       FIFO is full.  If the timeout is reached before
      --                       there is space available in the FIFO, the user
      --                       VI receives the EnableOut signal, but the data
      --                       has not been pushed.  
      vTimeout               : in  std_logic_vector(31 downto 0);
      
      -- vEnableIn           : This is the signal from the user VI indicating
      --                       that he wishes to perform a push.
      vEnableIn              : in  std_logic;
      
      -- vEnableOut          : This is the signal to the user VI indicating 
      --                       that the push has occurred or timeout has
      --                       occurred.  This stays asserted until the VI
      --                       asserts EnableClear.
      vEnableOut             : out std_logic;
      
      -- vEnableClear        : This is the signal from the user VI to clear the
      --                       EnableOut signal and indicate that EnableIn
      --                       should be re-processed.
      vEnableClear           : in  std_logic;      
      
      -- vCtCount            : The current FIFO empty count in the ViClk domain.
      vCtCount               : out unsigned(31 downto 0);
      
      -- Enable chain for the empty count.
      vCtEnableIn            : in  std_logic;
      vCtEnableOut           : out std_logic;
      vCtEnableOutClear      : in  std_logic;
      
      
      -------------------------------------------------------------------------
      -- User VI interface for stream state info and transitioning
      -------------------------------------------------------------------------
      
      -- The enable chain for the stream state in the VI clock domain.
      vStreamStateEnableIn : in std_logic;
      vStreamStateEnableOut : out std_logic;
      vStreamStateEnableClear : in std_logic;
      vStreamStateOut : out StreamStateValue_t;
      
      -- The enable chain for the stream state in the default clock domain.
      dStreamStateEnableIn : in std_logic;
      dStreamStateEnableOut : out std_logic;
      dStreamStateEnableClear : in std_logic;
      dStreamStateOut : out StreamStateValue_t;
      
      -- The enable chain for the start request.
      dStartRequestEnableIn : in std_logic;
      dStartRequestEnableOut : out std_logic;
      dStartRequestEnableClear : in std_logic;
      
      -- The enable chain for the stop request.
      dStopRequestEnableIn : in std_logic;
      dStopRequestEnableOut : out std_logic;
      dStopRequestEnableClear : in std_logic;
      
      -- The enable chain for the stop with flush request.
      dStopWithFlushRequestEnableIn : in std_logic;
      dStopWithFlushRequestEnableOut : out std_logic;
      dStopWithFlushRequestEnableClear : in std_logic;
      dStopWithFlushRequestTimedOut : out std_logic;
      dStopWithFlushRequestTimeout : in signed(31 downto 0);
      
      dCurrentStreamState : out StreamStateValue_t;
      
      -------------------------------------------------------------------------
      -- IRQ signals
      -------------------------------------------------------------------------
      
      -- The IRQ output to the communication interface.
      bIrq : out IrqStatusToInterface_t
      
    );
end DmaPortCommIfcInputWrapper;


architecture structure of DmaPortCommIfcInputWrapper is

  --vhook_sigstart
  signal bArbiterDoneStdLogic: std_logic;
  signal bInputStreamInterfaceFromFifo: InputStreamInterfaceFromFifo_t;
  signal bInputStreamInterfaceToFifo: InputStreamInterfaceToFifo_t;
  --vhook_sigend

begin
  
  bArbiterDone <= to_Boolean(bArbiterDoneStdLogic);

  --vhook_e DmaPortCommIfcInputStream
  --vhook_a kSampleWidth kDataWidth
  --vhook_a bInputDataInterfaceFromFifo bNiDmaInputDataToDma
  --vhook_a binputDataInterfaceToFifo bNiDmaInputDataFromDma
  --vhook_a bArbiterDone bArbiterDoneStdLogic
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
      bArbiterDone                  => bArbiterDoneStdLogic,
      bArbiterGrant                 => bArbiterGrant,
      bRegPortIn                    => bRegPortIn,
      bRegPortOut                   => bRegPortOut,
      bInputStreamInterfaceToFifo   => bInputStreamInterfaceToFifo,
      bInputStreamInterfaceFromFifo => bInputStreamInterfaceFromFifo,
      bIrq                          => bIrq);

      
  --vhook_e DmaPortCommIfcInputFifoInterface
  --vhook_a kSampleWidth kDataWidth
  --vhook_a kPeerToPeer kPeerToPeerStream
  --vhook_a kNumOfSamplesPerWrite 1
  --vhook_a kWriteUsingHandshaking false
  --vhook_a vReadyForInput open
  --vhook_a vFlushEnableOut open
  --vhook_a vFlushEnableClear '0'
  --vhook_a vFlushEnableIn '0'
  --vhook_a aBusReset aReset
  --vhook_a vInputValid '0'
  --vhook_a aDiagramReset false
  DmaPortCommIfcInputFifoInterfacex: entity work.DmaPortCommIfcInputFifoInterface (structure)
    generic map (
      kFifoDepth             => kFifoDepth,
      kSampleWidth           => kDataWidth,
      kNumOfSamplesPerWrite  => 1,
      kScl                   => kScl,
      kCountScl              => kCountScl,
      kSignExtend            => kSignExtend,
      kFxpType               => kFxpType,
      kPeerToPeer            => kPeerToPeerStream,
      kDisableOnFifoTimeout  => kDisableOnFifoTimeout,
      kViClkIsDefaultClk     => kViClkIsDefaultClk,
      kWriteUsingHandshaking => false)
    port map (
      aDiagramReset                    => false,
      aBusReset                        => aReset,
      BusClk                           => BusClk,
      bInputStreamInterfaceToFifo      => bInputStreamInterfaceToFifo,
      bInputStreamInterfaceFromFifo    => bInputStreamInterfaceFromFifo,
      ViClk                            => ViClk,
      vDataIn                          => vDataIn,
      vFull                            => vFull,
      vTimeout                         => vTimeout,
      vEnableIn                        => vEnableIn,
      vEnableOut                       => vEnableOut,
      vEnableClear                     => vEnableClear,
      vFlushEnableIn                   => '0',
      vFlushEnableOut                  => open,
      vFlushEnableClear                => '0',
      vCtCount                         => vCtCount,
      vCtEnableIn                      => vCtEnableIn,
      vCtEnableOut                     => vCtEnableOut,
      vCtEnableOutClear                => vCtEnableOutClear,
      vInputValid                      => '0',
      vReadyForInput                   => open,
      DefaultClk                       => DefaultClk,
      vStreamStateEnableIn             => vStreamStateEnableIn,
      vStreamStateEnableOut            => vStreamStateEnableOut,
      vStreamStateEnableClear          => vStreamStateEnableClear,
      vStreamStateOut                  => vStreamStateOut,
      dStreamStateEnableIn             => dStreamStateEnableIn,
      dStreamStateEnableOut            => dStreamStateEnableOut,
      dStreamStateEnableClear          => dStreamStateEnableClear,
      dStreamStateOut                  => dStreamStateOut,
      dCurrentStreamState              => dCurrentStreamState,
      dStartRequestEnableIn            => dStartRequestEnableIn,
      dStartRequestEnableOut           => dStartRequestEnableOut,
      dStartRequestEnableClear         => dStartRequestEnableClear,
      dStopRequestEnableIn             => dStopRequestEnableIn,
      dStopRequestEnableOut            => dStopRequestEnableOut,
      dStopRequestEnableClear          => dStopRequestEnableClear,
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableIn,
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOut,
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClear,
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeout,
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOut);


end structure; 
      
