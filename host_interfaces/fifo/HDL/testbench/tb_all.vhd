-------------------------------------------------------------------------------
--
-- File: tb_all.vhd
-- Original Project: LabVIEW FPGA
--
-------------------------------------------------------------------------------
-- (c) Copyright National Instruments Corporation
-- All Rights Reserved
-- National Instruments Internal Information
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

end test;
