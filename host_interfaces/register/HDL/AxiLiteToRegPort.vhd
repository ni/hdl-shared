-------------------------------------------------------------------------------
--
-- File: AxiLiteToRegPort.vhd
--
-------------------------------------------------------------------------------
-- (c) 2025 Copyright National Instruments Corporation
-- 
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
-- This entity converts AXI-Lite interface to RegPort interface.
-- Acts as an AXI-Lite slave that translates transactions to RegPort read/write.
--
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  
library work;
  use work.PkgNiUtilities.all;
  use work.PkgCommunicationInterface.all;
  
entity AxiLiteToRegPort is
  generic(
    kDataWidth : natural := 32;
    kAddrWidth : natural := 32
  );
  port(
    -- Clock and Reset
    aClk    : in std_logic;
    aReset  : in boolean;

    -- AXI-Lite Slave Interface
    -- Write Address Channel
    sAxiAwAddr  : in  std_logic_vector(kAddrWidth-1 downto 0);
    sAxiAwProt  : in  std_logic_vector(2 downto 0);
    sAxiAwValid : in  std_logic;
    sAxiAwReady : out std_logic;
    
    -- Write Data Channel
    sAxiWData   : in  std_logic_vector(kDataWidth-1 downto 0);
    sAxiWStrb   : in  std_logic_vector((kDataWidth/8)-1 downto 0);
    sAxiWValid  : in  std_logic;
    sAxiWReady  : out std_logic;
    
    -- Write Response Channel
    sAxiBresp   : out std_logic_vector(1 downto 0);
    sAxiBValid  : out std_logic;
    sAxiBReady  : in  std_logic;
    
    -- Read Address Channel
    sAxiArAddr  : in  std_logic_vector(kAddrWidth-1 downto 0);
    sAxiArProt  : in  std_logic_vector(2 downto 0);
    sAxiArValid : in  std_logic;
    sAxiArReady : out std_logic;
    
    -- Read Data Channel
    sAxiRData   : out std_logic_vector(kDataWidth-1 downto 0);
    sAxiRResp   : out std_logic_vector(1 downto 0);
    sAxiRValid  : out std_logic;
    sAxiRReady  : in  std_logic;

    -- RegPort Interface
    bRegPortOut : out RegPortOut_t;
    bRegPortIn  : in  RegPortIn_t
  );  
end entity AxiLiteToRegPort;

architecture rtl of AxiLiteToRegPort is

  -- AXI Response codes
  constant kAxiRespOkay   : std_logic_vector(1 downto 0) := "00";
  constant kAxiRespSlverr : std_logic_vector(1 downto 0) := "10";

  -- State machines
  type WriteState_t is (IDLE, WAIT_BOTH, WRITE_REG, WRITE_RESP);
  type ReadState_t is (IDLE, READ_REG, READ_RESP);
  
  signal WriteState : WriteState_t;
  signal ReadState  : ReadState_t;
  
  -- Internal registers
  signal aWriteAddr : unsigned(kAddrWidth-1 downto 0);
  signal aWriteData : std_logic_vector(kDataWidth-1 downto 0);
  signal aReadAddr  : unsigned(kAddrWidth-1 downto 0);
  signal aReadData  : std_logic_vector(kDataWidth-1 downto 0);
  
  signal aAwAddrLatched : boolean;
  signal aWDataLatched  : boolean;

