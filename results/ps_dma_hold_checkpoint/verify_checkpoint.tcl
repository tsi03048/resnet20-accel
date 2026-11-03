set here [file normalize [file dirname [info script]]]
open_checkpoint [file join $here system.dcp]
set clock [get_clocks clk_fpga_0]
if {[llength $clock]!=1 || abs([get_property PERIOD $clock]-10.0)>0.000001} {error "Expected one 100 MHz FCLK"}
report_clocks -file [file join $here clocks.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $here timing.rpt]
check_timing -verbose -file [file join $here check_timing.rpt]
puts "HOLD_CHECKPOINT_REOPEN_COMPLETE (validate saved budget/timing with Python)"
exit 0
