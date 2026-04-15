-------------------------------------------------------------------------------
--
-- File: HdlSharedInputFifoInterface.vhd
-- Author: Matthew Koenn
-- Original Project: LabVIEW FPGA
-- Date: 11 June 2008
--
-------------------------------------------------------------------------------
-- (c) 2008 Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--
-- This file implements the input DMA FIFO that connects to the Chinch LvFpga
-- interface.  The module consists of an input FIFO, stream state management,
-- and some interconnect between them.
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgNiUtilities.all;

  -- The pkg that specifies several signals used by the user VI and register
  -- framework.
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;

  -- The pkg containing the definitions for the FIFO interface signals.
  use work.PkgDmaPortDmaFifos.all;

  -- Contains functions for determining depths of data packing FIFOs.
  use work.PkgDmaPortDataPackingFifo.all;

  -- Contains stream state definitions.
  use work.PkgDmaPortCommIfcStreamStates.all;

  -- This package contains the definitions for the interface between the NI DMA IP and
  -- the application specific logic.
  use work.PkgNiDma.all;


entity HdlSharedInputFifoInterface is
    generic(

      -- kFifoDepth      : This is the size of the DMA FIFO in terms of bus data width
      --                   words.
      kFifoDepth         : natural  := 1024;

      -- kSampleWidth     : This is the width of one sample coming from the user VI.
      kSampleWidth        : positive := 32;

      -- kNumOfSamplesPerWrite : This the number of samples that are written in the FIFO
      --                    at one time;
      kNumOfSamplesPerWrite    : positive := 1;

      -- kSignExtend     : This boolean controls whether or not to sign extend
      --                   the data before it is sent to the host.  This is
      --                   used if the data type is a fixed-point number, and
      --                   the generic is set dynamically by LabVIEW.
      kSignExtend        : boolean  := false;

      -- kFxpType        : This boolean indicates whether the data type is a
      --                   FXP type.
      kFxpType           : boolean  := false;

      -- kPeerToPeer     : This boolean indicates whether the stream is a normal
      --                   target to host stream or a peer-to-peer source stream.
      kPeerToPeer        : boolean  := false;

      -- kDisableOnFifoTimeout  : This sets whether or not the stream disables when an
      --                          overflow/underflow occurs.
      kDisableOnFifoTimeout     : boolean

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

      -- The signals going from the top level communication interface to the
      -- FIFO.
      bInputStreamInterfaceToFifo : in InputStreamInterfaceToFifo_t;

      -- The signals going from the FIFO to the top level communication
      -- interface.
      bInputStreamInterfaceFromFifo : out InputStreamInterfaceFromFifo_t;
      -------------------------------------------------------------------------
      -- User VI interface for writing
      -------------------------------------------------------------------------

      -- DefaultClk       : The user HDL clock for writing
      DefaultClk          : in std_logic;

      -- dDataIn     : The data coming from the user VI to push into the FIFO.
      dDataIn        : in std_logic_vector(kSampleWidth*kNumOfSamplesPerWrite-1 downto 0);

      -- dFull       : This indicates to the user VI when the FIFO is full.
      dFull          : out boolean;

      -- Write strobe 
      dWriteFifo     : in  boolean;

      -- Flush strobe
      dFlush         : in  boolean;

      -- dCtCount     : The current FIFO empty count in the DefaultClk domain.
      dCtCount        : out unsigned(31 downto 0);

      -- Handshaking signals
      dInputValid            : in  boolean;
      dReadyForInput         : out boolean;

      -------------------------------------------------------------------------
      -- User VI interface for stream state info and transitioning
      -------------------------------------------------------------------------

      -- Stream state in the VI clock domain.
      dStreamStateOut : out StreamStateValue_t;

      -- State transition request signals 
      dStartRequest                 : in  boolean;
      dStopRequest                  : in  boolean;
      dFlushTimeoutRequest          : in  boolean;
      dStopWithFlushRequest         : in  boolean

    );
