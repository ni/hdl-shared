"""Shared wrapper nihdlsettings.py for the hdl-shared simulation tests.

This wrapper is passed to nihdl via ``--config=<this file>`` by the test shell
``run_tests.py``. It loads each project's own nihdlsettings.py from the
invocation directory, then applies CI/pipeline test overrides so the tests use
the tools installed on the build agent instead of the per-developer Windows
paths hard-coded in each project's settings.

hdl-shared is simulation only (no LabVIEW target plugins, no Vivado bitfile
builds), so the only overrides are the ModelSim and Vivado tools-folder
redirects driven from environment variables:

  * ``set_modelsim_tools_folder`` is redirected to the MODELSIM environment
    variable when ``--set use_modelsim_env=1`` is passed. MODELSIM points at the
    modelsim.ini file, so its parent directory is used as the tools folder.
  * ``set_vivado_tools_folder`` is redirected to the XILINX environment variable
    when ``--set use_xilinx_env=1`` is passed.

The behavior is driven entirely by generic ``--set KEY=VALUE`` overrides that
nihdl exposes to hooks as ``context.settings`` -- no per-variant wrapper files.
Both overrides are no-ops when the corresponding environment variable is unset,
so the wrapper is safe to use on a developer machine too.
"""

import os

from labview_fpga_hdl_tools.command_hooks import load_settings


def pre_all(context):
    """Wrapper hook: load the project settings, then apply CI tool overrides.

    Recognized ``--set`` keys (passed to nihdl on the command line):
      * ``use_modelsim_env=1``  override the ModelSim tools folder from the
        MODELSIM environment variable (set_modelsim_tools_folder). MODELSIM
        points at the modelsim.ini file, so its parent directory is used as the
        tools folder. No-op if MODELSIM is unset. Forwarded by run_tests.py's
        --modelsim-from-env flag.
      * ``use_xilinx_env=1``    override the Vivado tools folder from the XILINX
        environment variable (set_vivado_tools_folder). No-op if XILINX is
        unset. Forwarded by run_tests.py's --xilinx-from-env flag.
    """
    # Load the project's own settings from the invocation (project) directory.
    # load_settings chdir's into that directory while running the project's
    # pre_all, so the project's relative file-list and dependency paths resolve
    # correctly before we apply the tool overrides below.
    target_settings = os.path.join(context.invocation_dir, "nihdlsettings.py")
    load_settings(target_settings, context)

    # CI/pipeline: select the ModelSim install via the MODELSIM environment
    # variable when explicitly enabled. MODELSIM points at the modelsim.ini
    # file, so use its parent directory as the tools folder.
    if context.settings.get("use_modelsim_env"):
        modelsim_ini = os.environ.get("MODELSIM")
        if modelsim_ini:
            context.config.set_modelsim_tools_folder(os.path.dirname(modelsim_ini))

    # CI/pipeline: select the Vivado install via the XILINX environment variable
    # when explicitly enabled.
    if context.settings.get("use_xilinx_env"):
        xilinx_path = os.environ.get("XILINX")
        if xilinx_path:
            context.config.set_vivado_tools_folder(xilinx_path)
