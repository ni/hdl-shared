"""Generate inline XDC constraints for HDL Shared FIFO CDC crossings.

Usage:
    1. Add your NiFifoWriter instance names to WRITER_FIFOS.
    2. Add your NiFifoReader instance names to READER_FIFOS.
    3. Run: python gen_constraints.py
    4. Append the generated hdl_fifo_constraints.xdc to your project constraints.

Instance names need only be the leaf instance name -- all generated XDC
patterns are prefixed with a '*' wildcard so they match at any hierarchy
depth.  Vivado's NAME =~ operator uses Tcl glob matching where '*' matches
zero or more characters (including '/'), so '*WriterFifo_inst/...' matches
both 'WriterFifo_inst/...' at the top level and 'Sub/WriterFifo_inst/...'
inside a submodule.

Examples:
    "WriterFifo_inst"                   -- matches at any hierarchy level
    "SubModule_inst/MyWriterFifo"       -- also works if you want to be specific
"""

import argparse
from pathlib import Path

# =========================================================================
#  USER CONFIGURATION — add FIFO instance names here
# =========================================================================

WRITER_FIFOS = [
    "NiFifoWriterCorex",     # TargetToHost FIFIO
]

READER_FIFOS = [
    "NiFifoReaderCorex",     # HostToTarget FIFO
]

# Clock parameters from MacallanClocks.xml
# Effective CDC period = 1/(freq*(1 + ppm/1e6)) - jitter
# This matches the exact values NI's constraint generator computes.
DMA_FREQ_HZ    = 250e6
BUS_FREQ_HZ    = 80e6
CLOCK_PPM      = 100       # AccuracyInPPM (same for both clocks)
CLOCK_JITTER_PS = 250      # JitterInPicoSeconds (same for both clocks)

def _effective_period_ns(freq_hz, ppm, jitter_ps):
    """Min guaranteed inter-edge time: shortest period minus jitter."""
    return 1e9 / (freq_hz * (1 + ppm / 1e6)) - jitter_ps / 1000

DMA_PERIOD_NS = _effective_period_ns(DMA_FREQ_HZ, CLOCK_PPM, CLOCK_JITTER_PS)
BUS_PERIOD_NS = _effective_period_ns(BUS_FREQ_HZ, CLOCK_PPM, CLOCK_JITTER_PS)

# Tcl variable names (set in the generated XDC/Tcl header)
DMA_T = "hdl_dma_T"   # -> DMA_PERIOD_NS
BUS_T = "hdl_bus_T"   # -> BUS_PERIOD_NS

# Output path — .tcl file (sourced after link_design via STEPS.OPT_DESIGN.TCL.PRE)
OUTPUT_FILE = Path(r"../objects/xdc/hdl_fifo_cdc_constraints.tcl")

# =========================================================================
#  XDC generation helpers
# =========================================================================

lines: list[str] = []


def emit(s=""):
    lines.append(s)


def gc(pattern):
    """get_cells with a glob pattern, matching the proven NI constraint style.

    Uses ``get_cells {pattern} -filter {IS_SEQUENTIAL==true}`` — the pattern
    is passed directly to Vivado's hierarchical name-matching engine, which
    works correctly even in a fully-flattened design.
    """
    return (
        f'[get_cells -quiet {{{pattern}}} '
        f'-filter {{IS_SEQUENTIAL==true}}]'
    )


def smd(delay, src, dst, datapath_only=True):
    """Emit a set_max_delay constraint."""
    dp = " -datapath_only" if datapath_only else ""
    lines.append(f"set_max_delay{dp} {delay} \\")
    lines.append(f"  -from {src} \\")
    lines.append(f"  -to   {dst}")


# =========================================================================
#  CDC primitive emitters — one per synchronizer building block
# =========================================================================

