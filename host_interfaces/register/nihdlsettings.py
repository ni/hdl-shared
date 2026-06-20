"""nihdlsettings.py - Settings for HDL Shared Host Register project."""


def pre_all(context):
    """Configure settings for the Register testbench project."""
    config = context.config

    # --- Tools ---
    config.set_vivado_tools_folder("C:/NIFPGA/programs/Vivado2021_1")
    config.set_vivado_tcl_scripts_folder("../common/TCL")

    # --- Vivado Project Settings ---
    config.set_vivado_top_entity("tb_NiSharedHostRegister")
    config.set_fpga_part("xcku040-ffva1156-2-e")
    config.set_vivado_project_folder("VivadoProject")

    # --- HDL Source Code ---
    config.add_hdl_file_list("vivadoprojectsources.txt")
    config.add_hdl_file_list("vivadoprojectdeps.txt")
