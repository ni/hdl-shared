This project contains shared code for HDL-to-Host registers.  The HDL examples can be instantiated in custom LV FPGA targets and the LabVIEW VI's are used with the NI-RIO host API.

You can use the LabVIEW FPGA HDL Tools to generate a Vivado project for simulation.

Install the LabVIEW FPGA HDL Tools:
pip install -r requirements.txt

Run these nihdl commands:
nihdl install-deps
nihdl create-project
nihdl launch-vivado

Then in Vivado, you can click Run Simulation to simulate the testbench