def emit_HB(prefix, label, iT, oT):
    """HandshakeBool — toggle + ready (NO data payload).  3 constraints.

    HandshakeBool is a toggle-only handshake.  It does NOT have
    iLclStoredData / ODataFlop registers — those exist only in the
    full HandshakeBase entity used by HandshakeBaseResetCross.
    """
    p = prefix
    emit(f"# --- HandshakeBool: {label} ({iT} -> {oT}) ---")
    smd(f"${oT}",              gc(f"{p}/*iPushToggle*"),            gc(f"{p}/BlkOut.oPushToggle0_ms*"))
    smd(f"${iT}",              gc(f"{p}/*oPushToggleToReady*"),     gc(f"{p}/*iRdyPushToggle_ms*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/*iRdyPushToggle_ms*"),    gc(f"{p}/*iRdyPushToggle_reg*"))
    emit()


def emit_HBRC(prefix, label, iT, oT):
    """HandshakeBaseResetCross — handshake + SyncIReset + SyncOReset.  14 constraints."""
    p = prefix
    emit(f"# --- HandshakeBaseResetCross: {label} ({iT} -> {oT}) ---")

    emit(f"# Handshake toggle/data/ready")
    smd(f"${oT}",              gc(f"{p}/BlkIn.iPushTogglex*"),       gc(f"{p}/BlkOut.oPushToggle0_msx*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/BlkOut.oPushToggle0_msx*"), gc(f"{p}/*oPushToggle1x*"))
    smd(f"[expr {{2.0*${oT}}}]", gc(f"{p}/BlkIn.iStoredDatax*"),     gc(f"{p}/BlkOut.oDataFlopx*"))
    smd(f"${iT}",              gc(f"{p}/*oPushToggleToReadyx*"),     gc(f"{p}/*iRdyPushToggle_msx*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/*iRdyPushToggle_msx*"),    gc(f"{p}/*iRdyPushTogglex*"))

    # SyncIReset: c1=OClk -> c2=IClk, kSpeedUp=true
    emit(f"# SyncIReset: c1(OClk)->c2(IClk), kSpeedUp=true  fwd=iT ret=oT")
    smd(f"${iT}",              gc(f"{p}/BlkOut.SyncIReset/c1ResetFastLclx*"),
                                gc(f"{p}/BlkOut.SyncIReset/c2ResetFe_msx*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/BlkOut.SyncIReset/c2ResetFe_msx*"),
                                gc(f"{p}/BlkOut.SyncIReset/SpeedUpWithFeFlopGen.SyncToClk2REfromFE*"))
    smd(f"${oT}",              gc(f"{p}/BlkOut.SyncIReset/SpeedUpWithFeFlopGen.SyncToClk2REfromFE*"),
                                gc(f"{p}/BlkOut.SyncIReset/c1ResetFromClk2_ms*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/BlkOut.SyncIReset/c1ResetFromClk2_ms*"),
                                gc(f"{p}/BlkOut.SyncIReset/c1ResetFromClk2_reg*"))
    smd(f"[expr {{2.0*${iT}}}]", gc(f"{p}/BlkOut.SyncIReset/c1ResetFastLclx*"),
                                gc(f"{p}/BlkIn.iPushTogglex*"), datapath_only=False)

    # SyncOReset: c1=IClk -> c2=OClk, kSpeedUp=false
    emit(f"# SyncOReset: c1(IClk)->c2(OClk), kSpeedUp=false  fwd=oT ret=iT")
    smd(f"${oT}",              gc(f"{p}/BlkOut.SyncOReset/c1ResetFastLclx*"),
                                gc(f"{p}/BlkOut.SyncOReset/c2ResetRe_msx*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/BlkOut.SyncOReset/c2ResetRe_msx*"),
                                gc(f"{p}/BlkOut.SyncOReset/DontSpeedUpWithFeFlopGen.SyncToClk2REfromRE*"))
    smd(f"${iT}",              gc(f"{p}/BlkOut.SyncOReset/DontSpeedUpWithFeFlopGen.SyncToClk2REfromRE*"),
                                gc(f"{p}/BlkOut.SyncOReset/c1ResetFromClk2_ms*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/BlkOut.SyncOReset/c1ResetFromClk2_ms*"),
                                gc(f"{p}/BlkOut.SyncOReset/c1ResetFromClk2_reg*"))
    emit()


