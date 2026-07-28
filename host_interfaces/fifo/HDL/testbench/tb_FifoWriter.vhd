-------------------------------------------------------------------------------
--
-- File: tb_FifoWriter.vhd
-- Original Project: LabVIEW FPGA
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--   Comprehensive testbench for NiSharedFifoWriter.
--   Tests FIFO push, DMA transfer, stream state transitions, reset,
--   arbiter thresholds, flush operations, SATCR management, eviction
--   timeout, and random stress testing.
--
--   Unlike the old DmaPortCommIfcInputWrapper testbench, this uses the
--   simplified strobe-based interfaces (no enable chains).
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;
  use work.PkgDmaPortCommIfcStreamStates.all;
  use work.PkgDmaPortDataPackingFifo.all;
  use work.PkgNiDma.all;
  use work.PkgNiDmaConfig.all;
  use work.PkgCommIntConfiguration.all;

entity tb_FifoWriter is
end tb_FifoWriter;

architecture test of tb_FifoWriter is

  ---------------------------------------------------------------------------
  -- DUT Configuration
  ---------------------------------------------------------------------------
  constant kFifoDepth         : natural  := 1023;
  constant kDataWidth         : positive := 32;
  constant kNumOfSamplesPerWrite : positive := 1;
  constant kBaseOffset        : natural  := 16#8000#;
  constant kStreamNumber      : natural  := 0;
  constant kEvictionTimeout   : natural  := 512;
  constant kPeerToPeerStream  : boolean  := false;
  constant kFxpType           : boolean  := false;
  constant kSignExtend        : boolean  := false;
  constant kDisableOnFifoTimeout : boolean := false;

  -- Derived constants
  constant kSampleSize     : natural := ActualSampleSize(
    SampleSizeInBits => kDataWidth,
    PeerToPeer       => kPeerToPeerStream,
    FxpType          => kFxpType);
  constant kSampleBytes    : natural := kSampleSize / 8;
  constant kFifoCountWidth : natural := Log2(kFifoDepth);
  constant kMaxTrackable   : natural := 2**kFifoCountWidth - 1;
  constant kMaxTransfer    : natural := kNiDmaInputMaxTransfer;
  constant kBusWidthBytes  : natural := kNiDmaDataWidthInBytes;

  -- Register offsets
  constant kControlOffset         : natural := 0;
  constant kStatusOffset          : natural := 4;
  constant kSatcrOffset           : natural := 8;
  constant kInterruptStatusOffset : natural := 16#0C#;
  constant kInterruptMaskOffset   : natural := 16#10#;
  constant kFifoCountOffset       : natural := 16#14#;

  -- Control register bit indices
  constant kResetBit               : natural := 0;
  constant kStartChannelBit        : natural := 1;
  constant kStopChannelBit         : natural := 2;
  constant kStopChannelWithFlushBit : natural := 3;
  constant kResetSatcrBit          : natural := 4;
  constant kLinkStreamBit          : natural := 5;
  constant kUnlinkStreamBit        : natural := 6;

  -- Status register bit indices
  constant kResetStatusBit         : natural := 0;
  constant kDisableStatusBit       : natural := 1;
  constant kStateBitLow            : natural := 2;
  constant kStateBitHigh           : natural := 3;
  constant kFlushingStatusBit      : natural := 7;
  constant kFlushingFailedStatusBit : natural := 8;

  -- Interrupt status bit indices
  constant kStartStreamIrqBit      : natural := 4;
  constant kStopStreamIrqBit       : natural := 6;

  -- Interrupt mask bit indices
  constant kEnableStartStreamIrqBit : natural := 4;
  constant kEnableStopStreamIrqBit  : natural := 6;

  -- Clock periods
  constant kBusClkPeriod : time := 8 ns;
  constant kViClkPeriod  : time := 23 ns;

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal BusClk : std_logic := '0';
  signal ViClk  : std_logic := '0';

  signal aReset        : boolean := true;
  signal bReset        : boolean := false;
  signal aDiagramReset : boolean := true;

  signal bNiDmaInputRequestToDma   : NiDmaInputRequestToDma_t;
  signal bNiDmaInputRequestFromDma : NiDmaInputRequestFromDma_t := kNiDmaInputRequestFromDmaZero;
  signal bNiDmaInputDataToDma      : NiDmaInputDataToDma_t;
  signal bNiDmaInputDataFromDma    : NiDmaInputDataFromDma_t := kNiDmaInputDataFromDmaZero;
  signal bNiDmaInputStatusFromDma  : NiDmaInputStatusFromDma_t := kNiDmaInputStatusFromDmaZero;

  signal bArbiterNormalReq    : std_logic;
  signal bArbiterEmergencyReq : std_logic;
  signal bArbiterDone         : std_logic;
  signal bArbiterGrant        : std_logic := '0';

  signal bRegPortIn  : RegPortIn_t := kRegPortInZero;
  signal bRegPortOut : RegPortOut_t;

  signal vDataIn        : std_logic_vector(kDataWidth * kNumOfSamplesPerWrite - 1 downto 0) := (others => '0');
  signal vFull          : boolean;
  signal vWriteFifo     : boolean := false;
  signal vFlush         : boolean := false;
  signal vCtCount       : unsigned(31 downto 0);
  signal vInputValid    : boolean := false;
  signal vReadyForInput : boolean;

  signal vStreamStateOut             : StreamStateValue_t;
  signal vStartStreamRequest         : boolean := false;
  signal vStopRequestStrobe          : boolean := false;
  signal vFlushTimeoutRequest        : boolean := false;
  signal vStopWithFlushRequestStrobe : boolean := false;

  signal bIrq : IrqStatusToInterface_t;

  signal StopSim : boolean := false;

  -- Protocol-checker violation counter (see NiSharedFifoWriterChecker below)
  signal WriterViolations : natural := 0;

  subtype TestStatusString_t is string(1 to 40);
  signal TestStatus : TestStatusString_t := (others => ' ');

  -- Timeout constant for wait statements
  constant kTimeout : time := 200 us;

  ---------------------------------------------------------------------------
  -- Clock generation
  ---------------------------------------------------------------------------
