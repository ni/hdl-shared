"""Generate inline XDC constraints for HDL Shared FIFO CDC crossings.

REQUIREMENT: the generated constraints are only valid when every FIFO's
ViClk port is driven by a USER_FREQ_HZ clock (80 MHz -- the target's BusClk /
PllClk80) and its BusClk port by a DMA_FREQ_HZ clock (250 MHz DmaClk).  The
periods are hard-coded; nothing checks them against the design.  If a FIFO's
ViClk runs at any other frequency the constraints are silently wrong (a faster
ViClk leaves the crossings under-constrained), so that target must not use the
shared hdl_fifo_cdc_constraints.xdc.

Usage:
    1. Add your NiSharedFifoWriter instance names to WRITER_FIFOS.
    2. Add your NiSharedFifoReader instance names to READER_FIFOS.
    3. Set DMA_FREQ_HZ / USER_FREQ_HZ to the clocks driving the FIFO ports.
    4. Run: python gen_constraints.py -o hdl_fifo_cdc_constraints.xdc

Clock naming:
    The FIFO port names do not match the FlexRIO target clock names.  This
    script never uses the bare names "BusClk"/"ViClk" for a clock; it uses
    the clock that actually drives each FIFO port:

      FIFO port   Driven by (UserHdl)               Here
      ---------   -------------------------------   ---------------------------
      BusClk      DmaClk (250 MHz)                  "DMA"  / $hdl_dmaclk_T
      ViClk       target BusClk = PllClk80 (80 MHz) "user" / $hdl_userclk_T

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
    "NiSharedFifoWriterCorex",   # TargetToHost FIFO
]

READER_FIFOS = [
    "NiSharedFifoReaderCorex",   # HostToTarget FIFO
]

# Clock parameters from the target clock definitions
# Effective CDC period = 1/(freq*(1 + ppm/1e6)) - jitter
# This matches the exact values NI's constraint generator computes.
DMA_FREQ_HZ    = 250e6     # clock on the FIFO BusClk port (DmaClk)
USER_FREQ_HZ   = 80e6      # clock on the FIFO ViClk port -- MUST match the real ViClk
CLOCK_PPM      = 100       # AccuracyInPPM (same for both clocks)
CLOCK_JITTER_PS = 250      # JitterInPicoSeconds (same for both clocks)

def _effective_period_ns(freq_hz, ppm, jitter_ps):
    """Min guaranteed inter-edge time: shortest period minus jitter."""
    return 1e9 / (freq_hz * (1 + ppm / 1e6)) - jitter_ps / 1000

DMA_PERIOD_NS = _effective_period_ns(DMA_FREQ_HZ, CLOCK_PPM, CLOCK_JITTER_PS)
USER_PERIOD_NS = _effective_period_ns(USER_FREQ_HZ, CLOCK_PPM, CLOCK_JITTER_PS)

# Tcl variable names (set in the generated XDC header)
DMA_T = "hdl_dmaclk_T"    # FIFO BusClk port domain -> DMA_PERIOD_NS
USER_T = "hdl_userclk_T"  # FIFO ViClk port domain  -> USER_PERIOD_NS

# Output path — .xdc file (sourced after link_design via STEPS.OPT_DESIGN.TCL.PRE)
OUTPUT_FILE = Path(r"../objects/xdc/hdl_fifo_cdc_constraints.xdc")

# =========================================================================
#  XDC generation helpers
# =========================================================================

lines: list[str] = []


def emit(s=""):
    lines.append(s)


def gc(pattern):
    """Sequential cells whose full hierarchical name glob-matches ``pattern``.

    Uses ``get_cells -hierarchical -filter {NAME =~ pattern}``, which matches
    whether or not synthesis flattens the hierarchy.  The plain
    ``get_cells {pattern}`` form only works on a netlist synthesized with
    ``-flatten_hierarchy full``: with hierarchy preserved its '*' does not
    cross hierarchy separators, so a leading '*' cannot absorb the parent
    hierarchy (e.g. UserHdl_inst/ReaderFifo_inst/) and synchronizer flops
    nested inside DFlop wrappers are never reached.
    """
    return (
        f'[get_cells -quiet -hierarchical '
        f'-filter {{NAME =~ {pattern} && IS_SEQUENTIAL}}]'
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


def emit_HBRC(prefix, label, iT, oT, has_data=True):
    """HandshakeBaseResetCross — handshake + SyncIReset + SyncOReset.  14 constraints.

    Pass has_data=False for instances whose iData is left open; they have no
    iStoredData/oDataFlop registers, so a data constraint would match nothing.
    """
    p = prefix
    emit(f"# --- HandshakeBaseResetCross: {label} ({iT} -> {oT}) ---")

    emit(f"# Handshake toggle/data/ready")
    smd(f"${oT}",              gc(f"{p}/BlkIn.iPushTogglex*"),       gc(f"{p}/BlkOut.oPushToggle0_msx*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/BlkOut.oPushToggle0_msx*"), gc(f"{p}/*oPushToggle1x*"))
    if has_data:
        smd(f"[expr {{2.0*${oT}}}]", gc(f"{p}/BlkIn.iStoredDatax*"), gc(f"{p}/BlkOut.oDataFlopx*"))
    smd(f"${iT}",              gc(f"{p}/*oPushToggleToReadyx*"),     gc(f"{p}/*iRdyPushToggle_msx*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/*iRdyPushToggle_msx*"),    gc(f"{p}/*iRdyPushTogglex*"))

    # SyncIReset: c1=IClk -> c2=OClk, kSpeedUp=true (verified against netlist clocks)
    emit(f"# SyncIReset: c1(IClk)->c2(OClk), kSpeedUp=true  fwd=oT ret=iT")
    smd(f"${oT}",              gc(f"{p}/BlkOut.SyncIReset/c1ResetFastLclx*"),
                                gc(f"{p}/BlkOut.SyncIReset/c2ResetFe_msx*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/BlkOut.SyncIReset/c2ResetFe_msx*"),
                                gc(f"{p}/BlkOut.SyncIReset/SpeedUpWithFeFlopGen.SyncToClk2REfromFE*"))
    smd(f"${iT}",              gc(f"{p}/BlkOut.SyncIReset/SpeedUpWithFeFlopGen.SyncToClk2REfromFE*"),
                                gc(f"{p}/BlkOut.SyncIReset/c1ResetFromClk2_ms*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/BlkOut.SyncIReset/c1ResetFromClk2_ms*"),
                                gc(f"{p}/BlkOut.SyncIReset/c1ResetFromClk2_reg*"))
    smd(f"[expr {{2.0*${iT}}}]", gc(f"{p}/BlkOut.SyncIReset/c1ResetFastLclx*"),
                                gc(f"{p}/BlkIn.iPushTogglex*"), datapath_only=False)

    # SyncOReset: c1=OClk -> c2=IClk, kSpeedUp=false (verified against netlist clocks)
    emit(f"# SyncOReset: c1(OClk)->c2(IClk), kSpeedUp=false  fwd=iT ret=oT")
    smd(f"${iT}",              gc(f"{p}/BlkOut.SyncOReset/c1ResetFastLclx*"),
                                gc(f"{p}/BlkOut.SyncOReset/c2ResetRe_msx*"))
    smd(f"[expr {{0.5*${iT}}}]", gc(f"{p}/BlkOut.SyncOReset/c2ResetRe_msx*"),
                                gc(f"{p}/BlkOut.SyncOReset/DontSpeedUpWithFeFlopGen.SyncToClk2REfromRE*"))
    smd(f"${oT}",              gc(f"{p}/BlkOut.SyncOReset/DontSpeedUpWithFeFlopGen.SyncToClk2REfromRE*"),
                                gc(f"{p}/BlkOut.SyncOReset/c1ResetFromClk2_ms*"))
    smd(f"[expr {{0.5*${oT}}}]", gc(f"{p}/BlkOut.SyncOReset/c1ResetFromClk2_ms*"),
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
    register in the destination (OClk) domain that feeds back into
    PulseSyncBase/iSigOut_msx in the source (IClk) domain.  This path lives
    OUTSIDE the PulseSyncBase prefix so emit_PS alone doesn't cover it.
    """
    ps_prefix = f"{inst}/{crossing_path}/PulseSyncBasex"
    emit_PS(ps_prefix, label, iT, oT)

    emit(f"# --- {label}: oRegisteredSigAck -> PulseSync iSigOut_ms ---")
    smd(f"${iT}",
        gc(f"{inst}/{crossing_path}/oRegisteredSigAck*"),
        gc(f"{inst}/{crossing_path}/PulseSyncBasex/iSigOut_msx*"))
    emit()