def emit_DSB(prefix, label, iT, oT):
    """DoubleSyncBool — async input double-synchronizer.  2 constraints."""
    p = prefix
    emit(f"# --- DoubleSyncBool: {label} ({iT} -> {oT}) ---")
    smd(f"${oT}",              gc(f"{p}*iDlySigx*"),
                                gc(f"{p}*DoubleSyncAsyncInBasex/oSig_msx*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}*DoubleSyncAsyncInBasex/oSig_msx*"),
                                gc(f"{p}*DoubleSyncAsyncInBasex/oSigx*"))
    emit()


def emit_PS(prefix, label, iT, oT):
    """PulseSyncBase — pulse handshake with ack.  4 constraints."""
    p = prefix
    emit(f"# --- PulseSyncBase: {label} ({iT} -> {oT}) ---")
    smd(f"${oT}",              gc(f"{p}/iHoldSigInx*"),     gc(f"{p}/oHoldSigIn_msx*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/oHoldSigIn_msx*"), gc(f"{p}/oLocalSigOutCEx*"))
    smd(f"${iT}",              gc(f"{p}/oLocalSigOutCEx*"),  gc(f"{p}/iSigOut_msx*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/iSigOut_msx*"),    gc(f"{p}/iSigOutx*"))
    emit()


def emit_PCC(prefix, label, iT, oT):
    """DmaPortFifoPtrClockCrossing — push/data/ack handshake.  5 constraints."""
    p = prefix
    emit(f"# --- DmaPortFifoPtrClockCrossing: {label} ({iT} -> {oT}) ---")
    smd(f"${oT}",              gc(f"{p}/iTogglePush*"),  gc(f"{p}/oPushRcvd_ms*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/oPushRcvd_ms*"), gc(f"{p}/oPushRcvd_reg*"))
    smd(f"[expr {{2.0*${oT}}}]", gc(f"{p}/iDataToPush*"),  gc(f"{p}/DataReg*"))
    smd(f"${iT}",              gc(f"{p}/oAck*"),         gc(f"{p}/iAckRcvd_ms*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/iAckRcvd_ms*"), gc(f"{p}/iAckRcvd_reg*"))
    emit()


def emit_pulse_sync_with_ack(inst, crossing_path, label, iT, oT):
    """PulseSyncBase + the oRegisteredSigAck -> iSigOut_msx intermediate path.

    The NiFpgaFifoPortReset Crossing.ClearTo{Push,Pop} has an oRegisteredSigAck
    register in the source clock domain that feeds into PulseSyncBase/iSigOut_msx
    in the destination domain.  This path lives OUTSIDE the PulseSyncBase prefix
    so emit_PS alone doesn't cover it.
    """
    ps_prefix = f"{inst}/{crossing_path}/PulseSyncBasex"
    emit_PS(ps_prefix, label, iT, oT)

    emit(f"# --- {label}: oRegisteredSigAck -> PulseSync iSigOut_ms ---")
    smd(f"${oT}",
        gc(f"{inst}/{crossing_path}/oRegisteredSigAck*"),
        gc(f"{inst}/{crossing_path}/PulseSyncBasex/iSigOut_msx*"))
    emit()


# =========================================================================
#  Top-level FIFO emitters
# =========================================================================

