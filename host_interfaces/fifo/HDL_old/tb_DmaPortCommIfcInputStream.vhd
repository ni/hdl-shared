-------------------------------------------------------------------------------
--
-- File: tb_DmaPortCommIfcInputStream.vhd
-- Author: Florin Hurgoi
-- Original Project: LabVIEW FPGA
-- Date: 10 October 2007
--
-------------------------------------------------------------------------------
-- (c) 2007 Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--   This is a testbench for DmaPortCommIfcInputStream.
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgNiSim.all;
  use work.PkgNiUtilities.all;

  -- This package contains the definitions for the LabVIEW FPGA register
  -- framework signals
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;

  -- Contains definitions for the DMA registers.
  use work.PkgDmaPortCommIfcRegs.all;

  use work.PkgDmaPortCommIfcStreamStates.all;
  use work.PkgDmaPortDataPackingFifo.all;

  use work.PkgNiDma.all;
  use work.PkgNiDmaConfig.all;

entity tb_DmaPortCommIfcInputStream is
end tb_DmaPortCommIfcInputStream;

architecture test of tb_DmaPortCommIfcInputStream is

  constant kNumberOfDUTs : natural := 10;

  constant kNiDmaInputRequestToDmaDone : NiDmaInputRequestToDma_t := (
    Request => true,
    Space => kNiDmaSpaceStream,
    Channel => (others => '0'),
    Address => (others => '0'),
    Baggage => (others => '0'),
    ByteSwap => (others => '0'),
    ByteLane => (others => '0'),
    ByteCount => (others => '0'),
    Done => true,
    EndOfRecord => false);

  -- Array signals to feed the DUTs
  type BooleanArray_t is array (kNumberOfDUTs-1 downto 0) of boolean;
  type StdLogicArray_t is array (kNumberOfDUTs-1 downto 0) of std_logic;
  type UnsignedArray_t is array (kNumberOfDUTs-1 downto 0) of
    unsigned(31 downto 0);
  type PositiveArray_t is array (kNumberOfDUTs-1 downto 0) of positive;
  type NaturalArray_t is array (kNumberOfDUTs-1 downto 0) of natural;
  type StdLogicVector32Array_t is array (kNumberOfDUTs-1 downto 0) of
    std_logic_vector(31 downto 0);
  type StdLogicVector64Array_t is array (kNumberOfDUTs-1 downto 0) of
    std_logic_vector(63 downto 0);
  type RegPortOutArray_t is array (kNumberOfDUTs-1 downto 0) of RegPortOut_t;
  type StreamStateValueArray_t is array (kNumberOfDUTs-1 downto 0) of StreamStateValue_t;
  type SignedArray_t is array (kNumberOfDUTs-1 downto 0) of signed(31 downto 0);
  type EmptyCountArray_t is array (kNumberOfDUTs-1 downto 0) of unsigned(31 downto 0);


  signal bArbiterNormalReqArray : StdLogicArray_t;
  signal bArbiterEmergencyReqArray : StdLogicArray_t;
  signal bArbiterDoneArray : BooleanArray_t;
  signal bArbiterGrantArray : StdLogicArray_t;
  signal bRegPortOutArray : RegPortOutArray_t;
  signal vDataInArray : StdLogicVector64Array_t;
  signal vFullArray : StdLogicArray_t;
  signal vEmptyCountArray : EmptyCountArray_t;
  signal vCtCountArray : EmptyCountArray_t;
  signal vCtEnableInArray : StdLogicArray_t;
  signal vCtEnableOutClearArray : StdLogicArray_t;
  signal vCtEnableOutArray : StdLogicArray_t;
  signal vTimeoutArray : StdLogicVector32Array_t;
  signal vEnableInArray : StdLogicArray_t;
  signal vEnableOutArray : StdLogicArray_t;
  signal vEnableClearArray : StdLogicArray_t;
  signal vStreamStateEnableInArray : StdLogicArray_t;
  signal vStreamStateEnableOutArray : StdLogicArray_t;
  signal vStreamStateEnableClearArray : StdLogicArray_t;
  signal vStreamStateOutArray : StreamStateValueArray_t;
  signal dStreamStateEnableInArray : StdLogicArray_t;
  signal dStreamStateEnableOutArray : StdLogicArray_t;
  signal dStreamStateEnableClearArray : StdLogicArray_t;
  signal dStreamStateOutArray : StreamStateValueArray_t;
  signal dStartRequestEnableInArray : StdLogicArray_t;
  signal dStartRequestEnableOutArray : StdLogicArray_t;
  signal dStartRequestEnableClearArray : StdLogicArray_t;
  signal dStopRequestEnableInArray : StdLogicArray_t;
  signal dStopRequestEnableOutArray : StdLogicArray_t;
  signal dStopRequestEnableClearArray : StdLogicArray_t;
  signal dStopWithFlushRequestEnableInArray : StdLogicArray_t;
  signal dStopWithFlushRequestEnableOutArray : StdLogicArray_t;
  signal dStopWithFlushRequestEnableClearArray : StdLogicArray_t;
  signal dStopWithFlushRequestTimedOutArray : StdLogicArray_t;
  signal dStopWithFlushRequestTimeoutArray : SignedArray_t;
  signal bIrqArray : IrqStatusArray_t(kNumberOfDUTs-1 downto 0);
  signal bNiDmaInputRequestToDma : NiDmaInputRequestToDma_t := kNiDmaInputRequestToDmaZero;
  signal bNiDmaInputRequestFromDma : NiDmaInputRequestFromDma_t;
  signal bNiDmaInputDataToDma : NiDmaInputDataToDma_t := kNiDmaInputDataToDmaZero;
  signal bNiDmaInputDataFromDma : NiDmaInputDataFromDma_t;
  signal bNiDmaInputDataToDmaLcl : NiDmaInputDataToDma_t;
  signal bNiDmaInputRequestToDmaArray: NiDmaInputRequestToDmaArray_t(kNumberOfDUTs-1 downto 0)
    := (others => kNiDmaInputRequestToDmaZero);
  signal bNiDmaInputDataToDmaArray: NiDmaInputDataToDmaArray_t(kNumberOfDUTs-1 downto 0)
    := (others => kNiDmaInputDataToDmaZero);
  signal bNiDmaInputDataFromDmaArray : NiDmaInputDataFromDmaArray_t(kNumberOfDUTs-1 downto 0)
    := (others => kNiDmaInputDataFromDmaZero);
  signal bLastNiDmaInputRequestToDma : NiDmaInputRequestToDma_t;
  signal bNiDmaInputDataFromDmaDly1, bNiDmaInputDataFromDmaDly : NiDmaInputDataFromDma_t;
  signal BytesReceivedSig : natural := 0;
  signal bRequestAcknowledge : boolean := false;
  signal NumOfReadsSig : natural := 0;
  signal ReceiveDataDone : boolean := false;
  signal ClkWaitBeforeDataTransfer : natural := 0;

  ---------------------------------------------------------------------------------------
  -- DUT Configurations
  --
  --  ----------------------------------------------------------------------------
  --  | DUT Number | Data Width | Depth | Eviction Timeout | Base Offset |   P2P |
  --  |          0 |          8 |  1023 |            16383 |         x10 |  true |
  --  |          1 |         16 |  1023 |              511 |         x40 | false |
  --  |          2 |         32 |  1023 |              511 |         x70 | false |
  --  |          3 |         64 |  1023 |              511 |        x100 | false |
  --  |          4 |         17 |     3 |              511 |        x130 |  true |
  --  |          5 |         51 |    63 |              511 |        x160 |  true |
  --  |          6 |          2 |  4095 |              511 |        x190 |  true |
  --  |          7 |         30 | 16383 |                8 |        x220 |  true |
  --  |          8 |          6 |  1023 |              511 |        x250 | false |
  --  |          9 |         18 |  1023 |              511 |        x280 | false |
  --  ----------------------------------------------------------------------------
  --
  ---------------------------------------------------------------------------------------

  -- The configuration for each DUT.
  constant kDataWidthArray : PositiveArray_t :=
    (18,6,30,2,51,17,64,32,16,8);
  constant kFxpTypeArray : BooleanArray_t :=
    (true, true, true,true,true,true,false,false,false,false);
  constant kFIFODepthArray : NaturalArray_t :=
    (1023,1023,16383,4095,63,3,1023,1023,1023,1023);
  constant kEvictionTimeoutArray : NaturalArray_t :=
    (511,511,8,511,511,511,511,511,511,16383);
  constant kBaseOffsetArray : NaturalArray_t :=
    (16#280#,16#250#,16#220#,16#190#,16#160#,16#130#,16#100#,16#70#,16#40#,16#10#);
  constant kPeerToPeerArray : BooleanArray_t :=
    (false,false,true,true,true,true,false,false,false,true);
  constant kEndpointArray : NaturalArray_t :=
    (0,0,15,0,2,1,0,0,0,0);
  constant kCountSclArray : BooleanArray_t :=
    (false,true,false,true,false,true,false,true,false,true);
  constant kDisableOnFifoTimeoutArray : BooleanArray_t :=
    (false,false,false,false,false,false,false,false,false,false);
  constant kViClkIsDefaultClk : boolean := false;

  signal bRegPortOut: RegPortOut_t;

  signal bTimeoutCount : natural;
  signal bResetTimeoutCount : boolean;

  --vhook_sigstart
  signal aReset: boolean;
  signal bNiDmaInputStatusFromDma: NiDmaInputStatusFromDma_t;
  signal bRegPortIn: RegPortIn_t;
  signal bReset: boolean;
  signal dCurrentStreamState: StreamStateValue_t;
  signal DefaultClk: std_logic := '0';
  signal ViClk: std_logic := '0';
  --vhook_sigend

  --vhook_nowarn dCurrentStreamState

  signal StopSim : boolean := false;
  signal TestStatus : TestStatusString_t := (others => ' ');
  --vhook_nowarn TestStatus*

  signal Clk : std_logic := '0';

  constant kViClkPeriod : Time := 23 ns;
  constant kDefaultClkPeriod : Time := 13 ns;

  -- This procedure waits for X rising edges of Clk
  procedure ClkWait (X : integer := 1) is
  begin
    for i in 1 to X loop
      wait until rising_edge(Clk);
    end loop;
  end procedure ClkWait;

  -- Get the FIFO width from the DMA configuration information.
  function GetFifoWidths(DataWidths : PositiveArray_t;
                         PeerToPeer : BooleanArray_t;
                         FxpType    : BooleanArray_t)
  return PositiveArray_t is

    variable ReturnVal : PositiveArray_t;

  begin

    for i in DataWidths'range loop

      ReturnVal(i) := ActualSampleSize(
        SampleSizeInBits => DataWidths(i),
        PeerToPeer       => PeerToPeer(i),
        FxpType          => FxpType(i));

    end loop;

    return ReturnVal;

  end GetFifoWidths;

  -- The widths of the data as treated on the bus side of the interface.
  constant kFifoDataWidthArray : PositiveArray_t :=
    GetFifoWidths(DataWidths => kDataWidthArray,
                  PeerToPeer => kPeerToPeerArray,
                  FxpType    => kFxpTypeArray);

begin

  -- Display the value of the TestStatus string
  VPrint(TestStatus);

  -- Set up the clock(s)
  Clk <= not Clk after 8 ns when not StopSim else '0';
  VIClk <= not VIClk after kViClkPeriod when not StopSim else '0';
  DefaultClk <= not DefaultClk after kDefaultClkPeriod when not StopSim else '0';

  bNiDmaInputStatusFromDma <= kNiDmaInputStatusFromDmaZero;

  --vhook_e DmaPortCommIfcInputWrapper DUT0
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(0)
  --vhook_a kDataWidth kDataWidthArray(0)
  --vhook_a kBaseOffset kBaseOffsetArray(0)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(0)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 0
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(0)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(0)
  --vhook_a kFxpType kFxpTypeArray(0)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(0)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(0)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(0)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(0)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(0)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(0)
  --vhook_a bArbiterDone bArbiterDoneArray(0)
  --vhook_a bArbiterGrant bArbiterGrantArray(0)
  --vhook_a bRegPortOut bRegPortOutArray(0)
  --vhook_a vDataIn vDataInArray(0)(kDataWidthArray(0)-1 downto 0)
  --vhook_a vFull vFullArray(0)
  --vhook_a vCtCount vCtCountArray(0)
  --vhook_a vCtEnableIn vCtEnableInArray(0)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(0)
  --vhook_a vCtEnableOut vCtEnableOutArray(0)
  --vhook_a vTimeout vTimeoutArray(0)
  --vhook_a vEnableIn vEnableInArray(0)
  --vhook_a vEnableOut vEnableOutArray(0)
  --vhook_a vEnableClear vEnableClearArray(0)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(0)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(0)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(0)
  --vhook_a vStreamStateOut vStreamStateOutArray(0)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(0)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(0)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(0)
  --vhook_a dStreamStateOut dStreamStateOutArray(0)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(0)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(0)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(0)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(0)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(0)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(0)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(0)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(0)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(0)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(0)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(0)
  --vhook_a bIrq bIrqArray(0)
  DUT0: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(0),
      kDataWidth            => kDataWidthArray(0),
      kBaseOffset           => kBaseOffsetArray(0),
      kScl                  => false,
      kCountScl             => kCountSclArray(0),
      kSignExtend           => false,
      kStreamNumber         => 0,
      kEvictionTimeout      => kEvictionTimeoutArray(0),
      kPeerToPeerStream     => kPeerToPeerArray(0),
      kFxpType              => kFxpTypeArray(0),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(0),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(0),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(0),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(0),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(0),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(0),
      bArbiterDone                     => bArbiterDoneArray(0),
      bArbiterGrant                    => bArbiterGrantArray(0),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(0),
      vDataIn                          => vDataInArray(0)(kDataWidthArray(0)-1 downto 0),
      vFull                            => vFullArray(0),
      vTimeout                         => vTimeoutArray(0),
      vEnableIn                        => vEnableInArray(0),
      vEnableOut                       => vEnableOutArray(0),
      vEnableClear                     => vEnableClearArray(0),
      vCtCount                         => vCtCountArray(0),
      vCtEnableIn                      => vCtEnableInArray(0),
      vCtEnableOut                     => vCtEnableOutArray(0),
      vCtEnableOutClear                => vCtEnableOutClearArray(0),
      vStreamStateEnableIn             => vStreamStateEnableInArray(0),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(0),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(0),
      vStreamStateOut                  => vStreamStateOutArray(0),
      dStreamStateEnableIn             => dStreamStateEnableInArray(0),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(0),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(0),
      dStreamStateOut                  => dStreamStateOutArray(0),
      dStartRequestEnableIn            => dStartRequestEnableInArray(0),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(0),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(0),
      dStopRequestEnableIn             => dStopRequestEnableInArray(0),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(0),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(0),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(0),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(0),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(0),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(0),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(0),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(0));



  --vhook_e DmaPortCommIfcInputWrapper DUT1
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(1)
  --vhook_a kDataWidth kDataWidthArray(1)
  --vhook_a kBaseOffset kBaseOffsetArray(1)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(1)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 1
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(1)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(1)
  --vhook_a kFxpType kFxpTypeArray(1)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(1)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(1)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(1)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(1)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(1)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(1)
  --vhook_a bArbiterDone bArbiterDoneArray(1)
  --vhook_a bArbiterGrant bArbiterGrantArray(1)
  --vhook_a bRegPortOut bRegPortOutArray(1)
  --vhook_a vDataIn vDataInArray(1)(kDataWidthArray(1)-1 downto 0)
  --vhook_a vFull vFullArray(1)
  --vhook_a vCtCount vCtCountArray(1)
  --vhook_a vCtEnableIn vCtEnableInArray(1)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(1)
  --vhook_a vCtEnableOut vCtEnableOutArray(1)
  --vhook_a vTimeout vTimeoutArray(1)
  --vhook_a vEnableIn vEnableInArray(1)
  --vhook_a vEnableOut vEnableOutArray(1)
  --vhook_a vEnableClear vEnableClearArray(1)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(1)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(1)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(1)
  --vhook_a vStreamStateOut vStreamStateOutArray(1)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(1)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(1)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(1)
  --vhook_a dStreamStateOut dStreamStateOutArray(1)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(1)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(1)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(1)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(1)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(1)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(1)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(1)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(1)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(1)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(1)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(1)
  --vhook_a bIrq bIrqArray(1)
  DUT1: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(1),
      kDataWidth            => kDataWidthArray(1),
      kBaseOffset           => kBaseOffsetArray(1),
      kScl                  => false,
      kCountScl             => kCountSclArray(1),
      kSignExtend           => false,
      kStreamNumber         => 1,
      kEvictionTimeout      => kEvictionTimeoutArray(1),
      kPeerToPeerStream     => kPeerToPeerArray(1),
      kFxpType              => kFxpTypeArray(1),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(1),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(1),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(1),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(1),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(1),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(1),
      bArbiterDone                     => bArbiterDoneArray(1),
      bArbiterGrant                    => bArbiterGrantArray(1),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(1),
      vDataIn                          => vDataInArray(1)(kDataWidthArray(1)-1 downto 0),
      vFull                            => vFullArray(1),
      vTimeout                         => vTimeoutArray(1),
      vEnableIn                        => vEnableInArray(1),
      vEnableOut                       => vEnableOutArray(1),
      vEnableClear                     => vEnableClearArray(1),
      vCtCount                         => vCtCountArray(1),
      vCtEnableIn                      => vCtEnableInArray(1),
      vCtEnableOut                     => vCtEnableOutArray(1),
      vCtEnableOutClear                => vCtEnableOutClearArray(1),
      vStreamStateEnableIn             => vStreamStateEnableInArray(1),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(1),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(1),
      vStreamStateOut                  => vStreamStateOutArray(1),
      dStreamStateEnableIn             => dStreamStateEnableInArray(1),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(1),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(1),
      dStreamStateOut                  => dStreamStateOutArray(1),
      dStartRequestEnableIn            => dStartRequestEnableInArray(1),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(1),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(1),
      dStopRequestEnableIn             => dStopRequestEnableInArray(1),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(1),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(1),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(1),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(1),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(1),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(1),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(1),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(1));



  --vhook_e DmaPortCommIfcInputWrapper DUT2
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(2)
  --vhook_a kDataWidth kDataWidthArray(2)
  --vhook_a kBaseOffset kBaseOffsetArray(2)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(2)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 2
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(2)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(2)
  --vhook_a kFxpType kFxpTypeArray(2)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(2)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(2)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(2)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(2)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(2)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(2)
  --vhook_a bArbiterDone bArbiterDoneArray(2)
  --vhook_a bArbiterGrant bArbiterGrantArray(2)
  --vhook_a bRegPortOut bRegPortOutArray(2)
  --vhook_a vDataIn vDataInArray(2)(kDataWidthArray(2)-1 downto 0)
  --vhook_a vFull vFullArray(2)
  --vhook_a vCtCount vCtCountArray(2)
  --vhook_a vCtEnableIn vCtEnableInArray(2)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(2)
  --vhook_a vCtEnableOut vCtEnableOutArray(2)
  --vhook_a vTimeout vTimeoutArray(2)
  --vhook_a vEnableIn vEnableInArray(2)
  --vhook_a vEnableOut vEnableOutArray(2)
  --vhook_a vEnableClear vEnableClearArray(2)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(2)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(2)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(2)
  --vhook_a vStreamStateOut vStreamStateOutArray(2)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(2)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(2)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(2)
  --vhook_a dStreamStateOut dStreamStateOutArray(2)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(2)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(2)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(2)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(2)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(2)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(2)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(2)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(2)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(2)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(2)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(2)
  --vhook_a bIrq bIrqArray(2)
  DUT2: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(2),
      kDataWidth            => kDataWidthArray(2),
      kBaseOffset           => kBaseOffsetArray(2),
      kScl                  => false,
      kCountScl             => kCountSclArray(2),
      kSignExtend           => false,
      kStreamNumber         => 2,
      kEvictionTimeout      => kEvictionTimeoutArray(2),
      kPeerToPeerStream     => kPeerToPeerArray(2),
      kFxpType              => kFxpTypeArray(2),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(2),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(2),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(2),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(2),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(2),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(2),
      bArbiterDone                     => bArbiterDoneArray(2),
      bArbiterGrant                    => bArbiterGrantArray(2),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(2),
      vDataIn                          => vDataInArray(2)(kDataWidthArray(2)-1 downto 0),
      vFull                            => vFullArray(2),
      vTimeout                         => vTimeoutArray(2),
      vEnableIn                        => vEnableInArray(2),
      vEnableOut                       => vEnableOutArray(2),
      vEnableClear                     => vEnableClearArray(2),
      vCtCount                         => vCtCountArray(2),
      vCtEnableIn                      => vCtEnableInArray(2),
      vCtEnableOut                     => vCtEnableOutArray(2),
      vCtEnableOutClear                => vCtEnableOutClearArray(2),
      vStreamStateEnableIn             => vStreamStateEnableInArray(2),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(2),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(2),
      vStreamStateOut                  => vStreamStateOutArray(2),
      dStreamStateEnableIn             => dStreamStateEnableInArray(2),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(2),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(2),
      dStreamStateOut                  => dStreamStateOutArray(2),
      dStartRequestEnableIn            => dStartRequestEnableInArray(2),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(2),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(2),
      dStopRequestEnableIn             => dStopRequestEnableInArray(2),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(2),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(2),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(2),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(2),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(2),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(2),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(2),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(2));



  --vhook_e DmaPortCommIfcInputWrapper DUT3
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(3)
  --vhook_a kDataWidth kDataWidthArray(3)
  --vhook_a kBaseOffset kBaseOffsetArray(3)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(3)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 3
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(3)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(3)
  --vhook_a kFxpType kFxpTypeArray(3)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(3)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(3)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(3)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(3)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(3)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(3)
  --vhook_a bArbiterDone bArbiterDoneArray(3)
  --vhook_a bArbiterGrant bArbiterGrantArray(3)
  --vhook_a bRegPortOut bRegPortOutArray(3)
  --vhook_a vDataIn vDataInArray(3)(kDataWidthArray(3)-1 downto 0)
  --vhook_a vFull vFullArray(3)
  --vhook_a vCtCount vCtCountArray(3)
  --vhook_a vCtEnableIn vCtEnableInArray(3)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(3)
  --vhook_a vCtEnableOut vCtEnableOutArray(3)
  --vhook_a vTimeout vTimeoutArray(3)
  --vhook_a vEnableIn vEnableInArray(3)
  --vhook_a vEnableOut vEnableOutArray(3)
  --vhook_a vEnableClear vEnableClearArray(3)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(3)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(3)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(3)
  --vhook_a vStreamStateOut vStreamStateOutArray(3)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(3)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(3)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(3)
  --vhook_a dStreamStateOut dStreamStateOutArray(3)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(3)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(3)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(3)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(3)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(3)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(3)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(3)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(3)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(3)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(3)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(3)
  --vhook_a bIrq bIrqArray(3)
  DUT3: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(3),
      kDataWidth            => kDataWidthArray(3),
      kBaseOffset           => kBaseOffsetArray(3),
      kScl                  => false,
      kCountScl             => kCountSclArray(3),
      kSignExtend           => false,
      kStreamNumber         => 3,
      kEvictionTimeout      => kEvictionTimeoutArray(3),
      kPeerToPeerStream     => kPeerToPeerArray(3),
      kFxpType              => kFxpTypeArray(3),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(3),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(3),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(3),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(3),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(3),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(3),
      bArbiterDone                     => bArbiterDoneArray(3),
      bArbiterGrant                    => bArbiterGrantArray(3),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(3),
      vDataIn                          => vDataInArray(3)(kDataWidthArray(3)-1 downto 0),
      vFull                            => vFullArray(3),
      vTimeout                         => vTimeoutArray(3),
      vEnableIn                        => vEnableInArray(3),
      vEnableOut                       => vEnableOutArray(3),
      vEnableClear                     => vEnableClearArray(3),
      vCtCount                         => vCtCountArray(3),
      vCtEnableIn                      => vCtEnableInArray(3),
      vCtEnableOut                     => vCtEnableOutArray(3),
      vCtEnableOutClear                => vCtEnableOutClearArray(3),
      vStreamStateEnableIn             => vStreamStateEnableInArray(3),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(3),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(3),
      vStreamStateOut                  => vStreamStateOutArray(3),
      dStreamStateEnableIn             => dStreamStateEnableInArray(3),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(3),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(3),
      dStreamStateOut                  => dStreamStateOutArray(3),
      dStartRequestEnableIn            => dStartRequestEnableInArray(3),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(3),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(3),
      dStopRequestEnableIn             => dStopRequestEnableInArray(3),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(3),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(3),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(3),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(3),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(3),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(3),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(3),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(3));



  --vhook_e DmaPortCommIfcInputWrapper DUT4
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(4)
  --vhook_a kDataWidth kDataWidthArray(4)
  --vhook_a kBaseOffset kBaseOffsetArray(4)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(4)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 4
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(4)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(4)
  --vhook_a kFxpType kFxpTypeArray(4)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(4)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(4)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(4)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(4)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(4)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(4)
  --vhook_a bArbiterDone bArbiterDoneArray(4)
  --vhook_a bArbiterGrant bArbiterGrantArray(4)
  --vhook_a bRegPortOut bRegPortOutArray(4)
  --vhook_a vDataIn vDataInArray(4)(kDataWidthArray(4)-1 downto 0)
  --vhook_a vFull vFullArray(4)
  --vhook_a vCtCount vCtCountArray(4)
  --vhook_a vCtEnableIn vCtEnableInArray(4)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(4)
  --vhook_a vCtEnableOut vCtEnableOutArray(4)
  --vhook_a vTimeout vTimeoutArray(4)
  --vhook_a vEnableIn vEnableInArray(4)
  --vhook_a vEnableOut vEnableOutArray(4)
  --vhook_a vEnableClear vEnableClearArray(4)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(4)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(4)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(4)
  --vhook_a vStreamStateOut vStreamStateOutArray(4)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(4)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(4)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(4)
  --vhook_a dStreamStateOut dStreamStateOutArray(4)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(4)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(4)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(4)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(4)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(4)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(4)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(4)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(4)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(4)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(4)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(4)
  --vhook_a bIrq bIrqArray(4)
  DUT4: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(4),
      kDataWidth            => kDataWidthArray(4),
      kBaseOffset           => kBaseOffsetArray(4),
      kScl                  => false,
      kCountScl             => kCountSclArray(4),
      kSignExtend           => false,
      kStreamNumber         => 4,
      kEvictionTimeout      => kEvictionTimeoutArray(4),
      kPeerToPeerStream     => kPeerToPeerArray(4),
      kFxpType              => kFxpTypeArray(4),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(4),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(4),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(4),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(4),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(4),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(4),
      bArbiterDone                     => bArbiterDoneArray(4),
      bArbiterGrant                    => bArbiterGrantArray(4),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(4),
      vDataIn                          => vDataInArray(4)(kDataWidthArray(4)-1 downto 0),
      vFull                            => vFullArray(4),
      vTimeout                         => vTimeoutArray(4),
      vEnableIn                        => vEnableInArray(4),
      vEnableOut                       => vEnableOutArray(4),
      vEnableClear                     => vEnableClearArray(4),
      vCtCount                         => vCtCountArray(4),
      vCtEnableIn                      => vCtEnableInArray(4),
      vCtEnableOut                     => vCtEnableOutArray(4),
      vCtEnableOutClear                => vCtEnableOutClearArray(4),
      vStreamStateEnableIn             => vStreamStateEnableInArray(4),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(4),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(4),
      vStreamStateOut                  => vStreamStateOutArray(4),
      dStreamStateEnableIn             => dStreamStateEnableInArray(4),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(4),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(4),
      dStreamStateOut                  => dStreamStateOutArray(4),
      dStartRequestEnableIn            => dStartRequestEnableInArray(4),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(4),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(4),
      dStopRequestEnableIn             => dStopRequestEnableInArray(4),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(4),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(4),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(4),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(4),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(4),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(4),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(4),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(4));



  --vhook_e DmaPortCommIfcInputWrapper DUT5
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(5)
  --vhook_a kDataWidth kDataWidthArray(5)
  --vhook_a kBaseOffset kBaseOffsetArray(5)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(5)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 5
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(5)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(5)
  --vhook_a kFxpType kFxpTypeArray(5)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(5)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(5)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(5)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(5)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(5)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(5)
  --vhook_a bArbiterDone bArbiterDoneArray(5)
  --vhook_a bArbiterGrant bArbiterGrantArray(5)
  --vhook_a bRegPortOut bRegPortOutArray(5)
  --vhook_a vDataIn vDataInArray(5)(kDataWidthArray(5)-1 downto 0)
  --vhook_a vFull vFullArray(5)
  --vhook_a vCtCount vCtCountArray(5)
  --vhook_a vCtEnableIn vCtEnableInArray(5)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(5)
  --vhook_a vCtEnableOut vCtEnableOutArray(5)
  --vhook_a vTimeout vTimeoutArray(5)
  --vhook_a vEnableIn vEnableInArray(5)
  --vhook_a vEnableOut vEnableOutArray(5)
  --vhook_a vEnableClear vEnableClearArray(5)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(5)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(5)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(5)
  --vhook_a vStreamStateOut vStreamStateOutArray(5)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(5)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(5)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(5)
  --vhook_a dStreamStateOut dStreamStateOutArray(5)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(5)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(5)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(5)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(5)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(5)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(5)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(5)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(5)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(5)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(5)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(5)
  --vhook_a bIrq bIrqArray(5)
  DUT5: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(5),
      kDataWidth            => kDataWidthArray(5),
      kBaseOffset           => kBaseOffsetArray(5),
      kScl                  => false,
      kCountScl             => kCountSclArray(5),
      kSignExtend           => false,
      kStreamNumber         => 5,
      kEvictionTimeout      => kEvictionTimeoutArray(5),
      kPeerToPeerStream     => kPeerToPeerArray(5),
      kFxpType              => kFxpTypeArray(5),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(5),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(5),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(5),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(5),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(5),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(5),
      bArbiterDone                     => bArbiterDoneArray(5),
      bArbiterGrant                    => bArbiterGrantArray(5),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(5),
      vDataIn                          => vDataInArray(5)(kDataWidthArray(5)-1 downto 0),
      vFull                            => vFullArray(5),
      vTimeout                         => vTimeoutArray(5),
      vEnableIn                        => vEnableInArray(5),
      vEnableOut                       => vEnableOutArray(5),
      vEnableClear                     => vEnableClearArray(5),
      vCtCount                         => vCtCountArray(5),
      vCtEnableIn                      => vCtEnableInArray(5),
      vCtEnableOut                     => vCtEnableOutArray(5),
      vCtEnableOutClear                => vCtEnableOutClearArray(5),
      vStreamStateEnableIn             => vStreamStateEnableInArray(5),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(5),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(5),
      vStreamStateOut                  => vStreamStateOutArray(5),
      dStreamStateEnableIn             => dStreamStateEnableInArray(5),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(5),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(5),
      dStreamStateOut                  => dStreamStateOutArray(5),
      dStartRequestEnableIn            => dStartRequestEnableInArray(5),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(5),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(5),
      dStopRequestEnableIn             => dStopRequestEnableInArray(5),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(5),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(5),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(5),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(5),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(5),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(5),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(5),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(5));



  --vhook_e DmaPortCommIfcInputWrapper DUT6
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(6)
  --vhook_a kDataWidth kDataWidthArray(6)
  --vhook_a kBaseOffset kBaseOffsetArray(6)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(6)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 6
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(6)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(6)
  --vhook_a kFxpType kFxpTypeArray(6)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(6)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(6)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(6)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(6)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(6)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(6)
  --vhook_a bArbiterDone bArbiterDoneArray(6)
  --vhook_a bArbiterGrant bArbiterGrantArray(6)
  --vhook_a bRegPortOut bRegPortOutArray(6)
  --vhook_a vDataIn vDataInArray(6)(kDataWidthArray(6)-1 downto 0)
  --vhook_a vFull vFullArray(6)
  --vhook_a vCtCount vCtCountArray(6)
  --vhook_a vCtEnableIn vCtEnableInArray(6)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(6)
  --vhook_a vCtEnableOut vCtEnableOutArray(6)
  --vhook_a vTimeout vTimeoutArray(6)
  --vhook_a vEnableIn vEnableInArray(6)
  --vhook_a vEnableOut vEnableOutArray(6)
  --vhook_a vEnableClear vEnableClearArray(6)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(6)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(6)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(6)
  --vhook_a vStreamStateOut vStreamStateOutArray(6)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(6)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(6)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(6)
  --vhook_a dStreamStateOut dStreamStateOutArray(6)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(6)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(6)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(6)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(6)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(6)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(6)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(6)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(6)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(6)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(6)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(6)
  --vhook_a bIrq bIrqArray(6)
  DUT6: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(6),
      kDataWidth            => kDataWidthArray(6),
      kBaseOffset           => kBaseOffsetArray(6),
      kScl                  => false,
      kCountScl             => kCountSclArray(6),
      kSignExtend           => false,
      kStreamNumber         => 6,
      kEvictionTimeout      => kEvictionTimeoutArray(6),
      kPeerToPeerStream     => kPeerToPeerArray(6),
      kFxpType              => kFxpTypeArray(6),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(6),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(6),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(6),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(6),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(6),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(6),
      bArbiterDone                     => bArbiterDoneArray(6),
      bArbiterGrant                    => bArbiterGrantArray(6),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(6),
      vDataIn                          => vDataInArray(6)(kDataWidthArray(6)-1 downto 0),
      vFull                            => vFullArray(6),
      vTimeout                         => vTimeoutArray(6),
      vEnableIn                        => vEnableInArray(6),
      vEnableOut                       => vEnableOutArray(6),
      vEnableClear                     => vEnableClearArray(6),
      vCtCount                         => vCtCountArray(6),
      vCtEnableIn                      => vCtEnableInArray(6),
      vCtEnableOut                     => vCtEnableOutArray(6),
      vCtEnableOutClear                => vCtEnableOutClearArray(6),
      vStreamStateEnableIn             => vStreamStateEnableInArray(6),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(6),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(6),
      vStreamStateOut                  => vStreamStateOutArray(6),
      dStreamStateEnableIn             => dStreamStateEnableInArray(6),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(6),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(6),
      dStreamStateOut                  => dStreamStateOutArray(6),
      dStartRequestEnableIn            => dStartRequestEnableInArray(6),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(6),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(6),
      dStopRequestEnableIn             => dStopRequestEnableInArray(6),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(6),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(6),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(6),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(6),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(6),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(6),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(6),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(6));



  --vhook_e DmaPortCommIfcInputWrapper DUT7
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(7)
  --vhook_a kDataWidth kDataWidthArray(7)
  --vhook_a kBaseOffset kBaseOffsetArray(7)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(7)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 7
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(7)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(7)
  --vhook_a kFxpType kFxpTypeArray(7)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(7)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(7)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(7)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(7)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(7)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(7)
  --vhook_a bArbiterDone bArbiterDoneArray(7)
  --vhook_a bArbiterGrant bArbiterGrantArray(7)
  --vhook_a bRegPortOut bRegPortOutArray(7)
  --vhook_a vDataIn vDataInArray(7)(kDataWidthArray(7)-1 downto 0)
  --vhook_a vFull vFullArray(7)
  --vhook_a vCtCount vCtCountArray(7)
  --vhook_a vCtEnableIn vCtEnableInArray(7)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(7)
  --vhook_a vCtEnableOut vCtEnableOutArray(7)
  --vhook_a vTimeout vTimeoutArray(7)
  --vhook_a vEnableIn vEnableInArray(7)
  --vhook_a vEnableOut vEnableOutArray(7)
  --vhook_a vEnableClear vEnableClearArray(7)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(7)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(7)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(7)
  --vhook_a vStreamStateOut vStreamStateOutArray(7)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(7)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(7)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(7)
  --vhook_a dStreamStateOut dStreamStateOutArray(7)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(7)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(7)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(7)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(7)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(7)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(7)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(7)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(7)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(7)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(7)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(7)
  --vhook_a bIrq bIrqArray(7)
  DUT7: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(7),
      kDataWidth            => kDataWidthArray(7),
      kBaseOffset           => kBaseOffsetArray(7),
      kScl                  => false,
      kCountScl             => kCountSclArray(7),
      kSignExtend           => false,
      kStreamNumber         => 7,
      kEvictionTimeout      => kEvictionTimeoutArray(7),
      kPeerToPeerStream     => kPeerToPeerArray(7),
      kFxpType              => kFxpTypeArray(7),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(7),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(7),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(7),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(7),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(7),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(7),
      bArbiterDone                     => bArbiterDoneArray(7),
      bArbiterGrant                    => bArbiterGrantArray(7),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(7),
      vDataIn                          => vDataInArray(7)(kDataWidthArray(7)-1 downto 0),
      vFull                            => vFullArray(7),
      vTimeout                         => vTimeoutArray(7),
      vEnableIn                        => vEnableInArray(7),
      vEnableOut                       => vEnableOutArray(7),
      vEnableClear                     => vEnableClearArray(7),
      vCtCount                         => vCtCountArray(7),
      vCtEnableIn                      => vCtEnableInArray(7),
      vCtEnableOut                     => vCtEnableOutArray(7),
      vCtEnableOutClear                => vCtEnableOutClearArray(7),
      vStreamStateEnableIn             => vStreamStateEnableInArray(7),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(7),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(7),
      vStreamStateOut                  => vStreamStateOutArray(7),
      dStreamStateEnableIn             => dStreamStateEnableInArray(7),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(7),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(7),
      dStreamStateOut                  => dStreamStateOutArray(7),
      dStartRequestEnableIn            => dStartRequestEnableInArray(7),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(7),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(7),
      dStopRequestEnableIn             => dStopRequestEnableInArray(7),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(7),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(7),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(7),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(7),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(7),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(7),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(7),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(7));



  --vhook_e DmaPortCommIfcInputWrapper DUT8
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(8)
  --vhook_a kDataWidth kDataWidthArray(8)
  --vhook_a kBaseOffset kBaseOffsetArray(8)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(8)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 8
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(8)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(8)
  --vhook_a kFxpType kFxpTypeArray(8)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(8)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(8)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(8)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(8)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(8)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(8)
  --vhook_a bArbiterDone bArbiterDoneArray(8)
  --vhook_a bArbiterGrant bArbiterGrantArray(8)
  --vhook_a bRegPortOut bRegPortOutArray(8)
  --vhook_a vDataIn vDataInArray(8)(kDataWidthArray(8)-1 downto 0)
  --vhook_a vFull vFullArray(8)
  --vhook_a vCtCount vCtCountArray(8)
  --vhook_a vCtEnableIn vCtEnableInArray(8)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(8)
  --vhook_a vCtEnableOut vCtEnableOutArray(8)
  --vhook_a vTimeout vTimeoutArray(8)
  --vhook_a vEnableIn vEnableInArray(8)
  --vhook_a vEnableOut vEnableOutArray(8)
  --vhook_a vEnableClear vEnableClearArray(8)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(8)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(8)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(8)
  --vhook_a vStreamStateOut vStreamStateOutArray(8)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(8)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(8)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(8)
  --vhook_a dStreamStateOut dStreamStateOutArray(8)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(8)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(8)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(8)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(8)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(8)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(8)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(8)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(8)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(8)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(8)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(8)
  --vhook_a bIrq bIrqArray(8)
  DUT8: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(8),
      kDataWidth            => kDataWidthArray(8),
      kBaseOffset           => kBaseOffsetArray(8),
      kScl                  => false,
      kCountScl             => kCountSclArray(8),
      kSignExtend           => false,
      kStreamNumber         => 8,
      kEvictionTimeout      => kEvictionTimeoutArray(8),
      kPeerToPeerStream     => kPeerToPeerArray(8),
      kFxpType              => kFxpTypeArray(8),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(8),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(8),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(8),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(8),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(8),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(8),
      bArbiterDone                     => bArbiterDoneArray(8),
      bArbiterGrant                    => bArbiterGrantArray(8),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(8),
      vDataIn                          => vDataInArray(8)(kDataWidthArray(8)-1 downto 0),
      vFull                            => vFullArray(8),
      vTimeout                         => vTimeoutArray(8),
      vEnableIn                        => vEnableInArray(8),
      vEnableOut                       => vEnableOutArray(8),
      vEnableClear                     => vEnableClearArray(8),
      vCtCount                         => vCtCountArray(8),
      vCtEnableIn                      => vCtEnableInArray(8),
      vCtEnableOut                     => vCtEnableOutArray(8),
      vCtEnableOutClear                => vCtEnableOutClearArray(8),
      vStreamStateEnableIn             => vStreamStateEnableInArray(8),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(8),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(8),
      vStreamStateOut                  => vStreamStateOutArray(8),
      dStreamStateEnableIn             => dStreamStateEnableInArray(8),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(8),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(8),
      dStreamStateOut                  => dStreamStateOutArray(8),
      dStartRequestEnableIn            => dStartRequestEnableInArray(8),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(8),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(8),
      dStopRequestEnableIn             => dStopRequestEnableInArray(8),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(8),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(8),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(8),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(8),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(8),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(8),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(8),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(8));



  --vhook_e DmaPortCommIfcInputWrapper DUT9
  --vhook_a BusClk Clk
  --vhook_a kFifoDepth kFifoDepthArray(9)
  --vhook_a kDataWidth kDataWidthArray(9)
  --vhook_a kBaseOffset kBaseOffsetArray(9)
  --vhook_a kSCL false
  --vhook_a kCountScl kCountSclArray(9)
  --vhook_a kSignExtend false
  --vhook_a kStreamNumber 9
  --vhook_a kEvictionTimeout kEvictionTimeoutArray(9)
  --vhook_a kPeerToPeerStream kPeerToPeerArray(9)
  --vhook_a kFxpType kFxpTypeArray(9)
  --vhook_a kDisableOnFifoTimeout kDisableOnFifoTimeoutArray(9)
  --vhook_a bNiDmaInputRequestToDma bNiDmaInputRequestToDmaArray(9)
  --vhook_a bNiDmaInputDataToDma bNiDmaInputDataToDmaArray(9)
  --vhook_a bNiDmaInputDataFromDma bNiDmaInputDataFromDmaArray(9)
  --vhook_a bArbiterNormalReq bArbiterNormalReqArray(9)
  --vhook_a bArbiterEmergencyReq bArbiterEmergencyReqArray(9)
  --vhook_a bArbiterDone bArbiterDoneArray(9)
  --vhook_a bArbiterGrant bArbiterGrantArray(9)
  --vhook_a bRegPortOut bRegPortOutArray(9)
  --vhook_a vDataIn vDataInArray(9)(kDataWidthArray(9)-1 downto 0)
  --vhook_a vFull vFullArray(9)
  --vhook_a vCtCount vCtCountArray(9)
  --vhook_a vCtEnableIn vCtEnableInArray(9)
  --vhook_a vCtEnableOutClear vCtEnableOutClearArray(9)
  --vhook_a vCtEnableOut vCtEnableOutArray(9)
  --vhook_a vTimeout vTimeoutArray(9)
  --vhook_a vEnableIn vEnableInArray(9)
  --vhook_a vEnableOut vEnableOutArray(9)
  --vhook_a vEnableClear vEnableClearArray(9)
  --vhook_a vStreamStateEnableIn vStreamStateEnableInArray(9)
  --vhook_a vStreamStateEnableOut vStreamStateEnableOutArray(9)
  --vhook_a vStreamStateEnableClear vStreamStateEnableClearArray(9)
  --vhook_a vStreamStateOut vStreamStateOutArray(9)
  --vhook_a dStreamStateEnableIn dStreamStateEnableInArray(9)
  --vhook_a dStreamStateEnableOut dStreamStateEnableOutArray(9)
  --vhook_a dStreamStateEnableClear dStreamStateEnableClearArray(9)
  --vhook_a dStreamStateOut dStreamStateOutArray(9)
  --vhook_a dStartRequestEnableIn dStartRequestEnableInArray(9)
  --vhook_a dStartRequestEnableOut dStartRequestEnableOutArray(9)
  --vhook_a dStartRequestEnableClear dStartRequestEnableClearArray(9)
  --vhook_a dStopRequestEnableIn dStopRequestEnableInArray(9)
  --vhook_a dStopRequestEnableOut dStopRequestEnableOutArray(9)
  --vhook_a dStopRequestEnableClear dStopRequestEnableClearArray(9)
  --vhook_a dStopWithFlushRequestEnableIn dStopWithFlushRequestEnableInArray(9)
  --vhook_a dStopWithFlushRequestEnableOut dStopWithFlushRequestEnableOutArray(9)
  --vhook_a dStopWithFlushRequestEnableClear dStopWithFlushRequestEnableClearArray(9)
  --vhook_a dStopWithFlushRequestTimedOut dStopWithFlushRequestTimedOutArray(9)
  --vhook_a dStopWithFlushRequestTimeout dStopWithFlushRequestTimeoutArray(9)
  --vhook_a bIrq bIrqArray(9)
  DUT9: entity work.DmaPortCommIfcInputWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepthArray(9),
      kDataWidth            => kDataWidthArray(9),
      kBaseOffset           => kBaseOffsetArray(9),
      kScl                  => false,
      kCountScl             => kCountSclArray(9),
      kSignExtend           => false,
      kStreamNumber         => 9,
      kEvictionTimeout      => kEvictionTimeoutArray(9),
      kPeerToPeerStream     => kPeerToPeerArray(9),
      kFxpType              => kFxpTypeArray(9),
      kDisableOnFifoTimeout => kDisableOnFifoTimeoutArray(9),
      kViClkIsDefaultClk    => kViClkIsDefaultClk)
    port map (
      aReset                           => aReset,
      bReset                           => bReset,
      BusClk                           => Clk,
      ViClk                            => ViClk,
      DefaultClk                       => DefaultClk,
      bNiDmaInputRequestToDma          => bNiDmaInputRequestToDmaArray(9),
      bNiDmaInputRequestFromDma        => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma             => bNiDmaInputDataToDmaArray(9),
      bNiDmaInputDataFromDma           => bNiDmaInputDataFromDmaArray(9),
      bNiDmaInputStatusFromDma         => bNiDmaInputStatusFromDma,
      bArbiterNormalReq                => bArbiterNormalReqArray(9),
      bArbiterEmergencyReq             => bArbiterEmergencyReqArray(9),
      bArbiterDone                     => bArbiterDoneArray(9),
      bArbiterGrant                    => bArbiterGrantArray(9),
      bRegPortIn                       => bRegPortIn,
      bRegPortOut                      => bRegPortOutArray(9),
      vDataIn                          => vDataInArray(9)(kDataWidthArray(9)-1 downto 0),
      vFull                            => vFullArray(9),
      vTimeout                         => vTimeoutArray(9),
      vEnableIn                        => vEnableInArray(9),
      vEnableOut                       => vEnableOutArray(9),
      vEnableClear                     => vEnableClearArray(9),
      vCtCount                         => vCtCountArray(9),
      vCtEnableIn                      => vCtEnableInArray(9),
      vCtEnableOut                     => vCtEnableOutArray(9),
      vCtEnableOutClear                => vCtEnableOutClearArray(9),
      vStreamStateEnableIn             => vStreamStateEnableInArray(9),
      vStreamStateEnableOut            => vStreamStateEnableOutArray(9),
      vStreamStateEnableClear          => vStreamStateEnableClearArray(9),
      vStreamStateOut                  => vStreamStateOutArray(9),
      dStreamStateEnableIn             => dStreamStateEnableInArray(9),
      dStreamStateEnableOut            => dStreamStateEnableOutArray(9),
      dStreamStateEnableClear          => dStreamStateEnableClearArray(9),
      dStreamStateOut                  => dStreamStateOutArray(9),
      dStartRequestEnableIn            => dStartRequestEnableInArray(9),
      dStartRequestEnableOut           => dStartRequestEnableOutArray(9),
      dStartRequestEnableClear         => dStartRequestEnableClearArray(9),
      dStopRequestEnableIn             => dStopRequestEnableInArray(9),
      dStopRequestEnableOut            => dStopRequestEnableOutArray(9),
      dStopRequestEnableClear          => dStopRequestEnableClearArray(9),
      dStopWithFlushRequestEnableIn    => dStopWithFlushRequestEnableInArray(9),
      dStopWithFlushRequestEnableOut   => dStopWithFlushRequestEnableOutArray(9),
      dStopWithFlushRequestEnableClear => dStopWithFlushRequestEnableClearArray(9),
      dStopWithFlushRequestTimedOut    => dStopWithFlushRequestTimedOutArray(9),
      dStopWithFlushRequestTimeout     => dStopWithFlushRequestTimeoutArray(9),
      dCurrentStreamState              => dCurrentStreamState,
      bIrq                             => bIrqArray(9));



  -- The NiDmaInputRequestToDma we want is the bitwise OR of all the
  -- NiDmaInputRequestToDmaArray outputs from all the DUTs
  InputRequestToDmaOr: process(bNiDmaInputRequestToDmaArray)

    variable RequestVar : boolean;
    variable SpaceVar : NiDmaSpace_t;
    variable ChannelVar : NiDmaGeneralChannel_t;
    variable AddressVar : NiDmaAddress_t;
    variable BaggageVar : NiDmaBaggage_t;
    variable ByteSwapVar : NiDmaByteSwap_t;
    variable ByteLanevar : NiDmaByteLane_t;
    variable ByteCountVar : NiDmaInputByteCount_t;
    variable DoneVar : boolean;
    variable EndOfRecordVar : boolean;

  begin

    RequestVar := false;
    SpaceVar := kNiDmaSpaceStream;
    ChannelVar := (others => '0');
    AddressVar := (others => '0');
    BaggageVar := (others => '0');
    ByteSwapVar := (others => '0');
    ByteLaneVar := (others => '0');
    ByteCountVar := (others => '0');
    DoneVar := false;
    EndOfRecordVar := false;

    for i in 0 to kNumberOfDUTs-1 loop
      RequestVar := RequestVar or bNiDmaInputRequestToDmaArray(i).Request;
      ChannelVar := ChannelVar or bNiDmaInputRequestToDmaArray(i).Channel;
      ByteSwapVar := ByteSwapVar or bNiDmaInputRequestToDmaArray(i).ByteSwap;
      ByteLaneVar := ByteLaneVar or bNiDmaInputRequestToDmaArray(i).ByteLane;
      ByteCountVar := ByteCountVar or bNiDmaInputRequestToDmaArray(i).ByteCount;
      DoneVar := DoneVar or bNiDmaInputRequestToDmaArray(i).Done;
      EndOfRecordVar := EndOfRecordVar or bNiDmaInputRequestToDmaArray(i).EndOfRecord;

    end loop;

    bNiDmaInputRequestToDma.Request <= RequestVar;
    bNiDmaInputRequestToDma.Space <= SpaceVar;
    bNiDmaInputRequestToDma.Channel <= ChannelVar;
    bNiDmaInputRequestToDma.Address <= AddressVar;
    bNiDmaInputRequestToDma.Baggage <= BaggageVar;
    bNiDmaInputRequestToDma.ByteSwap <= ByteSwapVar;
    bNiDmaInputRequestToDma.ByteLane <= ByteLaneVar;
    bNiDmaInputRequestToDma.ByteCount <= ByteCountVar;
    bNiDmaInputRequestToDma.Done <= DoneVar;
    bNiDmaInputRequestToDma.EndOfRecord <= EndOfRecordVar;

  end process InputRequestToDmaOr;

  InputDataToDmaOr: process(bNiDmaInputDataToDmaArray)
    variable DataVar: NiDmaData_t;
  begin
    DataVar := (others => '0');

    for i in 0 to kNumberOfDUTs-1 loop
      DataVar := DataVar or bNiDmaInputDataToDmaArray(i).Data;
    end loop;

    bNiDmaInputDataToDmaLcl.Data <= DataVar;

  end process InputDataToDmaOr;

  bNiDmaInputDataToDma <= bNiDmaInputDataToDmaLcl;


  InputDataFromDmaDemux: process (bNiDmaInputDataFromDma)
  begin

    for i in 0 to kNumberOfDUTs-1 loop
      bNiDmaInputDataFromDmaArray(i) <= kNiDmaInputDataFromDmaZero;
    end loop;

    bNiDmaInputDataFromDmaArray(to_integer(bNiDmaInputDataFromDma.Channel)) <=
      bNiDmaInputDataFromDma;

  end process InputDataFromDmaDemux;


  -- For the RegPortOut signals coming from the DUT, when want to bitwise
  -- or these signals.  The exception is the ready signal, which should be
  -- an AND.
  RegPortOutOr: process(bRegPortOutArray)
    variable readyVar : boolean;
    variable dataValidVar : boolean;
    variable dataVar : std_logic_vector(31 downto 0);
  begin

    readyVar := true;
    dataValidVar := false;
    dataVar := (others=>'0');

    for i in 0 to kNumberOfDUTs-1 loop
      readyVar := readyVar and bRegPortOutArray(i).Ready;
      dataValidVar := dataValidVar or bRegPortOutArray(i).DataValid;
      dataVar := dataVar or bRegPortOutArray(i).Data;
    end loop;

    bRegPortOut.Ready <= readyVar;
    bRegPortOut.DataValid <= dataValidVar;
    bRegPortOut.Data <= dataVar;

  end process RegPortOutOr;


  -- On the rising edge of the bus clock, there should only be one reg port
  -- signal transmitting and only one inputTx signal transmitting.  These
  -- signals are bitwise OR'd, so they must transmit zeros when they are not
  -- transmitting.
  CheckRespondingPorts: process(Clk)
    variable numRegPortResponding : integer;
    variable numInputRequestResponding : integer;
    variable numInputDataResponding : integer;
  begin

    if rising_edge(Clk) and not aReset then

      numRegPortResponding := 0;
      numInputRequestResponding := 0;
      numInputDataResponding := 0;

      for i in 0 to kNumberOfDUTs-1 loop
        if bRegPortOutArray(i).DataValid then
          if bRegPortOutArray(i).Data /= Zeros(bRegPortOutArray(i).Data'length) then
            numRegPortResponding := numRegPortResponding + 1;
          end if;
        end if;

        if(bNiDmaInputDataToDmaArray(i).Data /= Zeros(bNiDmaInputDataToDma.Data'length)) then
          numInputDataResponding := numInputDataResponding + 1;
        end if;

        if bNiDmaInputRequestToDmaArray(i).Request = true then
          numInputRequestResponding := numInputRequestResponding + 1;

          assert(bArbiterGrantArray(i) = '1')
            report "Stream " & Image(i) & " transmitting on the bus when " &
                  "arbiter grant has not been given."
            severity error;

        end if;
      end loop;

      assert(numRegPortResponding < 2)
        report "There are more than 1 RegPortOut signals responding."
        severity error;

      assert(numInputRequestResponding < 2)
        report "There are more than 1 InputRequest signals responding."
        severity error;

      assert(numInputDataResponding < 2)
        report "There are more than 1 InputData signals responding."
        severity error;

    end if;

  end process CheckRespondingPorts;

  -- Continually poll the empty counts so that they can be queried within the
  -- testbench.
  PollEmptyCounts: for i in 0 to kNumberOfDUTs-1 generate

    process
    begin

      if aReset then
        wait until not aReset;
      end if;

      vCtEnableInArray(i) <= '0';
      vCtEnableOutClearArray(i) <= '0';

      if not kCountSclArray(i) then

        -- Strobe the enable in.
        wait until falling_edge(Clk) or aReset;
        vCtEnableInArray(i) <= '1';
        wait until falling_edge(Clk) or aReset;
        vCtEnableInArray(i) <= '0';

        -- Wait for enable out.
        if not vCtEnableOutArray(i) = '1' then
          wait until (falling_edge(Clk) and vCtEnableOutArray(i) = '1') or aReset;
        end if;
        vEmptyCountArray(i) <= vCtCountArray(i);
        vCtEnableOutClearArray(i) <= '1';

        wait until rising_edge(Clk) or aReset;
        wait for 1 ns;
        vCtEnableOutClearArray(i) <= '0';

      else

        -- Strobe the enable in.
        wait until rising_edge(Clk) or aReset;
        wait for 1 ns;
        vCtEnableInArray(i) <= '1';
        wait until falling_edge(Clk) or aReset;
        assert (vCtEnableOutArray(i) = '1') or aReset
          report "vEnableOut not asserting for query count in SCL."
          severity error;
        vEmptyCountArray(i) <= vCtCountArray(i);

      end if;

    end process;

  end generate PollEmptyCounts;

  TimeoutCountTracker: process(aReset, Clk)
  begin
    if aReset then
      bTimeoutCount <= 0;
    elsif rising_edge(Clk) then
      if bResetTimeoutCount then
        bTimeoutCount <= 0;
      else
        bTimeoutCount <= bTimeoutCount + 1;
      end if;
    end if;
  end process TimeoutCountTracker;


  MainTestProc: process

    variable readValue : std_logic_vector(31 downto 0);
    variable AlignmentSize : NaturalArray_t;

    -------------------------------------------------------------------------------------
    -- ResetDuts
    --
    -- Performs an asynchronous reset of all DUTs.
    -------------------------------------------------------------------------------------
    procedure ResetDuts is
    begin

      aReset <= true;
      ClkWait(1);
      aReset <= false;

      for i in AlignmentSize'range loop
        AlignmentSize(i) := kNiDmaInputMaxTransfer;
      end loop;

    end procedure ResetDuts;

    -------------------------------------------------------------------------------------
    -- CheckInputRequestToDmaSignals
    --
    -- Make sure that the input signals from the DUTs match the expected signal and
    -- throw an error if they don't.
    -------------------------------------------------------------------------------------
    procedure CheckInputRequestToDmaSignals(
      NiDmaInputRequestToDma : NiDmaInputRequestToDma_t
    ) is
    begin

      assert(bNiDmaInputRequestToDma.Request = NiDmaInputRequestToDma.Request)
        report "NiDmaInputRequestToDma.Request has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.Space = NiDmaInputRequestToDma.Space)
        report "NiDmaInputRequestToDma.Space has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.Address = NiDmaInputRequestToDma.Address)
        report "NiDmaInputRequestToDma.Address has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.Baggage = NiDmaInputRequestToDma.Baggage)
        report "NiDmaInputRequestToDma.Baggage has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.ByteSwap = NiDmaInputRequestToDma.ByteSwap)
        report "NiDmaInputRequestToDma.ByteSwap has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.ByteLane = NiDmaInputRequestToDma.ByteLane)
        report "NiDmaInputRequestToDma.ByteLane has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.ByteCount = NiDmaInputRequestToDma.ByteCount)
        report "NiDmaInputRequestToDma.ByteCount has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.Done = NiDmaInputRequestToDma.Done)
        report "NiDmaInputRequestToDma.Done has an incorrect value."
        severity error;
      assert(bNiDmaInputRequestToDma.EndOfRecord = NiDmaInputRequestToDma.EndOfRecord)
        report "NiDmaInputRequestToDma.EndOfRecord has an incorrect value."
        severity error;

    end procedure CheckInputRequestToDmaSignals;

    -------------------------------------------------------------------------------------
    -- CheckInputDataToDmaSignals
    --
    -- Make sure that the input signals from the DUTs match the expected signal and
    -- throw an error if they don't.
    -------------------------------------------------------------------------------------
    procedure CheckInputDataToDmaSignals(
      Data : integer

    ) is
    begin

      assert(bNiDmaInputDataToDmaLcl.Data = std_logic_vector(to_unsigned
                                        (Data,bNiDmaInputDataToDmaLcl.Data'length)))
        report "NiDmaInputDataToDma.Data has an incorrect value."
        severity error;

    end procedure CheckInputDataToDmaSignals;

    -------------------------------------------------------------------------------------
    -- CheckArbiterSignals
    --
    -- Make sure that the arbiter request and done signals from the DUTs are the
    -- expected value and throw an error if they aren't.
    -------------------------------------------------------------------------------------
    procedure CheckArbiterSignals(
      ArbiterNormalReq : std_logic := '0';
      ArbiterEmergencyReq : std_logic := '0';
      ArbiterDone : boolean := false;
      Stream : natural
    ) is
    begin

      assert(bArbiterNormalReqArray(Stream) = ArbiterNormalReq)
        report "ArbiterNormalReq has an incorrect value."
        severity error;
      assert(bArbiterEmergencyReqArray(Stream) = ArbiterEmergencyReq)
        report "ArbiterEmergencyReq has an incorrect value."
        severity error;
      assert(bArbiterDoneArray(Stream) = ArbiterDone)
        report "ArbiterDone has an incorrect value."
        severity error;

    end procedure CheckArbiterSignals;

    -------------------------------------------------------------------------------------
    -- CheckArbiterSignals
    --
    -- Determine what the expected behavior for the signals from the DUT to the arbiter
    -- should be based on the FIFO full count, SATCR value, max packet size, and FIFO
    -- depth.  Then verify that the arbiter signals match the value and throw an error
    -- if they don't.
    -------------------------------------------------------------------------------------
    procedure CheckArbiterSignals(
      FifoFullCountInSamples : natural;
      SatcrValue : natural;
      MaxPacketSize : natural;
      FifoDepth : positive;
      WaitCycles : natural;
      Disabled : boolean;
      StreamNumber : natural
    ) is
      constant kDataWidth : natural := kFifoDataWidthArray(StreamNumber);
      constant kSampleMultiply : natural := 2**(6-Log2(kDataWidth));
    begin

      if(Disabled) then
        assert(bArbiterNormalReqArray(StreamNumber) = '0')
          report "Arbiter normal req signal is asserting inappropriately."
          severity error;
        assert(bArbiterEmergencyReqArray(StreamNumber) = '0')
          report "Arbiter emergency req signal is asserting inappropriately."
          severity error;
      elsif(SatcrValue > 0) then
        if(FifoFullCountInSamples > 0 and WaitCycles >=
           kEvictionTimeoutArray(StreamNumber)) then
          assert(bArbiterEmergencyReqArray(StreamNumber) = '1')
            report "Arbiter emergency req not asserting on eviction timeout"
            severity error;
        elsif(FifoFullCountInSamples >= (FIFODepth+1)*kSampleMultiply/2) then
          assert(bArbiterEmergencyReqArray(StreamNumber) = '1')
            report "Arbiter emergency req signal is not asserting when required."
            severity error;
        elsif(FifoFullCountInSamples >= (FIFODepth+1)*kSampleMultiply/4 or
              FifoFullCountInSamples >= MaxPacketSize/kDataWidth*8 or
              FifoFullCountInSamples >= SatcrValue/kDataWidth*8) then
          assert(bArbiterNormalReqArray(StreamNumber) = '1')
            report "Arbiter normal req signal is not requesting when required."
            severity error;
          assert(bArbiterEmergencyReqArray(StreamNumber) = '0')
            report "Arbiter emergency req signal is asserting inappropriately."
            severity error;
        else
          assert(bArbiterNormalReqArray(StreamNumber) = '0')
            report "Arbiter normal req signal is asserting inappropriately."
            severity error;
          assert(bArbiterEmergencyReqArray(StreamNumber) = '0')
            report "Arbiter emergency req signal is asserting inappropriately."
            severity error;
        end if;
      else
        assert(bArbiterNormalReqArray(StreamNumber) = '0')
          report "Arbiter normal req signal is asserting inappropriately."
          severity error;
        assert(bArbiterEmergencyReqArray(StreamNumber) = '0')
          report "Arbiter emergency req signal is asserting inappropriately."
          severity error;
      end if;

    end procedure CheckArbiterSignals;


    -------------------------------------------------------------------------------------
    -- CheckRegPortSignals
    --
    -- Make sure that the register port signals from the DUT are responding as
    -- expected and throw an error if not.
    -------------------------------------------------------------------------------------
    procedure CheckRegPortSignals(
      Data : std_logic_vector(31 downto 0) := (others => '0');
      DataValid : boolean;
      Ready : boolean := true
    ) is
    begin

      assert(bRegPortOut.Data = Data)
        report "RegPortOut.Data has an incorrect value."
        severity error;
      assert(bRegPortOut.DataValid = DataValid)
        report "RegPortOut.DataValid has an incorrect value."
        severity error;
      assert(bRegPortOut.Ready = Ready)
        report "RegPortOut.Ready has an incorrect value."
        severity error;

    end procedure CheckRegPortSignals;

    -------------------------------------------------------------------------------------
    -- CheckRegPortSignals
    --
    -- Make sure that the register port signals from the DUT are responding as
    -- expected and throw an error if not.
    -------------------------------------------------------------------------------------
    procedure CheckRegPortSignals(
      Data : integer;
      DataValid : boolean;
      Ready : boolean := true
    ) is
    begin
      CheckRegPortSignals(Data=>std_logic_vector(to_unsigned(Data,32)),
        DataValid=>DataValid,Ready=>Ready);
    end procedure CheckRegPortSignals;


    -------------------------------------------------------------------------------------
    -- CheckIrqSignals
    --
    -- Make sure that the IRQ signals for the specified stream match the expected
    -- values.
    -------------------------------------------------------------------------------------
    procedure CheckIrqSignals(
      Status : std_logic;
      Stream : natural
    ) is
    begin

      assert bIrqArray(Stream).Status = Status
        report "Expected IRQ status for stream " & Image(Stream) & " is " &
               Image(to_boolean(Status)) & " but actual value is " &
               Image(to_boolean(bIrqArray(Stream).Status))
        severity error;

    end procedure CheckIrqSignals;


    -------------------------------------------------------------------------------------
    -- CheckViSignals
    --
    -- Make sure that the signals going from the DUT to the VI match the expected values
    -- and throw an error if not.  Pass an 'X' for any signals where the value does not
    -- matter.
    -------------------------------------------------------------------------------------
    procedure CheckViSignals(
      Full : std_logic := 'X';
      EnableOut : std_logic := 'X';
      StartRequestEnableOut : std_logic := 'X';
      StopRequestEnableOut : std_logic := 'X';
      StopWithFlushRequestEnableOut : std_logic := 'X';
      dClkStreamStateEnableOut : std_logic := 'X';
      vClkStreamStateEnableOut : std_logic := 'X';
      Stream : natural
    ) is
    begin

      assert(Full = 'X' or vFullArray(Stream) = Full)
        report "Full has an incorrect value for stream " & Image(Stream) & "."
        severity error;
      assert(EnableOut = 'X' or vEnableOutArray(Stream) = EnableOut)
        report "EnableOut has an incorrect value for stream " & Image(Stream) & "."
        severity error;
      assert(StartRequestEnableOut = 'X' or dStartRequestEnableOutArray(Stream)
             = StartRequestEnableOut)
        report "dStartRequestEnableOut has an incorrect value for stream " &
               Image(Stream) & "."
        severity error;
      assert(StopRequestEnableOut = 'X' or dStopRequestEnableOutArray(Stream)
             = StopRequestEnableOut)
        report "dStopRequestEnableOut has an incorrect value for stream " &
               Image(Stream) & "."
        severity error;
      assert(StopWithFlushRequestEnableOut = 'X' or
             dStopWithFlushRequestEnableOutArray(Stream) = StopWithFlushRequestEnableOut)
        report "dStopWithFlushRequestEnableOut has an incorrect value for stream " &
               Image(Stream) & "."
        severity error;
      assert(dClkStreamStateEnableOut = 'X' or
             dStreamStateEnableOutArray(Stream) = dClkStreamStateEnableOut)
        report "dStreamStateEnableOut has an incorrect value for stream " &
               Image(Stream) & "."
        severity error;
      assert(vClkStreamStateEnableOut = 'X' or
             vStreamStateEnableOutArray(Stream) = vClkStreamStateEnableOut)
        report "vStreamStateEnableOut has an incorrect value for stream " &
               Image(Stream) & "."
        severity error;


    end procedure CheckViSignals;


    ---------------------------------------------------------------------------
    -- CheckDefaultClkStreamState
    --
    -- Checks the VI stream state from the DefaultClk domain.
    ---------------------------------------------------------------------------
    procedure CheckDefaultClkStreamState(
      Stream : natural;
      State : StreamState_t
    ) is
    begin

      -- Strobe enable in.
      dStreamStateEnableInArray(Stream) <= '1';

      wait until falling_edge(DefaultClk) and dStreamStateEnableOutArray(Stream) = '1';

      -- Check the stream state.
      assert to_StreamState(dStreamStateOutArray(Stream)) = State
        report "Expected DefaultClk stream state was " &
          Image(to_StreamStateValue(State)) & " but actual state was " &
          Image(dStreamStateOutArray(Stream))
        severity error;

      -- Strobe enable clear.
      dStreamStateEnableInArray(Stream) <= '0';
      dStreamStateEnableClearArray(Stream) <= '1';

      -- Wait for the next DefaultClk falling edge to reset enable clear.
      wait until falling_edge(DefaultClk);

      dStreamStateEnableClearArray(Stream) <= '0';

    end procedure CheckDefaultClkStreamState;


    ---------------------------------------------------------------------------
    -- WaitOnDefaultClkStreamState
    --
    -- Checks the VI stream state from the DefaultClk domain until it reaches
    -- the desired state.
    ---------------------------------------------------------------------------
    procedure WaitOnDefaultClkStreamState(
      Stream : natural;
      State : StreamState_t
    ) is
      constant kMaxSanityCount : natural := 10;
      variable StateAttained : boolean := false;
      variable SanityCount : natural := 0;
    begin

      while not StateAttained and SanityCount < kMaxSanityCount loop

        -- Strobe enable in.
        dStreamStateEnableInArray(Stream) <= '1';

        wait until falling_edge(DefaultClk) and dStreamStateEnableOutArray(Stream) = '1';

        -- Check the stream state.
        StateAttained := to_StreamState(dStreamStateOutArray(Stream)) = State;

        -- Strobe enable clear.
        dStreamStateEnableInArray(Stream) <= '0';
        dStreamStateEnableClearArray(Stream) <= '1';

        -- Wait for the next DefaultClk falling edge to reset enable clear.
        wait until falling_edge(DefaultClk);

        dStreamStateEnableClearArray(Stream) <= '0';

        SanityCount := SanityCount + 1;

      end loop;

      assert StateAttained
        report "Timeout while waiting for state " & Image(to_StreamStateValue(State)) &
               " on stream " & Image(Stream)
        severity error;

    end procedure WaitOnDefaultClkStreamState;


    ---------------------------------------------------------------------------
    -- CheckViClkStreamState
    --
    -- Checks the VI stream state from the ViClk domain.
    ---------------------------------------------------------------------------
    procedure CheckViClkStreamState(
      Stream : natural;
      State : StreamState_t
    ) is
    begin

      -- Strobe enable in.
      vStreamStateEnableInArray(Stream) <= '1';

      wait until falling_edge(VIClk) and vStreamStateEnableOutArray(Stream) = '1';

      -- Check the stream state.
      assert to_StreamState(vStreamStateOutArray(Stream)) = State
        report "Expected ViClk stream state was " &
          Image(to_StreamStateValue(State)) & " but actual state was " &
          Image(vStreamStateOutArray(Stream))
        severity error;

      -- Strobe enable clear.
      vStreamStateEnableInArray(Stream) <= '0';
      vStreamStateEnableClearArray(Stream) <= '1';

      -- Wait for the next DefaultClk falling edge to reset enable clear.
      wait until falling_edge(ViClk);

      vStreamStateEnableClearArray(Stream) <= '0';

    end procedure CheckViClkStreamState;


    ---------------------------------------------------------------------------
    -- WaitOnViClkStreamState
    --
    -- Checks the VI stream state from the ViClk domain until it reaches
    -- the desired state.
    ---------------------------------------------------------------------------
    procedure WaitOnViClkStreamState(
      Stream : natural;
      State : StreamState_t
    ) is
      constant kMaxSanityCount : natural := 10;
      variable StateAttained : boolean := false;
      variable SanityCount : natural := 0;
    begin

      while not StateAttained and SanityCount < kMaxSanityCount loop

        -- Strobe enable in.
        vStreamStateEnableInArray(Stream) <= '1';

        wait until falling_edge(VIClk) and vStreamStateEnableOutArray(Stream) = '1';

        -- Check the stream state.
        StateAttained := to_StreamState(vStreamStateOutArray(Stream)) = State;

        -- Strobe enable clear.
        vStreamStateEnableInArray(Stream) <= '0';
        vStreamStateEnableClearArray(Stream) <= '1';

        -- Wait for the next DefaultClk falling edge to reset enable clear.
        wait until falling_edge(VIClk);

        vStreamStateEnableClearArray(Stream) <= '0';

        SanityCount := SanityCount + 1;

      end loop;

      assert StateAttained
        report "Timeout while waiting for state " & Image(to_StreamStateValue(State)) &
               " on stream " & Image(Stream)
        severity error;

    end procedure WaitOnViClkStreamState;


    ---------------------------------------------------------------------------
    -- CheckDiagramStreamState
    --
    -- Checks the VI stream state from the DefaultClk domain and ViClk domain
    -- ports.
    ---------------------------------------------------------------------------
    procedure CheckDiagramStreamState(
      Stream : natural;
      State : StreamState_t
    ) is
    begin

      CheckDefaultClkStreamState(Stream, State);
      CheckViClkStreamState(Stream, State);

    end procedure CheckDiagramStreamState;


    ---------------------------------------------------------------------------
    -- WaitOnDiagramStreamState
    --
    -- Checks the VI stream state from the DefaultClk domain and ViClk domain
    -- ports until it reaches the desired state.
    ---------------------------------------------------------------------------
    procedure WaitOnDiagramStreamState(
      Stream : natural;
      State : StreamState_t
    ) is
    begin

      WaitOnDefaultClkStreamState(Stream, State);
      WaitOnViClkStreamState(Stream, State);

    end procedure WaitOnDiagramStreamState;



    ---------------------------------------------------------------------------
    -- RegisterWrite
    --
    -- Perform a register write with the specified data and address.
    ---------------------------------------------------------------------------
    procedure RegisterWrite(
      Value : std_logic_vector(31 downto 0);
      Address : std_logic_vector(31 downto 0)
    ) is
    begin

      wait until falling_edge(Clk);

      -- Wait until register port is ready
      while not bRegPortOut.Ready loop
        wait until falling_edge(Clk);
      end loop;

      -- Set the write, address, and data lines
      bRegPortIn.Wt <= true;
      bRegPortIn.Rd <= false;
      bRegPortIn.Data <= Value;
      bRegPortIn.Address <= resize(unsigned(Address(31 downto 2)),
        bRegPortIn.Address'length);

      -- Clock in the write
      ClkWait(1);

      bRegPortIn.Wt <= false;

    end procedure RegisterWrite;

    ---------------------------------------------------------------------------
    -- RegisterWrite
    --
    -- Perform a register write with the specified data and address.
    ---------------------------------------------------------------------------
    procedure RegisterWrite(
      Value : integer;
      Address : std_logic_vector(31 downto 0)
    ) is
    begin
      RegisterWrite(Value=>std_logic_vector(to_unsigned(Value,32)),
                    Address=>Address);
    end procedure RegisterWrite;

    ---------------------------------------------------------------------------
    -- RegisterWrite
    --
    -- Perform a register write with the specified data and address.
    ---------------------------------------------------------------------------
    procedure RegisterWrite(
      Value : integer;
      Address : natural
    ) is
    begin
      RegisterWrite(
        Value=>Value,
        Address=>std_logic_vector(to_unsigned(Address,32)));
    end procedure RegisterWrite;


    ---------------------------------------------------------------------------
    -- RegisterRead
    --
    -- Perform a register read at the selected address.  The data is returned
    -- in the readValue variable.
    ---------------------------------------------------------------------------
    procedure RegisterRead(
      Address : std_logic_vector(31 downto 0)
    ) is
    begin

      wait until falling_edge(Clk);

      -- Wait until register port is ready
      while not bRegPortOut.Ready loop
        wait until falling_edge(Clk);
      end loop;

      -- Set the read and address lines
      bRegPortIn.Wt <= false;
      bRegPortIn.Rd <= true;
      bRegPortIn.Address <= resize(unsigned(Address(31 downto 2)),
        bRegPortIn.Address'length);

      -- Clock in the read
      ClkWait(1);

      wait for 1 ns;

      bRegPortIn.Rd <= false;

      -- We should always get the read response on the clock cycle after the
      -- read is strobed.
      assert(bRegPortOut.DataValid = true)
        report "DataValid not true the clock cycle after a read strobe"
        severity error;

      readValue := bRegPortOut.Data;

    end procedure RegisterRead;

    ---------------------------------------------------------------------------
    -- RegisterRead
    --
    -- Perform a register read at the selected address.  The data is returned
    -- in the readValue variable.
    ---------------------------------------------------------------------------
    procedure RegisterRead(
      Address : natural
    ) is
    begin
      RegisterRead(std_logic_vector(to_unsigned(Address,32)));
    end procedure RegisterRead;


    ---------------------------------------------------------------------------
    -- PushPoint
    --
    -- Pushes the selected value into the FIFO for the selected stream number.
    ---------------------------------------------------------------------------
    procedure PushPoint(
      Value : std_logic_vector(63 downto 0);
      Stream : natural;
      ExpectTimeout : boolean := false
    ) is
    begin

      vDataInArray(Stream) <= Value;
      vEnableInArray(Stream) <= '1';

      wait until vEnableOutArray(Stream) = '1';

      wait until falling_edge(VIClk);

      -- Check whether or not we received a timeout.
      if ExpectTimeout then
        assert vFullArray(Stream) = '1'
          report "Timeout did not occur as expected for stream " & Image(Stream)
          severity error;
      else
        assert vFullArray(Stream) = '0'
          report "Timeout occurred unexpectedly for stream " & Image(Stream)
          severity error;
      end if;

      vEnableInArray(Stream) <= '0';
      vEnableClearArray(Stream) <= '1';

      -- Wait for the next VIClk to clock in enable clear
      wait until falling_edge(VIClk);

      vEnableClearArray(Stream) <= '0';

    end procedure PushPoint;

    ---------------------------------------------------------------------------
    -- PushPoint
    --
    -- Pushes the selected value into the FIFO for the selected stream number.
    ---------------------------------------------------------------------------
    procedure PushPoint(
      Value : integer;
      Stream : natural;
      ExpectTimeout : boolean := false
    ) is
    begin
      PushPoint(Value => std_logic_vector(to_unsigned(Value,64)),
                Stream=>Stream,
                ExpectTimeout=>ExpectTimeout);
    end procedure PushPoint;


    ---------------------------------------------------------------------------
    -- FillFifo
    --
    -- Pushes consecutive points from start value to end value into the FIFO
    -- for the selected DUT number.
    ---------------------------------------------------------------------------
    procedure FillFifo(
      StartValue : integer;
      EndValue : integer;
      Stream : natural) is
    begin
      for i in StartValue to EndValue loop
        PushPoint(i,Stream);
      end loop;

      -- Wait one more VI Clk so that the fifo full count has crossed clock
      -- domains
      wait until rising_edge(VIClk);
    end procedure FillFifo;


    ---------------------------------------------------------------------------
    -- ReceiveData
    --
    -- This function simply receives data from the specified stream until at
    -- least the desired amount of data has been received.  It does not check
    -- the data or verify that data is being sent correctly.  The actual
    -- amount of data received (in bytes) is returned.
    ---------------------------------------------------------------------------
    procedure ReceiveData (
      StreamNumber : natural;
      NumberOfBytes : natural
    ) is
      variable NumberOfReads : natural;
    begin

      -- We need to compute the number of transfers we have to do based on the
      -- number of bytes in the transfer and kNiDmaInputMaxTransfer
      if NumberOfBytes <= kNiDmaInputMaxTransfer then
        NumberOfReads := 1;
      elsif NumberOfBytes mod kNiDmaInputMaxTransfer = 0 then
        NumberOfReads := NumberOfBytes/kNiDmaInputMaxTransfer;
      else
        NumberOfReads := (NumberOfBytes/kNiDmaInputMaxTransfer) + 1;
      end if;
        NumOfReadsSig <= NumberOfReads;
       --vhook_nowarn NumOfReadsSig
      for i in 1 to NumberOfReads loop
        if (bArbiterNormalReqArray(StreamNumber) = '1'
          or bArbiterEmergencyReqArray(StreamNumber) = '1') then

          -- Assert the grant for data request
          bArbiterGrantArray(StreamNumber) <= '1';
        end if;

        wait until bRequestAcknowledge;
        bNiDmaInputRequestFromDma.Acknowledge <= true;

        wait until rising_edge(Clk);
        assert bArbiterDoneArray(StreamNumber)
          report "The Arbiter is not done with with accessing the Input Request bus"
          severity error;

        bArbiterGrantArray(StreamNumber) <= '0';
        bNiDmaInputRequestFromDma.Acknowledge <= false;

        wait until bNiDmaInputDataFromDma.TransferEnd;

        assert BytesReceivedSig = bLastNiDmaInputRequestToDma.ByteCount
          report "The number of bytes received in the current transfer is " &
                  Image(BytesReceivedSig) & LF &
                 "The expected number of bytes in the current transfer is " &
                  Image(to_integer(bLastNiDmaInputRequestToDma.ByteCount))
          severity error;

      end loop;

      wait until rising_edge(Clk);

    end ReceiveData;


    ---------------------------------------------------------------------------
    -- ResetDataCheck
    --
    -- Generates a strobe signal that reset the data generattion in the
    -- DataCheck process. This procedure needs to be called after ReceiveData
    -- procedure when all the data was read or the remaining data will be never read.
    ---------------------------------------------------------------------------
    procedure ResetDataCheck is
    begin

      ClkWait(2);
      wait until falling_edge(Clk);
      ReceiveDataDone <= true;
      wait until rising_edge(Clk);
      ReceiveDataDone <= false;

    end procedure ResetDataCheck;
    ---------------------------------------------------------------------------
    -- EnableStream
    --
    -- Set the enable bit for the specified stream and wait until the stream
    -- is enabled.
    ---------------------------------------------------------------------------
    procedure EnableStream(
      StreamNumber : natural)
    is

      constant kMaxSanityCount : natural := 200;
      variable SanityCount : natural;

    begin

      -- Set the enable bit.
      RegisterWrite(Value=>2**BitFieldIndex(StartChannel),
                    Address=>kBaseOffsetArray(StreamNumber) + OffsetValue(Control));

      -- Wait until the stream is enabled.  Use a sanity check to make sure we don't
      -- wait forever.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));

      SanityCount := 0;
      while readValue(BitFieldIndex(DisableStatus)) /= '0' and
            SanityCount < kMaxSanityCount loop
        RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
        SanityCount := SanityCount + 1;
      end loop;

      assert(readValue(BitFieldIndex(DisableStatus)) = '0')
        report "Stream did not enable after enable bit set."
        severity error;

    end procedure EnableStream;


    ---------------------------------------------------------------------------
    -- DisableStream
    --
    -- Set the disable bit for the specified stream, accept the done header,
    -- and wait until the stream is disabled.  This procedure should not be
    -- called while the stream is in the middle of sending data.  If the flush
    -- option is used, a flush and disable is performed in place of a disable.
    -- In this case, the expected amount of data will be flushed before
    -- checking for the done header.
    ---------------------------------------------------------------------------
    procedure DisableStream(
      StreamNumber              : natural;
      Flush                     : boolean := false;
      NumberOfDataBytesForFlush : natural := 0)
    is

      constant kMaxSanityCount : natural := 10;
      variable SanityCount : natural;

    begin

      -- Set the disable bit.
      if Flush then
        RegisterWrite(Value=>2**BitFieldIndex(StopChannelWithFlush),
                      Address=>kBaseOffsetArray(StreamNumber) + OffsetValue(Control));
        ReceiveData(StreamNumber => StreamNumber,
                    NumberOfBytes => NumberOfDataBytesForFlush);
        ResetDataCheck;
      else
        RegisterWrite(Value=>2**BitFieldIndex(StopChannel),
                      Address=>kBaseOffsetArray(StreamNumber) + OffsetValue(Control));
      end if;

      -- Wait for the done request.
      ClkWait(1);
      wait until falling_edge(Clk) and bArbiterEmergencyReqArray(StreamNumber) = '1';
      bArbiterGrantArray(StreamNumber) <= '1';

      wait until falling_edge(Clk);

    -- Check the done request
    CheckInputRequestToDmaSignals(NiDmaInputRequestToDma => kNiDmaInputRequestToDmaDone);

      -- Accept the Done word
      bNiDmaInputRequestFromDma.Acknowledge <= true;
      wait for 1 ns;
      assert(bArbiterDoneArray(StreamNumber))
        report "Arbiter done signal not going true"
        severity error;

      wait until falling_edge(Clk);

      bNiDmaInputRequestFromDma.Acknowledge <= false;
      bArbiterGrantArray(StreamNumber) <= '0';

      -- Wait until the stream is disabled.  Use a sanity check to make sure we don't
      -- wait forever.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));

      SanityCount := 0;
      while readValue(BitFieldIndex(DisableStatus)) /= '1' and
            SanityCount < kMaxSanityCount loop
        RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
        SanityCount := SanityCount + 1;
      end loop;

      assert(readValue(BitFieldIndex(DisableStatus)) = '1')
        report "Stream did not disable after disable bit set."
        severity error;

    end procedure DisableStream;


    ---------------------------------------------------------------------------
    -- StopStreamFromDiagram
    --
    -- Stop the stream from the diagram, accept the done header,
    -- and wait until the stream is disabled.  This procedure should not be
    -- called while the stream is in the middle of sending data.  If the flush
    -- option is used, a flush and disable is performed in place of a disable.
    -- In this case, the expected amount of data will be flushed before
    -- checking for the done header.
    ---------------------------------------------------------------------------
    procedure StopStreamFromDiagram(
      StreamNumber              : natural;
      Flush                     : boolean := false;
      NumberOfDataBytesForFlush : natural := 0;
      FlushTimeout              : integer := -1;
      DoFlushTimeout            : boolean := false)
    is

      constant kMaxSanityCount : natural := 10;
      variable SanityCount : natural;

    begin

      -- Make sure the IRQ line is false.
      CheckIrqSignals(Status => '0', Stream => StreamNumber);

      -- Set the disable bit.
      if Flush then

        -- Strobe enable in.
        dStopWithFlushRequestTimeoutArray(StreamNumber) <= to_signed(FlushTimeout,32);
        dStopWithFlushRequestEnableInArray(StreamNumber) <= '1';

        -- Receive the flush data unless we'd rather time out.
        if not DoFlushTimeout then
          ReceiveData(StreamNumber => StreamNumber,
                      NumberOfBytes => NumberOfDataBytesForFlush);
          ResetDataCheck;
        end if;

        -- Wait for the IRQ line to go high for the flushing IRQ.
        wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '1';

        -- Make sure the only interrupt is the flushing interrupt.
        RegisterRead(Address => kBaseOffsetArray(StreamNumber)+
                                OffsetValue(InterruptStatus));
        assert unsigned(readValue) = 2**BitFieldIndex(FlushingIrq)
          report "Flushing IRQ status bit is not set appropriately after flush."
          severity error;

        -- Clear the flushing interrupt.
        RegisterWrite(Value => 2**BitFieldIndex(FlushingIrq),
                      Address => kBaseOffsetArray(StreamNumber)+
                                 OffsetValue(InterruptStatus));

        -- Make sure the IRQ line clears.
        wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '0';

      else

        -- Strobe the enable in.
        dStopRequestEnableInArray(StreamNumber) <= '1';

      end if;

      -- The state in the default clock domain should change to the flushing state.
      WaitOnDefaultClkStreamState(StreamNumber, Flushing);

      -- Wait for the flush to timeout.
      if DoFlushTimeout then
        for i in 0 to FlushTimeout loop
          wait until rising_edge(DefaultClk);
          ClkWait(3);
        end loop;
      end if;

      -- Wait for the done header.
      ClkWait(1);
      wait until falling_edge(Clk) and bArbiterEmergencyReqArray(StreamNumber) = '1';
      bArbiterGrantArray(StreamNumber) <= '1';

      wait until falling_edge(Clk);

      -- Check the Done Request
      CheckInputRequestToDmaSignals(
        NiDmaInputRequestToDma => kNiDmaInputRequestToDmaDone);

      -- Accept the Done Packet
      bNiDmaInputRequestFromDma.Acknowledge <= true;
      wait for 1 ns;
      assert(bArbiterDoneArray(StreamNumber))
        report "Arbiter done signal not going true"
        severity error;

      wait until falling_edge(Clk);

      bNiDmaInputRequestFromDma.Acknowledge <= false;
      bArbiterGrantArray(StreamNumber) <= '0';

      if Flush then

        wait until falling_edge(DefaultClk) and
                   dStopWithFlushRequestEnableOutArray(StreamNumber) = '1';

        -- Make sure the timed out bit is set if a timeout was expected.
        if DoFlushTimeout then
          assert dStopWithFlushRequestTimedOutArray(StreamNumber)='1'
            report "Expected flush timeout but did not occur."
            severity error;
        else
          assert dStopWithFlushRequestTimedOutArray(StreamNumber)='0'
            report "Flush timeout occurred but was not expected."
            severity error;
        end if;

        -- Strobe enable clear.
        dStopWithFlushRequestEnableInArray(StreamNumber) <= '0';
        dStopWithFlushRequestEnableClearArray(StreamNumber) <= '1';

        -- Wait for the next DefaultClk falling edge to reset enable clear.
        wait until falling_edge(DefaultClk);

        dStopWithFlushRequestEnableClearArray(StreamNumber) <= '0';

        dStopWithFlushRequestTimeoutArray(StreamNumber) <= to_signed(-1,32);

      else

        wait until falling_edge(DefaultClk) and dStopRequestEnableOutArray(StreamNumber)
          = '1';

        -- Strobe enable clear.
        dStopRequestEnableInArray(StreamNumber) <= '0';
        dStopRequestEnableClearArray(StreamNumber) <= '1';

        -- Wait for the next DefaultClk falling edge to reset enable clear.
        wait until falling_edge(DefaultClk);

        dStopRequestEnableClearArray(StreamNumber) <= '0';

      end if;


      -- Wait until the stream is disabled.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));

      SanityCount := 0;
      while readValue(BitFieldIndex(DisableStatus)) /= '1' and
            SanityCount < kMaxSanityCount loop
        RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
        SanityCount := SanityCount + 1;
      end loop;

      assert(readValue(BitFieldIndex(DisableStatus)) = '1')
        report "Stream did not disable after disable bit set."
        severity error;

    end procedure StopStreamFromDiagram;


    ---------------------------------------------------------------------------
    -- CheckStreamState
    --
    -- Reads the stream state value and checks it against the expected value.
    ---------------------------------------------------------------------------
    procedure CheckStreamState (
      StreamNumber : natural;
      ExpectedState : StreamStateValue_t
    ) is
    begin

      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));

      assert(readValue(BitFieldIndex(State)+StreamStateValue_t'length-1 downto
             BitFieldIndex(State)) = ExpectedState)
        report "Stream state does not match expected stream state."
        severity error;

    end procedure CheckStreamState;

    ---------------------------------------------------------------------------
    -- CheckStreamState
    --
    -- Reads the stream state value and checks it against the expected value.
    ---------------------------------------------------------------------------
    procedure CheckStreamState (
      StreamNumber : natural;
      ExpectedState : StreamState_t
    ) is
      variable ExpectedStateValue : StreamStateValue_t;
    begin

      if ExpectedState = Unlinked then
        ExpectedStateValue := kStreamStateUnlinked;
      elsif ExpectedState = Disabled then
        ExpectedStateValue := kStreamStateDisabled;
      elsif ExpectedState = Enabled then
        ExpectedStateValue := kStreamStateEnabled;
      elsif ExpectedState = Flushing then
        ExpectedStateValue := kStreamStateFlushing;
      end if;

      CheckStreamState(
        StreamNumber => StreamNumber,
        ExpectedState => ExpectedStateValue);

    end procedure CheckStreamState;


    ---------------------------------------------------------------------------
    -- WaitOnStreamState
    --
    -- Waits until the stream state reaches the desired value.  Use a sanity
    -- counter so that the procedure doesn't wait forever for the state.
    ---------------------------------------------------------------------------
    procedure WaitOnStreamState (
      StreamNumber : natural;
      DesiredState : StreamStateValue_t
    ) is
      constant kMaxSanityCount : natural := 20;
      variable SanityCount : natural;
    begin

      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));

      SanityCount := 0;
      while readValue(BitFieldIndex(State)+StreamStateValue_t'length-1 downto
            BitFieldIndex(State)) /= DesiredState and
            SanityCount < kMaxSanityCount loop

        RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
        SanityCount := SanityCount + 1;

      end loop;

      assert(readValue(BitFieldIndex(State)+StreamStateValue_t'length-1 downto
             BitFieldIndex(State)) = DesiredState)
        report "Stream state does not match expected stream state."
        severity error;

    end procedure WaitOnStreamState;

    ---------------------------------------------------------------------------
    -- WaitOnStreamState
    --
    -- Waits until the stream state reaches the desired value.
    ---------------------------------------------------------------------------
    procedure WaitOnStreamState (
      StreamNumber : natural;
      DesiredState : StreamState_t
    ) is
      variable DesiredStateValue : StreamStateValue_t;
    begin

      if DesiredState = Unlinked then
        DesiredStateValue := kStreamStateUnlinked;
      elsif DesiredState = Disabled then
        DesiredStateValue := kStreamStateDisabled;
      elsif DesiredState = Enabled then
        DesiredStateValue := kStreamStateEnabled;
      elsif DesiredState = Flushing then
        DesiredStateValue := kStreamStateFlushing;
      end if;

      WaitOnStreamState(
        StreamNumber => StreamNumber,
        DesiredState => DesiredStateValue);

    end procedure WaitOnStreamState;


    ---------------------------------------------------------------------------
    -- StartStreamFromDiagram
    --
    -- Initiates a start stream request from the diagram and tests that the
    -- interrupt is set appropriately.
    ---------------------------------------------------------------------------
    procedure StartStreamFromDiagram(
      StreamNumber : natural;
      WriteSatcr   : boolean := false;
      SatcrValueInBytes : natural := 0
    ) is
    begin

      -- Strobe enable in.
      dStartRequestEnableInArray(StreamNumber) <= '1';

      -- Wait until the IRQ is asserted.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '1';

      -- Check that the IRQ is the Start Stream IRQ.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '1'
        report "Start stream IRQ bit not asserted after requesting stream start."
        severity error;

      -- Clear the start stream IRQ bit.
      RegisterWrite(Value=>2**BitFieldIndex(StartStreamIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptStatus));

      -- Wait until the IRQ is cleared.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '0';

      -- Make sure the start stream IRQ is cleared.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '0'
        report "Start stream IRQ bit not clearing."
        severity error;

      -- Enable the stream from the host.
      EnableStream(StreamNumber);

      -- Write the SATCR.
      if WriteSatcr then
        RegisterWrite(Value=> SatcrValueInBytes,
                      Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
      end if;

      wait until falling_edge(DefaultClk) and
        dStartRequestEnableOutArray(StreamNumber) = '1';

      -- Strobe enable clear.
      dStartRequestEnableInArray(StreamNumber) <= '0';
      dStartRequestEnableClearArray(StreamNumber) <= '1';

      -- Wait for the next DefaultClk falling edge to reset enable clear.
      wait until falling_edge(DefaultClk);

      dStartRequestEnableClearArray(StreamNumber) <= '0';

    end procedure StartStreamFromDiagram;


    ---------------------------------------------------------------------------
    -- DoStateTransitionTest
    --
    --
    ---------------------------------------------------------------------------
    procedure DoStateTransitionTest(
      StreamNumber : natural
    ) is

      constant kDataWidth : natural := kFifoDataWidthArray(StreamNumber);
      constant kFifoDepth : natural := kFIFODepthArray(StreamNumber);

    begin

      ResetDuts;

      -----------------------------------------------------------------------------------
      -- Test enable IRQ behavior.
      -----------------------------------------------------------------------------------

      TestStatus <= rs("Testing enable IRQ behavior.");
      wait for 0 ns;

      -- Enable the start stream IRQ mask.
      RegisterWrite(Value=>2**BitFieldIndex(EnableStartStreamIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptMask));

      -- Make sure we start up in the Unlinked state.
      CheckStreamState(StreamNumber, Unlinked);
      CheckDiagramStreamState(StreamNumber, Unlinked);

      -- Strobe enable in.
      wait until falling_edge(DefaultClk);
      dStartRequestEnableInArray(StreamNumber) <= '1';
      wait until rising_edge(DefaultClk);
      dStartRequestEnableInArray(StreamNumber) <= '0';

      -- Ensure that the IRQ does not get asserted.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '1' for 4 us;
      assert bIrqArray(StreamNumber).Status = '0'
        report "IRQ asserted incorrectly."
        severity error;

      -- Link the stream.
      RegisterWrite(Value => 2**BitFieldIndex(LinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Wait until the IRQ is asserted.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '1' for 4 us;
      assert bIrqArray(StreamNumber).Status = '1'
        report "IRQ not asserting correctly."
        severity error;

      -- Check that the IRQ is the Start Stream IRQ.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '1'
        report "Start stream IRQ bit not asserted after requesting stream start."
        severity error;

      -- Clear the start stream IRQ bit.
      RegisterWrite(Value=>2**BitFieldIndex(StartStreamIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptStatus));

      -- Wait until the IRQ is cleared.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '0';

      -- Make sure the start stream IRQ is cleared.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '0'
        report "Start stream IRQ bit not clearing."
        severity error;

      -- Wait for the state to transition to the Disabled state.
      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Try to enable the stream without writing the SATCR first.
      EnableStream(StreamNumber);

      -- Make sure it stays in the Disabled state.
      for i in 0 to 10 loop
        CheckStreamState(StreamNumber, Disabled);
        CheckDiagramStreamState(StreamNumber, Disabled);

        -- Make sure the empty count reads zero while the stream is disabled.
        assert vEmptyCountArray(StreamNumber) = to_unsigned(0,
          vEmptyCountArray(StreamNumber)'length)
          report "Empty count not reporting empty while disabled."
          severity error;

      end loop;

      -- Disable and unlink the stream.
      DisableStream(StreamNumber);
      RegisterWrite(Value => 2**BitFieldIndex(UnlinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Make sure the IRQ is not set.
      assert bIrqArray(StreamNumber).Status = '0'
        report "IRQ asserted incorrectly."
        severity error;

      -- Link the stream and make sure the IRQ sets.
      -- Wait until the IRQ is asserted.
      RegisterWrite(Value => 2**BitFieldIndex(LinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '1' for 4 us;
      assert bIrqArray(StreamNumber).Status = '1'
        report "IRQ not asserting correctly."
        severity error;

      -- Check that the IRQ is the Start Stream IRQ.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '1'
        report "Start stream IRQ bit not asserted after requesting stream start."
        severity error;

      -- Clear the start stream IRQ bit.
      RegisterWrite(Value=>2**BitFieldIndex(StartStreamIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptStatus));

      -- Wait until the IRQ is cleared.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '0';

      -- Make sure the start stream IRQ is cleared.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '0'
        report "Start stream IRQ bit not clearing."
        severity error;

      -- Unlink the stream.
      RegisterWrite(Value => 2**BitFieldIndex(UnlinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Reset the stream.
      ResetDuts;

      -----------------------------------------------------------------------------------
      -- Test state transitioning without flushing from host.
      -----------------------------------------------------------------------------------

      TestStatus <= rs("Testing host state transitioning without flushing.");
      wait for 0 ns;

      -- Make sure we start up in the Unlinked state
      CheckStreamState(StreamNumber, Unlinked);
      CheckDiagramStreamState(StreamNumber, Unlinked);

      -- Set the linked bit.
      RegisterWrite(Value => 2**BitFieldIndex(LinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Wait for the state to transition to the Disabled state.
      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Enable the overflow IRQ mask.
      RegisterWrite(Value=>2**BitFieldIndex(EnableOverflowIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptMask));

      -- Try to push a point and make sure it fails.
      PushPoint(
        Value => 55,
        Stream => 0,
        ExpectTimeout => true);

      -- Wait until the IRQ is asserted for overflow.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '1';

      -- Check that the IRQ is the overflow IRQ.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(OverflowIrq)) = '1'
        report "Overflow IRQ not asserting correctly."
        severity error;

      -- Clear the overflow IRQ bit.
      RegisterWrite(Value=>2**BitFieldIndex(OverflowIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptStatus));

      -- Wait until the IRQ is cleared.
      wait until falling_edge(Clk) and bIrqArray(StreamNumber).Status = '0';

      -- Make sure the overflow bit in the status register is set.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(OverflowStatus)) = '1'
        report "Overflow status not asserting correctly."
        severity error;

      -- Clear the overflow status bit.
      RegisterWrite(Value=>2**BitFieldIndex(ClearOverflowStatus),
                    Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Make sure the overflow status bit cleared.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(OverflowStatus)) = '0'
        report "Overflow status not clearing correctly."
        severity error;

      -- Make sure the start stream IRQ is cleared.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(InterruptStatus));
      assert readValue(BitFieldIndex(StartStreamIrq)) = '0'
        report "Start stream IRQ bit not clearing."
        severity error;

      -- Try to enable the stream without writing the SATCR first.
      EnableStream(StreamNumber);

      -- Make sure it stays in the Disabled state.
      for i in 0 to 10 loop
        CheckStreamState(StreamNumber, Disabled);
        CheckDiagramStreamState(StreamNumber, Disabled);
      end loop;

      -- Disable the stream, then set SATCR and enable it for real.
      DisableStream(StreamNumber);
      EnableStream(StreamNumber);
      RegisterWrite(Value=> kFifoDepth*kDataWidth/8,
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
      WaitOnStreamState(StreamNumber, Enabled);
      WaitOnDiagramStreamState(StreamNumber, Enabled);

      -- Fill the fifo.
      FillFifo(1,kFifoDepth,StreamNumber);

      -- Receive some of the data in the FIFO, but not all of it so that we can test
      -- stopping without flushing.
      ReceiveData(
        StreamNumber => StreamNumber,
        NumberOfBytes => 1*kDataWidth/8);

      ResetDataCheck;

      -- Do a stop without flush.
      DisableStream(StreamNumber);

      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Check that the flush and flush failed bits are not set.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingStatus)) = '0'
        report "Flushing status incorrectly set."
        severity error;
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingFailedStatus)) = '0'
        report "Flushing failed status incorrectly set."
        severity error;

      -- Reset the SATCR.
      RegisterWrite(Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control),
                    Value => 2**BitFieldIndex(ResetSatcr));


      -----------------------------------------------------------------------------------
      -- Test state transitioning with flushing from host.
      -----------------------------------------------------------------------------------

      TestStatus <= rs("Testing host state transitioning with flushing.");
      wait for 0 ns;

      -- Set SATCR and enable the stream.
      EnableStream(StreamNumber);
      RegisterWrite(Value=> ((kFifoDepth+1)*64/kDataWidth-1)*kDataWidth/8,
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
      WaitOnStreamState(StreamNumber, Enabled);
      WaitOnDiagramStreamState(StreamNumber, Enabled);

      -- Make sure the FIFO cleared.
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(FifoCount));
      assert unsigned(readValue) = 0
        report "FIFO count value is non-zero following an enable"
        severity error;

      -- Fill the fifo.
      FillFifo(1,(kFifoDepth+1)*64/kDataWidth-1,StreamNumber);

      -- Wait for the FIFO to fill.
      wait until falling_edge(ViClk) and vEmptyCountArray(StreamNumber) =
        to_unsigned(0, vEmptyCountArray(StreamNumber)'length) for 10*kViClkPeriod;
      assert vEmptyCountArray(StreamNumber) = to_unsigned(0,
        vEmptyCountArray(StreamNumber)'length)
        report "Empty count not reporting full following FIFO fill."
        severity error;

      -- Receive some of the data in the FIFO before we issue the flush.
      ReceiveData(StreamNumber  => StreamNumber,
                  NumberOfBytes => kNiDmaInputMaxTransfer);

      -- Do a stop with flush.
      DisableStream(StreamNumber              => StreamNumber,
                    Flush                     => true,
                    NumberOfDataBytesForFlush => (((kFifoDepth+1)*64/kDataWidth-1)*
                                                 kDataWidth/8) - kNiDmaInputMaxTransfer);

      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Check to make sure the FIFO is empty.
      RegisterRead(Address => kBaseOffsetArray(StreamNumber)+OffsetValue(FifoCount));
      assert to_integer(unsigned(readValue)) = 0
        report "FIFO count not empty after a flush."
        severity error;
      if kPeerToPeerArray(StreamNumber) then
        assert vEmptyCountArray(StreamNumber) =
               unsigned(Zeros(vEmptyCountArray(StreamNumber)'length))
          report "Empty count not reporting empty following flush."
          severity error;
      else
        assert vEmptyCountArray(StreamNumber) = to_unsigned((kFifoDepth+1)*64/
               kDataWidth-1,vEmptyCountArray(StreamNumber)'length)
          report "Empty count not reporting empty following flush."
          severity error;
      end if;

      -- Check that the flush bit is set and flush failed bit is not set.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingStatus)) = '1'
        report "Flushing status incorrectly set."
        severity error;
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingFailedStatus)) = '0'
        report "Flushing failed status incorrectly set."
        severity error;

      -- Unlink the stream.
      RegisterWrite(Value => 2**BitFieldIndex(UnlinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      WaitOnStreamState(StreamNumber, Unlinked);
      WaitOnDiagramStreamState(StreamNumber, Unlinked);


      -----------------------------------------------------------------------------------
      -- Test state transitioning without flushing from diagram.
      -----------------------------------------------------------------------------------

      TestStatus <= rs("Testing diagram state transitioning without flushing.");
      wait for 0 ns;

      -- Enable the start stream IRQ mask.
      RegisterWrite(Value=>2**BitFieldIndex(EnableStartStreamIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptMask));

      -- Enable the flushing IRQ mask.
      RegisterWrite(Value=>2**BitFieldIndex(EnableFlushingIrq),
                    Address=>kBaseOffsetArray(StreamNumber)+
                             OffsetValue(InterruptMask));

      -- Make sure we start up in the Unlinked state
      CheckStreamState(StreamNumber, Unlinked);
      CheckDiagramStreamState(StreamNumber, Unlinked);

      -- Set the linked bit.
      RegisterWrite(Value => 2**BitFieldIndex(LinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Wait for the state to transition to the Disabled state.
      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Try to enable the stream without writing the SATCR first.
      EnableStream(StreamNumber);

      -- Make sure it stays in the Disabled state.
      for i in 0 to 10 loop
        CheckStreamState(StreamNumber, Disabled);
        CheckDiagramStreamState(StreamNumber, Disabled);
      end loop;

      -- Disable the stream, then set SATCR and enable it for real.
      DisableStream(StreamNumber);
      StartStreamFromDiagram(StreamNumber, true, kFifoDepth*kDataWidth/8);
      WaitOnStreamState(StreamNumber, Enabled);
      WaitOnDiagramStreamState(StreamNumber, Enabled);

      -- Fill the fifo.
      FillFifo(1,kFifoDepth,StreamNumber);

      -- Receive some of the data in the FIFO, but not all of it so that we can test
      -- stopping without flushing.
      ReceiveData(
        StreamNumber => StreamNumber,
        NumberOfBytes => 1*kDataWidth/8);

      ResetDataCheck;

      -- Do a stop without flush.
      StopStreamFromDiagram(StreamNumber);

      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Check that the flush and flush failed bits are not set.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingStatus)) = '0'
        report "Flushing status incorrectly set."
        severity error;
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingFailedStatus)) = '0'
        report "Flushing failed status incorrectly set."
        severity error;

      -- Reset the SATCR.
      RegisterWrite(Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control),
                    Value => 2**BitFieldIndex(ResetSatcr));


      -----------------------------------------------------------------------------------
      -- Test state transitioning with flushing from diagram.
      -----------------------------------------------------------------------------------

      TestStatus <= rs("Testing diagram state transitioning with flushing.");
      wait for 0 ns;

      -- Set SATCR and enable the stream.
      StartStreamFromDiagram(StreamNumber, true, ((kFifoDepth+1)*64/kDataWidth-1)*
        kDataWidth/8);
      WaitOnStreamState(StreamNumber, Enabled);
      WaitOnDiagramStreamState(StreamNumber, Enabled);

      -- Make sure the FIFO cleared.
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(FifoCount));
      assert unsigned(readValue) = 0
        report "FIFO count value is non-zero following an enable"
        severity error;

      -- Fill the fifo.
      FillFifo(1,(kFifoDepth+1)*64/kDataWidth-1,StreamNumber);

      -- Wait for the FIFO to fill.
      wait until falling_edge(ViClk) and vEmptyCountArray(StreamNumber) =
        to_unsigned(0, vEmptyCountArray(StreamNumber)'length)
        for 10*kViClkPeriod;
      assert vEmptyCountArray(StreamNumber) = to_unsigned(0,
        vEmptyCountArray(StreamNumber)'length)
        report "Empty count not reporting full following FIFO fill."
        severity error;

      -- Receive some of the data in the FIFO before we issue the flush.
      ReceiveData(StreamNumber  => StreamNumber,
                  NumberOfBytes => kNiDmaInputMaxTransfer);

      -- Do a stop with flush.
      StopStreamFromDiagram(StreamNumber              => StreamNumber,
                            Flush                     => true,
                            NumberOfDataBytesForFlush => ((kFifoDepth+1)*64/kDataWidth-1)
                                                         *kDataWidth/8 - kNiDmaInputMaxTransfer
                            );

      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Check to make sure the FIFO is empty.
      RegisterRead(Address => kBaseOffsetArray(StreamNumber)+OffsetValue(FifoCount));
      assert to_integer(unsigned(readValue)) = 0
        report "FIFO count not empty after a flush."
        severity error;
      if kPeerToPeerArray(StreamNumber) then
        assert vEmptyCountArray(StreamNumber) =
               unsigned(Zeros(vEmptyCountArray(StreamNumber)'length))
          report "Empty count not reporting empty following flush."
          severity error;
      else
        assert vEmptyCountArray(StreamNumber) = to_unsigned((kFifoDepth+1)*64/
               kDataWidth-1,vEmptyCountArray(StreamNumber)'length)
          report "Empty count not reporting empty following flush."
          severity error;
      end if;

      -- Check that the flush bit is set and flush failed bit is not set.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingStatus)) = '1'
        report "Flushing status incorrectly set."
        severity error;
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingFailedStatus)) = '0'
        report "Flushing failed status incorrectly set."
        severity error;

      -- Unlink the stream.
      RegisterWrite(Value => 2**BitFieldIndex(UnlinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      WaitOnStreamState(StreamNumber, Unlinked);
      WaitOnDiagramStreamState(StreamNumber, Unlinked);


      -----------------------------------------------------------------------------------
      -- Test state transitioning with flushing timeout from diagram.
      -----------------------------------------------------------------------------------

      TestStatus <= rs("Testing diagram state transitioning with flush timeout.");
      wait for 0 ns;

      -- Set SATCR then link and enable the stream.
      RegisterWrite(Value => 2**BitFieldIndex(LinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      StartStreamFromDiagram(StreamNumber, true, kFifoDepth*kDataWidth/8);
      WaitOnStreamState(StreamNumber, Enabled);
      WaitOnDiagramStreamState(StreamNumber, Enabled);

      -- Make sure the FIFO cleared.
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(FifoCount));
      assert unsigned(readValue) = 0
        report "FIFO count value is non-zero following an enable"
        severity error;

      -- Fill the fifo.
      FillFifo(1,kFifoDepth,StreamNumber);

      -- Receive some of the data in the FIFO before we issue the flush.
      ReceiveData(StreamNumber  => StreamNumber,
                  NumberOfBytes => kNiDmaInputMaxTransfer);

      -- Do a stop with flush and timeout.
      StopStreamFromDiagram(StreamNumber              => StreamNumber,
                            Flush                     => true,
                            NumberOfDataBytesForFlush => (kFifoDepth*kDataWidth/8) -
                                                         kNiDmaInputMaxTransfer,
                            FlushTimeout              => 10,
                            DoFlushTimeout            => true);

      WaitOnStreamState(StreamNumber, Disabled);
      WaitOnDiagramStreamState(StreamNumber, Disabled);

      -- Check that the flush bit is set and flush failed bit is set.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingStatus)) = '1'
        report "Flushing status incorrectly set."
        severity error;
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingFailedStatus)) = '1'
        report "Flushing failed status incorrectly set."
        severity error;

      -- Make sure the flushing bits clear.
      RegisterWrite(Value => 2**BitFieldIndex(ClearFlushingStatus),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      RegisterWrite(Value => 2**BitFieldIndex(ClearFlushingFailedStatus),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingStatus)) = '0'
        report "Flushing status not clearing correctly."
        severity error;
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Status));
      assert readValue(BitFieldIndex(FlushingFailedStatus)) = '0'
        report "Flushing failed status not clearing correctly."
        severity error;

      -- Unlink the stream.
      RegisterWrite(Value => 2**BitFieldIndex(UnlinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));
      WaitOnStreamState(StreamNumber, Unlinked);
      WaitOnDiagramStreamState(StreamNumber, Unlinked);

    end procedure DoStateTransitionTest;


    ---------------------------------------------------------------------------
    -- DoDataRequest
    --
    -- This procedure sets values for the FIFO full count and SATCR, and then
    -- monitors the stream under test to ensure that the arbiter request flags
    -- are generated appropriately and that the proper request and data are
    -- sent.  The procedure will continue to run while the stream is able to
    -- send data.  This allows us to test that transitions from the last word
    -- of a packet to the next header word is the minimum.  Also, additional
    -- clock cycles can be inserted before asserting grant and accept for request,
    -- or accept for data words.
    --
    --
    -- PARAMETERS:
    --
    -- FifoFullCountInSamples    : The value to initialize the FIFO full count
    --                             in terms of samples
    -- SatcrValue                : The value to initialize SATCR
    -- ClkWaitBeforeGrant        : The number of extra clock cycles to wait
    --                             before asserting grant
    -- ClkWaitBeforeRequestAccept : The number of clock cycles to wait between
    --                             the Request being available and accepting it
    -- StreamNumber              : The stream number to test.  This chooses
    --                             the corresponding DUT to test.
    -- DisableDuringRequest      : Setting this to true will disable the stream
    --                             after the first packet transmission has
    --                             begun.  It will then exit the procedure
    --                             after the first transmission has completed,
    --                             ensuring that the stream disables.
    -- NumExtraSatcrWrites       : After the initial SATCR write is made and
    --                             data starts transferring, this many
    --                             additional SATCR writes will be made.
    -- ExtraSatcrWriteValue      : This is the value by which SATCR is
    --                             incremented for each additional SATCR write.
    --
    ---------------------------------------------------------------------------
    procedure DoDataRequest(
      FifoFullCountInSamples : natural;
      SatcrValue : natural;
      ClkWaitBeforeGrant : natural := 0;
      ClkWaitBeforeRequestAccept : natural := 0;
      ClkWaitBeforeDataAccept : natural := 0;
      StreamNumber : natural := 0;
      DisableDuringRequest : boolean := false;
      NumExtraSatcrWrites : natural := 0;
      ExtraSatcrWriteValue : natural := 0
    ) is

      constant kSampleShift : natural := Log2(kFifoDataWidthArray(StreamNumber))-3;

      constant kSampleMultiply : natural := 64/kFifoDataWidthArray(StreamNumber);

      variable i : integer;
      variable FIFODepth : positive;
      variable EvictionTimeout : integer;
      variable CurrentFifoCountInSamples : natural := 0;
      variable CurrentSatcrCount : integer := 0;
      variable BytesTransmitted : integer := 0;
      variable StartingByteLane : integer := 0;
      variable ExpectedSizeInBytes : natural := 0;
      variable DisabledDuringRequest : boolean := false;
      variable ExtraSatcrWrites : natural := NumExtraSatcrWrites;
      variable SanityCount : natural;

    begin

      -- Reset to clear any eviction timeout counters
      ResetDuts;

      --
      ClkWaitBeforeDataTransfer <= ClkWaitBeforeDataAccept;

      -- CURRENT STATE: Disabled

      FIFODepth := kFIFODepthArray(StreamNumber);
      StartingByteLane := 0;

      assert(FifoFullCountInSamples <= FIFODepth*(2**(3-kSampleShift)))
        report "FifoFullCount cannot be greater than FIFODepth"
        severity error;

      -- Make sure we start up in the Unlinked state
      CheckStreamState(StreamNumber, Unlinked);

      -- Set the linked bit.
      RegisterWrite(Value => 2**BitFieldIndex(LinkStream),
                    Address => kBaseOffsetArray(StreamNumber)+OffsetValue(Control));

      -- Wait for the state to transition to the Disabled state.
      WaitOnStreamState(StreamNumber, Disabled);

      -- Set the destination endpoint for a peer to peer stream
      -- if kPeerToPeerArray(StreamNumber) then
        -- RegisterWrite(Value=>kEndpointArray(StreamNumber),
                      -- Address=>kBaseOffsetArray(StreamNumber));
      -- end if;

      -- Make sure the stream is still in the Disabled state.
      CheckStreamState(StreamNumber, Disabled);

      -- Start the stream.
      EnableStream(StreamNumber);

      -- Set SATCR
      RegisterWrite(Value=>SatcrValue,
                    Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
      CurrentSatcrCount := SatcrValue;

      -- Wait an extra clock cycle for the SATCR value to propogate.
      ClkWait(1);

      -- Verify the value in SATCR
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
      assert(readValue = std_logic_vector(to_unsigned(SatcrValue,32)))
        report "SATCR value not correct after SATCR write."
        severity error;

      -- Wait for the state to transition to the Enabled state.
      WaitOnStreamState(StreamNumber, Enabled);
      WaitOnViClkStreamState(StreamNumber, Enabled);

      -- Fill the fifo to the depth specified in FifoFullCount
      FillFifo(1,FifoFullCountInSamples,StreamNumber);
      CurrentFifoCountInSamples := FifoFullCountInSamples;

      bResetTimeoutCount <= true;
      ClkWait(1);
      bResetTimeoutCount <= false;

      -- Wait until the FIFO has received the values.
      RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
      SanityCount := 0;
      while unsigned(readValue(31 downto 0)) /= FifoFullCountInSamples and
            SanityCount < 20 loop
        RegisterRead(Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
        SanityCount := SanityCount + 1;
      end loop;

      -- CURRENT STATE: Idle

      -- Check the arbiter request flag values
      CheckArbiterSignals(
        CurrentFifoCountInSamples,
        CurrentSatcrCount,
        AlignmentSize(StreamNumber),
        FIFODepth,
        bTimeoutCount,
        false,
        StreamNumber);

      -- Check if the Input Request to NI DMA is Zero
      CheckInputRequestToDmaSignals(
        NiDmaInputRequestToDma => kNiDmaInputRequestToDmaZero);

      -- Wait until next rising edge when state machine moves to the request
      -- arbiter access state (if a request is high)
      ClkWait(1);

      -- CURRENT STATE: WaitForArbiter OR Idle

      -- Keep looping while there is more data to send.
      while(CurrentSATCRCount > 0 and CurrentFifoCountInSamples > 0
            and not DisabledDuringRequest) loop
        -- StdPrint("AilgnmentSize= " & Image(AlignmentSize(StreamNumber)));
        -- StdPrint("kSampleShift= " & Image(kSampleShift));
        -- StdPrint("FifoDataWidth= " & Image(kFifoDataWidthArray(StreamNumber)));
        -- StdPrint("DataWidth= " & natural'image(Log2(kFifoDataWidthArray(StreamNumber))));
        -- Set the expected size to the min of the count values
        if(CurrentFifoCountInSamples*(2**kSampleShift) >= AlignmentSize(StreamNumber)
           and CurrentSATCRCount >= AlignmentSize(StreamNumber)) then
          ExpectedSizeInBytes := AlignmentSize(StreamNumber);
        elsif(CurrentFifoCountInSamples*(2**kSampleShift) >= CurrentSATCRCount and
              AlignmentSize(StreamNumber) >= CurrentSATCRCount) then
          ExpectedSizeInBytes := CurrentSATCRCount;
        else
          ExpectedSizeInBytes := CurrentFifoCountInSamples*(2**kSampleShift);
        end if;

        wait for 1 ns;

        -- Check if the Input Request to NI DMA is Zero
        CheckInputRequestToDmaSignals(
          NiDmaInputRequestToDma => kNiDmaInputRequestToDmaZero);

        -- Wait any additional clock cycles
        ClkWait(ClkWaitBeforeGrant);

        -- CURRENT STATE: WaitForArbiter OR Idle

        -- Wait for an eviction timeout if the FIFO is not full enough to
        -- generate flags.
        if (CurrentFifoCountInSamples < (FIFODepth+1)*kSampleMultiply/4 and
            CurrentFifoCountInSamples*(2**kSampleShift) <
            Smaller(AlignmentSize(StreamNumber), CurrentSATCRCount) and
            bTimeoutCount <= kEvictionTimeoutArray(StreamNumber)) then

          wait for 1 ns;

          -- Make sure the arbiter signals are not true.
          CheckArbiterSignals(
            ArbiterNormalReq => '0',
            ArbiterEmergencyReq => '0',
            Stream => StreamNumber);

          -- Need to estimate the timeout counter value because it depends on when
          -- data is transferred from the VI clock domain to the BusClk domain.
          ClkWait(kEvictionTimeoutArray(StreamNumber) - bTimeoutCount + 32);

          wait for 1 ns;

          -- Make sure the emergency flag is now true.
          CheckArbiterSignals(
            ArbiterNormalReq => '0',
            ArbiterEmergencyReq => '1',
            Stream => StreamNumber);
        end if;

        -- CURRENT STATE: WaitForArbiter

        -- Check the arbiter request flag values again.
        CheckArbiterSignals(
          CurrentFifoCountInSamples,
          CurrentSATCRCount,
          AlignmentSize(StreamNumber),
          FIFODepth,
          bTimeoutCount,
          false,
          StreamNumber
        );

        -- Now assert the grant signal
        bArbiterGrantArray(StreamNumber) <= '1';

        wait until falling_edge(Clk);

        -- Check if the Input Request to NI DMA is Zero
        CheckInputRequestToDmaSignals(
          NiDmaInputRequestToDma => kNiDmaInputRequestToDmaZero);

        -- CURRENT STATE: SendPacketRequest

        wait until falling_edge(Clk);

        -- Set the disable flag if we are testing disable
        if DisableDuringRequest then

          -- First, hit disable on the circuit
          RegisterWrite(Value=>2**BitFieldIndex(StopChannel),
                        Address=>kBaseOffsetArray(0) + OffsetValue(Control));

          -- Assert that the circuit is not disabled yet
          RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
          assert(readValue(BitFieldIndex(DisableStatus)) = '0')
            report "Circuit disabled before transmission complete."
            severity error;

        end if;

        -- Now wait a few clock cycles and assert accept
        ClkWait(ClkWaitBeforeRequestAccept);

        if ClkWaitBeforeRequestAccept > 0 then
          wait until falling_edge(Clk);
        end if;

        CheckInputRequestToDmaSignals(NiDmaInputRequestToDma
          =>  (Request => true,
              Space => kNiDmaSpaceStream,
              Channel => to_unsigned(StreamNumber,bNiDmaInputRequestToDma.Channel'length),
              Address => (others => '0'),
              Baggage => (others => '0'),
              ByteSwap => (others => '0'),
              ByteLane => to_unsigned(StartingByteLane, bNiDmaInputRequestToDma.ByteLane'length),
              ByteCount => to_unsigned(ExpectedSizeInBytes, bNiDmaInputRequestToDma.ByteCount'length),
              Done => false,
              EndOfRecord => false));

        -- Accept the Request
        if bRequestAcknowledge then
          bNiDmaInputRequestFromDma.Acknowledge <= true;
        else
          wait until bRequestAcknowledge;
          bNiDmaInputRequestFromDma.Acknowledge <= true;
        end if;

        -- Reset the time out counter
        bResetTimeoutCount <= true;

        ClkWait(1);
        bNiDmaInputRequestFromDma.Acknowledge <= false;
        bArbiterGrantArray(StreamNumber) <= '0';
        bResetTimeoutCount <= false;

        -- wait until all requested data is transferred
        wait until bNiDmaInputDataFromDma.TransferEnd;

        assert BytesReceivedSig = bLastNiDmaInputRequestToDma.ByteCount
          report "The number of bytes received in the current transfer is " &
                  Image(BytesReceivedSig) & LF &
                 "The expected number of bytes in the current transfer is " &
                  Image(to_integer(bLastNiDmaInputRequestToDma.ByteCount))
          severity error;

        -- CURRENT STATE: Idle OR WaitForArbiter

        StartingByteLane := (ExpectedSizeInBytes+StartingByteLane) mod 8;
        AlignmentSize(StreamNumber) := AlignmentSize(StreamNumber)-ExpectedSizeInBytes;
        if AlignmentSize(StreamNumber) = 0 then
          AlignmentSize(StreamNumber) := kNiDmaInputMaxTransfer;
        end if;

        -- StdPrint("CurrentFifoCountInSamples = " & Image(CurrentFifoCountInSamples));
        -- StdPrint("ExpectedSizeInBytes = " & Image(ExpectedSizeInBytes));
        -- StdPrint("kDataWidth = " & Image(kDataWidthArray(StreamNumber)));
        -- Update the number of samples that will remain in the FIFO after the request
        -- will be satisfied.
        CurrentFifoCountInSamples := CurrentFifoCountInSamples - ExpectedSizeInBytes/
          (kFifoDataWidthArray(StreamNumber)/8);

        -- Update SATCR current value.
        CurrentSATCRCount := CurrentSATCRCount - ExpectedSizeInBytes;

        ClkWait(2);

        -- CURRENT STATE: Idle OR WaitForArbiter

        -- If we disabled during the transmission, check that we get the done
        -- packet.
        if(DisableDuringRequest) then

          ClkWait(1);

          -- CURRENT STATE: DisableRequest

          -- Assert arbiter grant
          ClkWait(1);
          assert(bArbiterEmergencyReqArray(StreamNumber) = '1')
            report "No request for arbiter access in DisableRequest state."
            severity error;
          bArbiterGrantArray(StreamNumber) <= '1';

          ClkWait(1);
          wait for 1 ns;

          -- CURRENT STATE: SendDoneHeader

          -- Check if the Input Request to NI DMA signals that the transfer is Done
          CheckInputRequestToDmaSignals(
            NiDmaInputRequestToDma => kNiDmaInputRequestToDmaDone);

          -- Accept the Input Request
          bNiDmaInputRequestFromDma.Acknowledge <= true;

          wait until falling_edge(Clk);
          assert(bArbiterDoneArray(StreamNumber))
            report "Arbiter done signal not going true"
            severity error;

          -- Hold accept true for exactly one clock cycle to consume the packet
          ClkWait(1);
          bNiDmaInputRequestFromDma.Acknowledge <= false;
          bArbiterGrantArray(StreamNumber) <= '0';

          -- CURRENT STATE: Disabled

          -- Check that the disabled flag goes true
          RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
          assert(readValue(BitFieldIndex(DisableStatus)) = '1')
            report "Disabled bit not going true after transmission."
            severity error;

          DisabledDuringRequest := true;
        end if;

        -- Handle the extra SATCR writes
        if ExtraSatcrWrites > 0 then
          RegisterWrite(Value=>ExtraSatcrWriteValue,
                        Address=>kBaseOffsetArray(StreamNumber)+OffsetValue(Satcr));
          CurrentSatcrCount := CurrentSatcrCount + ExtraSatcrWriteValue;
          ExtraSatcrWrites := ExtraSatcrWrites - 1;
          ClkWait(2);
        end if;

      end loop;

    end procedure DoDataRequest;

    variable Rand : Random_t;
    --vhook_nowarn *Rand

    variable RandomDut : natural;
    --vhook_nowarn *RandomDut

  begin

    -- Set initial values
    bNiDmaInputRequestFromDma <= kNiDmaInputRequestFromDmaZero;

    bReset <= false;

    bResetTimeoutCount <= false;

    bRegPortIn.Data <= (others => '0');
    bRegPortIn.Address <= (others => '0');
    bRegPortIn.Rd <= false;
    bRegPortIn.Wt <= false;

    for i in 0 to kNumberOfDUTs-1 loop
      bArbiterGrantArray(i) <= '0';
      vDataInArray(i) <= (others => '0');
      vTimeoutArray(i) <= std_logic_vector(to_unsigned(10,
        vTimeoutArray(i)'length));
      vEnableInArray(i) <= '0';
      vEnableClearArray(i) <= '0';
      vStreamStateEnableClearArray(i) <= '0';
      vStreamStateEnableInArray(i) <= '0';
      dStreamStateEnableClearArray(i) <= '0';
      dStreamStateEnableInArray(i) <= '0';
      dStartRequestEnableInArray(i) <= '0';
      dStartRequestEnableClearArray(i) <= '0';
      dStopRequestEnableInArray(i) <= '0';
      dStopRequestEnableClearArray(i) <= '0';
      dStopWithFlushRequestEnableInArray(i) <= '0';
      dStopWithFlushRequestEnableClearArray(i) <= '0';
      dStopWithFlushRequestTimeoutArray(i) <= to_signed(-1,
        dStopWithFlushRequestTimeoutArray(i)'length);
      AlignmentSize(i) := kNiDmaInputMaxTransfer;
    end loop;

    TestStatus <= rs("Reseting the DUT...");
    wait for 0 ns;

    -- Reset the DUTs
    ResetDuts;

    -- Wait a few clocks and check initial values
    ClkWait(5);

    CheckInputRequestToDmaSignals(
      NiDmaInputRequestToDma => kNiDmaInputRequestToDmaZero);

      CheckInputDataToDmaSignals (Data => 0);

    for i in 0 to kNumberOfDUTs-1 loop
      CheckArbiterSignals(
        ArbiterNormalReq => '0',
        ArbiterEmergencyReq => '0',
        ArbiterDone => false,
        Stream => i);
      CheckViSignals(
        Full => '0',
        EnableOut => '0',
        Stream => i);
    end loop;

    CheckRegPortSignals(
      Data => Zeros(bRegPortOut.Data'length),
      DataValid => false,
      Ready => true);

    TestStatus <= rs("Reset successful!");
    wait for 0 ns;


    TestStatus <= rs("Enabling the DMA stream...");
    wait for 0 ns;

    -- First let's enable the DMA stream
    EnableStream(0);

    TestStatus <= rs("Enable successful!");
    wait for 0 ns;


    -- Now let's set the SATCR and read it back
    RegisterWrite(Value => 512,
                  Address => kBaseOffsetArray(0)+OffsetValue(Satcr));

    -- Wait an extra clock cycle for the SATCR value to propogate.
    ClkWait(1);

    RegisterRead(Address => kBaseOffsetArray(0)+OffsetValue(Satcr));
    assert(readValue = std_logic_vector(to_unsigned(512,32)))
      report "SATCR does not have the proper value."
      severity error;


    ---------------------------------------------------------------------------
    -- Asynchronous reset testing
    ---------------------------------------------------------------------------

    TestStatus <= rs("Testing asynchronous reset operation...");
    wait for 0 ns;

    -- To test the reset operation, a number of points will be pushed into the
    -- FIFO so that the stream requests arbiter access.  Also, the SATCR has
    -- already been written with a sufficiently large value.  Then, it can be
    -- determined if the FIFO and registers reset as required.

    WaitOnViClkStreamState(0, Enabled);

    -- Now let's push some points to the FIFO
    for i in 1 to 128-1 loop

      PushPoint(i,0);

      -- Make sure the arbiter signals are still valid
      CheckArbiterSignals(
        ArbiterNormalReq => '0',
        ArbiterEmergencyReq => '0',
        ArbiterDone => false,
        Stream => 0);

    end loop;

    -- Push one more point and check that the normal flag goes true
    PushPoint(128,0);

    -- Need to wait some clock cycles for the fifo full count to propagate
    -- to the bus clk domain.
    wait until falling_edge(VIClk);
    wait until falling_edge(VIClk);
    wait until falling_edge(VIClk);
--    report "ArbiterNormalReq value is:" & Image(bArbiterNormalReqArray(0));
--    report "ArbiterEmargencyReq value is:" & Image(bArbiterEmergencyReqArray(0));
    CheckArbiterSignals(
      ArbiterNormalReq => '1',
      ArbiterEmergencyReq => '0',
      ArbiterDone => false,
      Stream => 0);

    -- Now start the reset

    -- First, hit disable on the circuit
    RegisterWrite(Value=>2**BitFieldIndex(StopChannel),
                  Address=>kBaseOffsetArray(0) + OffsetValue(Control));

    -- Assert grant for the done packet
    ClkWait(2);
    wait until falling_edge(Clk);
    CheckArbiterSignals(
      ArbiterNormalReq => '0',
      ArbiterEmergencyReq => '1',
      ArbiterDone => false,
      Stream => 0);
    bArbiterGrantArray(0) <= '1';

    -- Check the Done Request
    wait until rising_edge(Clk);
    wait for 1 ns;

    -- Check the Done Request
    CheckInputRequestToDmaSignals(
      NiDmaInputRequestToDma => kNiDmaInputRequestToDmaDone);

    -- Accept the Request
    bNiDmaInputRequestFromDma.Acknowledge <= true;

    wait until falling_edge(Clk);
    assert(bArbiterDoneArray(0))
      report "Arbiter done signal not going true"
      severity error;

    -- Hold accept true for exactly one clock cycle to consume the packet
    ClkWait(1);
    bNiDmaInputRequestFromDma.Acknowledge <= false;
    bArbiterGrantArray(0) <= '0';

    -- Poll until the disable has completed
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    while readValue(BitFieldIndex(DisableStatus)) = '0' loop
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    end loop;

    -- Make sure the arbiter signals are no longer requesting
    CheckArbiterSignals(
      ArbiterNormalReq => '0',
      ArbiterEmergencyReq => '0',
      ArbiterDone => false,
      Stream => 0);

    -- Now set the reset bit
    RegisterWrite(Value=>2**BitFieldIndex(Reset),
                  Address=>kBaseOffsetArray(0) + OffsetValue(Control));

    -- Poll until the reset has completed
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    while readValue(BitFieldIndex(ResetStatus)) = '0' loop
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    end loop;

    -- Check the values after reset
    CheckInputRequestToDmaSignals(
      NiDmaInputRequestToDma => kNiDmaInputRequestToDmaZero);

    CheckArbiterSignals(
      ArbiterNormalReq => '0',
      ArbiterEmergencyReq => '0',
      ArbiterDone => false,
      Stream => 0);
    CheckViSignals(
      Full => '0',
      EnableOut => '0',
      Stream => 0);

    -- Read SATCR and ensure that it has reset to zero
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Satcr));
    assert(readValue = Zeros(32))
      report "SATCR did not reset to zero."
      severity error;

    TestStatus <= rs("Asynchronous Reset successful!");
    wait for 0 ns;


    ---------------------------------------------------------------------------
    -- Synchronous reset testing
    ---------------------------------------------------------------------------

    TestStatus <= rs("Testing synchronous reset operation...");
    wait for 0 ns;

    -- To test the reset operation, a number of points will be pushed into the
    -- FIFO so that the stream requests arbiter access.  Also, the SATCR has
    -- already been written with a sufficiently large value.  Then, it can be
    -- determined if the FIFO and registers reset as required.

    -- Enable the circuit
    EnableStream(0);

    -- Write SATCR
    RegisterWrite(Value=>700*8, Address=>kBaseOffsetArray(0)+OffsetValue(Satcr));

    WaitOnViClkStreamState(0, Enabled);

    -- Push some points to the FIFO
    FillFifo(1,700*8,0);


    -- Make sure the arbiter signals are requesting
    wait until falling_edge(Clk);
    CheckArbiterSignals(
      ArbiterNormalReq => '1',
      ArbiterEmergencyReq => '1',
      ArbiterDone => false,
      Stream => 0);

    -- Give the grant to start a transfer
    bArbiterGrantArray(0) <= '1';
    ClkWait(2);

    -- Check arbiter values before resetting
    CheckArbiterSignals(
      ArbiterNormalReq => '1',
      ArbiterEmergencyReq => '1',
      ArbiterDone => false,
      Stream => 0);

    -- Now assert the synchronous reset for one clock cycle.
    bReset <= true;
    ClkWait(1);
    bArbiterGrantArray(0) <= '0';
    bReset <= false;

    -- Poll until the reset has completed
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    while readValue(BitFieldIndex(ResetStatus)) = '0' loop
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    end loop;

    -- Check the values after reset
    CheckInputRequestToDmaSignals(
      NiDmaInputRequestToDma => kNiDmaInputRequestToDmaZero);
    CheckArbiterSignals(
      ArbiterNormalReq => '0',
      ArbiterEmergencyReq => '0',
      ArbiterDone => false,
      Stream => 0);
    CheckViSignals(
      Full => '0',
      EnableOut => '0',
      Stream => 0);

    -- Read SATCR and ensure that it has reset to zero
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Satcr));
    assert(readValue = Zeros(32))
      report "SATCR did not reset to zero."
      severity error;

    -- Check that the disabled bit is set
    RegisterRead(Address => kBaseOffsetArray(0)+OffsetValue(Status));
    assert(readValue(BitFieldIndex(DisableStatus)) = '1')
      report "Status register does not have the proper value."
      severity error;

    TestStatus <= rs("Synchronous reset testing successful!");
    wait for 0 ns;


    TestStatus <= rs("Testing normal DMA transfers");
    wait for 0 ns;


    ---------------------------------------------------------------------------
    -- State Transition Tests
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Performing State Transition Tests");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoStateTransitionTest(0);

    TestStatus <= rs("State Transition Tests complete!");
    wait for 0 ns;

    -----------------------------------------------------------------------------
    -- Normal DMA Transmission tests
    --
    -- These tests test normal DMA transactions with varying data width, SATCR,
    -- FIFO full count, and clock wait values.
    --
    -- The outer loop performs the same tests with differing data widths.  This
    -- is necessary because each data width is a separate DUT, and data width
    -- for a single DUT cannot be changed on the fly.
    -----------------------------------------------------------------------------

    for DUTNumber in 3 downto 0 loop

      ---------------------------------------------------------------------------
      -- Test 1 : Normal DMA Transmission
      --          Priority:      Normal
      --          # of Data Elements:  1
      --          Size limiter:  SATCR
      --          # of requests:  1
      --          Clock waits:   5
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 1");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 350*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 1*8,
        ClkWaitBeforeGrant => 5,
        ClkWaitBeforeRequestAccept => 5,
        ClkWaitBeforeDataAccept => 5,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;


      ---------------------------------------------------------------------------
      -- Test 2 : Normal DMA Transmission
      --          Priority:      Normal
      --          # of Data Elements:  1
      --          Size limiter:  SATCR
      --          # of requests:  1
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      ResetDuts;

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 2");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 350*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 1*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;


      ---------------------------------------------------------------------------
      -- Test 3 : Normal DMA Transmission
      --          Priority:      Normal
      --          # of Data Elements:  10
      --          Size limiter:  SATCR
      --          # of requests:  1
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 3");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 350*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 10*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;


      ---------------------------------------------------------------------------
      -- Test 4 : Normal DMA Transmission
      --          Priority:      Normal
      --          # of Data Elements:  300
      --          Size limiter:  Max Packet Size
      --          # of requests:  19
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 4");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 300*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 300*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 5 : Normal DMA Transmission
      --          Priority:      Emergency
      --          # of Data Elements:  600
      --          Size limiter:  Max packet size
      --          # of requests:  600/((kNiDmaInputMaxTransfer/
      --                          (kFifoDataWidthArray(DUTNumber))/8))+1
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 5");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 600*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 800*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 6 : Normal DMA Transmission
      --          Priority:      Emergency
      --          # of Data Elements:  1
      --          Size limiter:  SATCR
      --          # of requests:  1
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 6");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 800*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 1*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 7 : Normal DMA Transmission
      --          Priority:      Emergency
      --          # of Data Elements:  20
      --          Size limiter:  Max Packet Size, SATCR
      --          # of requests:  2
      --          Clock waits:   100
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 7");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 800*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 20*8,
        ClkWaitBeforeGrant => 100,
        ClkWaitBeforeRequestAccept => 100,
        ClkWaitBeforeDataAccept => 100,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 8 : Normal DMA Transmission
      --          Priority:      Emergency
      --          # of Data Elements:  Max FIFO full count
      --          Size limiter:  Max Packet Size, FIFO full count
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 8");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => kFIFODepthArray(DUTNumber)*
                                  (2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => to_integer(unsigned(Ones(31))),
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;


      ---------------------------------------------------------------------------
      -- Test 9 : Normal DMA Transmission
      --          Priority:      None
      --          Payload size:  0
      --          Size limiter:  FIFO count
      --          # of packets:  0
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 9");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 0,
        SatcrValue => to_integer(unsigned(Ones(31))),
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 10: Normal DMA Transmission
      --          Priority:      None
      --          Payload size:  0
      --          Size limiter:  SATCR
      --          # of packets:  0
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 10");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 512*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 0*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

    end loop;

    ---------------------------------------------------------------------------
    -- Normal DMA Transmissions with varying FIFO depths.
    --
    -- The following tests use FIFO sizes of 63, 3, and 4095.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- Test 11: Normal DMA Transmission
    --          Priority:      Normal
    --          Payload size:  1
    --          Size limiter:  FIFOFullCount
    --          FIFO Depth:    3
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 11");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 1*2,
      SatcrValue => 16*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 4
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 12: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  2
    --          Size limiter:  FIFOFullCount
    --          FIFO Depth:    3
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 12");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 2*2,
      SatcrValue => 1024*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 4
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 13: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  3
    --          Size limiter:  FIFOFullCount
    --          FIFO Depth:    3
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 13");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 3*2,
      SatcrValue => 1024*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 4
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 14: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  2
    --          Size limiter:  SATCR
    --          FIFO Depth:    3
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 14");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 3*2,
      SatcrValue => 2*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 4
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 15: Normal DMA Transmission
    --          Priority:      None
    --          Payload size:  0
    --          Size limiter:  FIFO Full Count
    --          FIFO Depth:    63
    --          # of packets:  0
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 15");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 8,
      SatcrValue => 1024*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 5
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 16: Normal DMA Transmission
    --          Priority:      Normal
    --          Payload size:  16
    --          Size limiter:  FIFO Full Count
    --          FIFO Depth:    63
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 16");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 16,
      SatcrValue => 1024*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 5
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 17: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  32
    --          Size limiter:  FIFO Full Count
    --          FIFO Depth:    63
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 17");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 32,
      SatcrValue => 1024*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 5
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;


    ---------------------------------------------------------------------------
    -- Test 18: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  63
    --          Size limiter:  FIFO Full Count
    --          FIFO Depth:    63
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 18");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 63,
      SatcrValue => 1024*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 5
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 19: Normal DMA Transmission
    --          Priority:      None
    --          Payload size:  0
    --          Size limiter:  FIFO Full Count
    --          FIFO Depth:    4095
    --          # of packets:  0
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 19");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 1023*8,
      SatcrValue => 5000*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 6
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 20: Normal DMA Transmission
    --          Priority:      Normal
    --          Payload size:  512
    --          Size limiter:  Max packet size
    --          FIFO Depth:    4095
    --          # of packets:  1
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 20");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 1024*8,
      SatcrValue => 5000*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 6
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 21: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  512
    --          Size limiter:  Max packet size
    --          FIFO Depth:    4095
    --          # of packets:  3
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 21");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 2048*8,
      SatcrValue => 5000*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 6
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Test 22: Normal DMA Transmission
    --          Priority:      Emergency
    --          Payload size:  512
    --          Size limiter:  Max packet size
    --          FIFO Depth:    4095
    --          # of packets:  6
    --          Clock waits:   0
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 22");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    DoDataRequest(
      FifoFullCountInSamples => 4094*8,
      SatcrValue => 5000*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 6
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;


    TestStatus <= rs("Testing additional SATCR writes");
    wait for 0 ns;

    for DUTNumber in 2 downto 0 loop

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 23");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 1023,
        SatcrValue => 1*kFifoDataWidthArray(DUTNumber)/8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber,
        NumExtraSatcrWrites => 10,
        ExtraSatcrWriteValue => 1*kFifoDataWidthArray(DUTNumber)/8
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;


      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 24");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 1023,
        SatcrValue => 2*kFifoDataWidthArray(DUTNumber)/8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber,
        NumExtraSatcrWrites => 10,
        ExtraSatcrWriteValue => 1*kFifoDataWidthArray(DUTNumber)/8
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 25");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 1023,
        SatcrValue => 7*kFifoDataWidthArray(DUTNumber)/8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber,
        NumExtraSatcrWrites => 10,
        ExtraSatcrWriteValue => 1*kFifoDataWidthArray(DUTNumber)/8
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 26");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 1023,
        SatcrValue => 3*kFifoDataWidthArray(DUTNumber)/8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber,
        NumExtraSatcrWrites => 10,
        ExtraSatcrWriteValue => 3*kFifoDataWidthArray(DUTNumber)/8
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 27");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 1023,
        SatcrValue => 448+kFifoDataWidthArray(DUTNumber)/8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber,
        NumExtraSatcrWrites => 5,
        ExtraSatcrWriteValue => 7*kFifoDataWidthArray(DUTNumber)/8
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

    end loop;

    ---------------------------------------------------------------------------
    -- Test 28: Disable functionality
    --          Priority:      Emergency
    --          Payload size:  512
    --          Size limiter:  Max packet size
    --          FIFO Depth:    1023
    --          Timeout Value: 0
    --          Grant clocks:  0
    --
    --          This test first ensures that the controller will never leave
    --          the idle state while disable is true.  When disable goes false,
    --          it should leave the idle state and finish transmission before
    --          disabling again.
    ---------------------------------------------------------------------------

    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;
    TestStatus <= rs("Test 28");
    wait for 0 ns;
    TestStatus <= rs("------------------------------------------------------");
    wait for 0 ns;

    -- First, reset the controller
    ResetDuts;

    -- Enable the stream
    EnableStream(0);

    -- Set SATCR
    RegisterWrite(Value => 1023*8,
                  Address => kBaseOffsetArray(0)+OffsetValue(Satcr));
    ClkWait(1);
    RegisterRead(Address => kBaseOffsetArray(0)+OffsetValue(Satcr));
    assert(readValue = std_logic_vector(to_unsigned(1023*8,32)))
      report "SATCR does not have the proper value."
      severity error;

    WaitOnViClkStreamState(0, Enabled);

    -- Fill the FIFO
    FillFifo(StartValue=>1, EndValue=>1023*8, Stream=>0);

    -- We should now be in the ArbiterGrant state.  Check the arbiter flags
    -- to ensure that this is the case.
    CheckArbiterSignals(
      ArbiterNormalReq => '1',
      ArbiterEmergencyReq => '1',
      ArbiterDone => false,
      Stream => 0);

    -- Now assert disable to move into the BeginDisable state.  Also assert
    -- ArbiterGrant.
    RegisterWrite(Value=>2**BitFieldIndex(StopChannel),
                  Address=>kBaseOffsetArray(0) + OffsetValue(Control));
    bArbiterGrantArray(0) <= '0';

    ClkWait(1);
    wait until falling_edge(Clk);

    -- Assert grant for the done packet
    CheckArbiterSignals(
      ArbiterNormalReq => '1',
      ArbiterEmergencyReq => '1',
      ArbiterDone => false,
      Stream => 0);
    bArbiterGrantArray(0) <= '1';

    ClkWait(1);
    wait until rising_edge(Clk);
    wait for 1 ns;

    -- Check the Done Request
    CheckInputRequestToDmaSignals(
      NiDmaInputRequestToDma => kNiDmaInputRequestToDmaDone);

    -- Accept the Request
    bNiDmaInputRequestFromDma.Acknowledge <= true;

    wait until falling_edge(Clk);
    assert(bArbiterDoneArray(0))
      report "Arbiter done signal not going true"
      severity error;

    -- Hold accept true for exactly one clock cycle to consume the packet
    ClkWait(1);
    bNiDmaInputRequestFromDma.Acknowledge <= false;
    bArbiterGrantArray(0) <= '0';

    -- Poll until the disable has completed
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    while readValue(BitFieldIndex(DisableStatus)) = '0' loop
      RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    end loop;


    -- The disabled signal should be true in this state.
    wait until falling_edge(Clk);
    assert(not bArbiterDoneArray(0))
      report "ArbiterDone stayed true too many clock cycles."
      severity error;
    RegisterRead(Address=>kBaseOffsetArray(0)+OffsetValue(Status));
    assert(readValue(BitFieldIndex(DisableStatus)) = '1')
      report "Status register does not have the proper value."
      severity error;

    DoDataRequest(
      FifoFullCountInSamples => 1023,
      SatcrValue => 1023*8,
      ClkWaitBeforeGrant => 0,
      ClkWaitBeforeRequestAccept => 0,
      ClkWaitBeforeDataAccept => 0,
      StreamNumber => 0,
      DisableDuringRequest => true
    );

    TestStatus <= rs("Passed!");
    wait for 0 ns;

    TestStatus <= rs("Testing FXP data to host.");
    wait for 0 ns;

    for DUTNumber in 9 downto 8 loop

      ---------------------------------------------------------------------------
      -- Test 29 : Normal DMA Transmission
      --           Priority:      Normal
      --           Payload size:  1
      --           Size limiter:  SATCR
      --           # of packets:  1
      --           Clock waits:   5
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 29");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FIFOFullCountInSamples => 350*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 1*8,
        ClkWaitBeforeGrant => 5,
        ClkWaitBeforeRequestAccept => 5,
        ClkWaitBeforeDataAccept => 5,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 30 : Normal DMA Transmission
      --           Priority:      Normal
      --           Payload size:  1
      --           Size limiter:  SATCR
      --           # of packets:  1
      --           Clock waits:   0
      ---------------------------------------------------------------------------

      ResetDuts;

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 30");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 350*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 1*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 31 : Normal DMA Transmission
      --           Priority:      Normal
      --           Payload size:  10
      --           Size limiter:  SATCR
      --           # of packets:  1
      --           Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 31");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 350*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 10*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 32: Normal DMA Transmission
      --          Priority:      Normal
      --          Payload size:  300
      --          Size limiter:  Max Packet Size
      --          # of packets:  1
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 32");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 300*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 300*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;


      ---------------------------------------------------------------------------
      -- Test 33: Normal DMA Transmission
      --          Priority:      Emergency
      --          Payload size:  64
      --          Size limiter:  Max packet size
      --          # of packets:  floor((600-256)/64)
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 33");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 600*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 800*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

      ---------------------------------------------------------------------------
      -- Test 34: Normal DMA Transmission
      --          Priority:      Emergency
      --          Payload size:  1
      --          Size limiter:  SATCR
      --          # of packets:  1
      --          Clock waits:   0
      ---------------------------------------------------------------------------

      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;
      TestStatus <= rs("Test 34");
      wait for 0 ns;
      TestStatus <= rs("Data width = " & Image(kDataWidthArray(DUTNumber)));
      wait for 0 ns;
      TestStatus <= rs("------------------------------------------------------");
      wait for 0 ns;

      DoDataRequest(
        FifoFullCountInSamples => 800*(2**(6-Log2((kFifoDataWidthArray(DUTNumber))))),
        SatcrValue => 1*8,
        ClkWaitBeforeGrant => 0,
        ClkWaitBeforeRequestAccept => 0,
        ClkWaitBeforeDataAccept => 0,
        StreamNumber => DUTNumber
      );

      TestStatus <= rs("Passed!");
      wait for 0 ns;
      TestStatus <= rs(" ");
      wait for 0 ns;

    end loop;

    ---------------------------------------------------------------------------
    -- Random testing
    ---------------------------------------------------------------------------
    for i in 1 to 50 loop

      TestStatus <= rs("Beginning Random Test " & Image(i));
      wait for 0 ns;

      RandomDut := Rand.GetNatural(4);

      DoDataRequest(
        FifoFullCountInSamples => Rand.GetNatural(1024),
        SatcrValue => Rand.GetNatural(2000)*kFifoDataWidthArray(RandomDut)/8,
        ClkWaitBeforeGrant => Rand.GetNatural(8),
        ClkWaitBeforeRequestAccept => Rand.GetNatural(8),
        ClkWaitBeforeDataAccept => Rand.GetNatural(8),
        StreamNumber => RandomDut,
        NumExtraSatcrWrites => Rand.GetNatural(20),
        ExtraSatcrWriteValue => Rand.GetNatural(100)*kFifoDataWidthArray(RandomDut)/8
      );

      TestStatus <= rs("Random Test " & Image(i) & " passed!");
      wait for 0 ns;

    end loop;

    StopSim <= true;
    wait;
  end process;



  ReadData:
  -- The process captures the request information sent over by DmaPort. It is assumed that
  -- no request is issued until all the data previously requested is transferred.
  -- This process also generates the signals needed to be sent to DmaPort on the
  -- Data bus together with the signal that will pop data from the FIFO.

  process(aReset, Clk)
    variable BytesReceived : natural := 0;
    variable bNiDmaInputRequestToDmaVar : NiDmaInputRequestToDma_t;
    variable ByteLaneVar : NiDmaByteLane_t;
    variable ByteEnableVar : NiDmaByteEnable_t;
    variable ByteCountVar : NiDmaBusByteCount_t;
    variable DmaChannelVar : NiDmaDmaChannelOneHot_t;
    variable i : natural := 0;
  begin
    if aReset then
      bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
      bRequestAcknowledge <= false;
      bNiDmaInputRequestToDmaVar := kNiDmaInputRequestToDmaZero;
      bLastNiDmaInputRequestToDma <= kNiDmaInputRequestToDmaZero;
      i := 0;
    elsif rising_edge(Clk) then
      bRequestAcknowledge <= false;

      -- When a request is received we have to capture the request information.
      -- bRequestAcknowledge just signal the main process that
      -- the request can be acknowledge
      if bNiDmaInputRequestToDma.Request then
        bNiDmaInputRequestToDmaVar := bNiDmaInputRequestToDma;
        bRequestAcknowledge <= true;
        BytesReceived := 0;
        i := 0;

      else

        if BytesReceived < to_integer(bNiDmaInputRequestToDmaVar.ByteCount) then

          -- Send Data information only after a set number of clock cycles
          if i >= ClkWaitBeforeDataTransfer then

            -- Generate the Input Data

            -- Generate the TransferStart and the Byte Lane
            bNiDmaInputDataFromDma.TransferStart <= false;

            -- The ByteLane is always 0 during the first data phase
            ByteLaneVar := (others => '0');
            if BytesReceived = 0 then
              bNiDmaInputDataFromDma.TransferStart <= true;

              -- the Byte Lane is copied from corresponding request
              ByteLaneVar := bNiDmaInputRequestToDmaVar.ByteLane;
            end if;

            -- Generate TransferEnd signals
            bNiDmaInputDataFromDma.TransferEnd <= false;
            if ByteLaneVar + (bNiDmaInputRequestToDmaVar.ByteCount - BytesReceived)
              <= kNiDmaDataWidthInBytes then

              bNiDmaInputDataFromDma.TransferEnd <= true;

            end if;

            -- Compute the Byte Enable
            ByteEnableVar := GetByteEnables(StartingLane => ByteLaneVar,
                          ByteCount => bNiDmaInputRequestToDmaVar.ByteCount-BytesReceived);

            -- Compute the Byte Count
            ByteCountVar := GetWordByteCount(StartingLane => ByteLaneVar,
                          ByteCount => bNiDmaInputRequestToDmaVar.ByteCount-BytesReceived);

            -- Compute the DmaChannel
            DmaChannelVar := GetDmaChannelOneHot(bNiDmaInputRequestToDmaVar.Space,
              bNiDmaInputRequestToDmaVar.Channel);


            bNiDmaInputDataFromDma.Space <= bNiDmaInputRequestToDmaVar.Space;
            bNiDmaInputDataFromDma.Channel <= bNiDmaInputRequestToDmaVar.Channel;
            bNiDmaInputDataFromDma.DmaChannel <= DmaChannelVar;
            bNiDmaInputDataFromDma.ByteLane <= ByteLaneVar;
            bNiDmaInputDataFromDma.ByteCount <= ByteCountVar;
            bNiDmaInputDataFromDma.Done <= bNiDmaInputRequestToDmaVar.Done;
            bNiDmaInputDataFromDma.EndOfRecord <= bNiDmaInputRequestToDmaVar.EndOfRecord;
            bNiDmaInputDataFromDma.ByteEnable <= ByteEnableVar;
            bNiDmaInputDataFromDma.Pop <= true;

            -- The number of bytes Read in a transfer represents the number of ones
            -- that are sent in the BytesEnable signal;
            BytesReceived := BytesReceived + to_integer(ByteCountVar);
          end if;

          i := i + 1;
        else

          bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
        end if;

      end if;

    end if;

      bLastNiDmaInputRequestToDma <= bNiDmaInputRequestToDmaVar;
      BytesReceivedSig <= BytesReceived; -- This signal is used just for debug.
      --vhook_nowarn BytesReceivedSig
  end process ReadData;

  DataReadLatency:
  -- This process implements the data read latency between the Pop and the moment when
  -- Data is available on the bNiDmaInputDataToDma bus. The implemented latency is 2
  -- meaning that Data will be available one clock cycle after the Pop is issued.
  -- The process actually delay the information sent together with Pops so that it will
  -- be available together with the Data. The ByteLane and ByteCount information
  -- is needed to check the received data.
  process(aReset, Clk)
  begin
    if aReset then
      bNiDmaInputDataFromDmaDly1 <= kNiDmaInputDataFromDmaZero;
      bNiDmaInputDataFromDmaDly <= kNiDmaInputDataFromDmaZero;
    elsif rising_edge(Clk) then
      bNiDmaInputDataFromDmaDly1 <= bNiDmaInputDataFromDma;
      bNiDmaInputDataFromDmaDly <= bNiDmaInputDataFromDmaDly1;
    end if;
  end process DataReadLatency;



  CheckData: process(aReset, Clk, bNiDmaInputDataFromDmaDly)
  -- This process verify if the received data match with the data that was written
  -- in the FIFO.
    variable SampleWidthInBits : natural := 64;
    variable SampleWidthInBytes : natural := 1;
    variable FirstDataSample: natural := 1;
    variable ExpectedData: std_logic_vector(kNiDmaDataWidth-1 downto 0) := (others => '0');
    variable ByteLaneVar: natural := 0;
    variable ByteCountVar: natural := 0;

  begin

  --vhook_nowarn CheckData/SampleWidthInBytes
  SampleWidthInBits := kFifoDataWidthArray(to_integer(bNiDmaInputDataFromDmaDly.Channel));
  SampleWidthInBytes := SampleWidthInBits/8;

    if aReset then
      FirstDataSample := 1;
    elsif rising_edge(Clk) then
      if ReceiveDataDone then
        FirstDataSample := 1;
      end if;
      if bNiDmaInputDataFromDmaDly.Pop then

        ByteLaneVar := to_integer(bNiDmaInputDataFromDmaDly.ByteLane);

        ByteCountVar := to_integer(bNiDmaInputDataFromDmaDly.ByteCount);

        -- Determine the expected data of the entire FIFO location
        ExpectedData := (others => '0');
        for i in 0 to ByteCountVar/SampleWidthInBytes-1 loop

          -- The values generated for the expected data should be defined on the
          -- number of bits that Data Width is defined even if the Fifo Data Width
          -- will be rounded up to the next power of two size.
          ExpectedData(ByteLaneVar*8+(i+1)*SampleWidthInBits-1
            downto ByteLaneVar*8+(i)*SampleWidthInBits) :=
            std_logic_vector(to_unsigned((FirstDataSample+i) mod
            2**smaller(kDataWidthArray(to_integer(bNiDmaInputDataFromDmaDly.Channel)),
            30), SampleWidthInBits));
        end loop;

        -- Each byte in a transfer is checked individually.
        for i in 1 to ByteCountVar loop

          assert bNiDmaInputDataToDma.Data((ByteLaneVar*8+i*8)-1 downto
            (ByteLaneVar*8+(i-1)*8)) = ExpectedData((ByteLaneVar*8+i*8)-1 downto
            (ByteLaneVar*8+(i-1)*8))
            report "The receive data is not as expected " & Image(i) & LF &
                     "The received data is " & Image(bNiDmaInputDataToDma.Data
                     ((ByteLaneVar*8+i*8)-1 downto (ByteLaneVar*8+(i-1)*8))) & LF &
                     "The expected data is " & Image(ExpectedData((ByteLaneVar*8+i*8)-1
                     downto (ByteLaneVar*8+(i-1)*8)))
            severity error;
        end loop;

      -- This is the first data byte of a data element transferred. The remaining data
      -- bytes of a data element transfered will be computed before the verification.
      FirstDataSample := FirstDataSample + ByteCountVar/(SampleWidthInBits/8);

      end if;

    end if;

  end process CheckData;


end test;
