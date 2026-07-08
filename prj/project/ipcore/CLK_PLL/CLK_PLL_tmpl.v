// Created by IP Generator (Version 2024.2 build 178169)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


CLK_PLL the_instance_name (
  .clkin1(clkin1),        // input 50.0MHz
  .pll_lock(pll_lock),    // output
  .clkout0(clkout0),      // output 100.0MHz
  .clkout1(clkout1),      // output 2.0MHz
  .clkout2(clkout2)       // output 160.0MHz
);
