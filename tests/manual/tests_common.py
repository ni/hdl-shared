#!/usr/bin/env python3
"""Shared helpers for running nihdl simulation tests across all hdl-shared projects.

This module is imported by the test shell ``run_tests.py``, which runs one or
more nihdl-command tests in every host-interface project (the directories under
``host_interfaces`` that contain a ``nihdlsettings.py``, e.g. ``register`` and
``fifo``).

hdl-shared only ships ModelSim simulation tests -- there are no LabVIEW target
plugins to generate and no Vivado projects to build -- so the only registered
tests are ``gen-modelsim`` and ``sim-modelsim``. Each test runs the nihdl
subcommand in a project directory through a shared wrapper nihdlsettings.py
(``tests/manual/nihdlsettings.py``), passed via ``--config``, which loads that
project's own ``nihdlsettings.py`` and then applies CI tool-folder overrides
(MODELSIM / XILINX from the environment) when requested. The run keeps going on
failures and reports a pass/fail summary.

The simulation verdict comes from the nihdl exit code: ``nihdl sim-modelsim``
parses the ModelSim transcript and returns a nonzero exit code on any testbench
fatal/error (it does not trust vsim's own exit code), so a return code of 0 is a
reliable PASS.
"""

from __future__ import annotations

import argparse
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


# ---------------------------------------------------------------------------
# Result data classes
# ---------------------------------------------------------------------------


@dataclass
class CommandResult:
    """Result for one nihdl command execution."""

    command: str
    return_code: int | None
    duration_seconds: float
    error_text: str = ""

    @property
    def status(self) -> str:
        """Return a human-readable status for reporting."""
        return "PASS" if self.return_code == 0 else "FAIL"

    @property
    def failed(self) -> bool:
        return self.return_code != 0


@dataclass
class DiscoveredTarget:
    """A project directory discovered under host_interfaces."""

    path: Path
    display_name: str


@dataclass
class TargetResult:
    """Aggregated result of running one command in one project."""

    target_name: str
    command_result: CommandResult

    @property
    def passed(self) -> bool:
        return not self.command_result.failed


# ---------------------------------------------------------------------------
# nihdl command/test definitions
# ---------------------------------------------------------------------------


@dataclass
class NihdlTest:
    """Definition of a single nihdl-command test run across all projects."""

    key: str  # CLI-friendly identifier, e.g. "sim-modelsim"
    label: str  # short column label for the summary, e.g. "sim"
    subcommand: list[str]  # nihdl args, e.g. ["gen-modelsim", "--overwrite"]
    description: str = ""


# Registry of all available nihdl-command tests. hdl-shared is simulation only.
NIHDL_TESTS: dict[str, NihdlTest] = {
    "gen-modelsim": NihdlTest(
        key="gen-modelsim",
        label="gen-sim",
        subcommand=["gen-modelsim", "--overwrite"],
        description="Generate (overwrite) the ModelSim simulation project",
    ),
    "sim-modelsim": NihdlTest(
        key="sim-modelsim",
        label="sim",
        subcommand=["sim-modelsim"],
        description="Run the ModelSim testbench simulation",
    ),
}


# ---------------------------------------------------------------------------
# Project discovery and command execution
# ---------------------------------------------------------------------------


# Repository root, relative to this file (tests/manual/tests_common.py).
# parents[0] = tests/manual, parents[1] = tests, parents[2] = repo root.
REPO_ROOT = Path(__file__).resolve().parents[2]


# Shared wrapper nihdlsettings.py passed to every nihdl command via --config.
# It loads each project's own settings and applies CI tool-folder overrides
# (MODELSIM / XILINX from the environment) driven by generic ``--set KEY=VALUE``
# overrides that nihdl forwards to the wrapper as ``context.settings``.
WRAPPER_SETTINGS = Path(__file__).resolve().parent / "nihdlsettings.py"


def default_host_interfaces_dir() -> Path:
    """Return the default <repo>/host_interfaces folder."""
    return REPO_ROOT / "host_interfaces"


def discover_targets(host_interfaces_dir: Path) -> list[DiscoveredTarget]:
    """Return project directories (containing nihdlsettings.py) under a folder.

    Projects are returned sorted by name. Directories without a
    ``nihdlsettings.py`` (such as ``common``) are skipped.
    """
    if not host_interfaces_dir.exists() or not host_interfaces_dir.is_dir():
        print(f"Warning: host_interfaces folder not found: {host_interfaces_dir}")
        return []

    found: list[DiscoveredTarget] = []
    for child in sorted(host_interfaces_dir.iterdir(), key=lambda p: p.name.lower()):
        if child.is_dir() and (child / "nihdlsettings.py").is_file():
            found.append(
                DiscoveredTarget(
                    path=child,
                    display_name=f"{host_interfaces_dir.name}/{child.name}",
                )
            )
    return found


def run_command(command: list[str], cwd: Path) -> CommandResult:
    """Run a command in cwd and return status without raising."""
    command_text = " ".join(command)
    print(f"    Running: {command_text}")

    start = time.perf_counter()
    error_text = ""
    try:
        completed = subprocess.run(command, cwd=str(cwd), check=False)
        return_code = completed.returncode
    except FileNotFoundError as exc:
        return_code = 127
        error_text = str(exc)
        print(f"    ERROR: {error_text}")

    duration_seconds = time.perf_counter() - start
    print(f"    Exit code: {return_code} ({duration_seconds:.1f}s)")

    return CommandResult(
        command=command_text,
        return_code=return_code,
        duration_seconds=duration_seconds,
        error_text=error_text,
    )