# =========================================================================
#  Top-level FIFO emitters
# =========================================================================

def emit_writer_fifo(inst):
    """Emit all CDC constraints for one NiSharedFifoWriter instance (TargetToHost).

    Internal structure (TargetToHost / Writer):
      Push = FIFO ViClk port  -> user clock (PllClk80, 80 MHz)
      Pop  = FIFO BusClk port -> DmaClk (250 MHz)
    """
    w = f"*{inst}"  # wildcard prefix for hierarchy-independent matching
    user, dma = USER_T, DMA_T

    emit("# =================================================================================")
    emit(f"#  {inst}  (NiSharedFifoWriter / TargetToHost)")
    emit("#    Push = user side (FIFO ViClk port), Pop = DMA side (FIFO BusClk port)")
    emit("# =================================================================================")
    emit()

    # StreamStateBlock HandshakeBool instances (user -> DMA)
    for name in ["HandshakeStopStreamRequest",
                 "HandshakeStopWithFlushRequest",
                 "HandshakeStartStreamRequest",
                 "HandshakeFlushTimeoutRequest"]:
        emit_HB(f"{w}/StreamStateBlock.{name}/HandshakeBasex",
                f"StreamStateBlock {name}", user, dma)

    # StreamStateBlock HandshakeBaseResetCross (user -> DMA)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeStateToBusClkDomain",
              "StreamStateBlock StateToBusClk", user, dma)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeOverflowStopRequest",
              "StreamStateBlock OverflowStop", user, dma, has_data=False)

    # Overflow handshake (user -> DMA)
    emit_HBRC(f"{w}/BlkOverflow.HandshakeOverflow",
              "BlkOverflow Overflow", user, dma, has_data=False)

    # DmaPortInStrmFifo gray counter (IClk=user -> OClk=DMA, entity-based wrapper)
    flags = f"{w}/DmaPortInStrmFifox/DmaPortInStrmFifoFlagsx"
    emit("# --- DmaPortInStrmFifo: gray counter user -> DMA ---")
    smd(f"${dma}",
        gc(f"{flags}/iWriteSamplePtrUnsGray*"),
        gc(f"{flags}/SyncToOClk/GrayPtrClockCrossing.OutputGrayReg_ms*"))
    smd(f"[expr {{0.5*${dma}}}]",
        gc(f"{flags}/SyncToOClk/GrayPtrClockCrossing.OutputGrayReg_ms*"),
        gc(f"{flags}/SyncToOClk/GrayPtrClockCrossing.OutputGrayReg/*"))
    emit()

    # DmaPortInStrmFifo disable signal (IClk=user -> OClk=DMA)
    emit("# --- DmaPortInStrmFifo: disable signal user -> DMA ---")
    smd(f"${dma}",
        gc(f"{flags}/iWritesDisabledSampPtrUnsGray*"),
        gc(f"{flags}/SyncToOClk/DisableSignalClockCrossing.SyncToOClk_ms*"))
    smd(f"[expr {{0.5*${dma}}}]",
        gc(f"{flags}/SyncToOClk/DisableSignalClockCrossing.SyncToOClk_ms*"),
        gc(f"{flags}/SyncToOClk/DisableSignalClockCrossing.SyncToOClk*"))
    emit()

    # DmaPortInStrmFifo PCC read pointer (OClk=DMA -> IClk=user)
    emit_PCC(f"{flags}/OClkToIClkCrossing.SyncToIClk",
             "read ptr DMA -> user", dma, user)

    # DmaPortInStrmFifo WritePointerHandshake (user -> DMA)
    emit_HBRC(f"{flags}/WritePointerHandshake",
              "WritePointerHandshake", user, dma)

    # EnableChain DoubleSyncBool (FifoClearController; the clear runs on the
    # DMA side, the push port is the user side)
    ec = f"{w}/DmaPortCommIfcComponentEnableChainx/Input.FifoClearController"
    emit_DSB(f"{ec}/PushSynchNeeded.ToPushDblSync",
             "FifoClear ToPush", dma, user)
    emit_DSB(f"{ec}/PushSynchNeeded.FromPushDblSync",
             "FifoClear FromPush", user, dma)

    # EnableChain PulseSync (NiFpgaFifoPortReset crossings)
    rst = f"{ec}/NiFpgaFifoPortResetx"
    emit_pulse_sync_with_ack(w,
        f"DmaPortCommIfcComponentEnableChainx/Input.FifoClearController"
        f"/NiFpgaFifoPortResetx/Crossing.ClearToPush",
        "ClearToPush", dma, user)
    emit_PS(f"{rst}/Crossing.PopToPush/PulseSyncBasex",
            "PopToPush", dma, user)
    emit_PS(f"{rst}/Crossing.PushToPop/PulseSyncBasex",
            "PushToPop", user, dma)

    # Async reset false paths
    emit(f"# --- Async reset paths: {inst} CLR/PRE ---")
    emit(f"set_false_path -to [get_pins -quiet -hier -filter {{NAME =~ {w}/*/CLR && IS_LEAF}}]")
    emit(f"set_false_path -to [get_pins -quiet -hier -filter {{NAME =~ {w}/*/PRE && IS_LEAF}}]")
    emit()


