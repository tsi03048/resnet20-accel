# Invoked by run_board.ps1 in an ASCII bundle. Programs one connected ZedBoard.
if {$argc!=1} {error "Expected bundle directory"}
set bundle [file normalize [lindex $argv 0]]
connect
set cpu [targets -filter {name =~ "*Cortex-A9*#0"} -target-properties]
if {[llength $cpu]!=1} {error "Connect exactly one Zynq Cortex-A9 core #0; inspect targets"}
targets -set -filter {name =~ "*Cortex-A9*#0"}
puts "BOARD_TARGETS=[targets]"
rst -system
after 1000
stop
fpga -file [file join $bundle system.bit]
source [file join $bundle ps7_init.tcl]
ps7_init
ps7_post_config
targets -set -filter {name =~ "*Cortex-A9*#0"}
rst -processor
source [file join $bundle inputs/load_packets.tcl]
foreach item $packet_downloads {
    lassign $item name address
    dow -data [file join $bundle inputs $name] $address
}
# Discard earlier report state before starting this ELF.
mwr 0x03000000 0 128
dow [file join $bundle app.elf]
con
set terminal 0
for {set n 0} {$n<180} {incr n} {
    after 1000
    set raw [lindex [mrd -value 0x03000004 1] 0]
    set state [expr {$raw & 0xffffffff}]
    if {$state==2 || ($state & 0x80000000)!=0} {set terminal 1;break}
}
stop
set values [mrd -value 0x03000000 72]
set f [open [file join $bundle board_report.words] w]
foreach value $values {puts $f [format "%08x" [expr {$value & 0xffffffff}]]}
close $f
if {!$terminal} {error "BOARD_TIMEOUT; report saved"}
if {$state!=2} {error "BOARD_FIRMWARE_FAILED state=$raw; report saved"}
puts "BOARD_PS_DMA_COMPLETED; validate all scores with tools.ps_dma_board_report"
exit
