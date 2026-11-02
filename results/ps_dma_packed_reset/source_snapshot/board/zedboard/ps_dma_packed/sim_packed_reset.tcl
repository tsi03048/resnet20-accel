set root [file normalize [file join [file dirname [info script]] ../../..]]
create_project packed_reset [file join $root build/packed_reset/project] -part xc7z020clg484-1 -force
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $root rtl/full_e2b_fpga_v2]] [current_fileset]
foreach name {full_model feature_ram sync_bram weight_bram mul_serial rne_serial} {add_files -norecurse [file join $root rtl/full_e2b_fpga_v2/${name}.sv]}
add_files -norecurse [list [file join $root rtl/full_e2b_fpga_v2/control_rom.svh] [file join $root rtl/full_e2b_v1/argmax10.sv] [file join $root rtl/ps_dma_v2/resnet20_axi_packed.sv]]
add_files -fileset sim_1 -norecurse [file join $root tb/ps_dma_v2/tb_packed_reset.sv]
set_property top tb_packed_reset [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run 5ms
close_sim
puts "PACKED_RESET_SIMULATION_FINISHED (require PACKED_RESET_PASS)"
exit 0