def emit_writer_fifo(inst):
    """Emit all CDC constraints for one NiFifoWriter instance (TargetToHost).

    Internal structure (TargetToHost / Writer):
      Push = DmaClk (250 MHz)   Pop = BusClk/PllClk80 (80 MHz)
    """
    w = f"*{inst}"  # wildcard prefix for hierarchy-independent matching

    emit("# =================================================================================")
    emit(f"#  {inst}  (NiFifoWriter / TargetToHost)")
    emit("#    Push = DmaClk (250 MHz), Pop = PllClk80 (80 MHz)")
    emit("# =================================================================================")
    emit()

    # StreamStateBlock HandshakeBool instances (DmaClk -> BusClk)
    for name in ["HandshakeStopStreamRequest",
                 "HandshakeStopWithFlushRequest",
                 "HandshakeStartStreamRequest",
                 "HandshakeFlushTimeoutRequest"]:
        emit_HB(f"{w}/StreamStateBlock.{name}/HandshakeBasex",
                f"StreamStateBlock {name}", DMA_T, BUS_T)

    # StreamStateBlock HandshakeBaseResetCross (DmaClk -> BusClk)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeStateToBusClkDomain",
              "StreamStateBlock StateToBusClk", DMA_T, BUS_T)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeOverflowStopRequest",
              "StreamStateBlock OverflowStop", DMA_T, BUS_T)

    # Overflow handshake (DmaClk -> BusClk)
    emit_HBRC(f"{w}/BlkOverflow.HandshakeOverflow",
              "BlkOverflow Overflow", DMA_T, BUS_T)

    # DmaPortInStrmFifo gray counter (DmaClk -> BusClk, entity-based wrapper)
    flags = f"{w}/DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx"
    emit("# --- DmaPortInStrmFifo: gray counter DmaClk -> BusClk ---")
    smd(f"${BUS_T}",
        gc(f"{flags}/iWriteSamplePtrUnsGray*"),
        gc(f"{flags}/SyncToOClk/GrayPtrClockCrossing.OutputGrayReg_ms*"))
    smd(f"[expr {{0.5*${BUS_T}}}]",
        gc(f"{flags}/SyncToOClk/GrayPtrClockCrossing.OutputGrayReg_ms*"),
        gc(f"{flags}/SyncToOClk/GrayPtrClockCrossing.OutputGrayReg/*"))
    emit()

    # DmaPortInStrmFifo disable signal (BusClk -> DmaClk)
    emit("# --- DmaPortInStrmFifo: disable signal BusClk -> DmaClk ---")
    smd(f"${DMA_T}",
        gc(f"{flags}/iWritesDisabledSampPtrUnsGray*"),
        gc(f"{flags}/SyncToOClk/DisableSignalClockCrossing.SyncToOClk_ms*"))
    smd(f"[expr {{0.5*${DMA_T}}}]",
        gc(f"{flags}/SyncToOClk/DisableSignalClockCrossing.SyncToOClk_ms*"),
        gc(f"{flags}/SyncToOClk/DisableSignalClockCrossing.SyncToOClk*"))
    emit()

    # DmaPortInStrmFifo PCC read pointer (BusClk -> DmaClk)
    emit_PCC(f"{flags}/OClkToIClkCrossing.SyncToIClk",
             "read ptr BusClk -> DmaClk", BUS_T, DMA_T)

    # DmaPortInStrmFifo WritePointerHandshake (DmaClk -> BusClk)
    emit_HBRC(f"{flags}/WritePointerHandshake",
              "WritePointerHandshake", DMA_T, BUS_T)

    # EnableChain DoubleSyncBool (FifoClearController)
    ec = f"{w}/DmaPortCommIfcComponentEnableChainx/Input.FifoClearController"
    emit_DSB(f"{ec}/PushSynchNeeded.ToPushDblSync",
             "FifoClear ToPush", BUS_T, DMA_T)
    emit_DSB(f"{ec}/PushSynchNeeded.FromPushDblSync",
             "FifoClear FromPush", DMA_T, BUS_T)

    # EnableChain PulseSync (NiFpgaFifoPortReset crossings)
    rst = f"{ec}/NiFpgaFifoPortResetx"
    emit_pulse_sync_with_ack(w,
        f"DmaPortCommIfcComponentEnableChainx/Input.FifoClearController"
        f"/NiFpgaFifoPortResetx/Crossing.ClearToPush",
        "ClearToPush", BUS_T, DMA_T)
    emit_PS(f"{rst}/Crossing.PopToPush/PulseSyncBasex",
            "PopToPush", BUS_T, DMA_T)
    emit_PS(f"{rst}/Crossing.PushToPop/PulseSyncBasex",
            "PushToPop", DMA_T, BUS_T)

    # Async reset false paths
    emit(f"# --- Async reset paths: {inst} CLR/PRE ---")
    emit(f"set_false_path -to [get_pins -quiet -hier -filter {{NAME =~ {w}/*/CLR && IS_LEAF}}]")
    emit(f"set_false_path -to [get_pins -quiet -hier -filter {{NAME =~ {w}/*/PRE && IS_LEAF}}]")
    emit()


