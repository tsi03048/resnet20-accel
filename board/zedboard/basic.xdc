# Source: Digilent/digilent-xdc Zedboard-Master.xdc, Clock Source Bank 13.
# ZedBoard only. This is not an Arty Z7 constraint file.
set_property PACKAGE_PIN Y9 [get_ports GCLK]
set_property IOSTANDARD LVCMOS33 [get_ports GCLK]
create_clock -period 10.000 -name GCLK [get_ports GCLK]
