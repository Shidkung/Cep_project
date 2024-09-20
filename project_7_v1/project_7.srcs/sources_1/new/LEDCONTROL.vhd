library ieee;
use ieee.std_logic_1164.all;
 
package Led_control is
 
  -- Outputs from the FIFO.
  type ledcontrol is record
    LED1  : std_logic;                -- FIFO Full Flag
    LED2 : std_logic;                -- FIFO Empty Flag
    LED3    : std_logic;
    LED4  : std_logic;
  end record ledcontrol;  
 
  -- Inputs to the FIFO.
 
  constant LED_CONTROL : ledcontrol := (LED1 => '1',
                                              LED2 => '1',
                                              LED3 => '1',
                                              LED4 =>'1');
   
end package Led_control;