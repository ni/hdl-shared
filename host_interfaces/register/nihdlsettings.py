"""nihdlsettings.py - Settings for HDL Shared Host Register project."""


def pre_all(context):
    """Configure settings for the Register testbench project."""
    config = context.config

    # --- Dependencies ---
    config.set_dependencies("../../dependencies.toml")

    # --- Tools ---
    config.set_vivado_tools_folder("C:/NIFPGA/programs/Vivado2021_1")
    config.set_vivado_tcl_scripts_folder("../common/TCL")
    config.set_modelsim_tools_folder("C:/modeltech_pe_2020.4")
    config.set_xilinx_sim_lib_folder("../../objects/sim_library")
    config.add_xilinx_sim_library("unisim")
    # Narrow compile_simlib to the target device family so it does not build
    # every Xilinx family (which takes hours). xcku040 is Kintex UltraScale.
    config.set_xilinx_sim_family("kintexu")

    # --- Vivado Project Settings ---
    config.set_vivado_top_entity("tb_NiSharedHostRegister")
    config.set_fpga_part("xcku040-ffva1156-2-e")
    config.set_vivado_project_folder("VivadoProject")

    # --- HDL Source Code ---
    config.add_hdl_file_list("vivadoprojectsources.txt")
    config.add_hdl_file_list("vivadoprojectdeps.txt")

    # --- ModelSim Project Settings ---
    config.set_modelsim_project_folder("ModelSimProject")
    config.add_modelsim_file_list("vivadoprojectsources.txt")
    config.add_modelsim_file_list("vivadoprojectdeps.txt")
