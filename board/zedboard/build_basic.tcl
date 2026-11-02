# vivado -mode batch -source board/zedboard/build_basic.tcl
set root [file normalize [file join [file dirname [info script]] ../..]]
create_project basic_vio [file join $root build/zedboard_basic] -part xc7z020clg484-1 -force
add_files [file join $root rtl/basic_v1/conv_toy.sv]
add_files [file join $root board/zedboard/basic_vio_top.sv]
add_files -fileset constrs_1 [file join $root board/zedboard/basic.xdc]
set_property top basic_vio_top [current_fileset]
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_basic
set_property -dict [list CONFIG.C_NUM_PROBE_IN {6} CONFIG.C_NUM_PROBE_OUT {2} \
    CONFIG.C_PROBE_IN0_WIDTH {32} CONFIG.C_PROBE_IN1_WIDTH {32} \
    CONFIG.C_PROBE_IN2_WIDTH {32} CONFIG.C_PROBE_IN3_WIDTH {32} \
    CONFIG.C_PROBE_IN4_WIDTH {2} CONFIG.C_PROBE_IN5_WIDTH {4} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT1_WIDTH {1}] [get_ips vio_basic]
generate_target all [get_ips vio_basic]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "synthesis incomplete"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "implementation incomplete"}
open_run impl_1
report_utilization -file [file join $root build/zedboard_basic/utilization.rpt]
report_timing_summary -file [file join $root build/zedboard_basic/timing.rpt]
set worst [get_timing_paths -max_paths 1]
if {[llength $worst] == 0 || [get_property SLACK $worst] < 0} {error "timing not verified/failed"}
puts "Build finished; review timing and program the matching bit/ltx pair in Hardware Manager."