def emit_reader_fifo(inst):
    """Emit all CDC constraints for one NiFifoReader instance (HostToTarget).

    Internal structure (HostToTarget / Reader):
      Push = BusClk/PllClk80 (80 MHz)   Pop = DmaClk (250 MHz)
    """
    w = f"*{inst}"  # wildcard prefix for hierarchy-independent matching

    emit("# =================================================================================")
    emit(f"#  {inst}  (NiFifoReader / HostToTarget)")
    emit("#    Push = PllClk80 (80 MHz), Pop = DmaClk (250 MHz)")
    emit("# =================================================================================")
    emit()

    # StreamStateBlock HandshakeBool instances (DmaClk -> BusClk)
    for name in ["HandshakeStopStreamRequest",
                 "HandshakeStartStreamRequest"]:
        emit_HB(f"{w}/StreamStateBlock.{name}/HandshakeBasex",
                f"StreamStateBlock {name}", DMA_T, BUS_T)

    # StreamStateBlock HandshakeBaseResetCross (DmaClk -> BusClk)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeUnderflowStopRequest",
              "StreamStateBlock UnderflowStop", DMA_T, BUS_T)

    # Underflow handshake (DmaClk -> BusClk)
    emit_HBRC(f"{w}/BlkUnderflow.HandshakeUnderflow",
              "BlkUnderflow Underflow", DMA_T, BUS_T)

    # HandshakeFullCount (DmaClk -> BusClk)
    emit_HBRC(f"{w}/HandshakeFullCount",
              "HandshakeFullCount", DMA_T, BUS_T)

    # DmaPortOutStrmFifo gray counter (DmaClk -> BusClk, process-based)
    flags = f"{w}/DmaPortOutStrmFifox/DmaPortOutStrmFifoFlagsx"
    emit("# --- DmaPortOutStrmFifo: gray counter DmaClk -> BusClk ---")
    smd(f"${BUS_T}",
        gc(f"{flags}/oReadSamplePtrUnsGray*"),
        gc(f"{flags}/iReadSamplePtrUnsGray_ms*"))
    smd(f"[expr {{0.5*${BUS_T}}}]",
        gc(f"{flags}/iReadSamplePtrUnsGray_ms*"),
        gc(f"{flags}/iReadSamplePtrUnsGray_reg*"))
    emit()

    # DmaPortOutStrmFifo PCC write pointer (BusClk -> DmaClk)
    emit_PCC(f"{flags}/IClkToOClkCrossing.SyncToOClk",
             "write ptr BusClk -> DmaClk", BUS_T, DMA_T)

    # PCC DataReg -> bStateInDefaultClkDomainClean (PllClk80 -> DmaClk)
    emit("# --- PCC DataReg -> bStateInDefaultClkDomainClean: PllClk80 -> DmaClk ---")
    smd(f"${DMA_T}",
        gc(f"{flags}/IClkToOClkCrossing.SyncToOClk/DataReg*"),
        gc(f"{w}/bStateInDefaultClkDomainClean_reg*"))
    emit()

    # EnableChain DoubleSyncBool (FifoClearController)
    ec = f"{w}/DmaPortCommIfcComponentEnableChainx/Output.FifoClearController"
    emit_DSB(f"{ec}/PopSynchNeeded.ToPopDblSync",
             "FifoClear ToPop", BUS_T, DMA_T)
    emit_DSB(f"{ec}/PopSynchNeeded.FromPopDblSync",
             "FifoClear FromPop", DMA_T, BUS_T)

    # EnableChain PulseSync (NiFpgaFifoPortReset crossings)
    rst = f"{ec}/NiFpgaFifoPortResetx"
    emit_pulse_sync_with_ack(w,
        f"DmaPortCommIfcComponentEnableChainx/Output.FifoClearController"
        f"/NiFpgaFifoPortResetx/Crossing.ClearToPop",
        "ClearToPop", BUS_T, DMA_T)
    # Note: PopToPush/PushToPop directions are SWAPPED vs WriterFifo because
    # ReaderFifo has Push=BusClk, Pop=DmaClk (opposite of WriterFifo).
    emit_PS(f"{rst}/Crossing.PopToPush/PulseSyncBasex",
            "PopToPush", DMA_T, BUS_T)
    emit_PS(f"{rst}/Crossing.PushToPop/PulseSyncBasex",
            "PushToPop", BUS_T, DMA_T)

    # Async reset false paths
    emit(f"# --- Async reset paths: {inst} CLR/PRE ---")
    emit(f"set_false_path -to [get_pins -quiet -hier -filter {{NAME =~ {w}/*/CLR && IS_LEAF}}]")
    emit(f"set_false_path -to [get_pins -quiet -hier -filter {{NAME =~ {w}/*/PRE && IS_LEAF}}]")
    emit()


