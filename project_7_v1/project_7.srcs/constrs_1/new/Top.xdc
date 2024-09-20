set_property DRIVE 12 [get_ports {DATA_OUT[7]}]
set_property DRIVE 12 [get_ports {DATA_OUT[6]}]
set_property DRIVE 12 [get_ports {DATA_OUT[5]}]
set_property DRIVE 12 [get_ports {DATA_OUT[4]}]
set_property DRIVE 12 [get_ports {DATA_OUT[3]}]
set_property DRIVE 12 [get_ports {DATA_OUT[2]}]
set_property DRIVE 12 [get_ports {DATA_OUT[1]}]
set_property DRIVE 12 [get_ports {DATA_OUT[0]}]

# 100 MHz clock from Basys3 onboard oscillator
set_property PACKAGE_PIN W5 [get_ports {CLK}]
set_property IOSTANDARD LVCMOS33 [get_ports {CLK}]
create_clock -period 10.000 [get_ports {CLK}] # 100 MHz input clock
set_property PACKAGE_PIN J2 [get_ports CS_N]
set_property IOSTANDARD LVCMOS33 [get_ports CS_N]

set_property IOSTANDARD LVCMOS33 [get_ports MISO]
set_property IOSTANDARD LVCMOS33 [get_ports MOSI]
set_property PACKAGE_PIN V17 [get_ports RST]
set_property IOSTANDARD LVCMOS33 [get_ports RST]
set_property IOSTANDARD LVCMOS33 [get_ports SCLK]
set_property PACKAGE_PIN G2 [get_ports MOSI]
set_property PACKAGE_PIN G3 [get_ports MISO]
set_property PACKAGE_PIN H2 [get_ports SCLK]


set_property PACKAGE_PIN L1 [get_ports LED1]
set_property PACKAGE_PIN P1 [get_ports LED2]
set_property PACKAGE_PIN N3 [get_ports LED3]
set_property PACKAGE_PIN P3 [get_ports LED4]

set_property IOSTANDARD LVCMOS33 [get_ports LED1]
set_property IOSTANDARD LVCMOS33 [get_ports LED2]
set_property IOSTANDARD LVCMOS33 [get_ports LED3]
set_property IOSTANDARD LVCMOS33 [get_ports LED4]