begin

  -- Write Address Channel Handler
  WriteAddrProc: process(aClk)
  begin
    if rising_edge(aClk) then
      if aReset then
        aAwAddrLatched <= false;
        aWriteAddr <= (others => '0');
        sAxiAwReady <= '0';
      else
        -- Default
        sAxiAwReady <= '0';
        
        -- Latch address when valid and in IDLE or waiting for data
        if sAxiAwValid = '1' and not aAwAddrLatched and 
           (WriteState = IDLE or (WriteState = WAIT_BOTH and not aWDataLatched)) then
          aWriteAddr <= unsigned(sAxiAwAddr);
          aAwAddrLatched <= true;
          sAxiAwReady <= '1';
        end if;
        
        -- Clear latch when write completes
        if WriteState = WRITE_RESP and sAxiBReady = '1' then
          aAwAddrLatched <= false;
        end if;
      end if;
    end if;
  end process WriteAddrProc;

  -- Write Data Channel Handler
  WriteDataProc: process(aClk)
  begin
    if rising_edge(aClk) then
      if aReset then
        aWDataLatched <= false;
        aWriteData <= (others => '0');
        sAxiWReady <= '0';
      else
        -- Default
        sAxiWReady <= '0';
        
        -- Latch data when valid and in IDLE or waiting for address
        if sAxiWValid = '1' and not aWDataLatched and 
           (WriteState = IDLE or (WriteState = WAIT_BOTH and not aAwAddrLatched)) then
          aWriteData <= sAxiWData;
          aWDataLatched <= true;
          sAxiWReady <= '1';
        end if;
        
        -- Clear latch when write completes
        if WriteState = WRITE_RESP and sAxiBReady = '1' then
          aWDataLatched <= false;
        end if;
      end if;
    end if;
  end process WriteDataProc;

  -- Write State Machine
  WriteStateMachine: process(aClk)
  begin
    if rising_edge(aClk) then
      if aReset then
        WriteState <= IDLE;
        bRegPortOut.Wt <= false;
        bRegPortOut.Address <= (others => '0');
        bRegPortOut.Data <= (others => '0');
        sAxiBresp <= kAxiRespOkay;
        sAxiBValid <= '0';
      else
        -- Default: deassert write strobe
        bRegPortOut.Wt <= false;
        
        case WriteState is
          when IDLE =>
            sAxiBValid <= '0';
            if aAwAddrLatched and aWDataLatched then
              -- Both address and data available, proceed to write
              WriteState <= WRITE_REG;
            elsif sAxiAwValid = '1' or sAxiWValid = '1' then
              -- Waiting for both address and data
              WriteState <= WAIT_BOTH;
            end if;
            
          when WAIT_BOTH =>
            if aAwAddrLatched and aWDataLatched then
              WriteState <= WRITE_REG;
            end if;
            
          when WRITE_REG =>
            -- Issue write to RegPort
            bRegPortOut.Address <= resize(aWriteAddr, bRegPortOut.Address'length);
            bRegPortOut.Data <= aWriteData;
            bRegPortOut.Wt <= true;
            -- Check if RegPort is ready
            if bRegPortIn.Ready then
              WriteState <= WRITE_RESP;
              sAxiBresp <= kAxiRespOkay;
              sAxiBValid <= '1';
            else
              -- Stay in WRITE_REG until ready
              WriteState <= WRITE_REG;
            end if;
            
          when WRITE_RESP =>
            -- Wait for master to accept response
            if sAxiBReady = '1' then
              sAxiBValid <= '0';
              WriteState <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process WriteStateMachine;

  -- Read Address Channel Handler
  ReadAddrProc: process(aClk)
  begin
    if rising_edge(aClk) then
      if aReset then
        aReadAddr <= (others => '0');
        sAxiArReady <= '0';
      else
        sAxiArReady <= '0';
        
        if ReadState = IDLE and sAxiArValid = '1' then
          aReadAddr <= unsigned(sAxiArAddr);
          sAxiArReady <= '1';
        end if;
      end if;
    end if;
  end process ReadAddrProc;

  -- Read State Machine
  ReadStateMachine: process(aClk)
  begin
    if rising_edge(aClk) then
      if aReset then
        ReadState <= IDLE;
        bRegPortOut.Rd <= false;
        aReadData <= (others => '0');
        sAxiRData <= (others => '0');
        sAxiRResp <= kAxiRespOkay;
        sAxiRValid <= '0';
      else
        -- Default: deassert read strobe
        bRegPortOut.Rd <= false;
        
        case ReadState is
          when IDLE =>
            sAxiRValid <= '0';
            if sAxiArValid = '1' then
              -- Issue read to RegPort
              bRegPortOut.Address <= resize(aReadAddr, bRegPortOut.Address'length);
              bRegPortOut.Rd <= true;
              ReadState <= READ_REG;
            end if;
            
          when READ_REG =>
            -- Wait for valid data from RegPort
            if bRegPortIn.DataValid then
              aReadData <= bRegPortIn.Data;
              sAxiRData <= bRegPortIn.Data;
              sAxiRResp <= kAxiRespOkay;
              sAxiRValid <= '1';
              ReadState <= READ_RESP;
            end if;
            
          when READ_RESP =>
            -- Wait for master to accept data
            if sAxiRReady = '1' then
              sAxiRValid <= '0';
              ReadState <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process ReadStateMachine;

  -- Ready signal (always ready for now, could add backpressure logic)
  bRegPortOut.Ready <= true;

end rtl;