def emit_reader_fifo(inst):
    """Emit all CDC constraints for one NiSharedFifoReader instance (HostToTarget).

    Internal structure (HostToTarget / Reader):
      Push = FIFO BusClk port -> DmaClk (250 MHz)
      Pop  = FIFO ViClk port  -> user clock (PllClk80, 80 MHz)
    """
    w = f"*{inst}"  # wildcard prefix for hierarchy-independent matching
    user, dma = USER_T, DMA_T

    emit("# =================================================================================")
    emit(f"#  {inst}  (NiSharedFifoReader / HostToTarget)")
    emit("#    Push = DMA side (FIFO BusClk port), Pop = user side (FIFO ViClk port)")
    emit("# =================================================================================")
    emit()

    # StreamStateBlock HandshakeBool instances (user -> DMA)
    for name in ["HandshakeStopStreamRequest",
                 "HandshakeStartStreamRequest"]:
        emit_HB(f"{w}/StreamStateBlock.{name}/HandshakeBasex",
                f"StreamStateBlock {name}", user, dma)

    # StreamStateBlock HandshakeBaseResetCross (user -> DMA)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeStateToBusClkDomain",
              "StreamStateBlock StateToBusClk", user, dma)
    emit_HBRC(f"{w}/StreamStateBlock.HandshakeUnderflowStopRequest",
              "StreamStateBlock UnderflowStop", user, dma, has_data=False)

    # Underflow handshake (user -> DMA)
    emit_HBRC(f"{w}/BlkUnderflow.HandshakeUnderflow",
              "BlkUnderflow Underflow", user, dma, has_data=False)

    # HandshakeFullCount (user -> DMA)
    emit_HBRC(f"{w}/HandshakeFullCount",
              "HandshakeFullCount", user, dma)

    # DmaPortOutStrmFifo gray counter (OClk=user -> IClk=DMA, process-based)
    flags = f"{w}/DmaPortOutStrmFifox/DmaPortOutStrmFifoFlagsx"
    emit("# --- DmaPortOutStrmFifo: gray counter user -> DMA ---")
    smd(f"${dma}",
        gc(f"{flags}/oReadSamplePtrUnsGray*"),
        gc(f"{flags}/iReadSamplePtrUnsGray_ms*"))
    smd(f"[expr {{0.5*${dma}}}]",
        gc(f"{flags}/iReadSamplePtrUnsGray_ms*"),
        gc(f"{flags}/iReadSamplePtrUnsGray_reg*"))
    emit()

    # DmaPortOutStrmFifo PCC write pointer (IClk=DMA -> OClk=user)
    emit_PCC(f"{flags}/IClkToOClkCrossing.SyncToOClk",
             "write ptr DMA -> user", dma, user)

    # EnableChain DoubleSyncBool (FifoClearController; the clear runs on the
    # DMA side, the pop port is the user side)
    ec = f"{w}/DmaPortCommIfcComponentEnableChainx/Output.FifoClearController"
    emit_DSB(f"{ec}/PopSynchNeeded.ToPopDblSync",
             "FifoClear ToPop", dma, user)
    emit_DSB(f"{ec}/PopSynchNeeded.FromPopDblSync",
             "FifoClear FromPop", user, dma)

    # EnableChain PulseSync (NiFpgaFifoPortReset crossings)
    rst = f"{ec}/NiFpgaFifoPortResetx"
    emit_pulse_sync_with_ack(w,
        f"DmaPortCommIfcComponentEnableChainx/Output.FifoClearController"
        f"/NiFpgaFifoPortResetx/Crossing.ClearToPop",
        "ClearToPop", dma, user)
    # Note: PopToPush/PushToPop directions are SWAPPED vs WriterFifo because
    # ReaderFifo has Push=DMA side, Pop=user side (opposite of WriterFifo).
    emit_PS(f"{rst}/Crossing.PopToPush/PulseSyncBasex",
            "PopToPush", user, dma)
    emit_PS(f"{rst}/Crossing.PushToPop/PulseSyncBasex",
            "PushToPop", dma, user)

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
    emit("## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    emit("## !! REQUIREMENT -- these constraints are ONLY valid if, for every FIFO:")
    emit(f"## !!   * the clock on the FIFO ViClk  port is {USER_FREQ_HZ / 1e6:.0f} MHz"
         " (target BusClk / PllClk80)")
    emit(f"## !!   * the clock on the FIFO BusClk port is {DMA_FREQ_HZ / 1e6:.0f} MHz (DmaClk)")
    emit("## !! The periods below are hard-coded.  With any other ViClk frequency these")
    emit("## !! constraints are silently wrong -- Vivado reports nothing, and a faster")
    emit("## !! ViClk leaves the clock-domain crossings under-constrained.")
    emit("## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    emit("##")
    emit("## Each constraint explicitly targets specific synchronizer flip-flops inside")
    emit("## each CDC component instance.  If the design changes, only the known safe")
    emit("## flip-flops are relaxed -- new logic will NOT be silently caught.")
    emit("##")
    emit("## Clock domains (effective periods from the target clock definitions).")
    emit("## NOTE: the FIFO port names do not match the target clock names --")
    emit("## the FIFO BusClk port is driven by DmaClk, NOT by the target's BusClk.")
    emit("##")
    emit("##   Variable        FIFO port  Driven by (UserHdl)        Freq       Effective period")
    emit(f"##   {DMA_T:<14}  BusClk     DmaClk                     "
         f"{DMA_FREQ_HZ / 1e6:>3.0f} MHz    {DMA_PERIOD_NS:.10f} ns")
    emit(f"##   {USER_T:<14}  ViClk      target BusClk (PllClk80)   "
         f"{USER_FREQ_HZ / 1e6:>3.0f} MHz    {USER_PERIOD_NS:.10f} ns")
    emit(f"##   Formula: 1/(freq*(1+PPM/1e6)) - jitter  [PPM={CLOCK_PPM}, jitter={CLOCK_JITTER_PS}ps]")
    emit("##")
    emit("## Section comments say \"user\" for the ViClk-port side and \"DMA\" for the")
    emit("## BusClk-port side.")
    emit("##")
    emit(f"## Writer FIFOs (TargetToHost): {', '.join(WRITER_FIFOS) or '(none)'}")
    emit(f"## Reader FIFOs (HostToTarget): {', '.join(READER_FIFOS) or '(none)'}")
    emit("##")
    emit("###################################################################################")
    emit()
    emit(f"set {DMA_T} {DMA_PERIOD_NS:.10f}")
    emit(f"set {USER_T} {USER_PERIOD_NS:.10f}")
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