# =========================================================================
#  Main
# =========================================================================

def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--output", type=Path, default=OUTPUT_FILE,
                        help="Output XDC file path")
    args = parser.parse_args()

    # Header
    emit("###################################################################################")
    emit("## HDL Shared FIFO CDC Constraints")
    emit("##")
    emit("## Auto-generated by gen_constraints.py")
    emit("##")
    emit("## Each constraint explicitly targets specific synchronizer flip-flops inside")
    emit("## each CDC component instance.  If the design changes, only the known safe")
    emit("## flip-flops are relaxed -- new logic will NOT be silently caught.")
    emit("##")
    emit("## Clock domains (effective periods from MacallanClocks.xml):")
    emit(f"##   DmaClk  = 250 MHz  ({DMA_PERIOD_NS:.10f} ns) -- ViClk / PCIe side")
    emit(f"##   BusClk  =  80 MHz  ({BUS_PERIOD_NS:.10f} ns) -- PllClk80 / comm side")
    emit(f"##   Formula: 1/(freq*(1+PPM/1e6)) - jitter  [PPM={CLOCK_PPM}, jitter={CLOCK_JITTER_PS}ps]")
    emit("##")
    emit(f"## Writer FIFOs (TargetToHost): {', '.join(WRITER_FIFOS) or '(none)'}")
    emit(f"## Reader FIFOs (HostToTarget): {', '.join(READER_FIFOS) or '(none)'}")
    emit("##")
    emit("###################################################################################")
    emit()
    emit(f"set {DMA_T} {DMA_PERIOD_NS:.10f}")
    emit(f"set {BUS_T} {BUS_PERIOD_NS:.10f}")
    emit()

    for inst in WRITER_FIFOS:
        emit_writer_fifo(inst)

    for inst in READER_FIFOS:
        emit_reader_fifo(inst)

    output_path = args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Generated {len(lines)} lines to {output_path}")


if __name__ == "__main__":
    main()
