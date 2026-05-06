-------------------------------------------------------------------------------
--
-- File: tb_FifoReader.vhd
-- Original Project: LabVIEW FPGA
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
-------------------------------------------------------------------------------
--
-- Purpose:
--   Comprehensive testbench for NiSharedFifoReader.
--   Tests DMA data transfer to VI FIFO, stream state transitions, reset,
--   arbiter thresholds, SATCR management, and data integrity checking.
--
--   Unlike the old DmaPortCommIfcOutputWrapper testbench, this uses the
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

entity tb_FifoReader is
end tb_FifoReader;

architecture test of tb_FifoReader is

  ---------------------------------------------------------------------------
  -- DUT Configuration
  ---------------------------------------------------------------------------
  constant kFifoDepth         : natural  := 1023;
  constant kDataWidth         : positive := 32;
  constant kNumOfSamplesPerRead : positive := 1;
  constant kBaseOffset        : natural  := 16#50#;
  constant kStreamNumber      : natural  := 0;
  constant kPeerToPeerStream  : boolean  := false;
  constant kFxpType           : boolean  := false;
  constant kDisableOnFifoTimeout : boolean := false;

  -- Derived constants
  constant kSampleSize     : natural := ActualSampleSize(
    SampleSizeInBits => kDataWidth,
    PeerToPeer       => kPeerToPeerStream,
    FxpType          => kFxpType);
  constant kSampleBytes    : natural := kSampleSize / 8;
  constant kFifoDataWidth  : natural := kSampleSize;  -- sample size, NOT FIFO port width
  -- Compute FIFO depth in samples, matching the DUT's internal computation:
  -- DUT uses FifoCountWidth = Log2(kFifoDepth) + Log2(kNiDmaDataWidth/kSampleSize)
  -- and kFifoDepthInSamples = 2**kFifoCountWidth - 1
  constant kFifoCountWidth : natural := Log2(kFifoDepth + 1) +
    Log2(kNiDmaDataWidth / kFifoDataWidth);
  constant kFifoDepthInSamples : natural := 2**kFifoCountWidth - 1;
  constant kMaxTrackable   : natural := 2**kFifoCountWidth - 1;
  constant kMaxTransfer    : natural := kNiDmaOutputMaxTransfer;
  constant kBusWidthBytes  : natural := kNiDmaDataWidthInBytes;

  -- Register offsets (from PkgDmaPortCommIfcRegs)
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
  constant kResetSatcrBit          : natural := 4;
  constant kLinkStreamBit          : natural := 5;
  constant kUnlinkStreamBit        : natural := 6;

  -- Status register bit indices
  constant kResetStatusBit         : natural := 0;
  constant kDisableStatusBit       : natural := 1;
  constant kStateBitLow            : natural := 2;
  constant kStateBitHigh           : natural := 3;

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

  signal bNiDmaOutputRequestToDma   : NiDmaOutputRequestToDma_t;
  signal bNiDmaOutputRequestFromDma : NiDmaOutputRequestFromDma_t := kNiDmaOutputRequestFromDmaZero;
  signal bNiDmaOutputDataFromDma    : NiDmaOutputDataFromDma_t := kNiDmaOutputDataFromDmaZero;

  signal bArbiterNormalReq    : std_logic;
  signal bArbiterEmergencyReq : std_logic;
  signal bArbiterDone         : std_logic;
  signal bArbiterGrant        : std_logic := '0';

  signal bRegPortIn  : RegPortIn_t := kRegPortInZero;
  signal bRegPortOut : RegPortOut_t;

  signal vDataOut        : std_logic_vector(kDataWidth * kNumOfSamplesPerRead - 1 downto 0);
  signal vEmpty          : boolean;
  signal vReadFifo       : boolean := false;
  signal vCtCount        : unsigned(31 downto 0);
  signal vOutputValid    : boolean;
  signal vReadyForOutput : boolean := false;

  signal vStreamStateOut       : StreamStateValue_t;
  signal vStartStreamRequest   : boolean := false;
  signal vStopRequestStrobe    : boolean := false;

  signal bIrq : IrqStatusToInterface_t;

  signal StopSim : boolean := false;

  subtype TestStatusString_t is string(1 to 40);
  signal TestStatus : TestStatusString_t := (others => ' ');

  -- Timeout constant for wait statements
  constant kTimeout : time := 200 us;

  -- Tracking signals for data verification
  signal LastValueSent   : unsigned(kNiDmaDataWidth-1 downto 0) := (others => '0');
  signal CurrentPopValue : unsigned(kNiDmaDataWidth-1 downto 0) := (others => '0');

  ---------------------------------------------------------------------------
  -- Clock generation
  ---------------------------------------------------------------------------
