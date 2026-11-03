# Implementation margin, not a measured clock-jitter claim.
# Tighten all synchronous clk_fpga_0 hold checks by 0.100 ns.
set hold_clock [get_clocks clk_fpga_0]
if {[llength $hold_clock]!=1 || abs([get_property PERIOD $hold_clock]-10.0)>0.000001} {error "Expected one 100 MHz FCLK"}
set_clock_uncertainty -hold 0.100 $hold_clock
puts "HOLD_MARGIN_APPLIED clock=clk_fpga_0 period_ns=10.000 user_hold_uncertainty_ns=0.100"