# ---------------------------------------------------------------------------
# Running a single nihdl-command test across all projects
# ---------------------------------------------------------------------------


def run_test(
    test: NihdlTest,
    targets: list[DiscoveredTarget],
    nihdl_cmd: str = "nihdl",
    use_modelsim_env: bool = False,
    use_xilinx_env: bool = False,
) -> list[TargetResult]:
    """Run one nihdl-command test in every project directory.

    Keeps going on failures and returns a list of per-project results. Each
    nihdl command runs in the project directory through the shared wrapper
    nihdlsettings.py (via --config), which loads that project's own settings and
    applies the requested CI tool-folder overrides.
    """
    print("\n" + "=" * 80)
    print(f"TEST: {test.key} \u2014 {test.description}")
    print("=" * 80)

    # Tune the shared wrapper's behavior via generic --set overrides that nihdl
    # forwards to the wrapper's hooks as context.settings.
    set_overrides: list[str] = []
    if use_modelsim_env:
        set_overrides += ["--set", "use_modelsim_env=1"]
    if use_xilinx_env:
        set_overrides += ["--set", "use_xilinx_env=1"]

    results: list[TargetResult] = []
    for target in targets:
        print("\n" + "-" * 80)
        print(f"Project: {target.display_name}")
        print(f"Directory: {target.path}")

        command = [
            nihdl_cmd,
            "--verbose",
            *test.subcommand,
            f"--config={WRAPPER_SETTINGS}",
            *set_overrides,
        ]
        command_result = run_command(command, target.path)

        results.append(
            TargetResult(
                target_name=target.display_name,
                command_result=command_result,
            )
        )

    return results


def print_test_summary(test: NihdlTest, results: list[TargetResult]) -> None:
    """Print a pass/fail summary for a single test."""
    print("\n" + "=" * 80)
    print(f"SUMMARY: {test.key}")
    print("=" * 80)

    passed_count = 0
    failed_count = 0

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        if result.passed:
            passed_count += 1
        else:
            failed_count += 1

        print(
            f"{result.target_name:34} {status:4} "
            f"{test.label}= {result.command_result.status:4}"
        )
        if result.command_result.error_text:
            print(f"  error: {result.command_result.error_text}")

    print("-" * 80)
    print(f"Total projects: {len(results)}")
    print(f"Passed: {passed_count}")
    print(f"Failed: {failed_count}")
    print("=" * 80)


# ---------------------------------------------------------------------------
# Shared CLI plumbing
# ---------------------------------------------------------------------------


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    """Add the project-selection and nihdl options common to every test."""
    parser.add_argument(
        "--host-interfaces-dir",
        type=Path,
        default=default_host_interfaces_dir(),
        help=(
            "Path to the host_interfaces folder containing the projects "
            f"(default: {default_host_interfaces_dir()})"
        ),
    )
    parser.add_argument(
        "--nihdl-cmd",
        default="nihdl",
        help="Command name or full path for nihdl executable (default: nihdl)",
    )
    parser.add_argument(
        "--modelsim-from-env",
        action="store_true",
        help=(
            "Override the ModelSim tools folder from the MODELSIM environment "
            "variable (set_modelsim_tools_folder). MODELSIM points at the "
            "modelsim.ini file, so its parent directory is used as the tools "
            "folder. Intended for CI/pipeline runs. No-op if MODELSIM is unset."
        ),
    )
    parser.add_argument(
        "--xilinx-from-env",
        action="store_true",
        help=(
            "Override the Vivado tools folder from the XILINX environment "
            "variable (set_vivado_tools_folder). Intended for CI/pipeline runs "
            "where XILINX selects the Vivado install. No-op if XILINX is unset."
        ),
    )
    parser.add_argument(
        "--target",
        action="append",
        metavar="NAME",
        help=(
            "Only run on the named project folder, e.g. --target fifo. "
            "Repeatable to select several. Matched case-insensitively against "
            "the project directory name. Defaults to every discovered project."
        ),
    )


def resolve_targets(args: argparse.Namespace) -> list[DiscoveredTarget]:
    """Discover projects based on the common CLI arguments.

    When --target is supplied, the discovered list is filtered down to the
    requested project folder name(s). Any name that matches nothing produces a
    warning listing the projects that are actually available.
    """
    discovered = discover_targets(args.host_interfaces_dir)

    requested = getattr(args, "target", None)
    if not requested:
        return discovered

    wanted = [name.strip().lower() for name in requested]
    selected: list[DiscoveredTarget] = []
    matched: set[str] = set()
    for target in discovered:
        folder = target.path.name.lower()
        display = target.display_name.lower()
        for name in wanted:
            if name == folder or name == display or display.endswith("/" + name):
                selected.append(target)
                matched.add(name)
                break

    unmatched = [orig for orig, low in zip(requested, wanted) if low not in matched]
    if unmatched:
        available = ", ".join(t.path.name for t in discovered) or "(none)"
        print(f"Warning: --target not found: {', '.join(unmatched)}")
        print(f"Available projects: {available}")
    return selected