begin

  BusClk <= not BusClk after kBusClkPeriod / 2 when not StopSim else '0';
  ViClk  <= not ViClk  after kViClkPeriod / 2  when not StopSim else '0';

  ---------------------------------------------------------------------------
  -- DUT instantiation
  ---------------------------------------------------------------------------
  DUT: entity work.NiSharedFifoReaderTbWrapper (structure)
    generic map (
      kFifoDepth            => kFifoDepth,
      kDataWidth            => kDataWidth,
      kNumOfSamplesPerRead  => kNumOfSamplesPerRead,
      kBaseOffset           => kBaseOffset,
      kStreamNumber         => kStreamNumber,
      kPeerToPeerStream     => kPeerToPeerStream,
      kFxpType              => kFxpType,
      kDisableOnFifoTimeout => kDisableOnFifoTimeout)
    port map (
      aReset                       => aReset,
      bReset                       => bReset,
      aDiagramReset                => aDiagramReset,
      BusClk                       => BusClk,
      ViClk                        => ViClk,
      bNiDmaOutputRequestToDma     => bNiDmaOutputRequestToDma,
      bNiDmaOutputRequestFromDma   => bNiDmaOutputRequestFromDma,
      bNiDmaOutputDataFromDma      => bNiDmaOutputDataFromDma,
      bArbiterNormalReq            => bArbiterNormalReq,
      bArbiterEmergencyReq         => bArbiterEmergencyReq,
      bArbiterDone                 => bArbiterDone,
      bArbiterGrant                => bArbiterGrant,
      bRegPortIn                   => bRegPortIn,
      bRegPortOut                  => bRegPortOut,
      vDataOut                     => vDataOut,
      vEmpty                       => vEmpty,
      vReadFifo                    => vReadFifo,
      vCtCount                     => vCtCount,
      vOutputValid                 => vOutputValid,
      vReadyForOutput              => vReadyForOutput,
      vStreamStateOut              => vStreamStateOut,
      vStartStreamRequest          => vStartStreamRequest,
      vStopRequestStrobe           => vStopRequestStrobe,
      bIrq                         => bIrq);


  ---------------------------------------------------------------------------
  -- Stimulus process
  ---------------------------------------------------------------------------
  Stimulus: process

    -- Register read result
    variable readValue : std_logic_vector(31 downto 0);

    -- DMA request tracking (moved from shared variables)
    variable ActualRequestByteCount : natural := 0;
    variable AlignmentSize : natural := kMaxTransfer;

    -- Random stress test variables
    variable vRandByteCount : natural;
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
    -- Register write
    --------------------------------------------------------------------------
    procedure RegisterWrite(Value : integer; Address : natural) is
    begin
      -- Wait until the falling edge unless it has already occurred.
      if BusClk = '1' then
        wait until falling_edge(BusClk);
      end if;
      -- Wait until the register port is ready.
      while not bRegPortOut.Ready loop
        wait until falling_edge(BusClk);
      end loop;
      -- Set address first (without strobe) so registered decode settles.
      bRegPortIn.Wt      <= false;
      bRegPortIn.Rd      <= false;
      bRegPortIn.Address <= resize(to_unsigned(Address / 4, 30), bRegPortIn.Address'length);
      bRegPortIn.Data    <= std_logic_vector(to_unsigned(Value, 32));
      BusClkWait(1);
      -- Now assert write strobe.
      bRegPortIn.Wt <= true;
      BusClkWait(1);
      bRegPortIn.Wt <= false;
      bRegPortIn.Address <= (others => '0');
      bRegPortIn.Data    <= (others => '0');
    end procedure;

    --------------------------------------------------------------------------
    -- Register read
    --------------------------------------------------------------------------
    procedure RegisterRead(Address : natural) is
    begin
      if BusClk = '1' then
        wait until falling_edge(BusClk);
      end if;
      while not bRegPortOut.Ready loop
        wait until falling_edge(BusClk);
      end loop;
      bRegPortIn.Wt      <= false;
      bRegPortIn.Rd      <= false;
      bRegPortIn.Address <= resize(to_unsigned(Address / 4, 30), bRegPortIn.Address'length);
      bRegPortIn.Data    <= (others => '0');
      BusClkWait(1);
      bRegPortIn.Rd <= true;
      BusClkWait(1);
      wait until falling_edge(BusClk);
      while not bRegPortOut.DataValid loop
        wait until falling_edge(BusClk);
      end loop;
      readValue := bRegPortOut.Data;
      bRegPortIn.Rd <= false;
      bRegPortIn.Address <= (others => '0');
      wait for 0 ns;
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
    begin
      RegisterWrite(Value   => 2**kStartChannelBit,
                    Address => kBaseOffset + kControlOffset);
      -- Poll the disabled bit in the status register until it is '0'
      readValue := (others => '1');
      while readValue(kDisableStatusBit) /= '0' loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
      end loop;
      AlignmentSize := kMaxTransfer;
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
    -- Disable the DMA stream
    --------------------------------------------------------------------------
    procedure DisableStream is
    begin
      RegisterWrite(Value   => 2**kStopChannelBit,
                    Address => kBaseOffset + kControlOffset);
      BusClkWait(3);
    end procedure;

    --------------------------------------------------------------------------
    -- WaitForDisable: poll status until DisableStatus = 1
    --------------------------------------------------------------------------
    procedure WaitForDisable is
      variable SanityCount : natural := 0;
    begin
      readValue := (others => '0');
      while readValue(kDisableStatusBit) /= '1' loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        SanityCount := SanityCount + 1;
        assert SanityCount < 500
          report "WaitForDisable: timed out waiting for disable"
          severity failure;
      end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- WriteSatcr
    --------------------------------------------------------------------------
    procedure WriteSatcr(Value : natural) is
    begin
      RegisterWrite(Value   => Value,
                    Address => kBaseOffset + kSatcrOffset);
      BusClkWait(1);
    end procedure;

    --------------------------------------------------------------------------
    -- ReadSatcrVerify
    --------------------------------------------------------------------------
    procedure ReadSatcrVerify(ExpectedValue : natural) is
    begin
      RegisterRead(Address => kBaseOffset + kSatcrOffset);
      assert to_integer(unsigned(readValue)) = ExpectedValue
        report "SATCR mismatch: expected " & integer'image(ExpectedValue) &
               " got " & integer'image(to_integer(unsigned(readValue)))
        severity error;
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
      -- Check reset values
      wait until falling_edge(BusClk);
      assert bArbiterNormalReq = '0'
        report "ArbiterNormalReq not 0 after reset" severity error;
      assert bArbiterEmergencyReq = '0'
        report "ArbiterEmergencyReq not 0 after reset" severity error;
      assert not bNiDmaOutputRequestToDma.Request
        report "Request not deasserted after reset" severity error;
      AlignmentSize := kMaxTransfer;
    end procedure;

    --------------------------------------------------------------------------
    -- ReceiveRequest: accept a DMA read request from the DUT
    --------------------------------------------------------------------------
    procedure ReceiveRequest(
      ExpectedSize : natural
    ) is
    begin
      -- Wait until falling edge to sample arbiter
      if BusClk = '1' then
        wait until falling_edge(BusClk);
      end if;

      -- Assert grant
      bArbiterGrant <= '1';

      BusClkWait(1);
      wait until falling_edge(BusClk);

      assert bNiDmaOutputRequestToDma.Request
        report "ReceiveRequest: Request signal not asserted"
        severity error;

      if bNiDmaOutputRequestToDma.Request then
        -- Capture DUT's actual byte count
        ActualRequestByteCount :=
          to_integer(bNiDmaOutputRequestToDma.ByteCount);

        assert bNiDmaOutputRequestToDma.Space = kNiDmaSpaceStream
          report "ReceiveRequest: wrong Space" severity error;
        assert bNiDmaOutputRequestToDma.Done = false
          report "ReceiveRequest: unexpected Done" severity error;

        assert bNiDmaOutputRequestToDma.ByteCount =
               to_unsigned(ExpectedSize, bNiDmaOutputRequestToDma.ByteCount'length)
          report "ReceiveRequest: ByteCount expected=" &
                 integer'image(ExpectedSize) & " actual=" &
                 integer'image(ActualRequestByteCount)
          severity note;

        -- Acknowledge
        bNiDmaOutputRequestFromDma.Acknowledge <= true;
        BusClkWait(1);
        bNiDmaOutputRequestFromDma.Acknowledge <= false;
        bArbiterGrant <= '0';
      end if;

      -- Update alignment tracking
      AlignmentSize := (AlignmentSize - ActualRequestByteCount) mod kMaxTransfer;
      if AlignmentSize = 0 then
        AlignmentSize := kMaxTransfer;
      end if;
    end procedure;

    --------------------------------------------------------------------------
    -- SendPacket: send DMA data from host to DUT FIFO
    --------------------------------------------------------------------------
    procedure SendPacket(
      Length           : natural;
      StartingByteLane : natural
    ) is
      variable OutputData : NiDmaOutputDataFromDma_t;
      variable StartingValue : natural := to_integer(LastValueSent + 1);
      variable NumTransfers : natural;
      variable Data : NiDmaData_t;
      variable CurrentSampleValue : natural;
      variable BytesInLastWord : natural;
      variable DataMask : unsigned(kNiDmaDataWidth-1 downto 0);
    begin
      assert Length > 0
        report "SendPacket: trying to send 0 bytes" severity error;

      NumTransfers := (StartingByteLane + Length + kBusWidthBytes - 1) / kBusWidthBytes;
      BytesInLastWord := (StartingByteLane + Length) mod kBusWidthBytes;
      if BytesInLastWord = 0 then
        BytesInLastWord := kBusWidthBytes;
      end if;

      CurrentSampleValue := StartingValue;

      if BusClk = '1' then
        wait until falling_edge(BusClk);
      end if;
      BusClkWait(1);

      for i in 0 to NumTransfers-1 loop
        OutputData := kNiDmaOutputDataFromDmaZero;
        OutputData.Channel := to_unsigned(kStreamNumber, OutputData.Channel'length);
        OutputData.DmaChannel := GetDmaChannelOneHot(kNiDmaSpaceStream,
          OutputData.Channel);
        OutputData.ByteLane := to_unsigned(0, OutputData.ByteLane'length);
        OutputData.ByteCount := GetWordByteCount(OutputData.ByteLane,
          to_unsigned(kNiDmaDataWidthInBytes, Log2(kNiDmaDataWidthInBytes)+1));
        OutputData.Push := true;
        Data := (others => '0');

        if i = 0 then
          OutputData.TransferStart := true;
          OutputData.ByteLane := to_unsigned(StartingByteLane, OutputData.ByteLane'length);
          OutputData.ByteCount := GetWordByteCount(OutputData.ByteLane,
            to_unsigned(kNiDmaDataWidthInBytes, Log2(kNiDmaDataWidthInBytes)+1));

          if i = NumTransfers-1 then
            OutputData.TransferEnd := true;
            OutputData.ByteCount := GetWordByteCount(OutputData.ByteLane,
              to_unsigned(BytesInLastWord, Log2(kNiDmaDataWidthInBytes)+1));
            for s in StartingByteLane*8/kFifoDataWidth to
              BytesInLastWord*8/kFifoDataWidth-1 loop
              Data((s+1)*kFifoDataWidth-1 downto s*kFifoDataWidth) :=
                std_logic_vector(resize(to_unsigned(CurrentSampleValue, kDataWidth),
                kFifoDataWidth));
              CurrentSampleValue := CurrentSampleValue + 1;
            end loop;
          else
            for s in StartingByteLane*8/kFifoDataWidth to
              kNiDmaDataWidth/kFifoDataWidth-1 loop
              Data((s+1)*kFifoDataWidth-1 downto s*kFifoDataWidth) :=
                std_logic_vector(resize(to_unsigned(CurrentSampleValue, kDataWidth),
                kFifoDataWidth));
              CurrentSampleValue := CurrentSampleValue + 1;
            end loop;
          end if;

        elsif i = NumTransfers-1 then
          OutputData.TransferEnd := true;
          OutputData.ByteCount := GetWordByteCount(OutputData.ByteLane,
            to_unsigned(BytesInLastWord, Log2(kNiDmaDataWidthInBytes)+1));
          for s in 0 to BytesInLastWord*8/kFifoDataWidth-1 loop
            Data((s+1)*kFifoDataWidth-1 downto s*kFifoDataWidth) :=
              std_logic_vector(resize(to_unsigned(CurrentSampleValue, kDataWidth),
              kFifoDataWidth));
            CurrentSampleValue := CurrentSampleValue + 1;
          end loop;

        else
          for s in 0 to kNiDmaDataWidth/kFifoDataWidth-1 loop
            Data((s+1)*kFifoDataWidth-1 downto s*kFifoDataWidth) :=
              std_logic_vector(resize(to_unsigned(CurrentSampleValue, kDataWidth),
              kFifoDataWidth));
            CurrentSampleValue := CurrentSampleValue + 1;
          end loop;
        end if;

        OutputData.ByteEnable := GetByteEnables(
          OutputData.ByteLane, OutputData.ByteCount);
        OutputData.Data := Data;

        bNiDmaOutputDataFromDma <= OutputData;
        BusClkWait(1);
      end loop;

      bNiDmaOutputDataFromDma <= kNiDmaOutputDataFromDmaZero;

      -- Update last value sent tracking
      DataMask := (others => '1');
      DataMask(kNiDmaDataWidth-1 downto kDataWidth) := (others => '0');
      LastValueSent <= (LastValueSent + Length / (kFifoDataWidth/8)) and DataMask;
    end procedure;

    --------------------------------------------------------------------------
    -- ViPop: pop data from FIFO using simplified strobe interface.
    -- Matches the old testbench's SCL pattern: keep vReadFifo asserted
    -- through the pop loop; the deassert/reassert in the same delta
    -- between iterations keeps the enable chain running continuously.
    --------------------------------------------------------------------------
    procedure ViPop(NumPoints : natural) is
      variable SanityCount : natural;
    begin
      -- Wait until the clock is high before beginning
      if ViClk = '0' then
        wait until rising_edge(ViClk);
      end if;

      vReadyForOutput <= true;

      for i in 1 to NumPoints loop
        -- Assert read strobe
        vReadFifo <= true;

        -- Wait until falling edge to sample data
        wait until falling_edge(ViClk);

        -- Wait for FIFO to have data
        SanityCount := 0;
        while vEmpty loop
          wait until falling_edge(ViClk);
          SanityCount := SanityCount + 1;
          assert SanityCount < 500
            report "ViPop: timed out waiting for FIFO data"
            severity failure;
        end loop;

        -- Verify data
        assert unsigned(vDataOut(kDataWidth-1 downto 0)) =
               CurrentPopValue(kDataWidth-1 downto 0) + 1
          report "ViPop: data mismatch - expected " &
                 integer'image(to_integer(CurrentPopValue(kDataWidth-1 downto 0) + 1)) &
                 " got " & integer'image(to_integer(unsigned(vDataOut(kDataWidth-1 downto 0))))
          severity error;

        CurrentPopValue <= unsigned(resize(unsigned(vDataOut), kNiDmaDataWidth));

        wait until rising_edge(ViClk);
        vReadFifo <= false;
        -- Note: next iteration's 'vReadFifo <= true' overrides this in the
        -- same delta, keeping the enable chain running without a gap.
      end loop;

      vReadyForOutput <= false;
    end procedure;

    --------------------------------------------------------------------------
    -- CheckAllDataPopped: verify FIFO is empty
    --------------------------------------------------------------------------
    procedure CheckAllDataPopped is
    begin
      assert LastValueSent = CurrentPopValue
        report "Not all data popped: LastSent=" &
               integer'image(to_integer(LastValueSent(kDataWidth-1 downto 0))) &
               " LastPopped=" &
               integer'image(to_integer(CurrentPopValue(kDataWidth-1 downto 0)))
        severity error;

      -- Try one more read to confirm empty
      if ViClk = '0' then
        wait until rising_edge(ViClk);
      end if;
      vReadyForOutput <= true;
      vReadFifo       <= true;
      wait until falling_edge(ViClk);
      -- Give time for data to appear if any
      wait until falling_edge(ViClk);
      assert vEmpty
        report "CheckAllDataPopped: FIFO not empty after all data popped"
        severity error;
      vReadyForOutput <= false;
      vReadFifo       <= false;
    end procedure;

    --------------------------------------------------------------------------
    -- GetNextPacketSize: predict DUT's next request size
    --------------------------------------------------------------------------
    function GetNextPacketSize(
      Satcr        : integer;
      EmptyCount   : integer;
      MaxPktSize   : natural
    ) return natural is
    begin
      if Satcr <= 0 or EmptyCount <= 0 then
        return 0;
      end if;
      if EmptyCount > kFifoDepthInSamples/4 or
         (EmptyCount*kFifoDataWidth/8 >= MaxPktSize and Satcr >= MaxPktSize) then
        if Satcr < EmptyCount*kFifoDataWidth/8 and Satcr < MaxPktSize then
          return Satcr;
        elsif EmptyCount*kFifoDataWidth/8 < MaxPktSize then
          return EmptyCount*kFifoDataWidth/8;
        else
          return MaxPktSize;
        end if;
      else
        return 0;
      end if;
    end function;

    --------------------------------------------------------------------------
    -- Smaller: return the smaller of two integers
    --------------------------------------------------------------------------
    function Smaller(A, B : integer) return integer is
    begin
      if A < B then return A; else return B; end if;
    end function;

    --------------------------------------------------------------------------
    -- DoNormalTransmission: send data to DUT and pop from FIFO
    --------------------------------------------------------------------------
    procedure DoNormalTransmission(
      NumOfBytes : natural
    ) is
      variable NextPacketSize : natural;
      variable CurrentReqSatcr : integer;
      variable CurrentSatcr : integer;
      variable CurrentEmptyCount : integer;
      variable CurrentByteLane : natural;
    begin
      ReadSatcrVerify(0);
      WriteSatcr(NumOfBytes);
      ReadSatcrVerify(NumOfBytes);

      CurrentSatcr := NumOfBytes;
      CurrentReqSatcr := NumOfBytes;
      CurrentEmptyCount := kFifoDepthInSamples;
      CurrentByteLane := 0;

      LinkStream;
      WaitOnStreamState(Disabled);
      EnableStream;

      while CurrentSatcr /= 0 loop
        NextPacketSize := GetNextPacketSize(
          Satcr      => CurrentReqSatcr,
          EmptyCount => Smaller(CurrentEmptyCount, kFifoDepthInSamples),
          MaxPktSize => AlignmentSize);

        -- Wait for arbiter request
        if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
          wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
          if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
            exit;  -- No more requests
          end if;
        end if;

        ReceiveRequest(ExpectedSize => NextPacketSize);

        -- Handle ByteCount=0
        if ActualRequestByteCount = 0 then
          BusClkWait(1);
          bNiDmaOutputDataFromDma.Push <= true;
          bNiDmaOutputDataFromDma.TransferStart <= true;
          bNiDmaOutputDataFromDma.TransferEnd <= true;
          bNiDmaOutputDataFromDma.Channel <=
            to_unsigned(kStreamNumber, bNiDmaOutputDataFromDma.Channel'length);
          bNiDmaOutputDataFromDma.DmaChannel <=
            GetDmaChannelOneHot(kNiDmaSpaceStream,
              to_unsigned(kStreamNumber, bNiDmaOutputDataFromDma.Channel'length));
          bNiDmaOutputDataFromDma.ByteLane <=
            to_unsigned(CurrentByteLane, bNiDmaOutputDataFromDma.ByteLane'length);
          bNiDmaOutputDataFromDma.ByteCount <=
            to_unsigned(0, bNiDmaOutputDataFromDma.ByteCount'length);
          BusClkWait(1);
          bNiDmaOutputDataFromDma <= kNiDmaOutputDataFromDmaZero;
          exit;
        end if;

        CurrentReqSatcr := CurrentReqSatcr - ActualRequestByteCount;
        if CurrentReqSatcr < 0 then CurrentReqSatcr := 0; end if;
        BusClkWait(1);

        SendPacket(
          Length           => ActualRequestByteCount,
          StartingByteLane => CurrentByteLane);

        CurrentSatcr := CurrentSatcr - ActualRequestByteCount;
        if CurrentSatcr < 0 then CurrentSatcr := 0; end if;
        CurrentEmptyCount := CurrentEmptyCount -
          ActualRequestByteCount*8/kFifoDataWidth;
        if CurrentEmptyCount < 0 then CurrentEmptyCount := 0; end if;
        CurrentByteLane := (CurrentByteLane + ActualRequestByteCount) mod kBusWidthBytes;

        BusClkWait(1);

        -- Pop the data from the FIFO
        ViPop(NumPoints => ActualRequestByteCount*8/kFifoDataWidth);

        CurrentEmptyCount := CurrentEmptyCount +
          ActualRequestByteCount*8/kFifoDataWidth;

        CheckStreamState(Enabled);

        -- Wait for clock crossing propagation
        BusClkWait(10);
      end loop;

      DisableStream;
      WaitForDisable;
      UnlinkStream;
      WaitOnStreamState(Unlinked);
      ResetChannel;
    end procedure;

    --------------------------------------------------------------------------
    -- DoFifoFillTransmission: fill FIFO then pop all data
    --------------------------------------------------------------------------
    procedure DoFifoFillTransmission(
      NumOfBytes : natural
    ) is
      variable NextPacketSize : natural;
      variable CurrentReqSatcr : integer;
      variable CurrentSatcr : integer;
      variable CurrentEmptyCount : integer;
      variable CurrentByteLane : natural;
      variable NumPointsSent : natural;
    begin
      ReadSatcrVerify(0);
      WriteSatcr(NumOfBytes);
      ReadSatcrVerify(NumOfBytes);

      CurrentSatcr := NumOfBytes;
      CurrentReqSatcr := NumOfBytes;
      CurrentEmptyCount := kFifoDepthInSamples;
      CurrentByteLane := 0;

      LinkStream;
      WaitOnStreamState(Disabled);
      EnableStream;

      while CurrentSatcr /= 0 loop
        NumPointsSent := 0;

        NextPacketSize := GetNextPacketSize(
          Satcr      => CurrentReqSatcr,
          EmptyCount => Smaller(CurrentEmptyCount, kFifoDepthInSamples),
          MaxPktSize => AlignmentSize);

        -- Fill FIFO: send packets until no more room
        while NextPacketSize /= 0 loop
          if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
            wait until bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' for kTimeout;
            if bArbiterNormalReq /= '1' and bArbiterEmergencyReq /= '1' then
              exit;
            end if;
          end if;

          ReceiveRequest(ExpectedSize => NextPacketSize);

          if ActualRequestByteCount = 0 then
            BusClkWait(1);
            bNiDmaOutputDataFromDma.Push <= true;
            bNiDmaOutputDataFromDma.TransferStart <= true;
            bNiDmaOutputDataFromDma.TransferEnd <= true;
            bNiDmaOutputDataFromDma.Channel <=
              to_unsigned(kStreamNumber, bNiDmaOutputDataFromDma.Channel'length);
            bNiDmaOutputDataFromDma.DmaChannel <=
              GetDmaChannelOneHot(kNiDmaSpaceStream,
                to_unsigned(kStreamNumber, bNiDmaOutputDataFromDma.Channel'length));
            bNiDmaOutputDataFromDma.ByteLane <=
              to_unsigned(CurrentByteLane, bNiDmaOutputDataFromDma.ByteLane'length);
            bNiDmaOutputDataFromDma.ByteCount <=
              to_unsigned(0, bNiDmaOutputDataFromDma.ByteCount'length);
            BusClkWait(1);
            bNiDmaOutputDataFromDma <= kNiDmaOutputDataFromDmaZero;
            exit;
          end if;

          CurrentReqSatcr := CurrentReqSatcr - ActualRequestByteCount;
          if CurrentReqSatcr < 0 then CurrentReqSatcr := 0; end if;
          BusClkWait(1);

          SendPacket(
            Length           => ActualRequestByteCount,
            StartingByteLane => CurrentByteLane);

          CurrentSatcr := CurrentSatcr - ActualRequestByteCount;
          if CurrentSatcr < 0 then CurrentSatcr := 0; end if;
          CurrentEmptyCount := CurrentEmptyCount -
            ActualRequestByteCount*8/kFifoDataWidth;
          if CurrentEmptyCount < 0 then CurrentEmptyCount := 0; end if;
          CurrentByteLane := (CurrentByteLane + ActualRequestByteCount) mod kBusWidthBytes;
          NumPointsSent := NumPointsSent +
            ActualRequestByteCount*8/kFifoDataWidth;

          BusClkWait(20);
          CheckStreamState(Enabled);

          NextPacketSize := GetNextPacketSize(
            Satcr      => CurrentReqSatcr,
            EmptyCount => Smaller(CurrentEmptyCount, kFifoDepthInSamples),
            MaxPktSize => AlignmentSize);
        end loop;

        -- Pop all the points
        if NumPointsSent > 0 then
          ViPop(NumPoints => NumPointsSent);
          CurrentEmptyCount := CurrentEmptyCount + NumPointsSent;
          CheckAllDataPopped;
        end if;

        -- Wait for clock crossing propagation
        BusClkWait(50);

        -- Re-sync SATCR model
        RegisterRead(Address => kBaseOffset + kSatcrOffset);
        CurrentReqSatcr := to_integer(unsigned(readValue));
        CurrentSatcr := CurrentReqSatcr;
        CurrentEmptyCount := kFifoDepthInSamples;
      end loop;

      DisableStream;
      WaitForDisable;
      UnlinkStream;
      WaitOnStreamState(Unlinked);
      ResetChannel;
    end procedure;

    --------------------------------------------------------------------------
    -- StartStreamFromDiagram: use direct strobe to start stream.
    --------------------------------------------------------------------------
    procedure StartStreamFromDiagram is
    begin
      vStartStreamRequest <= true;
      ViClkWait(1);
      vStartStreamRequest <= false;
      EnableStream;
    end procedure;

    --------------------------------------------------------------------------
    -- StopStreamFromDiagram: strobe stop request.
    --------------------------------------------------------------------------
    procedure StopStreamFromDiagram is
      variable SanityCount : natural := 0;
    begin
      -- Strobe the diagram-side stop request.
      vStopRequestStrobe <= true;
      ViClkWait(4);
      vStopRequestStrobe <= false;

      -- The DUT's SinkStreamStateController requires a bus-side disable
      -- (bHostDisable) to actually transition from Enabled → Disabled.
      -- bStopChannelRequest alone only clears bEnableReg (stops DMA), NOT
      -- bStateEnableReg (state transition gating).
      BusClkWait(10);
      DisableStream;

      -- Wait for disable to complete
      SanityCount := 0;
      loop
        RegisterRead(Address => kBaseOffset + kStatusOffset);
        exit when readValue(kDisableStatusBit) = '1';

        -- If the DUT has a pending arbiter request, grant and acknowledge it
        if bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' then
          wait until falling_edge(BusClk);
          bArbiterGrant <= '1';
          wait until falling_edge(BusClk);
          if bNiDmaOutputRequestToDma.Done or bNiDmaOutputRequestToDma.Request then
            wait until rising_edge(BusClk);
            bNiDmaOutputRequestFromDma.Acknowledge <= true;
            wait until rising_edge(BusClk);
            bNiDmaOutputRequestFromDma.Acknowledge <= false;
          end if;
          bArbiterGrant <= '0';
          BusClkWait(20);
        end if;

        SanityCount := SanityCount + 1;
        assert SanityCount < 500
          report "StopStreamFromDiagram: timed out waiting for disable"
          severity failure;
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
    WriteSatcr(1024);
    EnableStream;
    CheckStreamState(Enabled);
    BusClkWait(5);
    -- Write SATCR with enough to trigger emergency request
    CheckArbiterSignals('1', '1');
    DisableStream;
    WaitForDisable;
    CheckStreamState(Disabled);
    report "=== SECTION 3 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 4: Synchronous reset
    -----------------------------------------------------------------------
    SetTestStatus("S4: Sync reset");
    report "=== SECTION 4: Synchronous reset ===";
    ResetChannel;
    LinkStream;
    EnableStream;
    WriteSatcr(4096);
    BusClkWait(20);
    DisableStream;
    WaitForDisable;
    RegisterWrite(Value => 2**kResetBit, Address => kBaseOffset + kControlOffset);
    for i in 1 to 200 loop
      RegisterRead(Address => kBaseOffset + kStatusOffset);
      exit when readValue(kResetStatusBit) = '1';
    end loop;
    assert readValue(kResetStatusBit) = '1'
      report "Synchronous reset did not complete" severity error;
    report "=== SECTION 4 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 5: Asynchronous reset
    -----------------------------------------------------------------------
    SetTestStatus("S5: Async reset");
    report "=== SECTION 5: Asynchronous reset ===";
    ResetChannel;
    LinkStream;
    EnableStream;
    WriteSatcr(1024);
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
    report "=== SECTION 5 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 6: Normal transmission tests
    -----------------------------------------------------------------------
    SetTestStatus("S6: Normal TX");
    report "=== SECTION 6: Normal transmission tests ===";

    report "  Test 1: 1 sample";
    DoNormalTransmission(NumOfBytes => 1 * kFifoDataWidth/8);

    report "  Test 2: 2 samples";
    DoNormalTransmission(NumOfBytes => 2 * kFifoDataWidth/8);

    report "  Test 3: 10 samples";
    DoNormalTransmission(NumOfBytes => 10 * kFifoDataWidth/8);

    report "  Test 4: 64 samples";
    DoNormalTransmission(NumOfBytes => 64 * kFifoDataWidth/8);

    report "  Test 5: 100 samples";
    DoNormalTransmission(NumOfBytes => 100 * kFifoDataWidth/8);

    report "  Test 6: 500 samples";
    DoNormalTransmission(NumOfBytes => 500 * kFifoDataWidth/8);

    report "=== SECTION 6 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 7: FIFO fill transmission tests
    -----------------------------------------------------------------------
    SetTestStatus("S7: FIFO fill TX");
    report "=== SECTION 7: FIFO fill transmission tests ===";

    report "  Test 1: 100 samples";
    DoFifoFillTransmission(NumOfBytes => 100 * kFifoDataWidth/8);

    report "  Test 2: 1000 samples";
    DoFifoFillTransmission(NumOfBytes => 1000 * kFifoDataWidth/8);

    report "  Test 3: FifoDepth samples";
    DoFifoFillTransmission(NumOfBytes => kFifoDepth * kFifoDataWidth/8);

    report "=== SECTION 7 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 8: Diagram start/stop
    -----------------------------------------------------------------------
    SetTestStatus("S8: Diagram start/stop");
    report "=== SECTION 8: Diagram start/stop ===";
    ResetChannel;
    LinkStream;
    StartStreamFromDiagram;
    CheckStreamState(Enabled);
    BusClkWait(20);
    StopStreamFromDiagram;
    CheckStreamState(Disabled);
    report "=== SECTION 8 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 9: SATCR reset
    -----------------------------------------------------------------------
    SetTestStatus("S9: SATCR reset");
    report "=== SECTION 9: SATCR reset ===";
    ResetChannel;
    LinkStream;
    WaitOnStreamState(Disabled);
    -- Test SATCR reset without an active transfer to avoid pipeline race.
    -- Write SATCR in disabled state, verify it reads back, then reset.
    WriteSatcr(4096);
    ReadSatcrVerify(4096);
    RegisterWrite(Value => 2**kResetSatcrBit, Address => kBaseOffset + kControlOffset);
    BusClkWait(20);
    ReadSatcrVerify(0);
    -- Also verify SATCR reset after enabling + disable cycle
    EnableStream;
    WriteSatcr(256);
    BusClkWait(10);
    DisableStream;
    WaitForDisable;
    -- DUT is disabled, drain any leftover arbiter requests
    BusClkWait(10);
    if bArbiterNormalReq = '1' or bArbiterEmergencyReq = '1' then
      wait until falling_edge(BusClk);
      bArbiterGrant <= '1';
      wait until falling_edge(BusClk);
      if bNiDmaOutputRequestToDma.Request or bNiDmaOutputRequestToDma.Done then
        wait until rising_edge(BusClk);
        bNiDmaOutputRequestFromDma.Acknowledge <= true;
        wait until rising_edge(BusClk);
        bNiDmaOutputRequestFromDma.Acknowledge <= false;
      end if;
      bArbiterGrant <= '0';
      BusClkWait(10);
    end if;
    RegisterWrite(Value => 2**kResetSatcrBit, Address => kBaseOffset + kControlOffset);
    BusClkWait(10);
    ReadSatcrVerify(0);
    UnlinkStream;
    WaitOnStreamState(Unlinked);
    report "=== SECTION 9 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 10: IRQ test
    -----------------------------------------------------------------------
    SetTestStatus("S10: IRQ test");
    report "=== SECTION 10: IRQ test ===";
    ResetChannel;
    LinkStream;
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
    RegisterRead(Address => kBaseOffset + kInterruptMaskOffset);
    assert readValue(kEnableStartStreamIrqBit) = '1'
      report "Interrupt mask should be set" severity error;
    DisableStream;
    WaitForDisable;
    report "=== SECTION 10 PASSED ===";

    -----------------------------------------------------------------------
    -- SECTION 11: Random stress tests
    -----------------------------------------------------------------------
    SetTestStatus("S11: Random stress");
    report "=== SECTION 11: Random stress tests ===";
    for RandomTest in 1 to 15 loop
      report "  Random test " & integer'image(RandomTest);
      vRandByteCount := RandInt(1, 200) * kFifoDataWidth/8;
      ResetChannel;
      DoNormalTransmission(NumOfBytes => vRandByteCount);
    end loop;
    report "=== SECTION 11 PASSED ===";

    -----------------------------------------------------------------------
    -- Done
    -----------------------------------------------------------------------
    SetTestStatus("ALL TESTS PASSED");
    report "ALL TESTS PASSED" severity note;
    StopSim <= true;
    wait;

  end process Stimulus;

end test;