begin

  BusClk <= not BusClk after kBusClkPeriod / 2 when not StopSim else '0';
  ViClk  <= not ViClk  after kViClkPeriod / 2  when not StopSim else '0';

  ---------------------------------------------------------------------------
  -- DUT instantiation
  ---------------------------------------------------------------------------
  DUT: entity work.NiSharedFifoWriterTbWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepth,
      kDataWidth            => kDataWidth,
      kNumOfSamplesPerWrite => kNumOfSamplesPerWrite,
      kBaseOffset           => kBaseOffset,
      kStreamNumber         => kStreamNumber,
      kEvictionTimeout      => kEvictionTimeout,
      kPeerToPeerStream     => kPeerToPeerStream,
      kFxpType              => kFxpType,
      kSignExtend           => kSignExtend,
      kDisableOnFifoTimeout => kDisableOnFifoTimeout)
    port map (
      aReset                      => aReset,
      bReset                      => bReset,
      aDiagramReset               => aDiagramReset,
      BusClk                      => BusClk,
      ViClk                       => ViClk,
      bNiDmaInputRequestToDma     => bNiDmaInputRequestToDma,
      bNiDmaInputRequestFromDma   => bNiDmaInputRequestFromDma,
      bNiDmaInputDataToDma        => bNiDmaInputDataToDma,
      bNiDmaInputDataFromDma      => bNiDmaInputDataFromDma,
      bNiDmaInputStatusFromDma    => bNiDmaInputStatusFromDma,
      bArbiterNormalReq           => bArbiterNormalReq,
      bArbiterEmergencyReq        => bArbiterEmergencyReq,
      bArbiterDone                => bArbiterDone,
      bArbiterGrant               => bArbiterGrant,
      bRegPortIn                  => bRegPortIn,
      bRegPortOut                 => bRegPortOut,
      vDataIn                     => vDataIn,
      vFull                       => vFull,
      vWriteFifo                  => vWriteFifo,
      vFlush                      => vFlush,
      vCtCount                    => vCtCount,
      vInputValid                 => vInputValid,
      vReadyForInput              => vReadyForInput,
      vStreamStateOut             => vStreamStateOut,
      vStartStreamRequest         => vStartStreamRequest,
      vStopRequestStrobe          => vStopRequestStrobe,
      vFlushTimeoutRequest        => vFlushTimeoutRequest,
      vStopWithFlushRequestStrobe => vStopWithFlushRequestStrobe,
      bIrq                        => bIrq);


  ---------------------------------------------------------------------------
  -- Passive writer-interface protocol monitor. It only observes the user-side
  -- (ViClk-domain) signals driven into the FIFO and asserts if the writer
  -- contract documented in fifo/docs/interface-descriptions.md is violated. It
  -- never drives any signal.
  ---------------------------------------------------------------------------
  WriterCheck: entity work.NiSharedFifoWriterChecker
    generic map (
      kName        => "tb_FifoWriter.DUT",
      kSampleWidth => vDataIn'length)
    port map (
      ViClk                       => ViClk,
      aReset                      => aDiagramReset,
      vFull                       => vFull,
      vWriteFifo                  => vWriteFifo,
      vInputValid                 => vInputValid,
      vDataIn                     => vDataIn,
      vStreamStateOut             => vStreamStateOut,
      vStartStreamRequest         => vStartStreamRequest,
      vStopRequestStrobe          => vStopRequestStrobe,
      vStopWithFlushRequestStrobe => vStopWithFlushRequestStrobe,
      ViolationCount              => WriterViolations);


  ---------------------------------------------------------------------------
  -- Stimulus process
  ---------------------------------------------------------------------------
  Stimulus: process

    -- Register read result
    variable readValue : std_logic_vector(31 downto 0);

    -- Random stress test variables
    variable vRandFillCount : natural;
    variable vRandSatcrVal  : natural;
    variable vRandClkWait   : natural;

    -- Wait for N rising edges of BusClk
    procedure BusClkWait(N : integer := 1) is
    begin
      for i in 1 to N loop
        wait until rising_edge(BusClk);
      end loop;
    end procedure;

    -- Wait for N rising edges of ViClk
    procedure ViClkWait(N : integer := 1) is
    begin
      for i in 1 to N loop
        wait until rising_edge(ViClk);
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- Send a DMA status response pulse (manual, for DisableStream etc.)
    --------------------------------------------------------------------------
    procedure SendDmaStatusResponse is
    begin
      wait until falling_edge(BusClk);
      bNiDmaInputStatusFromDma.Ready      <= true;
      bNiDmaInputStatusFromDma.Space      <= kNiDmaSpaceStream;
      bNiDmaInputStatusFromDma.DmaChannel <= (kStreamNumber => true, others => false);
      wait until rising_edge(BusClk);
      bNiDmaInputStatusFromDma <= kNiDmaInputStatusFromDmaZero;
    end procedure;

    --------------------------------------------------------------------------
    -- Register write: drive bRegPortIn for two BusClk rising edges.
    --------------------------------------------------------------------------
    procedure RegisterWrite(Value : integer; Address : natural) is
    begin
      wait until falling_edge(BusClk);
      while not bRegPortOut.Ready loop
        wait until falling_edge(BusClk);
      end loop;
      bRegPortIn.Wt      <= true;
      bRegPortIn.Rd      <= false;
      bRegPortIn.Data    <= std_logic_vector(to_unsigned(Value, 32));
      bRegPortIn.Address <= resize(to_unsigned(Address / 4, 30), bRegPortIn.Address'length);
      BusClkWait(1);
      BusClkWait(1);
      bRegPortIn.Wt <= false;
    end procedure;

    --------------------------------------------------------------------------
    -- Register read: drive bRegPortIn, capture result.
    --------------------------------------------------------------------------
    procedure RegisterRead(Address : natural) is
    begin
      wait until falling_edge(BusClk);
      while not bRegPortOut.Ready loop
        wait until falling_edge(BusClk);
      end loop;
      bRegPortIn.Wt      <= false;
      bRegPortIn.Rd      <= true;
      bRegPortIn.Address <= resize(to_unsigned(Address / 4, 30), bRegPortIn.Address'length);
      BusClkWait(1);
      BusClkWait(1);
      bRegPortIn.Rd <= false;
      wait for 1 ns;
      if not bRegPortOut.DataValid then
        report "RegisterRead: DataValid not asserted for address " &
               integer'image(Address)
          severity error;
      end if;
      readValue := bRegPortOut.Data;
    end procedure;

    --------------------------------------------------------------------------
    -- Check stream state from Status register
    --------------------------------------------------------------------------
    procedure CheckStreamState(ExpectedState : StreamState_t) is
      variable StateValue : StreamStateValue_t;
    begin
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      StateValue := readValue(kStateBitHigh downto kStateBitLow);
      assert to_StreamState(StateValue) = ExpectedState
        report "Stream state mismatch: expected " &
               StreamState_t'image(ExpectedState) & " got " &
               StreamState_t'image(to_StreamState(StateValue))
        severity error;
    end procedure;

    --------------------------------------------------------------------------
    -- WaitOnStreamState: poll Status until stream reaches desired state
    --------------------------------------------------------------------------
    procedure WaitOnStreamState(DesiredState : StreamState_t) is
      variable StateValue : StreamStateValue_t;
      variable SanityCount : natural := 0;
    begin
      loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        StateValue := readValue(kStateBitHigh downto kStateBitLow);
        exit when to_StreamState(StateValue) = DesiredState;
        SanityCount := SanityCount + 1;
        assert SanityCount < 500
          report "WaitOnStreamState: timed out waiting for " &
                 StreamState_t'image(DesiredState)
          severity failure;
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- Enable the DMA stream via host register write.
    --------------------------------------------------------------------------
    procedure EnableStream is
      variable SanityCount : natural := 0;
    begin
      RegisterWrite(Value   => 2**kStartChannelBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(50);
      loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        exit when readValue(kDisableStatusBit) = '0';
        SanityCount := SanityCount + 1;
        assert SanityCount < 200
          report "EnableStream: timed out"
          severity failure;
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- Link the stream (Unlinked -> Disabled)
    --------------------------------------------------------------------------
    procedure LinkStream is
    begin
      RegisterWrite(Value   => 2**kLinkStreamBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(20);
      WaitOnStreamState(Disabled);
    end procedure;

    --------------------------------------------------------------------------
    -- Unlink the stream (Disabled -> Unlinked)
    --------------------------------------------------------------------------
    procedure UnlinkStream is
    begin
      RegisterWrite(Value   => 2**kUnlinkStreamBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(20);
      WaitOnStreamState(Unlinked);
    end procedure;

    --------------------------------------------------------------------------
    -- Disable the DMA stream (no flush).
    --------------------------------------------------------------------------
    procedure DisableStream is
      variable SanityCount     : natural := 0;
      variable vBytesTotal     : natural;
      variable vWordsRemaining : natural;
    begin
      RegisterWrite(Value   => 2**kStopChannelBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(10);
      loop
        if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
          wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
          assert bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1'
            report "DisableStream: timed out waiting for arbiter request"
            severity failure;
        end if;
        wait until falling_edge(BusClk);
        bArbiterGrant <= '1';
        if not (bNiDmaInputRequestToDma.Request or bNiDmaInputRequestToDma.Done) then
          wait until bNiDmaInputRequestToDma.Request or bNiDmaInputRequestToDma.Done for kTimeout;
        end if;
        assert bNiDmaInputRequestToDma.Request or bNiDmaInputRequestToDma.Done
          report "DisableStream: timed out waiting for DMA request"
          severity failure;

        if bNiDmaInputRequestToDma.Done then
          wait until rising_edge(BusClk);
          bNiDmaInputRequestFromDma.Acknowledge <= true;
          wait until rising_edge(BusClk);
          bNiDmaInputRequestFromDma.Acknowledge <= false;
          bArbiterGrant <= '0';
          BusClkWait(1);
          SendDmaStatusResponse;
          exit;
        else
          vBytesTotal := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
          if vBytesTotal = 0 then
            vBytesTotal := 256;
          end if;
          vWordsRemaining := (vBytesTotal + kBusWidthBytes - 1) / kBusWidthBytes;
          wait until rising_edge(BusClk);
          bNiDmaInputRequestFromDma.Acknowledge <= true;
          wait until rising_edge(BusClk);
          bNiDmaInputRequestFromDma.Acknowledge <= false;
          bArbiterGrant <= '0';
          for i in 1 to vWordsRemaining loop
            wait until falling_edge(BusClk);
            bNiDmaInputDataFromDma.Pop <= true;
            bNiDmaInputDataFromDma.TransferStart <= (i = 1);
            bNiDmaInputDataFromDma.TransferEnd <= (i = vWordsRemaining);
            wait until rising_edge(BusClk);
          end loop;
          wait until falling_edge(BusClk);
          bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
          BusClkWait(2);
          SendDmaStatusResponse;
        end if;
        SanityCount := SanityCount + 1;
        assert SanityCount < 20
          report "DisableStream: too many flush transfers before Done"
          severity failure;
      end loop;
      BusClkWait(50);
      SanityCount := 0;
      loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        exit when readValue(kDisableStatusBit) = '1';
        SanityCount := SanityCount + 1;
        assert SanityCount < 200
          report "DisableStream: timed out waiting for disable"
          severity failure;
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- Disable with flush via host register write.
    -- First drains any pending DMA transfers, then writes StopChannelWithFlush,
    -- then handles the flush drain and Done sequence.
    --------------------------------------------------------------------------
    procedure DisableStreamWithFlush is
      variable SanityCount     : natural := 0;
      variable vBytesTotal     : natural;
      variable vWordsRemaining : natural;
    begin
      -- Step 1: Drain any pending arbiter requests before issuing flush.
      -- This ensures the DMA controller is in Idle state when we write
      -- StopChannelWithFlush, avoiding a FifoClear race condition.
      SanityCount := 0;
      while bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' loop
        -- Inline transfer: grant → request → ack → data → status
        wait until falling_edge(BusClk);
        bArbiterGrant <= '1';
        if not bNiDmaInputRequestToDma.Request then
          wait until bNiDmaInputRequestToDma.Request for kTimeout;
        end if;
        assert bNiDmaInputRequestToDma.Request
          report "DisableStreamWithFlush: pre-drain request timeout"
          severity failure;
        vBytesTotal := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
        if vBytesTotal = 0 then
          vBytesTotal := 256;
        end if;
        vWordsRemaining := (vBytesTotal + kBusWidthBytes - 1) / kBusWidthBytes;
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= true;
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= false;
        bArbiterGrant <= '0';
        for i in 1 to vWordsRemaining loop
          wait until falling_edge(BusClk);
          bNiDmaInputDataFromDma.Pop <= true;
          bNiDmaInputDataFromDma.TransferStart <= (i = 1);
          bNiDmaInputDataFromDma.TransferEnd <= (i = vWordsRemaining);
          wait until rising_edge(BusClk);
        end loop;
        wait until falling_edge(BusClk);
        bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
        BusClkWait(2);
        SendDmaStatusResponse;
        SanityCount := SanityCount + 1;
        assert SanityCount < 50
          report "DisableStreamWithFlush: too many pre-flush drains"
          severity failure;
        BusClkWait(5);
      end loop;

      -- Step 2: Write StopChannelWithFlush
      RegisterWrite(Value   => 2**kStopChannelWithFlushBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(20);

      -- Step 3: Wait for the DMA to complete the flush and disable.
      -- After StopChannelWithFlush with pre-drained requests, the DMA
      -- controller does an internal FifoClear then transitions to Disabled
      -- without needing further arbiter handshakes. However, if the DMA
      -- does request more transfers (e.g., some data arrived between drain
      -- and flush write), handle those too.
      SanityCount := 0;
      loop
        -- Check if already disabled
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        if readValue(kDisableStatusBit) = '1' then
          exit;
        end if;

        -- If arbiter is requesting, handle the transfer
        if bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' then
          wait until falling_edge(BusClk);
          bArbiterGrant <= '1';
          if not (bNiDmaInputRequestToDma.Request or bNiDmaInputRequestToDma.Done) then
            wait until bNiDmaInputRequestToDma.Request or bNiDmaInputRequestToDma.Done for kTimeout;
          end if;
          assert bNiDmaInputRequestToDma.Request or bNiDmaInputRequestToDma.Done
            report "DisableStreamWithFlush: timed out waiting for DMA"
            severity failure;

          if bNiDmaInputRequestToDma.Done then
            wait until rising_edge(BusClk);
            bNiDmaInputRequestFromDma.Acknowledge <= true;
            wait until rising_edge(BusClk);
            bNiDmaInputRequestFromDma.Acknowledge <= false;
            bArbiterGrant <= '0';
            BusClkWait(1);
            SendDmaStatusResponse;
            exit;
          else
            vBytesTotal := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
            if vBytesTotal = 0 then
              vBytesTotal := 256;
            end if;
            vWordsRemaining := (vBytesTotal + kBusWidthBytes - 1) / kBusWidthBytes;
            wait until rising_edge(BusClk);
            bNiDmaInputRequestFromDma.Acknowledge <= true;
            wait until rising_edge(BusClk);
            bNiDmaInputRequestFromDma.Acknowledge <= false;
            bArbiterGrant <= '0';
            for i in 1 to vWordsRemaining loop
              wait until falling_edge(BusClk);
              bNiDmaInputDataFromDma.Pop <= true;
              bNiDmaInputDataFromDma.TransferStart <= (i = 1);
              bNiDmaInputDataFromDma.TransferEnd <= (i = vWordsRemaining);
              wait until rising_edge(BusClk);
            end loop;
            wait until falling_edge(BusClk);
            bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
            BusClkWait(2);
            SendDmaStatusResponse;
          end if;
        else
          BusClkWait(10);
        end if;

        SanityCount := SanityCount + 1;
        assert SanityCount < 500
          report "DisableStreamWithFlush: timed out waiting for disable"
          severity failure;
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- Push data using the simplified strobe interface.
    --------------------------------------------------------------------------
    procedure PushData(Value : integer) is
    begin
      wait until rising_edge(ViClk) and vReadyForInput;
      vDataIn      <= std_logic_vector(to_unsigned(Value, vDataIn'length));
      vInputValid  <= true;
      vWriteFifo   <= true;
      wait until rising_edge(ViClk);
      vWriteFifo   <= false;
      vInputValid  <= false;
    end procedure;

    --------------------------------------------------------------------------
    -- Fill FIFO with Count samples starting at StartValue.
    --------------------------------------------------------------------------
    procedure FillFifo(StartValue : natural; Count : natural) is
    begin
      for i in 0 to Count - 1 loop
        PushData((StartValue + i) mod 65536);
      end loop;
      ViClkWait(10);
      BusClkWait(10);
    end procedure;

    --------------------------------------------------------------------------
    -- Receive one DMA data transfer (arbiter handshake + data phase).
    --------------------------------------------------------------------------
    procedure ReceiveOneDmaTransfer is
      variable vBytesTotal     : natural;
      variable vWordsRemaining : natural;
    begin
      if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
        wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
        assert bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1'
          report "ReceiveOneDmaTransfer: timed out waiting for arbiter"
          severity failure;
      end if;
      wait until falling_edge(BusClk);
      bArbiterGrant <= '1';
      if not bNiDmaInputRequestToDma.Request then
        wait until bNiDmaInputRequestToDma.Request for kTimeout;
      end if;
      assert bNiDmaInputRequestToDma.Request
        report "ReceiveOneDmaTransfer: timed out waiting for Request"
        severity failure;

      vBytesTotal := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
      if vBytesTotal = 0 then
        vBytesTotal := 256;
      end if;
      vWordsRemaining := (vBytesTotal + kBusWidthBytes - 1) / kBusWidthBytes;

      wait until rising_edge(BusClk);
      bNiDmaInputRequestFromDma.Acknowledge <= true;
      wait until rising_edge(BusClk);
      bNiDmaInputRequestFromDma.Acknowledge <= false;
      bArbiterGrant <= '0';

      for i in 1 to vWordsRemaining loop
        wait until falling_edge(BusClk);
        bNiDmaInputDataFromDma.Pop <= true;
        bNiDmaInputDataFromDma.TransferStart <= (i = 1);
        bNiDmaInputDataFromDma.TransferEnd <= (i = vWordsRemaining);
        wait until rising_edge(BusClk);
      end loop;
      wait until falling_edge(BusClk);
      bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
      BusClkWait(2);
      SendDmaStatusResponse;
    end procedure;

    --------------------------------------------------------------------------
    -- ReceiveData: handle multiple DMA transfers for NumberOfBytes.
    --------------------------------------------------------------------------
    procedure ReceiveData(NumberOfBytes : natural) is
      variable NumberOfReads : natural;
      variable ByteCount     : natural;
    begin
      if NumberOfBytes <= kMaxTransfer then
        NumberOfReads := 1;
      elsif NumberOfBytes mod kMaxTransfer = 0 then
        NumberOfReads := NumberOfBytes / kMaxTransfer;
      else
        NumberOfReads := (NumberOfBytes / kMaxTransfer) + 1;
      end if;

      for i in 1 to NumberOfReads loop
        if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
          wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
          if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
            RegisterRead(Address => kBaseOffset + kStatusOffset);
            if readValue(kDisableStatusBit) = '1' then
              return;
            end if;
            assert false report "ReceiveData: timed out" severity failure;
          end if;
        end if;

        wait until falling_edge(BusClk);
        bArbiterGrant <= '1';
        if not bNiDmaInputRequestToDma.Request then
          wait until bNiDmaInputRequestToDma.Request for kTimeout;
        end if;
        assert bNiDmaInputRequestToDma.Request
          report "ReceiveData: timed out waiting for Request"
          severity failure;

        ByteCount := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
        if bNiDmaInputRequestToDma.Done and ByteCount = 0 then
          wait until rising_edge(BusClk);
          bNiDmaInputRequestFromDma.Acknowledge <= true;
          wait until rising_edge(BusClk);
          bNiDmaInputRequestFromDma.Acknowledge <= false;
          bArbiterGrant <= '0';
          BusClkWait(1);
          SendDmaStatusResponse;
          return;
        end if;

        ReceiveOneDmaTransfer;
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- CheckArbiterSignals: check expected arbiter flags.
    --------------------------------------------------------------------------
    procedure CheckArbiterSignals(
      ExpNormalReq    : std_logic;
      ExpEmergencyReq : std_logic
    ) is
    begin
      assert bArbiterNormalReq = ExpNormalReq
        report "ArbiterNormalReq: expected " & std_logic'image(ExpNormalReq) &
               " got " & std_logic'image(bArbiterNormalReq)
        severity error;
      assert bArbiterEmergencyReq = ExpEmergencyReq
        report "ArbiterEmergencyReq: expected " & std_logic'image(ExpEmergencyReq) &
               " got " & std_logic'image(bArbiterEmergencyReq)
        severity error;
    end procedure;

    --------------------------------------------------------------------------
    -- DoDataRequest: full data transfer test cycle.
    --------------------------------------------------------------------------
    procedure DoDataRequest(
      FifoFillSamples         : natural;
      SatcrValueInBytes       : natural;
      ClkWaitBeforeGrant      : natural := 0;
      ExtraSatcrWrites        : natural := 0;
      ExtraSatcrValue         : natural := 0
    ) is
      variable CurrentSatcr    : natural;
      variable CurrentFifoFill : natural;
      variable AlignmentSize   : natural;
      variable ExpectedSize    : natural;
      variable EffectiveFill   : natural;
      variable ExtraSatcrCount : natural;
      variable SanityCount     : natural;
      variable vBytesTotal     : natural;
      variable vWordsRemaining : natural;
    begin
      -- Reset channel
      RegisterWrite(Value   => 2**kResetBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(10);
      for i in 1 to 200 loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        exit when readValue(kResetStatusBit) = '1';
      end loop;
      assert readValue(kResetStatusBit) = '1'
        report "DoDataRequest: reset did not complete" severity failure;

      -- Link and enable
      LinkStream;
      EnableStream;

      -- Write SATCR
      RegisterWrite(Value   => SatcrValueInBytes,
                    Address => kBaseOffset + kSatcrOffset);
      BusClkWait(5);

      -- Fill FIFO (cap to max trackable)
      EffectiveFill := FifoFillSamples;
      if EffectiveFill > kMaxTrackable then
        EffectiveFill := kMaxTrackable;
      end if;
      if EffectiveFill > 0 then
        FillFifo(1, EffectiveFill);
      end if;

      CurrentSatcr    := SatcrValueInBytes;
      CurrentFifoFill := EffectiveFill;
      AlignmentSize   := kMaxTransfer;
      ExtraSatcrCount := ExtraSatcrWrites;

      -- Main transfer loop
      SanityCount := 0;
      while CurrentSatcr > 0 and CurrentFifoFill > 0 loop
        -- Compute expected packet size
        ExpectedSize := AlignmentSize;
        if ExpectedSize > CurrentSatcr then
          ExpectedSize := CurrentSatcr;
        end if;
        if ExpectedSize > CurrentFifoFill * kSampleBytes then
          ExpectedSize := CurrentFifoFill * kSampleBytes;
        end if;

        BusClkWait(ClkWaitBeforeGrant);

        -- Wait for arbiter request
        if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
          wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
          if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
            exit;
          end if;
        end if;

        wait until falling_edge(BusClk);
        bArbiterGrant <= '1';

        -- Wait for Request
        wait until falling_edge(BusClk);
        if not bNiDmaInputRequestToDma.Request then
          wait until bNiDmaInputRequestToDma.Request for kTimeout;
        end if;
        assert bNiDmaInputRequestToDma.Request
          report "DoDataRequest: timed out waiting for Request"
          severity failure;

        vBytesTotal := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
        if vBytesTotal = 0 then
          vBytesTotal := 256;
        end if;
        vWordsRemaining := (vBytesTotal + kBusWidthBytes - 1) / kBusWidthBytes;

        -- Acknowledge
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= true;
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= false;
        bArbiterGrant <= '0';

        -- Data phase
        for i in 1 to vWordsRemaining loop
          wait until falling_edge(BusClk);
          bNiDmaInputDataFromDma.Pop <= true;
          bNiDmaInputDataFromDma.TransferStart <= (i = 1);
          bNiDmaInputDataFromDma.TransferEnd <= (i = vWordsRemaining);
          wait until rising_edge(BusClk);
        end loop;
        wait until falling_edge(BusClk);
        bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
        BusClkWait(2);
        SendDmaStatusResponse;

        -- Update tracking
        if vBytesTotal >= kMaxTransfer then
          AlignmentSize := kMaxTransfer;
        else
          AlignmentSize := kMaxTransfer - vBytesTotal;
        end if;

        if CurrentFifoFill >= vBytesTotal / kSampleBytes then
          CurrentFifoFill := CurrentFifoFill - vBytesTotal / kSampleBytes;
        else
          CurrentFifoFill := 0;
        end if;

        if CurrentSatcr >= vBytesTotal then
          CurrentSatcr := CurrentSatcr - vBytesTotal;
        else
          CurrentSatcr := 0;
        end if;

        -- Extra SATCR writes
        if ExtraSatcrCount > 0 and CurrentSatcr = 0 then
          RegisterWrite(Value   => ExtraSatcrValue,
                        Address => kBaseOffset + kSatcrOffset);
          BusClkWait(5);
          CurrentSatcr    := ExtraSatcrValue;
          ExtraSatcrCount := ExtraSatcrCount - 1;
        end if;

        SanityCount := SanityCount + 1;
        assert SanityCount < 500
          report "DoDataRequest: too many transfer iterations"
          severity failure;
      end loop;

      -- Disable stream
      DisableStream;
    end procedure;

    --------------------------------------------------------------------------
    -- ResetChannel: sync reset + wait for ResetStatus, then LinkStream.
    --------------------------------------------------------------------------
    procedure ResetChannel is
    begin
      RegisterWrite(Value   => 2**kResetBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(10);
      for i in 1 to 200 loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        exit when readValue(kResetStatusBit) = '1';
      end loop;
      assert readValue(kResetStatusBit) = '1'
        report "ResetChannel: reset did not complete" severity failure;
      LinkStream;
    end procedure;

    --------------------------------------------------------------------------
    -- StartStreamFromDiagram: use direct strobe to start stream.
    --------------------------------------------------------------------------
    procedure StartStreamFromDiagram(
      WriteSatcr        : boolean := false;
      SatcrValueInBytes : natural := 0
    ) is
    begin
      vStartStreamRequest <= true;
      ViClkWait(1);
      vStartStreamRequest <= false;
      EnableStream;
      if WriteSatcr then
        RegisterWrite(Value   => SatcrValueInBytes,
                      Address => kBaseOffset + kSatcrOffset);
        BusClkWait(5);
      end if;
    end procedure;

    --------------------------------------------------------------------------
    -- StopStreamFromDiagram: strobe stop request, optionally with flush.
    --------------------------------------------------------------------------
    procedure StopStreamFromDiagram(
      Flush           : boolean := false;
      FlushBytes      : natural := 0;
      DoFlushTimeout  : boolean := false;
      FlushTimeoutClk : natural := 0
    ) is
      variable SanityCount     : natural := 0;
      variable vBytesTotal     : natural;
      variable vWordsRemaining : natural;
    begin
      if Flush then
        vStopWithFlushRequestStrobe <= true;
        ViClkWait(1);
        vStopWithFlushRequestStrobe <= false;
        if FlushBytes > 0 then
          ReceiveData(FlushBytes);
        end if;
        if DoFlushTimeout then
          BusClkWait(FlushTimeoutClk);
          vFlushTimeoutRequest <= true;
          ViClkWait(1);
          vFlushTimeoutRequest <= false;
        end if;
      else
        vStopRequestStrobe <= true;
        ViClkWait(1);
        vStopRequestStrobe <= false;
      end if;

      BusClkWait(20);

      -- Check if already disabled
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      if readValue(kDisableStatusBit) = '1' then
        return;
      end if;

      -- Handle Done request
      if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
        wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
        if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
          RegisterRead(Address => kBaseOffset + kStatusOffset);
          if readValue(kDisableStatusBit) = '1' then
            return;
          end if;
          assert false
            report "StopStreamFromDiagram: timed out waiting for arbiter"
            severity failure;
        end if;
      end if;

      wait until falling_edge(BusClk);
      bArbiterGrant <= '1';
      if not (bNiDmaInputRequestToDma.Done or bNiDmaInputRequestToDma.Request) then
        wait until bNiDmaInputRequestToDma.Done or
                   bNiDmaInputRequestToDma.Request for kTimeout;
      end if;

      if bNiDmaInputRequestToDma.Done then
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= true;
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= false;
        bArbiterGrant <= '0';
        BusClkWait(1);
        SendDmaStatusResponse;
      elsif bNiDmaInputRequestToDma.Request then
        vBytesTotal := to_integer(unsigned(bNiDmaInputRequestToDma.ByteCount));
        if vBytesTotal = 0 then vBytesTotal := 256; end if;
        vWordsRemaining := (vBytesTotal + kBusWidthBytes - 1) / kBusWidthBytes;
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= true;
        wait until rising_edge(BusClk);
        bNiDmaInputRequestFromDma.Acknowledge <= false;
        bArbiterGrant <= '0';
        for i in 1 to vWordsRemaining loop
          wait until falling_edge(BusClk);
          bNiDmaInputDataFromDma.Pop <= true;
          bNiDmaInputDataFromDma.TransferStart <= (i = 1);
          bNiDmaInputDataFromDma.TransferEnd <= (i = vWordsRemaining);
          wait until rising_edge(BusClk);
        end loop;
        wait until falling_edge(BusClk);
        bNiDmaInputDataFromDma <= kNiDmaInputDataFromDmaZero;
        BusClkWait(2);
        SendDmaStatusResponse;
      end if;

      BusClkWait(50);
      SanityCount := 0;
      loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        exit when readValue(kDisableStatusBit) = '1';
        SanityCount := SanityCount + 1;
        assert SanityCount < 200
          report "StopStreamFromDiagram: timed out waiting for disable"
          severity failure;
      end loop;
    end procedure;

    -- Random number generation
    variable Seed1 : positive := 42;
    variable Seed2 : positive := 17;

    impure function RandInt(Min, Max : integer) return integer is
      variable r : real;
    begin
      uniform(Seed1, Seed2, r);
      return Min + integer(r * real(Max - Min));
    end function;

    --------------------------------------------------------------------------
    -- Set the TestStatus signal for waveform display in ModelSim.
    --------------------------------------------------------------------------
    procedure SetTestStatus(S : string) is
      variable Padded : TestStatusString_t := (others => ' ');
    begin
      if S'length >= TestStatus'length then
        Padded := S(S'left to S'left + TestStatus'length - 1);
      else
        Padded(1 to S'length) := S;
      end if;
      TestStatus <= Padded;
    end procedure;

  begin

    -----------------------------------------------------------------------
    -- SECTION 1: Release resets
    -----------------------------------------------------------------------
    SetTestStatus("S1: Releasing resets");
    report "=== SECTION 1: Releasing resets ===";
    BusClkWait(5);
    aReset <= false;
    BusClkWait(20);
    aDiagramReset <= false;
    BusClkWait(30);

    CheckStreamState(Unlinked);
    CheckArbiterSignals('0', '0');
    report "=== SECTION 1 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 2: Link / Unlink test
    -----------------------------------------------------------------------
    SetTestStatus("S2: Link/Unlink");
    report "=== SECTION 2: Link/Unlink test ===";
    LinkStream;
    CheckStreamState(Disabled);
    UnlinkStream;
    CheckStreamState(Unlinked);
    LinkStream;
    CheckStreamState(Disabled);
    report "=== SECTION 2 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 3: Basic enable / disable from host
    -----------------------------------------------------------------------
    SetTestStatus("S3: Enable/Disable");
    report "=== SECTION 3: Basic enable/disable ===";
    RegisterWrite(Value => 1024, Address => kBaseOffset + kSatcrOffset);
    EnableStream;
    CheckStreamState(Enabled);
    FillFifo(1, 36);
    BusClkWait(20);
    ReceiveOneDmaTransfer;
    DisableStream;
    CheckStreamState(Disabled);
    report "=== SECTION 3 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 4: FIFO full and drain test
    -----------------------------------------------------------------------
    SetTestStatus("S4: FIFO full test");
    report "=== SECTION 4: FIFO full test ===";
    EnableStream;
    RegisterWrite(Value => 2048 * 8, Address => kBaseOffset + kSatcrOffset);
    for i in 1 to kFifoDepth loop
      wait until rising_edge(ViClk);
      if vFull or not vReadyForInput then
        vWriteFifo  <= false;
        vInputValid <= false;
        exit;
      end if;
      vDataIn     <= std_logic_vector(to_unsigned(i mod 256, vDataIn'length));
      vInputValid <= true;
      vWriteFifo  <= true;
    end loop;
    wait until rising_edge(ViClk);
    vWriteFifo  <= false;
    vInputValid <= false;
    ViClkWait(3);
    BusClkWait(5);
    for i in 1 to 5 loop
      if bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' then
        ReceiveOneDmaTransfer;
      end if;
    end loop;
    ViClkWait(5);
    DisableStream;
    report "=== SECTION 4 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 5: Disable with flush from host
    -----------------------------------------------------------------------
    SetTestStatus("S5: Flush (host)");
    report "=== SECTION 5: Disable with flush (host) ===";
    ResetChannel;
    EnableStream;
    RegisterWrite(Value => 4096, Address => kBaseOffset + kSatcrOffset);
    FillFifo(1, 128);
    BusClkWait(20);
    DisableStreamWithFlush;
    BusClkWait(50);
    WaitOnStreamState(Disabled);
    RegisterRead(Address => kBaseOffset + kStatusOffset);
    assert readValue(kFlushingStatusBit) = '1'
      report "FlushingStatus should be set after flush"
      severity error;
    report "=== SECTION 5 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 6: Asynchronous reset
    -----------------------------------------------------------------------
    SetTestStatus("S6: Async reset");
    report "=== SECTION 6: Asynchronous reset ===";
    ResetChannel;
    EnableStream;
    RegisterWrite(Value => 1024, Address => kBaseOffset + kSatcrOffset);
    FillFifo(1, 64);
    BusClkWait(20);
    aReset <= true;
    aDiagramReset <= true;
    BusClkWait(10);
    CheckArbiterSignals('0', '0');
    aReset <= false;
    BusClkWait(20);
    aDiagramReset <= false;
    BusClkWait(30);
    CheckStreamState(Unlinked);
    LinkStream;
    report "=== SECTION 6 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 7: Synchronous reset
    -----------------------------------------------------------------------
    SetTestStatus("S7: Sync reset");
    report "=== SECTION 7: Synchronous reset ===";
    ResetChannel;
    EnableStream;
    RegisterWrite(Value => 4096, Address => kBaseOffset + kSatcrOffset);
    FillFifo(1, 200);
    BusClkWait(20);
    DisableStream;
    RegisterWrite(Value => 2**kResetBit, Address => kBaseOffset + kControlOffset);
    for i in 1 to 200 loop
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      exit when readValue(kResetStatusBit) = '1';
    end loop;
    assert readValue(kResetStatusBit) = '1'
      report "Synchronous reset did not complete" severity error;
    LinkStream;
    report "=== SECTION 7 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 8: Diagram start/stop without flush
    -----------------------------------------------------------------------
    SetTestStatus("S8: Diagram no-flush");
    report "=== SECTION 8: Diagram start/stop (no flush) ===";
    ResetChannel;
    StartStreamFromDiagram(WriteSatcr => true, SatcrValueInBytes => 1024);
    CheckStreamState(Enabled);
    FillFifo(1, 64);
    BusClkWait(20);
    if bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' then
      ReceiveOneDmaTransfer;
    end if;
    StopStreamFromDiagram(Flush => false);
    CheckStreamState(Disabled);
    report "=== SECTION 8 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 9: Diagram start/stop with flush
    -----------------------------------------------------------------------
    SetTestStatus("S9: Diagram flush");
    report "=== SECTION 9: Diagram start/stop (with flush) ===";
    ResetChannel;
    StartStreamFromDiagram(WriteSatcr => true, SatcrValueInBytes => 4096);
    CheckStreamState(Enabled);
    FillFifo(1, 128);
    BusClkWait(20);
    StopStreamFromDiagram(Flush => true, FlushBytes => 128 * kSampleBytes);
    CheckStreamState(Disabled);
    RegisterRead(Address => kBaseOffset + kStatusOffset);
    assert readValue(kFlushingStatusBit) = '1'
      report "FlushingStatus should be set after diagram flush"
      severity error;
    report "=== SECTION 9 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 10: DoDataRequest tests
    -----------------------------------------------------------------------
    SetTestStatus("S10: DoDataRequest");
    report "=== SECTION 10: DoDataRequest tests ===";

    report "  Test 1: SATCR=1 sample, ClkWait=5";
    DoDataRequest(
      FifoFillSamples   => 350,
      SatcrValueInBytes  => 1 * kSampleBytes,
      ClkWaitBeforeGrant => 5);

    report "  Test 2: SATCR=1 sample, ClkWait=0";
    DoDataRequest(
      FifoFillSamples   => 350,
      SatcrValueInBytes  => 1 * kSampleBytes);

    report "  Test 3: SATCR=10 samples";
    DoDataRequest(
      FifoFillSamples   => 350,
      SatcrValueInBytes  => 10 * kSampleBytes);

    report "  Test 4: Count=300, SATCR=300 samples";
    DoDataRequest(
      FifoFillSamples   => 300,
      SatcrValueInBytes  => 300 * kSampleBytes);

    report "  Test 5: Count=600, SATCR=800 (emergency)";
    DoDataRequest(
      FifoFillSamples   => 600,
      SatcrValueInBytes  => 800 * kSampleBytes);

    report "  Test 6: Count=1, SATCR=1";
    DoDataRequest(
      FifoFillSamples   => 1,
      SatcrValueInBytes  => 1 * kSampleBytes);

    report "  Test 7: Count=512, large SATCR, ClkWait=50";
    DoDataRequest(
      FifoFillSamples   => 512,
      SatcrValueInBytes  => 65536,
      ClkWaitBeforeGrant => 50);

    report "  Test 8: Max trackable fill";
    DoDataRequest(
      FifoFillSamples   => kMaxTrackable,
      SatcrValueInBytes  => kMaxTrackable * kSampleBytes);

    report "  Test 9: Empty FIFO";
    DoDataRequest(
      FifoFillSamples   => 0,
      SatcrValueInBytes  => 65536);

    report "  Test 10: Zero SATCR";
    DoDataRequest(
      FifoFillSamples   => 512,
      SatcrValueInBytes  => 0);

    report "=== SECTION 10 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 11: Extra SATCR write tests
    -----------------------------------------------------------------------
    SetTestStatus("S11: SATCR replenish");
    report "=== SECTION 11: Extra SATCR writes ===";
    report "  SATCR replenishment (1 sample + 5 extras)";
    DoDataRequest(
      FifoFillSamples   => 200,
      SatcrValueInBytes  => 1 * kSampleBytes,
      ExtraSatcrWrites   => 5,
      ExtraSatcrValue    => 1 * kSampleBytes);

    report "  Large SATCR replenishment";
    DoDataRequest(
      FifoFillSamples   => 300,
      SatcrValueInBytes  => kMaxTransfer,
      ExtraSatcrWrites   => 3,
      ExtraSatcrValue    => kMaxTransfer);

    report "=== SECTION 11 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 12: Eviction timeout
    -----------------------------------------------------------------------
    SetTestStatus("S12: Eviction timeout");
    report "=== SECTION 12: Eviction timeout ===";
    RegisterWrite(Value => 2**kResetBit, Address => kBaseOffset + kControlOffset);
    BusClkWait(10);
    for i in 1 to 200 loop
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      exit when readValue(kResetStatusBit) = '1';
    end loop;
    LinkStream;
    EnableStream;
    RegisterWrite(Value => 4096, Address => kBaseOffset + kSatcrOffset);
    BusClkWait(5);
    FillFifo(1, 10);
    BusClkWait(5);
    CheckArbiterSignals('0', '0');
    BusClkWait(kEvictionTimeout + 50);
    CheckArbiterSignals('0', '1');
    ReceiveOneDmaTransfer;
    BusClkWait(5);
    DisableStream;
    report "=== SECTION 12 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 13: Flush timeout from diagram
    -----------------------------------------------------------------------
    SetTestStatus("S13: Flush timeout");
    report "=== SECTION 13: Flush timeout ===";
    EnableStream;
    RegisterWrite(Value => 1 * kSampleBytes, Address => kBaseOffset + kSatcrOffset);
    BusClkWait(5);
    FillFifo(1, 200);
    BusClkWait(20);
    StopStreamFromDiagram(
      Flush           => true,
      FlushBytes      => 0,
      DoFlushTimeout  => true,
      FlushTimeoutClk => 50);
    CheckStreamState(Disabled);
    RegisterRead(Address => kBaseOffset + kStatusOffset);
    assert readValue(kFlushingFailedStatusBit) = '1'
      report "FlushingFailedStatus should be set after flush timeout"
      severity error;
    report "=== SECTION 13 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 14: SATCR reset
    -----------------------------------------------------------------------
    SetTestStatus("S14: SATCR reset");
    report "=== SECTION 14: SATCR reset ===";
    RegisterWrite(Value => 2**kResetBit, Address => kBaseOffset + kControlOffset);
    BusClkWait(10);
    for i in 1 to 200 loop
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      exit when readValue(kResetStatusBit) = '1';
    end loop;
    LinkStream;
    EnableStream;
    -- Write SATCR and fill FIFO so DMA wants to transfer
    RegisterWrite(Value => 4096, Address => kBaseOffset + kSatcrOffset);
    BusClkWait(5);
    FillFifo(1, kMaxTransfer / kSampleBytes);
    BusClkWait(20);
    -- Arbiter should be requesting (SATCR > 0, FIFO has data)
    assert bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1'
      report "Arbiter should be requesting before SATCR reset" severity error;
    -- Drain pending request, then ResetSatcr
    ReceiveOneDmaTransfer;
    BusClkWait(10);
    RegisterWrite(Value => 2**kResetSatcrBit, Address => kBaseOffset + kControlOffset);
    BusClkWait(100);
    -- Drain any request that was already queued before the SATCR reset
    if bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' then
      ReceiveOneDmaTransfer;
      BusClkWait(50);
    end if;
    -- After SATCR reset and draining, arbiter should NOT be requesting
    CheckArbiterSignals('0', '0');
    DisableStream;
    report "=== SECTION 14 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 15: IRQ test
    -----------------------------------------------------------------------
    SetTestStatus("S15: IRQ test");
    report "=== SECTION 15: IRQ test ===";
    RegisterWrite(Value => 2**kResetBit, Address => kBaseOffset + kControlOffset);
    BusClkWait(10);
    for i in 1 to 200 loop
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      exit when readValue(kResetStatusBit) = '1';
    end loop;
    LinkStream;
    -- Set interrupt mask AFTER reset so it persists
    RegisterWrite(Value => 2**kEnableStartStreamIrqBit,
                  Address => kBaseOffset + kInterruptMaskOffset);
    BusClkWait(5);
    EnableStream;
    BusClkWait(20);
    RegisterRead(Address => kBaseOffset + kInterruptStatusOffset);
    if readValue(kStartStreamIrqBit) = '1' then
      RegisterWrite(Value => 2**kStartStreamIrqBit,
                    Address => kBaseOffset + kInterruptStatusOffset);
      BusClkWait(5);
      RegisterRead(Address => kBaseOffset + kInterruptStatusOffset);
      assert readValue(kStartStreamIrqBit) = '0'
        report "StartStreamIrq should be cleared" severity error;
    end if;
    -- Verify interrupt mask register is readable
    RegisterRead(Address => kBaseOffset + kInterruptMaskOffset);
    assert readValue(kEnableStartStreamIrqBit) = '1'
      report "Interrupt mask should be set" severity error;
    DisableStream;
    report "=== SECTION 15 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 16: Random stress tests (20 iterations)
    -----------------------------------------------------------------------
    SetTestStatus("S16: Random stress");
    report "=== SECTION 16: Random stress tests ===";
    for RandomTest in 1 to 20 loop
      report "  Random test " & integer'image(RandomTest);
      vRandFillCount := RandInt(1, kMaxTrackable / 2);
      vRandSatcrVal  := RandInt(1, vRandFillCount) * kSampleBytes;
      vRandClkWait   := RandInt(0, 10);
      DoDataRequest(
        FifoFillSamples   => vRandFillCount,
        SatcrValueInBytes  => vRandSatcrVal,
        ClkWaitBeforeGrant => vRandClkWait);
    end loop;
    report "=== SECTION 16 PASSED ===";

    -----------------------------------------------------------------------
    -- Done
    -----------------------------------------------------------------------
    SetTestStatus("ALL TESTS PASSED");
    report "ALL TESTS PASSED" severity note;
    assert WriterViolations = 0
      report "FAIL: FIFO writer protocol violations detected"
      severity error;
    StopSim <= true;
    wait;

  end process Stimulus;

end test;
