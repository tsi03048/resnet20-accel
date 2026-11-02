# Standalone real DMA IP loopback with AXI DDR/PS BFMs. No CNN/PS boot claim.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set out [file join $root build/dma_ip_sim]
file mkdir $out
create_project dma_ip_sim [file join $out project] -part xc7z020clg484-1 -force
set_property target_language Verilog [current_project]
set_param general.maxThreads 4
create_ip -name axi_dma -vendor xilinx.com -library ip -version 7.1 -module_name dma_under_test
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {1} CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_include_mm2s_dre {0} CONFIG.c_include_s2mm_dre {0} CONFIG.c_sg_length_width {23} \
    CONFIG.c_mm2s_burst_size {16} CONFIG.c_s2mm_burst_size {16}] [get_ips dma_under_test]
generate_target simulation [get_ips dma_under_test]
add_files -fileset sim_1 -norecurse [file join $root tb/ps_dma_v1/tb_dma_ip.sv]
set_property top tb_dma_ip [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
puts "DMA_IP_SIMULATION_FINISHED (require DMA_IP_PASS in simulator log)"
exit 0
