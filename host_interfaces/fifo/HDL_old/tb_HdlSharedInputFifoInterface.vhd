-------------------------------------------------------------------------------
--
-- File: tb_HdlSharedInputFifoInterface.vhd
--
-------------------------------------------------------------------------------
-- Purpose:
--   Testbench that instantiates both the new HdlSharedInputFifoInterface and
--   the old (enable-chain based) version side by side.
--
--   Old version: each enable chain is exercised with the pattern:
--     1. Assert EnableIn
--     2. Wait until EnableOut asserts
--     3. De-assert EnableIn
--     4. Assert EnableClear for 2 clock cycles
--     5. De-assert EnableClear
--
--   New version: each boolean strobe input is pulsed for one clock cycle.
--
--   Each interface is tested in its own procedure so the call order can be
--   easily rearranged in the main process.
--
-- NOTE: Both DUTs share entity name "HdlSharedInputFifoInterface".
--       The old version (HdlSharedInputFifoInterfaceOld.vhd) must be compiled
--       into a separate VHDL library called "old_lib":
--
--         vcom -work old_lib  HdlSharedInputFifoInterfaceOld.vhd
--         vcom -work work     HdlSharedInputFifoInterface.vhd
--         vcom -work work     tb_HdlSharedInputFifoInterface.vhd
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  use work.PkgDmaPortCommunicationInterface.all;
  use work.PkgDmaPortDmaFifos.all;
  use work.PkgDmaPortDataPackingFifo.all;
  use work.PkgDmaPortCommIfcStreamStates.all;
  use work.PkgNiDma.all;

entity tb_HdlSharedInputFifoInterface is
end entity tb_HdlSharedInputFifoInterface;


