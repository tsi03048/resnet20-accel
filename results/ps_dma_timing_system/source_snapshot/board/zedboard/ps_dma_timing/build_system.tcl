# Complete ZedBoard Rev-D PS7/DDR/GP0/HP0 + AXI DMA system. No core OOC timing exceptions.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set out [file join $root build/zedboard_ps_timing]
file mkdir $out
set reports [file join $out reports]
file mkdir $reports
set phase preflight
proc status {state detail} {
    global reports phase
    set f [open [file join $reports status.txt] w];puts $f "status=$state\nphase=$phase\ndetail=$detail";close $f
}
proc reports {prefix} {
    global reports
    report_utilization -file [file join $reports ${prefix}_utilization.rpt]
    report_utilization -hierarchical -file [file join $reports ${prefix}_hierarchical.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $reports ${prefix}_timing_summary.rpt]
    report_timing -delay_type max -max_paths 10 -path_type full_clock_expanded -file [file join $reports ${prefix}_worst_setup.rpt]
    report_timing -delay_type min -max_paths 10 -path_type full_clock_expanded -file [file join $reports ${prefix}_worst_hold.rpt]
    check_timing -verbose -file [file join $reports ${prefix}_check_timing.rpt]
    report_drc -file [file join $reports ${prefix}_drc.rpt]
}
status RUNNING preflight
if {[catch {
    set_param general.maxThreads 4
    set_param board.repoPaths [list [file join $root third_party/avnet_bdf]]
    create_project zedboard_ps_timing [file join $out project] -part xc7z020clg484-1 -force
    set boards [get_board_parts -quiet *:zedboard:part0:1.5]
    if {[llength $boards]!=1} {error "Expected vendored Avnet ZedBoard board definition 1.5: $boards"}
    set_property board_part [lindex $boards 0] [current_project]
    set_property target_language Verilog [current_project]
    set_property include_dirs [list [file join $root rtl/full_e2b_fpga_v3]] [current_fileset]
    foreach file {full_model feature_ram sync_bram weight_bram mul_serial rne_serial} {
        add_files -norecurse [file join $root rtl/full_e2b_fpga_v3/${file}.sv]
    }
    add_files -norecurse [file join $root rtl/full_e2b_v1/argmax10.sv]
    add_files -norecurse [file join $root rtl/full_e2b_fpga_v3/control_rom.svh]
    add_files -norecurse [file join $root rtl/ps_dma_v3/resnet20_axi_packed.sv]
    add_files -norecurse [file join $root rtl/ps_dma_v3/resnet20_axi_packed_bd.v]
    create_bd_design system
    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
    set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
        CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_RST0_PORT {1}] $ps
    set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma]
    set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {1} CONFIG.c_include_s2mm {1} \
        CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_m_axi_s2mm_data_width {64} \
        CONFIG.c_m_axis_mm2s_tdata_width {32} CONFIG.c_s_axis_s2mm_tdata_width {32} \
        CONFIG.c_include_mm2s_dre {0} CONFIG.c_include_s2mm_dre {0} CONFIG.c_sg_length_width {23} \
        CONFIG.c_mm2s_burst_size {16} CONFIG.c_s2mm_burst_size {16}] $dma
    set accel [create_bd_cell -type module -reference resnet20_axi_packed_bd accel]
    set ctl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 control]
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ctl
    set mem [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 memory]
    set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $mem
    set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset]
    set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one]
    set_property CONFIG.CONST_VAL {1} $one
    set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 zero]
    set_property CONFIG.CONST_VAL {0} $zero
    connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins control/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins control/M00_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins control/M01_AXI] [get_bd_intf_pins accel/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins memory/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins memory/S01_AXI]
    connect_bd_intf_net [get_bd_intf_pins memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
    connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins accel/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins accel/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins ps7/S_AXI_HP0_ACLK] \
        [get_bd_pins control/ACLK] [get_bd_pins control/S00_ACLK] [get_bd_pins control/M00_ACLK] [get_bd_pins control/M01_ACLK] \
        [get_bd_pins memory/ACLK] [get_bd_pins memory/S00_ACLK] [get_bd_pins memory/S01_ACLK] [get_bd_pins memory/M00_ACLK] \
        [get_bd_pins dma/s_axi_lite_aclk] [get_bd_pins dma/m_axi_mm2s_aclk] [get_bd_pins dma/m_axi_s2mm_aclk] \
        [get_bd_pins accel/aclk] [get_bd_pins reset/slowest_sync_clk]
    connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
    connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
    connect_bd_net [get_bd_pins zero/dout] [get_bd_pins reset/aux_reset_in] [get_bd_pins reset/mb_debug_sys_rst]
    connect_bd_net [get_bd_pins reset/interconnect_aresetn] [get_bd_pins control/ARESETN] [get_bd_pins control/S00_ARESETN] \
        [get_bd_pins control/M00_ARESETN] [get_bd_pins control/M01_ARESETN] [get_bd_pins memory/ARESETN] \
        [get_bd_pins memory/S00_ARESETN] [get_bd_pins memory/S01_ARESETN] [get_bd_pins memory/M00_ARESETN]
    connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins dma/axi_resetn] [get_bd_pins accel/aresetn]
    assign_bd_address
    assign_bd_address -offset 0x40400000 -range 64K -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs dma/S_AXI_LITE/Reg] -force
    assign_bd_address -offset 0x43c00000 -range 4K -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs accel/S_AXI/reg0] -force
    validate_bd_design
    if {[get_property CONFIG.C_EXT_RESET_HIGH $rst]!=0} {error "PS FCLK_RESET0_N must be interpreted as active-low"}
    save_bd_design
    set f [open [file join $reports system_config.txt] w]
    puts $f "tool=[version -short]\npart=xc7z020clg484-1\nboard_part=[get_property BOARD_PART [current_project]]\ntop=system_wrapper\nmode=complete_PS7_DDR_AXI_DMA_system\nclock_period_ns=10.000"
    foreach key {PCW_UIPARAM_DDR_PARTNO PCW_UIPARAM_DDR_FREQ_MHZ PCW_FPGA0_PERIPHERAL_FREQMHZ PCW_USE_M_AXI_GP0 PCW_USE_S_AXI_HP0} {puts $f "$key=[get_property CONFIG.$key $ps]"}
    foreach key {c_include_sg c_sg_length_width c_m_axi_mm2s_data_width c_m_axis_mm2s_tdata_width c_s_axis_s2mm_tdata_width} {puts $f "$key=[get_property CONFIG.$key $dma]"}
    foreach seg [get_bd_addr_segs] {puts $f "address_segment=$seg [get_property OFFSET $seg] [get_property RANGE $seg]"}
    close $f
    write_bd_tcl -force [file join $out system_export.tcl]
    generate_target all [get_files system.bd]
    set wrapper [make_wrapper -files [get_files system.bd] -top]
    add_files -norecurse $wrapper
    set_property top system_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    set phase synthesis;status RUNNING synthesis
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "System synthesis failed"}
    open_run synth_1
    reports post_synth
    close_design
    set phase implementation;status RUNNING implementation
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithAggressiveHoldFix [get_runs impl_1]
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "System implementation/bitstream failed"}
    open_run impl_1
    reports post_route
    report_route_status -file [file join $reports post_route_status.rpt]
    report_clocks -file [file join $reports clocks.rpt]
    write_checkpoint -force [file join $out system_post_route.dcp]
    write_hw_platform -fixed -include_bit -force -file [file join $out system.xsa]
    set bits [get_property DIRECTORY [get_runs impl_1]]
    file copy -force [file join $bits system_wrapper.bit] [file join $out system.bit]
    set phase complete;status COMPLETE bitstream_and_xsa
} msg opts]} {
    status FAILED $msg;puts stderr "PS_SYSTEM_FAILED phase=$phase message=$msg";puts stderr [dict get $opts -errorinfo];exit 1
}
puts "PS_SYSTEM_COMPLETE output=$out"
exit 0
