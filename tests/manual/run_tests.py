#!/usr/bin/env python3
"""Test shell: run nihdl simulation tests across all hdl-shared projects.

This is the single entry point for the hdl-shared simulation tests. Each "test"
runs one nihdl subcommand in every host-interface project (the directories under
``host_interfaces`` that contain a ``nihdlsettings.py``, e.g. ``register`` and
``fifo``), using that project's own ``nihdlsettings.py``.

hdl-shared is simulation only: the only available tests are ``gen-modelsim`` and
``sim-modelsim``. There are no LabVIEW target plugins to generate and no Vivado
projects to build or compile. Each nihdl command runs through a shared wrapper
nihdlsettings.py (``tests/manual/nihdlsettings.py``, passed via ``--config``)
that loads the project's own settings and, for CI runs, redirects the ModelSim /
Vivado tools folders from the MODELSIM / XILINX environment variables
(--modelsim-from-env / --xilinx-from-env).

Generate the ModelSim projects and then run the testbench simulations:

    python run_tests.py gen-modelsim sim-modelsim

Run a single test:

    python run_tests.py sim-modelsim

List the available tests and the nihdl subcommand each one runs:

    python run_tests.py --list

Run with no arguments to run the full gen-modelsim -> sim-modelsim sweep:

    python run_tests.py

Tests run in the exact order you list them. The shell keeps going if a test
fails and prints a per-test summary plus an overall summary at the end.

See "python run_tests.py --help" for the full list of options.
"""

from __future__ import annotations

import argparse
import sys

from tests_common import (
    NIHDL_TESTS,
    add_common_arguments,
    print_test_summary,
    resolve_targets,
    run_test,
)

# The full sweep run when no tests are given on the command line.
DEFAULT_SEQUENCE = ["gen-modelsim", "sim-modelsim"]


def _print_available_tests() -> None:
    """Print the registered tests, the nihdl subcommand, and descriptions."""
    print("Available nihdl-command tests:\n")
    key_width = max(len(key) for key in NIHDL_TESTS)
    cmd_width = max(len(" ".join(t.subcommand)) for t in NIHDL_TESTS.values())
    print(f"  {'TEST':{key_width}}  {'NIHDL COMMAND':{cmd_width}}  DESCRIPTION")
    for key, test in NIHDL_TESTS.items():
        nihdl_cmd = " ".join(test.subcommand)
        print(f"  {key:{key_width}}  {nihdl_cmd:{cmd_width}}  {test.description}")
    print(
        "\nEach test runs 'nihdl <command>' in every project. To see the options "
        "for a\nspecific nihdl subcommand, ask nihdl directly, e.g.:\n"
        "    nihdl gen-modelsim --help\n"
        "    nihdl sim-modelsim --help"
    )


def main() -> int:
    epilog = (
        "tests:\n"
        "  Give one or more test keys (see the choices above) in the order to\n"
        "  run them. Omit to run the full gen-modelsim -> sim-modelsim sweep.\n"
        "  Each test runs 'nihdl <command>' in every discovered project.\n"
        "\n"
        "project selection:\n"
        "  Every directory under host_interfaces that contains a\n"
        "  nihdlsettings.py is a project (e.g. register, fifo). Use\n"
        "  --host-interfaces-dir to point at a different folder. Use --target\n"
        "  NAME (repeatable) to run on just one project, e.g. --target fifo.\n"
        "\n"
        "nihdl subcommand options:\n"
        "  The --xxx options below belong to THIS script. The options of each\n"
        "  underlying nihdl subcommand are owned by nihdl itself. To discover\n"
        "  them, ask nihdl directly:\n"
        "      nihdl gen-modelsim --help\n"
        "      nihdl sim-modelsim --help\n"
        "\n"
        "examples:\n"
        "  python run_tests.py --list\n"
        "  python run_tests.py\n"
        "  python run_tests.py gen-modelsim sim-modelsim\n"
        "  python run_tests.py sim-modelsim --target fifo\n"
        "  python run_tests.py sim-modelsim --nihdl-cmd C:/path/to/nihdl.exe\n"
    )
    parser = argparse.ArgumentParser(
        prog="run_tests.py",
        description=(
            "Run nihdl simulation tests (gen-modelsim, sim-modelsim) across all "
            "host_interfaces projects in hdl-shared."
        ),
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "tests",
        nargs="*",
        metavar="TEST",
        help=(
            "Sequence of tests to run, in order. "
            f"Choices: {', '.join(NIHDL_TESTS)}. "
            "Omit to run the full gen-modelsim -> sim-modelsim sweep."
        ),
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List the available tests (and the nihdl subcommand each runs) and exit",
    )
    add_common_arguments(parser)
    args = parser.parse_args()

    if args.list:
        _print_available_tests()
        return 0

    requested = list(args.tests) if args.tests else list(DEFAULT_SEQUENCE)

    unknown = [key for key in requested if key not in NIHDL_TESTS]
    if unknown:
        print(f"Unknown test(s): {', '.join(unknown)}")
        print(f"Valid tests: {', '.join(NIHDL_TESTS)}")
        return 2

    targets = resolve_targets(args)
    if not targets:
        print("No projects with nihdlsettings.py found.")
        return 1

    print(f"Found {len(targets)} projects.")
    print(f"Running tests in order: {' -> '.join(requested)}")

    overall: dict[str, bool] = {}
    for test_key in requested:
        test = NIHDL_TESTS[test_key]
        results = run_test(
            test,
            targets,
            nihdl_cmd=args.nihdl_cmd,
            use_modelsim_env=args.modelsim_from_env,
            use_xilinx_env=args.xilinx_from_env,
        )
        print_test_summary(test, results)
        overall[test_key] = all(result.passed for result in results)

    print("\n" + "#" * 80)
    print("OVERALL SUMMARY")
    print("#" * 80)
    for test_key in requested:
        status = "PASS" if overall[test_key] else "FAIL"
        print(f"  {test_key:16} {status}")
    print("#" * 80)

    return 0 if all(overall.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
