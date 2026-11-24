-------------------------------------------------------------------------------
--
-- File: tb_all.vhd
-- Original Project: LabVIEW FPGA
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
--
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------
--
-- Purpose:
--   Top-level testbench that instantiates both the input and output FIFO
--   testbenches so they can run concurrently in a single simulation.
--
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;

entity tb_all is
end tb_all;

architecture test of tb_all is
begin

  InputFifoTb : entity work.tb_FifoWriter(test);

  OutputFifoTb : entity work.tb_FifoReader(test);

  -- Same Reader suite at the pxie-7912 clock ratio (core BusClk = DmaClk
  -- 250 MHz, ViClk = PllClk80 80 MHz) and with ViClk faster than BusClk.
  OutputFifoTbHwRatio : entity work.tb_FifoReader(test)
    generic map (kBusClkPeriod => 4 ns, kViClkPeriod => 12.5 ns);

  OutputFifoTbFastViClk : entity work.tb_FifoReader(test)
    generic map (kBusClkPeriod => 12 ns, kViClkPeriod => 5 ns);

end test;
