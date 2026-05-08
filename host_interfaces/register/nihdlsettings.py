"""nihdlsettings.py - Settings for HDL Shared Host Register project."""


def pre_all(context):
    """Configure settings for the Register testbench project."""
    config = context.config

    # --- Tools ---
    config.set_vivado_tools_path("C:/NIFPGA/programs/Vivado2021_1")
    config.set_vivado_tcl_scripts_folder("../common/TCL")

    # --- Vivado Project Settings ---
    config.set_top_level_entity("tb_NiSharedHostRegister")
    config.set_fpga_part("xcku040-ffva1156-2-e")
    config.set_vivado_project_path("VivadoProject/HdlRegister.xpr")

    config.add_hdl_file_list("vivadoprojectsources.txt")
    config.add_hdl_file_list("vivadoprojectdeps.txt")

    config.set_use_gen_lv_window_files(False)
