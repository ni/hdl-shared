# hdl-shared Release Process

This document covers the process to test and release the **hdl-shared** GitHub repository.


## Repo Release Versioning

The hdl-shared repo versioning is decoupled from NI product releases and use semantic versioning (e.g. 2.5.0)

## Release HDL Shared GitHub Repo

Before release, we want to run the testbenches on the main branch.

Run ModelSim simulations in both the FIFO and register project folders:
- C:\dev\github\hdl-shared\host_interfaces\fifo
- C:\dev\github\hdl-shared\host_interfaces\register

> nihdl create-modelsim --overwrite

> nihdl sim-modelsim

Create a release branch:
- Name: releases/1.0.0
- Source branch: main

Note: If you are doing a development release, you should skip making the release branch

Make the release:
- Name: 1.0.0
- Tag: 1.0.0
- Target: releases/1.0.0

Note: If you are doing a development release, name it 1.0.0.dev0 and set the "Pre-release" label

