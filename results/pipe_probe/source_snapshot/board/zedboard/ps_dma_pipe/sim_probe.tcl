set root [file normalize [file join [file dirname [info script]] ../../..]]
file mkdir [file join $root results/pipe_probe]
create_project pipe_probe [file join $root build/pipe_probe/project] -part xc7z020clg484-1 -force
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $root rtl/full_e2b_fpga_v3]] [current_fileset]
foreach name {full_model feature_ram sync_bram weight_bram mul_serial rne_serial} {add_files -norecurse [file join $root rtl/full_e2b_fpga_v3/${name}.sv]}
add_files -norecurse [list [file join $root rtl/full_e2b_fpga_v3/control_rom.svh] [file join $root rtl/full_e2b_v1/argmax10.sv]]
add_files -fileset sim_1 -norecurse [file join $root tb/ps_dma_v3/tb_pipe_probe.sv]
set_property top tb_pipe_probe [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property -name xsim.simulate.xsim.more_options -value "-testplusarg ROOT=$root" -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run 5ms
close_sim
puts "PIPE_PROBE_SIMULATION_FINISHED (require PIPE_PROBE_PASS)"
exit 0
