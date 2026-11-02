# vivado -mode batch -source board/zedboard/build_full.tcl -tclargs synth|route
# Measures the unmodified bit-exact core, not a ZedBoard pin/PS/DDR top.
set root [file normalize [file join [file dirname [info script]] ../..]]
set action [expr {$argc > 0 ? [lindex $argv 0] : "synth"}]
if {$action ni {synth route}} {error "Expected synth or route"}
set variant [expr {$argc > 1 ? [lindex $argv 1] : "baseline"}]
if {$variant ni {baseline flat}} {error "Expected baseline or flat"}
set core_dir [expr {$variant eq "flat" ? "full_e2b_flat_v1" : "full_e2b_v1"}]
set out [file join $root build/zedboard_full]
set reports [file join $out reports]
file mkdir $reports
set phase preflight
proc state_file {status detail} {
    global reports phase
    set f [open [file join $reports status.txt] w]
    puts $f "status=$status"
    puts $f "phase=$phase"
    puts $f "detail=$detail"
    close $f
}
proc write_reports {prefix} {
    global reports
    report_utilization -file [file join $reports ${prefix}_utilization.rpt]
    report_utilization -hierarchical -file [file join $reports ${prefix}_hierarchical.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
        -file [file join $reports ${prefix}_timing_summary.rpt]
    report_timing -delay_type max -max_paths 10 -path_type full_clock_expanded \
        -file [file join $reports ${prefix}_worst_setup.rpt]
    report_timing -delay_type min -max_paths 10 -path_type full_clock_expanded \
        -file [file join $reports ${prefix}_worst_hold.rpt]
    check_timing -verbose -file [file join $reports ${prefix}_check_timing.rpt]
    report_drc -file [file join $reports ${prefix}_drc.rpt]
    set f [open [file join $reports ${prefix}_cells.tsv] w]
    puts $f "reference\tcount"
    foreach pattern {LUT* FD* RAMB18* RAMB36* DSP48* RAM32* RAM64* MUXF* BUFG*} {
        set filter [format {REF_NAME =~ %s} $pattern]
        puts $f "$pattern\t[llength [get_cells -hier -filter $filter]]"
    }
    close $f
}
state_file RUNNING started
if {[catch {
    create_project -in_memory -part xc7z020clg484-1
    set_property target_language Verilog [current_project]
    set_property include_dirs [list [file join $root rtl/full_e2b_v1]] [current_fileset]
    set_param general.maxThreads 4
    set f [open [file join $reports environment.txt] w]
    puts $f "tool=[version -short]"
    puts $f "part=xc7z020clg484-1"
    puts $f "top=full_model"
    puts $f "mode=out_of_context"
    puts $f "clock_period_ns=10.000"
    puts $f "interface_max_delay_ns=2.000"
    puts $f "action=$action"
    puts $f "variant=$variant"
    close $f
    read_verilog -sv [list [file join $root rtl/full_e2b_v1/requant_full.sv] \
        [file join $root rtl/full_e2b_v1/argmax10.sv] [file join $root rtl/$core_dir/full_model.sv]]
    read_xdc [file join $root board/zedboard/full_core.xdc]
    set phase synthesis
    state_file RUNNING synthesis
    synth_design -top full_model -part xc7z020clg484-1 -mode out_of_context
    set phase post_synthesis_reports
    write_checkpoint -force [file join $out post_synth.dcp]
    write_reports post_synth
    if {$action eq "route"} {
        set phase optimization
        opt_design
        set phase placement
        place_design
        set phase routing
        route_design
        set phase post_route_reports
        write_checkpoint -force [file join $out post_route.dcp]
        write_reports post_route
        report_route_status -file [file join $reports post_route_status.rpt]
    }
    set phase complete
    state_file COMPLETE $action
} message options]} {
    state_file FAILED $message
    puts stderr "FULL_CORE_FAILED phase=$phase message=$message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "FULL_CORE_COMPLETE action=$action reports=$reports"
exit 0
