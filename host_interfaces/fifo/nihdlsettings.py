"""nihdlsettings.py - Settings for HDL Shared Input FIFO project."""


def pre_all(context):
    """Configure settings for the FIFO testbench project."""
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

    # --- ModelSim Project Settings ---
    config.set_modelsim_project_folder("ModelSimProject")
    config.set_modelsim_top_entity("tb_all")
    config.add_modelsim_file_list("modelsimprojectsources.txt")
    config.add_modelsim_file_list("../../deps/flexrio-deps/hdl_shared_deps_list/hdlsharedvivadoprojectdeps.txt")
    # ModelSim compiles the ENTIRE hdlsharedvivadoprojectdeps.txt list, so the nidmaip
    # packages (e.g. PkgNiDma) are always compiled even for projects that do not use the
    # DMA/FIFO datapath. Those packages consume PkgNiDmaConfig.vhd, which is intentionally
    # NOT in hdlsharedvivadoprojectdeps because it is target-family-specific and would
    # conflict with the target-specific version when custom targets consume the shared HDL.
    # So each project must supply one concrete version itself; we pick it here for simulation.
    config.add_modelsim_file_list("../common/targetspecificdeps.txt")