end HdlSharedInputFifoInterface;


architecture structure of HdlSharedInputFifoInterface is

  -- The constant represents the sample width rounded up to the closer standard data type.
  constant kSampleSize : integer := ActualSampleSize (SampleSizeInBits => kSampleWidth,
                                                      PeerToPeer => kPeerToPeer,
                                                      FxpType => kFxpType);

  -- The address width represents the number of bits nedeed to represent the FIFO's depth
  -- in terms of data bus width words.
  constant kAddressWidth : integer := Log2(kFifoDepth);

  -- This is the width of the data written in the FIFO on the VI side;
  constant kWrPortWidth : integer := kSampleSize*kNumOfSamplesPerWrite;

  constant kDataZero : std_logic_vector(kWrPortWidth-1 downto 0) := (others=>'0');

  -- The count width, which is the address width with the sample size taken into account.
  constant kFifoCountWidth : integer := FifoCountWidth(SampleSize => kSampleSize,
                                                       AddressWidth => kAddressWidth);


  signal dFullFromFifo: boolean;
  signal dEmptyCount, dEmptyCountLoc: unsigned(kFifoCountWidth-1 downto 0);
  signal bFifoFullCount: unsigned(kFifoCountWidth-1 downto 0);
  signal bStreamState : StreamStateValue_t;
  signal dFifoOverflow : std_logic;
  signal dFifoOverflowFlag : std_logic;
  signal bStateInDefaultClkDomain : StreamStateValue_t;
  signal dWritesDisabled, dWritesDisabledForController : boolean;
  signal bWritesDisabled : boolean;
  signal bTransferEnd: boolean;
  signal bPop, bPopFifo: boolean;
  signal bByteEnableDirect: NiDmaByteEnable_t;
  signal dCombinedStopRequest : boolean;

  signal bByteCount: NiDmaBusByteCount_t;
  signal bByteLanePtr: NiDmaByteLane_t;
  signal bDmaReset: boolean;
  signal bFifoDataOut: NiDmaData_t;
  signal bFifoOverflow: boolean;
  signal bNumReadSamples: unsigned(kFifoCountWidth-1 downto 0);
  signal bOverflowStopRequest: boolean;
  signal bResetDone: boolean;
  signal bResetForFifo: boolean;
  signal bRsrvReadSpaces: boolean;
  signal bStartStreamRequest: boolean;
  signal bFlushTimeoutRequest: boolean;
  signal bStopStreamRequestFromDiagram: boolean;
  signal bStopStreamWithFlushRequest: boolean;
  signal bWriteDetected: boolean;
  signal dPushStateToBusClkDomain: boolean;
  signal dDisable: boolean;
  signal dFifoDataIn: std_logic_vector(kWrPortWidth-1 downto 0);
  signal dOverflowStopRequest: boolean;
  signal dPush: boolean;
  signal dPushPop: boolean;
  signal dResetForFifo: boolean;
  signal dStateDisable: boolean;
  signal dStreamStateValueFromControllerEarly: std_logic_vector(bStreamState'length-1 downto 0);
  
  signal dStreamStateValueFromController: std_logic_vector(bStreamState'length-1 downto 0);
  signal dStreamStateValueFromControllerDly: std_logic_vector(bStreamState'length-1 downto 0) := to_StreamStateValue(Unlinked);
  signal dDisableEarly : boolean;
  
  signal dAlmostFull        : boolean;
  signal dInputValidQual    : boolean;
  signal dReadyForInputBool : boolean;
  signal dReadyForInputReg  : boolean := true;
  
  
  signal bFlushReqFifo : std_logic;


begin

  bDmaReset <= bInputStreamInterfaceToFifo.DmaReset;
  bPop <= bInputStreamInterfaceToFifo.Pop;
  bTransferEnd <= bInputStreamInterfaceToFifo.TransferEnd;
  bByteEnableDirect <= bInputStreamInterfaceToFifo.ByteEnable;
  bNumReadSamples <= resize(bInputStreamInterfaceToFifo.NumReadSamples,
                     bNumReadSamples'length);
  bRsrvReadSpaces <= bInputStreamInterfaceToFifo.RsrvReadSpaces;
  bStreamState <= bInputStreamInterfaceToFifo.StreamState;
  bByteCount <= bInputStreamInterfaceToFifo.ByteCount;

  bInputStreamInterfaceFromFifo.ByteLanePtr <= bByteLanePtr;
  bInputStreamInterfaceFromFifo.ResetDone <= bResetDone;
  bInputStreamInterfaceFromFifo.FifoDataOut <= bFifoDataOut;
  bInputStreamInterfaceFromFifo.FifoFullCount <= resize(bFifoFullCount,
    bInputStreamInterfaceFromFifo.FifoFullCount'length);
  bInputStreamInterfaceFromFifo.FifoOverflow <= bFifoOverflow;
  bInputStreamInterfaceFromFifo.StartStreamRequest <= bStartStreamRequest;
  bInputStreamInterfaceFromFifo.StopStreamRequest <= bStopStreamRequestFromDiagram or
    bFlushTimeoutRequest;
  bInputStreamInterfaceFromFifo.StopStreamWithFlushRequest <=
    bStopStreamWithFlushRequest or bOverflowStopRequest;
  bInputStreamInterfaceFromFifo.FlushRequest <= to_Boolean(bFlushReqFifo);
  bInputStreamInterfaceFromFifo.WritesDisabled <= bWritesDisabled;
  bInputStreamInterfaceFromFifo.WriteDetected <= bWriteDetected;
  bInputStreamInterfaceFromFifo.StateInDefaultClkDomain <= bStateInDefaultClkDomain;
  
  bPopFifo <= bPop and ((not bTransferEnd) or bByteEnableDirect(bByteEnableDirect'left));

  DmaPortCommIfcComponentEnableChainx: entity work.DmaPortCommIfcComponentEnableChain (rtl)
  generic map (
    kInput       => true,                    -- in  boolean := true
    kSCL         => true,                    -- in  boolean := false
    kDataWidth   => kWrPortWidth,            -- in  natural := 32
    kHandshaking => true)                    -- in  boolean := false
  port map (
    aReset                     => aDiagramReset,               -- in  boolean
    PClk                       => DefaultClk,                       -- in  std_logic
    BusClk                     => BusClk,                      -- in  std_logic
    pEnableIn                  => dWriteFifo,                  -- in  boolean
    pEnableOut                 => open,                        -- out boolean
    pEnableClear               => false,                       -- in  boolean
    pHandshakingPushPopRequest => dInputValidQual,             -- in  boolean
    pPushPop                   => dPushPop,                    -- out boolean
    pDisable                   => dDisable,                    -- out boolean
    pResetForFifo              => dResetForFifo,               -- out boolean
    bResetForFifo              => bResetForFifo,               -- out boolean
    bResetBitFromRegister      => bDmaReset,                   -- in  boolean
    bResetDone                 => bResetDone,                  -- out boolean
    pStateDisable              => dStateDisable,               -- in  boolean
    pTimeout                   => (others => '0'),             -- in  std_logic_vector(
    pDataOut                   => open,                        -- out std_logic_vector(
    pFlag                      => dFifoOverflowFlag,           -- out std_logic
    pDataOutFromFifo           => kDataZero,                   -- in  std_logic_vector(
    pFlagFromFifo              => to_StdLogic(dFullFromFifo)); -- in  std_logic


  -- Each sample in the dDataIn needs to be resized to actual sample size.
  -- Swap the samples order in a write data port for the multi element write case.
  DataInResize: process (dDataIn)
  begin
    for i in 0 to kNumOfSamplesPerWrite-1 loop
      if kSignExtend then
        dFifoDataIn((kNumOfSamplesPerWrite-i)*kSampleSize-1 downto
        (kNumOfSamplesPerWrite-i-1)*kSampleSize) <= std_logic_vector(resize(
            signed(dDataIn((i+1)*kSampleWidth-1 downto i*kSampleWidth)), kSampleSize));
      else
        dFifoDataIn((kNumOfSamplesPerWrite-i)*kSampleSize-1 downto
        (kNumOfSamplesPerWrite-i-1)*kSampleSize) <= std_logic_vector(resize(
            unsigned(dDataIn((i+1)*kSampleWidth-1 downto i*kSampleWidth)), kSampleSize));
      end if;
    end loop;
  end process;
  

  DmaPortInStrmFifox: entity work.DmaPortInStrmFifo (rtl)
    generic map (
      kAddressWidth             => kAddressWidth,                  -- in  natural := 8
      kSampleSize               => kSampleSize,                    -- in  natural := 8
      kWrPortWidth              => kWrPortWidth,                   -- in  natural := 8
      kNumOfSamplesPerWrite     => kNumOfSamplesPerWrite,          -- in  positive := 1
      kFifoCountWidth           => kFifoCountWidth,                -- in  natural
      kDataTypeIsSigned         => kSignExtend,                    -- in  boolean := fals
      kCorrelatedDataWidth      => bStreamState'length,            -- in  integer := 0
      kCorrelatedDataResetValue => to_StreamStateValue(Unlinked))  -- in  std_logic_vecto
    port map (
      aReset             => aDiagramReset,                         -- in  boolean
      IClk               => DefaultClk,                                 -- in  std_logic
      iReset             => dResetForFifo,                         -- in  boolean
      iWrite             => dPush,                                 -- in  boolean
      iFlush             => dFlush,                                -- in  boolean
      iDataIn            => dFifoDataIn,                           -- in  std_logic_vecto
      iEmptyCount        => dEmptyCountLoc,                        -- out unsigned(kFifoC
      iWritesDisabled    => dWritesDisabledForController,          -- in  boolean
      iCorrelatedDataOut => dStreamStateValueFromControllerEarly,  -- out std_logic_vecto
      OClk               => BusClk,                                -- in  std_logic
      oReset             => bResetForFifo,                         -- in  boolean
      oRead              => bPopFifo,                              -- in  boolean
      oPop               => bPop,                                  -- in  boolean
      oByteCount         => bByteCount,                            -- in  NiDmaBusByteCou
      oByteLanePtr       => bByteLanePtr,                          -- out NiDmaByteLane_t
      oNumReadSamples    => bNumReadSamples,                       -- in  unsigned(kFifoC
      oRsrvReadSpaces    => bRsrvReadSpaces,                       -- in  boolean
      oDataOut           => bFifoDataOut,                          -- out NiDmaData_t
      oFullCount         => bFifoFullCount,                        -- out unsigned(kFifoC
      oWritesDisabled    => bWritesDisabled,                       -- out boolean
      oWriteDetected     => bWriteDetected,                        -- out boolean
      oFlushReqFifo      => bFlushReqFifo,                         -- out std_logic
      oCorrelatedDataIn  => bStreamState);                         -- in  std_logic_vecto
      
  WritesDisabledDelayed:if kPeerToPeer generate        
    StreamStateFlop: process (aDiagramReset, DefaultClk)
    begin
      if aDiagramReset then
        dStreamStateValueFromControllerDly <= to_StreamStateValue(Unlinked);
      elsif rising_edge(DefaultClk) then
        dStreamStateValueFromControllerDly <= dStreamStateValueFromControllerEarly;
      end if;
    end process;
  end generate WritesDisabledDelayed;
      
  dStreamStateValueFromController <= dStreamStateValueFromControllerDly when kPeerToPeer else
                                    dStreamStateValueFromControllerEarly;
      

  -- Report the number of elements available for writing as zero if it is a peer-to-peer
  -- stream and the stream is not enabled.
  dEmptyCount <= dEmptyCountLoc when not dStateDisable else
                 (others=>'0');

  dCtCount <= resize(dEmptyCount, dCtCount'length);

  -- Do not allow a push to occur when the FIFO is full.  This will prevent
  -- any overflows from occuring.
  dPush <= dPushPop and not dFullFromFifo;

  -- The FIFO is full whenever the empty count is zero.
  dFullFromFifo <= dEmptyCount < kNumOfSamplesPerWrite;
  dFull <= to_boolean(dFifoOverflowFlag);

  -- In case of Handshaking report the overflow condition only when the dInputValid is asserted
  -- while the FIFO is full.
  dFifoOverflow <= to_stdlogic(to_boolean(dFifoOverflowFlag) and dInputValid);
  
  ---------------------------------------------------------------------------------------
  -- Handshaking interface 
  --------------------------------------------------------------------------------------  
  -- This flag asserts when only one write operation can be performed
  -- The number of empty slots must be greater or equal than the amount written 
  -- in one transaction, but smaller than two write transactions 
  dAlmostFull <= (dEmptyCount >= kNumOfSamplesPerWrite) and (dEmptyCount < (2*kNumOfSamplesPerWrite));
  
  -- This flag is qualified with registered Ready For Input, because the 4-wire
  -- protocol explicitly states that Input Valid can only assert if Ready For Input was 
  -- asserted in the previous cycle. This behavior must be ensured by the upstream component,
  -- but we are making sure that it's correct by qualifying Input Valid here, also.
  dInputValidQual <= dInputValid and dReadyForInputReg;
  
  -- Added dDisableEarly for the P2P case using Handshaking
  -- This disables dReadyForInputBool one cycle earlier, thus stopping the pushes as soon
  -- as Flushing or Disable state begins. In Flushing or Disable, the FIFO will not accept any data, so
  -- we must alert the user one cycle earlier, since iReadyForInput indicates the readiness of the FIFO on
  -- the next cycle.
  dReadyForInputBool <= not (dFullFromFifo or (dAlmostFull and dPushPop) or dDisable or dDisableEarly);
  
  dReadyForInput <= dReadyForInputBool;
  
  -- By setting the register to true, pushed data will be accepted
  -- on the first cycle, if iInputValid is true. This was done to
  -- benefit designs where the enable chain is removed from the SCTL.
  ReadyForInputFlop : process (DefaultClk, aDiagramReset)
  begin
    if aDiagramReset then
      dReadyForInputReg <= true;
    elsif rising_edge (DefaultClk) then
      dReadyForInputReg <= dReadyForInputBool;
    end if;
  end process ReadyForInputFlop;
  


  ---------------------------------------------------------------------------------------
  -- Stream State Components
  ---------------------------------------------------------------------------------------
  StreamStateBlock: block

    signal dStreamStateValue, dStreamStateValueFromController : StreamStateValue_t;
    signal dStreamState, dStreamStateFromController : StreamState_t;
    signal bPushStateToDefaultClkDomain : boolean;

  begin

    -- Always allow pushes for a non-peer-to-peer stream.  For a P2P source stream,
    -- pushing to the FIFO is only enabled when the stream is in the Enabled state.
    -- The WritesDisabled signal to be sent back to the BusClk domain is based on the
    -- unlatched stream state, since this value must be guaranteed to eventually settle
    -- to false while the stream state from the controller is Enabled.  Otherwise,
    -- handshaking for the ChinchDmaSourceStreamStateController would not be
    -- possible.
    
    dWritesDisabled <= not (dStreamStateValue = to_StreamStateValue(Enabled));
    dWritesDisabledForController <= not (dStreamStateFromController = Enabled);
    dStateDisable <= dWritesDisabled when kPeerToPeer else false;
    
    dDisableEarly <= not (to_StreamState(dStreamStateValueFromControllerEarly) = Enabled) 
                      when kPeerToPeer else false;
                      
    -- For VI clock domain state reporting
    dCombinedStopRequest <= dStopWithFlushRequest or dStopRequest or dOverflowStopRequest;

    -- NEED CLOCK CROSSING HERE
    bStartStreamRequest <= dStartRequest;

    -- NEED CLOCK CROSSING HERE
    bStopStreamRequestFromDiagram <= dCombinedStopRequest;
    
    -- NEED CLOCK CROSSING HERE
    bStopStreamWithFlushRequest <= dStopWithFlushRequest;

    -- NEED CLOCK CROSSING HERE
    bFlushTimeoutRequest <= dFlushTimeoutRequest;


    -------------------------------------------------------------------------------------
    -- Stream State Outputs
    -------------------------------------------------------------------------------------

    dStreamStateOut <= dStreamStateValue;


    -------------------------------------------------------------------------------------
    -- Handshake the Stream State
    -------------------------------------------------------------------------------------

    dStreamStateFromController <= to_StreamState(dStreamStateValueFromController);

    -- Handshake the stream state from the VI clock domain back to the BusClk
    -- domain.  This handshake requires the safe reset handshake because the request
    -- signal goes from the asynchronous diagram reset domain to the asynchronous bus
    -- reset domain.


    HandshakeStateToBusClkDomain: entity work.HandshakeBaseResetCross (rtl)
      generic map (
        kDataWidth => dStreamStateValueFromController'length)  -- in  integer := 1
      port map (
        aResetToDlyPush    => open,                             -- in  integer := 0
        aResetToIResetFast => open,                             -- in  integer := 0
        aPushToggleDly     => open,                             -- in  integer := 0
        aIReset            => aDiagramReset,                    -- in  boolean
        IClk               => DefaultClk,                            -- in  std_logic
        iPush              => dPushStateToBusClkDomain,         -- in  boolean
        iData              => dStreamStateValueFromController,  -- in  std_logic_vector(k
        iStoredData        => open,                             -- out std_logic_vector(k
        iReady             => dPushStateToBusClkDomain,         -- out boolean := false
        iOResetStatus      => open,                             -- out boolean := false
        aOReset            => aBusReset,                        -- in  boolean
        OClk               => BusClk,                           -- in  std_logic
        oDataValid         => open,                             -- out boolean := false
        oDataAck           => true,                             -- in  boolean := true
        oData              => bStateInDefaultClkDomain);             -- out std_logic_vector(k


    -------------------------------------------------------------------------------------
    -- Stream State Latching Components
    -------------------------------------------------------------------------------------


    -- Track the state to report to the DefaultClk domain.
    -- This component is used so that the state is immediately reported as
    -- flushing after a stop request is made before the actual state is reported as
    -- flushing.

    StateHolderForDefaultClkDomain: entity work.DmaPortCommIfcComponentInputStateHolder (rtl)
      port map (
        aReset          => aDiagramReset,               -- in  boolean
        ViClk           => DefaultClk,                  -- in  std_logic
        vStreamStateOut => dStreamState,                -- out StreamState_t
        vStreamState    => dStreamStateFromController,  -- in  StreamState_t
        vStopRequest    => dCombinedStopRequest);       -- in  boolean


    dStreamStateValue <= to_StreamStateValue(dStreamState);


    -------------------------------------------------------------------------------------
    -- Disable on Overflow
    -------------------------------------------------------------------------------------


    -- Stop the stream from the DefaultClk domain if an overflow occurs and disable on
    -- overflow is enabled.
    dOverflowStopRequest <= kDisableOnFifoTimeout and dStreamState = Enabled and
      to_Boolean(dFifoOverflow);

    -------------------------------------------------------------------------------------
    -- Handshake the overflow stop request to the BusClk domain.
    --
    -- This handshake requires the safe reset handshake because the request signal
    -- goes from the asynchronous diagram reset domain to the asynchronous bus reset
    -- domain.
    --
    --
    -- !ASSUMPTION!
    -- The iReady signal is ignored, which means that if a stream disables due to
    -- overflow and then re-enables before the handshake is ready, an overflow could
    -- potentially ignored.  I am making the assumption that this will not happen because
    -- the host is required to enable a stream, and this should be much slower than the
    -- time required to handshake the overflow stop request.
    -------------------------------------------------------------------------------------

    HandshakeOverflowStopRequest: entity work.HandshakeBaseResetCross (rtl)
      generic map (
        kDataWidth => 2)  -- in  integer := 1
      port map (
        aResetToDlyPush    => open,                  -- in  integer := 0
        aResetToIResetFast => open,                  -- in  integer := 0
        aPushToggleDly     => open,                  -- in  integer := 0
        aIReset            => aDiagramReset,         -- in  boolean
        IClk               => DefaultClk,                 -- in  std_logic
        iPush              => dOverflowStopRequest,  -- in  boolean
        iData              => open,                  -- in  std_logic_vector(kDataWidth-1
        iStoredData        => open,                  -- out std_logic_vector(kDataWidth-1
        iReady             => open,                  -- out boolean := false
        iOResetStatus      => open,                  -- out boolean := false
        aOReset            => aBusReset,             -- in  boolean
        OClk               => BusClk,                -- in  std_logic
        oDataValid         => bOverflowStopRequest,  -- out boolean := false
        oDataAck           => true,                  -- in  boolean := true
        oData              => open);                 -- out std_logic_vector(kDataWidth-1

  end block StreamStateBlock;


  ---------------------------------------------------------------------------------------
  -- Overflow detector
  ---------------------------------------------------------------------------------------
  BlkOverflow: block
    signal dFifoOverflowStrobe, dHsModuleReady : boolean;
  begin

    -- Create the FIFO overflow strobe based on the overflow signal and the push/pop signal.
    -- Qualify this with the HS ready signal so that a push is not
    -- sent while the HS module is in the middle of a previous HS.  This means that an
    -- overflow could be missed by the module, but this will only happen if the HS were
    -- already in the process of handshaking a previous overflow.  Since the overflow is
    -- setting an interrupt bit on the BusClk side, this is ok as long as the time
    -- between handshakes is less than the time for the host to receive and handle the
    -- interrupt.

    dFifoOverflowStrobe <= to_Boolean(dFifoOverflow) and dPushPop and
      dHsModuleReady;


    -- This handshake requires the safe reset handshake because the bFifoOverflow signal
    -- goes from the asynchronous diagram reset domain to the asynchronous bus reset
    -- domain. Even though the bFifoOverflow signal is quiesced during diagram reset,
    -- the handshake module is still unsafe since the data valid signal is an xor of
    -- two flip flops, which could be reset at different times and produce metastability
    -- on the data valid signal. Using the safe handshake prevents any metastability
    -- from propagating to the asynchronous bus reset domain.

    -- Set up the reset safe handshake equivalent to the HandshakeBool so that the
    -- true pulse is only seen for one clock cycle in the BusClk domain.


    HandshakeOverflow: entity work.HandshakeBaseResetCross (rtl)
      generic map (
        kDataWidth => 2)  -- in  integer := 1
      port map (
        aResetToDlyPush    => open,                 -- in  integer := 0
        aResetToIResetFast => open,                 -- in  integer := 0
        aPushToggleDly     => open,                 -- in  integer := 0
        aIReset            => aDiagramReset,        -- in  boolean
        IClk               => DefaultClk,                -- in  std_logic
        iPush              => dFifoOverflowStrobe,  -- in  boolean
        iData              => open,                 -- in  std_logic_vector(kDataWidth-1 
        iStoredData        => open,                 -- out std_logic_vector(kDataWidth-1 
        iReady             => dHsModuleReady,       -- out boolean := false
        iOResetStatus      => open,                 -- out boolean := false
        aOReset            => aBusReset,            -- in  boolean
        OClk               => BusClk,               -- in  std_logic
        oDataValid         => bFifoOverflow,        -- out boolean := false
        oDataAck           => true,                 -- in  boolean := true
        oData              => open);                -- out std_logic_vector(kDataWidth-1 



  end block BlkOverflow;


end structure;
