"""nihdlsettings.py - Settings for HDL Shared Input FIFO project."""


def pre_all(context):
    """Configure settings for the FIFO testbench project."""
    config = context.config

    # --- Tools ---
    config.set_vivado_tools_folder("C:/NIFPGA/programs/Vivado2021_1")
    config.set_vivado_tcl_scripts_folder("../common/TCL")
    config.set_modelsim_tools_folder("C:/modeltech_pe_2020.4")
    config.set_xilinx_sim_lib_folder("C:/dev/libraries/vivado/2021.1/modelsim_PE_2020")

    # --- Vivado Project Settings ---
    config.set_top_level_entity("tb_all")
    config.set_fpga_part("xcku040-ffva1156-2-e")
    config.set_vivado_project_folder("VivadoProject")

    # --- HDL Source Code ---
    config.add_hdl_file_list("vivadoprojectsources.txt")
    config.add_hdl_file_list("vivadoprojecttestbenchsources.txt")
    config.add_hdl_file_list("../../deps/flexrio-deps/hdl_shared_deps_list/hdlsharedvivadoprojectdeps.txt")

    # --- ModelSim Project Settings ---
    config.set_modelsim_project_folder("ModelSimProject")
    config.add_modelsim_file_list("vivadoprojectsources.txt")
    config.add_modelsim_file_list("vivadoprojecttestbenchsources.txt")
    config.add_modelsim_file_list("../../deps/flexrio-deps/hdl_shared_deps_list/hdlsharedvivadoprojectdeps.txt")
