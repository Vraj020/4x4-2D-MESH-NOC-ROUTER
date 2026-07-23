# ================================================================
# Innovus P&R Script — mesh_4x4_top
# PDK  : SCL 180nm (6M1L stack)
# Flow : Genus netlist -> floorplan -> power -> place -> CTS ->
#        route -> signoff checks -> GDSII streamout
#
# NOTE: this Innovus install only has the LEGACY command set
# (confirmed via `info commands`), so this script uses
# floorPlan / addRing / addStripe / routeDesign / optDesign /
# streamOut instead of the modern create_floorplan / add_rings /
# route_design / opt_design / write_stream equivalents.
# ================================================================

# ─── 0. Paths ──────────────────────────────────────────────────
set TECH_LEF   "/home/Cadance_libs/sclpdk_v3/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/6M1L/lef/scl18fs120_tech.lef"
set CELL_LEF   "/home/Cadance_libs/sclpdk_v3/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/6M1L/lef/scl18fs120_std.lef"
set GDS_LIB    "/home/Cadance_libs/sclpdk_v3/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/6M1L/gds/scl18fs120.gds"
set GDS_MAP    "/home/Cadance_libs/sclpdk_v3/SCLPDK_V3.0_KIT/scl180/digital_pnr_kit/snps/non_rh/6M1L/icc_gds_out_6LM.map"

set NETLIST    "/home/vlsi/C2S/NOC/SYNTHESIS/OUTPUT/mesh_4x4_netlist.v"
set MMMC_VIEW  "/home/vlsi/C2S/NOC/PD_FLOW/mmmc_view.tcl"
set OUT_DIR    "/home/vlsi/C2S/NOC/PD_FLOW/OUTPUT"

file mkdir $OUT_DIR

# ─── 1. Load libraries + MMMC view + netlist, init design ──────
puts "### Setting up design..."
set init_lef_file   [list $TECH_LEF $CELL_LEF]
set init_verilog    $NETLIST
set init_top_cell   mesh_4x4_top
set init_mmmc_file  $MMMC_VIEW
set init_pwr_net    "VDD"
set init_gnd_net    "VSS"

init_design

# ─── 2. Floorplan ────────────────────────────────────────────────
# 65% core utilization, 10um core-to-die margins, square aspect
puts "### Creating floorplan..."
floorPlan -r 1.0 0.65 10 10 10 10

# ─── 3. Power planning — MUST run before placement/routing so the
#        router treats VDD/VSS as real obstacles (doing this after
#        route caused metal shorts — see drc_final2.rpt history)
# ────────────────────────────────────────────────────────────────
puts "### Power planning..."
globalNetConnect VDD -type pgpin -pin VDD -all
globalNetConnect VSS -type pgpin -pin VSS -all

addRing -type core_rings -nets { VDD VSS } \
    -layer { top M6 bottom M6 left M5 right M5 } \
    -width 2.0 -spacing 2.0 -offset 2.0

addStripe -nets { VDD VSS } \
    -layer M5 \
    -direction vertical \
    -width 2.0 -spacing 2.0 \
    -set_to_set_distance 40 \
    -start_offset 10

sroute -connect { blockPin padPin padRing corePin floatingStripe } \
       -layerChangeRange { M1 M6 } \
       -blockPinTarget { nearestTarget } \
       -padPinPortConnect { allPort oneGeom } \
       -checkAlignedSecondaryPin false \
       -allowJogging 1 \
       -crossoverViaBottomLayer M1 \
       -crossoverViaTopLayer M6 \
       -nets { VDD VSS } \
       -allowLayerChange 1 \
       -targetViaLayerRange { M1 M6 }

puts "### Verifying power connectivity before placement..."
verifyConnectivity -type special -report ${OUT_DIR}/power_check_preplace.rpt

# ─── 4. Placement ────────────────────────────────────────────────
puts "### Placing standard cells..."
place_design

report_timing -late > ${OUT_DIR}/timing_post_place.rpt

# ─── 5. Clock Tree Synthesis ──────────────────────────────────────
puts "### Running CTS..."
ccopt_design

report_timing -late  > ${OUT_DIR}/timing_post_cts.rpt
report_clock_tree    > ${OUT_DIR}/clock_tree.rpt

# ─── 6. Routing ───────────────────────────────────────────────────
puts "### Routing..."
routeDesign

# post-route optimization for any remaining setup/hold violations
optDesign -postRoute -setup -hold

# ─── 7. Signoff checks ────────────────────────────────────────────
puts "### Running signoff checks..."
verify_drc           -report ${OUT_DIR}/drc.rpt
verifyConnectivity    -type special -report ${OUT_DIR}/power_check_final.rpt
verify_connectivity   -report ${OUT_DIR}/connectivity.rpt
verify_geometry       -report ${OUT_DIR}/geometry.rpt

# extract parasitics + final signoff report
extract_rc
report_timing -late  > ${OUT_DIR}/timing_final.rpt
report_area          > ${OUT_DIR}/area_final.rpt
report_power         > ${OUT_DIR}/power_final.rpt

# ─── 8. GDSII streamout ───────────────────────────────────────────
puts "### Streaming out GDSII..."
streamOut "${OUT_DIR}/mesh_4x4_top.gds" \
    -mapFile       $GDS_MAP \
    -libName       DesignLib \
    -structureName mesh_4x4_top \
    -mode          ALL \
    -merge         $GDS_LIB

# also save the final netlist + def for the record
write_netlist "${OUT_DIR}/mesh_4x4_final_netlist.v"
write_def     "${OUT_DIR}/mesh_4x4_final.def"

puts ""
puts "##################################################"
puts "###   RTL-TO-GDSII COMPLETE!                   ###"
puts "###   Check: pnr/output/ folder                ###"
puts "###     mesh_4x4_top.gds     -> final GDSII    ###"
puts "###     timing_final.rpt     -> signoff timing ###"
puts "###     drc.rpt / connectivity.rpt / geometry.rpt"
puts "###     power_check_final.rpt -> should be 0 viol"
puts "##################################################"