architecture sim of tb_HdlSharedInputFifoInterface is

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  constant kClkPeriod         : time     := 10 ns;
  constant kFifoDepth         : natural  := 1024;
  constant kSampleWidth       : positive := 32;
  constant kNumSamplesPerWrite : positive := 1;
  constant kNumSamplesPerRead  : positive := 1;

  ---------------------------------------------------------------------------
  -- Shared clocks and resets
  ---------------------------------------------------------------------------
  signal BusClk         : std_logic := '0';
  signal ViClk          : std_logic := '0';
  signal DefaultClk     : std_logic := '0';
  signal aDiagramReset  : boolean   := true;
  signal aBusReset      : boolean   := true;
  signal StopSim        : boolean   := false;

  ---------------------------------------------------------------------------
  -- NEW DUT signals
  ---------------------------------------------------------------------------
  signal new_bToFifo                    : InputStreamInterfaceToFifo_t := kInputStreamInterfaceToFifoZero;
  signal new_bFromFifo                  : InputStreamInterfaceFromFifo_t;
  signal new_vDataIn                    : std_logic_vector(kSampleWidth*kNumSamplesPerWrite-1 downto 0) := (others => '0');
  signal new_vFull                      : boolean;
  signal new_vWriteFifo                 : boolean := false;
  signal new_vFlush                     : boolean := false;
  signal new_vCtCount                   : unsigned(31 downto 0);
  signal new_vInputValid                : boolean := false;
  signal new_vReadyForInput             : boolean;
  signal new_vStreamStateOut            : StreamStateValue_t;
  signal new_vStartStreamRequest        : boolean := false;
  signal new_vStopRequest               : boolean := false;
  signal new_vFlushTimeoutRequest       : boolean := false;
  signal new_vStopWithFlushRequest      : boolean := false;

  ---------------------------------------------------------------------------
  -- OLD DUT signals
  ---------------------------------------------------------------------------
  signal old_bToFifo                    : InputStreamInterfaceToFifo_t := kInputStreamInterfaceToFifoZero;
  signal old_bFromFifo                  : InputStreamInterfaceFromFifo_t;
  signal old_vDataIn                    : std_logic_vector(kSampleWidth*kNumSamplesPerWrite-1 downto 0) := (others => '0');
  signal old_vFull                      : std_logic;
  signal old_vTimeout                   : std_logic_vector(31 downto 0) := (others => '0');
  -- Write enable chain
  signal old_vEnableIn                  : std_logic := '0';
  signal old_vEnableOut                 : std_logic;
  signal old_vEnableClear               : std_logic := '0';
  -- Flush enable chain
  signal old_vFlushEnableIn             : std_logic := '0';
  signal old_vFlushEnableOut            : std_logic;
  signal old_vFlushEnableClear          : std_logic := '0';
  -- Count enable chain
  signal old_vCtCount                   : unsigned(31 downto 0);
  signal old_vCtEnableIn                : std_logic := '0';
  signal old_vCtEnableOut               : std_logic;
  signal old_vCtEnableOutClear          : std_logic := '0';
  -- Handshaking
  signal old_vInputValid                : std_logic := '0';
  signal old_vReadyForInput             : std_logic;
  -- VI clock stream state enable chain
  signal old_vStreamStateEnableIn       : std_logic := '0';
  signal old_vStreamStateEnableOut      : std_logic;
  signal old_vStreamStateEnableClear    : std_logic := '0';
  signal old_vStreamStateOut            : StreamStateValue_t;
  -- Default clock stream state enable chain
  signal old_dStreamStateEnableIn       : std_logic := '0';
  signal old_dStreamStateEnableOut      : std_logic;
  signal old_dStreamStateEnableClear    : std_logic := '0';
  signal old_dStreamStateOut            : StreamStateValue_t;
  signal old_dCurrentStreamState        : StreamStateValue_t;
  -- Start request enable chain
  signal old_dStartRequestEnableIn      : std_logic := '0';
  signal old_dStartRequestEnableOut     : std_logic;
  signal old_dStartRequestEnableClear   : std_logic := '0';
  -- Stop request enable chain
  signal old_dStopRequestEnableIn       : std_logic := '0';
  signal old_dStopRequestEnableOut      : std_logic;
  signal old_dStopRequestEnableClear    : std_logic := '0';
  -- Stop with flush request enable chain
  signal old_dStopWithFlushRequestEnableIn    : std_logic := '0';
  signal old_dStopWithFlushRequestEnableOut   : std_logic;
  signal old_dStopWithFlushRequestEnableClear : std_logic := '0';
  signal old_dStopWithFlushRequestTimeout     : signed(31 downto 0) := (others => '0');
  signal old_dStopWithFlushRequestTimedOut    : std_logic;

  ---------------------------------------------------------------------------
  -- OLD OUTPUT DUT signals
  ---------------------------------------------------------------------------
  signal oldout_bToFifo                          : OutputStreamInterfaceToFifo_t := kOutputStreamInterfaceToFifoZero;
  signal oldout_bFromFifo                         : OutputStreamInterfaceFromFifo_t;
  signal oldout_vDataOut                          : std_logic_vector(kSampleWidth*kNumSamplesPerRead-1 downto 0);
  signal oldout_vEmpty                            : std_logic;
  signal oldout_vTimeout                          : std_logic_vector(31 downto 0) := (others => '0');
  signal oldout_vEnableIn                         : std_logic := '0';
  signal oldout_vEnableOut                        : std_logic;
  signal oldout_vEnableClear                      : std_logic := '0';
  signal oldout_vCtCount                          : unsigned(31 downto 0);
  signal oldout_vCtEnableIn                       : std_logic := '0';
  signal oldout_vCtEnableOut                      : std_logic;
  signal oldout_vCtEnableOutClear                 : std_logic := '0';
  signal oldout_vOutputValid                      : std_logic;
  signal oldout_vReadyForOutput                   : std_logic := '0';
  signal oldout_vStreamStateEnableIn              : std_logic := '0';
  signal oldout_vStreamStateEnableOut             : std_logic;
  signal oldout_vStreamStateEnableClear           : std_logic := '0';
  signal oldout_vStreamStateOut                   : StreamStateValue_t;
  signal oldout_dStreamStateEnableIn              : std_logic := '0';
  signal oldout_dStreamStateEnableOut             : std_logic;
  signal oldout_dStreamStateEnableClear           : std_logic := '0';
  signal oldout_dStreamStateOut                   : StreamStateValue_t;
  signal oldout_dCurrentStreamState               : StreamStateValue_t;
  signal oldout_dStartRequestEnableIn             : std_logic := '0';
  signal oldout_dStartRequestEnableOut            : std_logic;
  signal oldout_dStartRequestEnableClear          : std_logic := '0';
  signal oldout_dStopRequestEnableIn              : std_logic := '0';
  signal oldout_dStopRequestEnableOut             : std_logic;
  signal oldout_dStopRequestEnableClear           : std_logic := '0';


  ---------------------------------------------------------------------------
  -- Helper: Drive a standard enable chain sequence.
  --   1. Assert EnableIn
  --   2. Wait until EnableOut asserts (sampled on rising_edge of clk)
  --   3. De-assert EnableIn
  --   4. Assert EnableClear for 2 clock cycles
  --   5. De-assert EnableClear
  ---------------------------------------------------------------------------
  procedure drive_enable_chain (
    signal clk          : in  std_logic;
    signal enable_in    : out std_logic;
    signal enable_out   : in  std_logic;
    signal enable_clear : out std_logic
  ) is
  begin
    enable_in <= '1';
    wait until rising_edge(clk) and enable_out = '1';
    enable_in <= '0';
    enable_clear <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    enable_clear <= '0';
  end procedure;

  ---------------------------------------------------------------------------
  -- Helper: Pulse a boolean strobe for one clock cycle.
  ---------------------------------------------------------------------------
  procedure drive_strobe (
    signal clk    : in  std_logic;
    signal strobe : out boolean
  ) is
  begin
    strobe <= true;
    wait until rising_edge(clk);
    strobe <= false;
    wait until rising_edge(clk);
  end procedure;


