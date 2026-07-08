-- Created by IP Generator (Version 2024.2 build 178169)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT CLK_PLL
  PORT (
    clkin1 : IN STD_LOGIC;  -- 50.0MHz
    pll_lock : OUT STD_LOGIC;
    clkout0 : OUT STD_LOGIC;  -- 100.0MHz
    clkout1 : OUT STD_LOGIC;  -- 2.0MHz
    clkout2 : OUT STD_LOGIC  -- 160.0MHz
  );
END COMPONENT;


the_instance_name : CLK_PLL
  PORT MAP (
    clkin1 => clkin1,
    pll_lock => pll_lock,
    clkout0 => clkout0,
    clkout1 => clkout1,
    clkout2 => clkout2
  );
