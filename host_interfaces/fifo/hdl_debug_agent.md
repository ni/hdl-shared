We have tools for compiling and simulating HDL

First, at a command line here:
C:\dev\github9-test\hdl-shared\host_interfaces\fifo>

Run this command:
nihdl create-modelsim

If there is already a modelsim project, you must type 
nihdl create-modelsim --overwrite

This will generate a new modelsim project using the right dependencies

Then in that same command window, navigate to here:
C:\dev\git\hw-flexrio\github\hdl_shared_deps

This will also output some .do files in ModelSimProject:
load_tb_all.do
sim_tb_all.do

You can edit that DO file to add this at the end:

vcd file output_file.vcd
vcd add /tb_all/*
run -all
vcd flush

these commands you add to the DO file will add signals to the VCD output
Feel free to change/add more "vcd add" lines depending on what you need to see to debug

You can use run -all or use something like run 10 us to run for a short period of time

The ouptut VCD file from modelsim goes here:
ModelSimProject\output_file.vcd

You can use the 

This will also report assertions and errors to the command prompt

Review the outputs of the simulation, review the VCD waveform logs

You can test this iteratively:
* Fix VHDL
* Add assertions, reporting into the testbench
* run vsmake
* Edit the load_tb_HdlSharedInputWrapper.do file to add signals to the VCD file
* run nisim
* see the output of the simulation in the command line
* Review the VCD file output to learn more about what his happening
* Repeat the process

Get the testbench working to test the DMA FIFO.

