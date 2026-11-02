# Core-only OOC experiment. These interface budgets are assumptions, not board pins.
create_clock -period 10.000 -name core_clk [get_ports clk]
set data_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock core_clk -max 2.000 $data_inputs
set_input_delay -clock core_clk -min 0.000 $data_inputs
set_output_delay -clock core_clk -max 2.000 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]
