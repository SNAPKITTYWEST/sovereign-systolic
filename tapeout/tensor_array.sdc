# SDC Timing Constraints for systolic_array_16x16 + Tensor Core
# Target: Sky130 / 100-200 MHz or commercial 7nm @ 800 MHz+

set clk_name clk
set clk_port_name clk
set clk_period 10.0 ;# 100 MHz for Sky130 (change to 1.25 for 800 MHz)

create_clock -name $clk_name -period $clk_period [get_ports $clk_port_name]

# Clock uncertainty / skew
set_clock_uncertainty -setup 0.25 [get_clocks $clk_name]
set_clock_uncertainty -hold 0.10 [get_clocks $clk_name]

# Clock transition
set_clock_transition 0.15 [get_clocks $clk_name]

# Input / Output delays (external interface)
set_input_delay -clock $clk_name -max 2.0 [all_inputs]
set_input_delay -clock $clk_name -min 0.5 [all_inputs]
set_output_delay -clock $clk_name -max 2.0 [all_outputs]
set_output_delay -clock $clk_name -min 0.5 [all_outputs]

# Remove clock from IO delay
set_input_delay -clock $clk_name 0 [get_ports $clk_port_name]
set_output_delay -clock $clk_name 0 [get_ports done]

# Load capacitance on outputs
set_load 0.05 [all_outputs]

# Driving cell for inputs
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_4 [all_inputs]

# Max fanout / transition
set_max_fanout 16 [current_design]
set_max_transition 0.5 [current_design]