begin

  ---------------------------------------------------------------------------
  -- Clock generation
  ---------------------------------------------------------------------------
  BusClk     <= not BusClk     after kClkPeriod/2 when not StopSim;
  ViClk      <= not ViClk      after kClkPeriod/2 when not StopSim;
  DefaultClk <= not DefaultClk after kClkPeriod/2 when not StopSim;

  ---------------------------------------------------------------------------
  -- NEW DUT instantiation
  ---------------------------------------------------------------------------
  u_new : entity work.HdlSharedInputFifoInterface(structure)
    generic map (
      kFifoDepth            => kFifoDepth,
      kSampleWidth          => kSampleWidth,
      kNumOfSamplesPerWrite => kNumSamplesPerWrite,
      kSignExtend           => false,
      kFxpType              => false,
      kPeerToPeer           => false,
      kDisableOnFifoTimeout => false)
    port map (
      aDiagramReset                 => aDiagramReset,
      aBusReset                     => aBusReset,
      BusClk                        => BusClk,
      bInputStreamInterfaceToFifo   => new_bToFifo,
      bInputStreamInterfaceFromFifo => new_bFromFifo,
      ViClk                         => ViClk,
      vDataIn                       => new_vDataIn,
      vFull                         => new_vFull,
      vWriteFifo                    => new_vWriteFifo,
      vFlush                        => new_vFlush,
      vCtCount                      => new_vCtCount,
      vInputValid                   => new_vInputValid,
      vReadyForInput                => new_vReadyForInput,
      vStreamStateOut               => new_vStreamStateOut,
      vStartStreamRequest           => new_vStartStreamRequest,
      vStopRequest                  => new_vStopRequest,
      vFlushTimeoutRequest          => new_vFlushTimeoutRequest,
      vStopWithFlushRequest         => new_vStopWithFlushRequest);

  ---------------------------------------------------------------------------
  -- OLD DUT instantiation  
  ---------------------------------------------------------------------------
  u_old : entity work.HdlSharedInputFifoInterfaceOld(structure)
    generic map (
      kFifoDepth             => kFifoDepth,
      kSampleWidth           => kSampleWidth,
      kNumOfSamplesPerWrite  => kNumSamplesPerWrite,
      kScl                   => false,
      kCountScl              => false,
      kSignExtend            => false,
      kFxpType               => false,
      kPeerToPeer            => false,
      kDisableOnFifoTimeout  => false,
      kViClkIsDefaultClk     => true,
      kWriteUsingHandshaking => false)
    port map (
      aDiagramReset                    => aDiagramReset,
      aBusReset                        => aBusReset,
      BusClk                           => BusClk,
      bInputStreamInterfaceToFifo      => old_bToFifo,
      bInputStreamInterfaceFromFifo    => old_bFromFifo,
      ViClk                            => ViClk,
      vDataIn                          => old_vDataIn,
      vFull                            => old_vFull,
      vTimeout                         => old_vTimeout,
      vEnableIn                        => old_vEnableIn,
      vEnableOut                       => old_vEnableOut,
      vEnableClear                     => old_vEnableClear,
      vFlushEnableIn                   => old_vFlushEnableIn,
      vFlushEnableOut                  => old_vFlushEnableOut,
      vFlushEnableClear                => old_vFlushEnableClear,
      vCtCount                         => old_vCtCount,
      vCtEnableIn                      => old_vCtEnableIn,
      vCtEnableOut                     => old_vCtEnableOut,
      vCtEnableOutClear                => old_vCtEnableOutClear,
      vInputValid                      => old_vInputValid,
      vReadyForInput                   => old_vReadyForInput,
      DefaultClk                       => DefaultClk,
      vStreamStateEnableIn             => old_vStreamStateEnableIn,
      vStreamStateEnableOut            => old_vStreamStateEnableOut,
      vStreamStateEnableClear          => old_vStreamStateEnableClear,
      vStreamStateOut                  => old_vStreamStateOut,
      dStreamStateEnableIn             => old_dStreamStateEnableIn,
      dStreamStateEnableOut            => old_dStreamStateEnableOut,
      dStreamStateEnableClear          => old_dStreamStateEnableClear,
      dStreamStateOut                  => old_dStreamStateOut,
      dCurrentStreamState              => old_dCurrentStreamState,
      dStartRequestEnableIn            => old_dStartRequestEnableIn,
      dStartRequestEnableOut           => old_dStartRequestEnableOut,
      dStartRequestEnableClear         => old_dStartRequestEnableClear,
      dStopRequestEnableIn             => old_dStopRequestEnableIn,
      dStopRequestEnableOut            => old_dStopRequestEnableOut,
      dStopRequestEnableClear          => old_dStopRequestEnableClear,
      dStopWithFlushRequestEnableIn    => old_dStopWithFlushRequestEnableIn,
      dStopWithFlushRequestEnableOut   => old_dStopWithFlushRequestEnableOut,
      dStopWithFlushRequestEnableClear => old_dStopWithFlushRequestEnableClear,
      dStopWithFlushRequestTimeout     => old_dStopWithFlushRequestTimeout,
      dStopWithFlushRequestTimedOut    => old_dStopWithFlushRequestTimedOut);

  ---------------------------------------------------------------------------
  -- OLD OUTPUT DUT instantiation
  ---------------------------------------------------------------------------
  u_old_output : entity work.HdlSharedOutputFifoInterfaceOld(structure)
    generic map (
      kFifoDepth             => kFifoDepth,
      kSampleWidth           => kSampleWidth,
      kNumOfSamplesPerRead   => kNumSamplesPerRead,
      kFxpType               => false,
      kScl                   => false,
      kCountScl              => false,
      kPeerToPeer            => false,
      kDisableOnFifoTimeout  => false,
      kViClkIsDefaultClk     => true,
      kReadUsingHandshaking  => false)
    port map (
      aDiagramReset                  => aDiagramReset,
      aBusReset                      => aBusReset,
      BusClk                         => BusClk,
      ViClk                          => ViClk,
      bOutputStreamInterfaceToFifo   => oldout_bToFifo,
      bOutputStreamInterfaceFromFifo => oldout_bFromFifo,
      vDataOut                       => oldout_vDataOut,
      vEmpty                         => oldout_vEmpty,
      vTimeout                       => oldout_vTimeout,
      vEnableIn                      => oldout_vEnableIn,
      vEnableOut                     => oldout_vEnableOut,
      vEnableClear                   => oldout_vEnableClear,
      vCtCount                       => oldout_vCtCount,
      vCtEnableIn                    => oldout_vCtEnableIn,
      vCtEnableOut                   => oldout_vCtEnableOut,
      vCtEnableOutClear              => oldout_vCtEnableOutClear,
      vOutputValid                   => oldout_vOutputValid,
      vReadyForOutput                => oldout_vReadyForOutput,
      DefaultClk                     => DefaultClk,
      vStreamStateEnableIn           => oldout_vStreamStateEnableIn,
      vStreamStateEnableOut          => oldout_vStreamStateEnableOut,
      vStreamStateEnableClear        => oldout_vStreamStateEnableClear,
      vStreamStateOut                => oldout_vStreamStateOut,
      dStreamStateEnableIn           => oldout_dStreamStateEnableIn,
      dStreamStateEnableOut          => oldout_dStreamStateEnableOut,
      dStreamStateEnableClear        => oldout_dStreamStateEnableClear,
      dStreamStateOut                => oldout_dStreamStateOut,
      dCurrentStreamState            => oldout_dCurrentStreamState,
      dStartRequestEnableIn          => oldout_dStartRequestEnableIn,
      dStartRequestEnableOut         => oldout_dStartRequestEnableOut,
      dStartRequestEnableClear       => oldout_dStartRequestEnableClear,
      dStopRequestEnableIn           => oldout_dStopRequestEnableIn,
      dStopRequestEnableOut          => oldout_dStopRequestEnableOut,
      dStopRequestEnableClear        => oldout_dStopRequestEnableClear);


  ---------------------------------------------------------------------------
  -- Main stimulus process
  ---------------------------------------------------------------------------
  main_proc : process

    -----------------------------------------------------------------------
    -- OLD version: enable chain test procedures (reorder calls as needed)
    -----------------------------------------------------------------------

    -- Write enable chain (ViClk domain)
    procedure old_test_write_enable_chain is
    begin
      report "OLD: Testing write enable chain";
      drive_enable_chain(ViClk,
                         old_vEnableIn,
                         old_vEnableOut,
                         old_vEnableClear);
      report "OLD: Write enable chain complete";
    end procedure;

    -- Flush enable chain (ViClk domain)
    procedure old_test_flush_enable_chain is
    begin
      report "OLD: Testing flush enable chain";
      drive_enable_chain(ViClk,
                         old_vFlushEnableIn,
                         old_vFlushEnableOut,
                         old_vFlushEnableClear);
      report "OLD: Flush enable chain complete";
    end procedure;

    -- Count enable chain (ViClk domain)
    procedure old_test_count_enable_chain is
    begin
      report "OLD: Testing count enable chain";
      drive_enable_chain(ViClk,
                         old_vCtEnableIn,
                         old_vCtEnableOut,
                         old_vCtEnableOutClear);
      report "OLD: Count enable chain complete";
    end procedure;

    -- VI-clock stream state enable chain (ViClk domain)
    procedure old_test_vi_stream_state_enable_chain is
    begin
      report "OLD: Testing VI stream state enable chain";
      drive_enable_chain(ViClk,
                         old_vStreamStateEnableIn,
                         old_vStreamStateEnableOut,
                         old_vStreamStateEnableClear);
      report "OLD: VI stream state enable chain complete";
    end procedure;

    -- Default-clock stream state enable chain (DefaultClk domain)
    procedure old_test_default_stream_state_enable_chain is
    begin
      report "OLD: Testing default-clock stream state enable chain";
      drive_enable_chain(DefaultClk,
                         old_dStreamStateEnableIn,
                         old_dStreamStateEnableOut,
                         old_dStreamStateEnableClear);
      report "OLD: Default-clock stream state enable chain complete";
    end procedure;

    -- Start request enable chain (DefaultClk domain)
    procedure old_test_start_request_enable_chain is
    begin
      report "OLD: Testing start request enable chain";
      drive_enable_chain(DefaultClk,
                         old_dStartRequestEnableIn,
                         old_dStartRequestEnableOut,
                         old_dStartRequestEnableClear);
      report "OLD: Start request enable chain complete";
    end procedure;

    -- Stop request enable chain (DefaultClk domain)
    procedure old_test_stop_request_enable_chain is
    begin
      report "OLD: Testing stop request enable chain";
      drive_enable_chain(DefaultClk,
                         old_dStopRequestEnableIn,
                         old_dStopRequestEnableOut,
                         old_dStopRequestEnableClear);
      report "OLD: Stop request enable chain complete";
    end procedure;

    -- Stop with flush request enable chain (DefaultClk domain)
    procedure old_test_stop_with_flush_request_enable_chain is
    begin
      report "OLD: Testing stop with flush request enable chain";
      drive_enable_chain(DefaultClk,
                         old_dStopWithFlushRequestEnableIn,
                         old_dStopWithFlushRequestEnableOut,
                         old_dStopWithFlushRequestEnableClear);
      report "OLD: Stop with flush request enable chain complete";
    end procedure;


    -----------------------------------------------------------------------
    -- NEW version: boolean strobe test procedures (reorder calls as needed)
    -----------------------------------------------------------------------

    -- Write FIFO strobe
    procedure new_test_write_fifo is
    begin
      report "NEW: Testing vWriteFifo strobe";
      drive_strobe(ViClk, new_vWriteFifo);
      report "NEW: vWriteFifo strobe complete";
    end procedure;

    -- Flush strobe
    procedure new_test_flush is
    begin
      report "NEW: Testing vFlush strobe";
      drive_strobe(ViClk, new_vFlush);
      report "NEW: vFlush strobe complete";
    end procedure;

    -- Start stream request strobe
    procedure new_test_start_stream_request is
    begin
      report "NEW: Testing vStartStreamRequest strobe";
      drive_strobe(ViClk, new_vStartStreamRequest);
      report "NEW: vStartStreamRequest strobe complete";
    end procedure;

    -- Stop request strobe
    procedure new_test_stop_request is
    begin
      report "NEW: Testing vStopRequest strobe";
      drive_strobe(ViClk, new_vStopRequest);
      report "NEW: vStopRequest complete";
    end procedure;

    -- Flush timeout request strobe
    procedure new_test_flush_timeout_request is
    begin
      report "NEW: Testing vFlushTimeoutRequest strobe";
      drive_strobe(ViClk, new_vFlushTimeoutRequest);
      report "NEW: vFlushTimeoutRequest complete";
    end procedure;

    -- Stop with flush request strobe
    procedure new_test_stop_with_flush_request is
    begin
      report "NEW: Testing vStopWithFlushRequest strobe";
      drive_strobe(ViClk, new_vStopWithFlushRequest);
      report "NEW: vStopWithFlushRequest complete";
    end procedure;

    -- Input valid strobe (handshaking)
    procedure new_test_input_valid is
    begin
      report "NEW: Testing vInputValid strobe";
      drive_strobe(ViClk, new_vInputValid);
      report "NEW: vInputValid strobe complete";
    end procedure;


  begin

    -----------------------------------------------------------------------
    -- Reset phase
    -----------------------------------------------------------------------
    aDiagramReset <= true;
    aBusReset     <= true;
    wait for 100 ns;
    aDiagramReset <= false;
    aBusReset     <= false;
    wait for 100 ns;

    -----------------------------------------------------------------------
    -- Old version tests  -- Reorder these calls as needed.
    -----------------------------------------------------------------------
    old_test_start_request_enable_chain;
    old_test_write_enable_chain;
    old_test_count_enable_chain;
    old_test_write_enable_chain;
    old_test_count_enable_chain;  
    old_test_flush_enable_chain;
    old_test_write_enable_chain;
    old_test_count_enable_chain;
    old_test_vi_stream_state_enable_chain;
    old_test_default_stream_state_enable_chain;
    old_test_stop_request_enable_chain;
    old_test_stop_with_flush_request_enable_chain;

    -----------------------------------------------------------------------
    -- New version tests  -- Reorder these calls as needed.
    -----------------------------------------------------------------------
    new_test_write_fifo;
    new_test_flush;
    new_test_start_stream_request;
    new_test_stop_request;
    new_test_flush_timeout_request;
    new_test_stop_with_flush_request;
    new_test_input_valid;

    -----------------------------------------------------------------------
    -- Done
    -----------------------------------------------------------------------
    wait for 100 ns;
    StopSim <= true;
    report "Simulation complete" severity note;
    wait;

  end process main_proc;

end architecture sim;
