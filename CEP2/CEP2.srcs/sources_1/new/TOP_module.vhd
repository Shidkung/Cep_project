----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/30/2024 10:44:55 AM
-- Design Name: 
-- Module Name: TOP_module - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.MATH_REAL.ALL;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity TOP_module is
Port (
        CLK       : in  std_logic;  -- System clock
        RST       : in  std_logic;  -- Reset signal
        --SPI_interface Master(For DAC)
        M_MISO      : in  std_logic;  -- Slave to master data
        M_MOSI      : out std_logic;  -- Master to slave data
        M_SCLK      : out std_logic;  -- SPI clock
        M_CS_N      : out std_logic_vector(2 downto 0);  -- Chip select signal
        --SPI_interface SLAVE
        S_MISO      : out  std_logic;  -- Slave to master data
        S_MOSI      : in std_logic;  -- Master to slave data
        S_SCLK      : in std_logic;  -- SPI clock
        S_CS_N      : in std_logic;  -- Chip select signal
        --INPUT_PIN
        GPIO_IN     : in std_logic_vector(3 to 0);
        ADC_IN     : in std_logic_vector(3 to 0);
        --OUTPUT PIN
        GPIO_OUT     : in std_logic_vector(3 to 0);
        ADC_OUT     : in std_logic_vector(3 to 0) ;
       --Signal with pi
       Switch     : in std_logic_vector(3 to 0) 
    );
end TOP_module;

architecture Behavioral of TOP_module is
    constant CLK_FREQ    : natural := 50_000_000; -- 50 MHz clock
    constant SCLK_FREQ   : natural := 5_000_000;  -- 5 MHz SPI clock
    constant WORD_SIZE   : natural := 16;         -- MCP4921 requires 16 bits
    constant SLAVE_COUNT : natural := 2;          -- Two slaves (MCP4921)
    signal din       : std_logic_vector(WORD_SIZE-1 downto 0);
    signal din_vld_m   : std_logic;
    signal din_rdy_m   : std_logic;
    signal din_last  : std_logic;
    signal sclk_int  : std_logic;
    signal cs_n_int_DAC  : std_logic_vector(SLAVE_COUNT-1 downto 0);
    signal mosi_int_DAC  : std_logic;
    -- Signals for interfacing with the SPI_SLAVE module
    signal DIN_Data     : std_logic_vector(15 downto 0); -- 16 bits for received data
    signal DIN_VLD      : std_logic;
    signal DIN_RDY      : std_logic := '1';  -- Always ready to receive
    signal DOUT_Data    : std_logic_vector(15 downto 0); -- 16 bits for response
    signal DOUT_Data_part1 : std_logic_vector(15 downto 0);  -- First 16 bits
    signal DOUT_Data_part2 : std_logic_vector(15 downto 0);  -- Second 16 bits
    signal DOUT_Data_part3 : std_logic_vector(15 downto 0);  -- Third 16 bits
    signal DOUT_VLD     : std_logic;
    signal Timestamp_ms : std_logic_vector(31 downto 0);
    signal current_slave :  std_logic_vector(natural(ceil(log2(real(SLAVE_COUNT))))-1 downto 0):="0"; -- '0' for MCP4921 #1, '1' for MCP4921 #2
    constant IGNORE:std_logic := '0'; -- 0:use, 1:ignore
	constant BUFFERED:std_logic := '0'; -- 0 :unbuffered, 1:buffered
	constant GAIN:std_logic := '1'; -- 0:2X, 1:1X
	constant ACTIVE:std_logic := '1'; -- 0:shutdown, 1:active
    -- State encoding: IDLE = 00, PREPARING = 01, RUNNING = 10, STOPPED = 11
    type State_Type is (IDLE, PREPARING, RUNNING, STOPPED);
    signal current_state : State_Type := IDLE;
    signal next_state    : State_Type;
    
    -- Temporary signal to store the data received from the master
   -- Replace the large std_logic_vector with a BRAM-based storage
    type Data_Memory_pin1 is array (0 to 1999) of std_logic_vector(47 downto 0);  -- 182 * 32-bit blocks
    type Pinconfigs is array (0 to 7) of std_logic_vector(31 downto 0);  -- 182 * 32-bit blocks
    signal Pinconfig : Pinconfigs :=(others =>(others=>'0'));
    signal Data_BRAM : Data_Memory_pin1 := (others => (others => '0'));  -- BRAM array to store timestamp and GPIO data
    signal Data_temp2   : std_logic_vector(15 downto 0);
    signal temp_pointer : integer := 0;
  -- signal temp_pointer_reg : integer := 0; -- This will act as the register
    signal ms_counter : integer := 0;  -- Millisecond counter
    signal ms_trigger : std_logic := '0';  -- Trigger signal for 1 ms event
    signal read_pointer : integer := 0;
    -- Signals for detecting the "start" and "stop" commands
    signal state_bit1 : std_logic := '0'; -- Indicates if "start" has been received
    signal state_bit2  : std_logic := '0'; 
    
    -- Commands
    constant START_CMD    : std_logic_vector(15 downto 0) := x"0111001101110100"; -- ASCII for 'st'
    constant STOP_CMD     : std_logic_vector(15 downto 0) := "0111001001110011"; -- ASCII for 'rs'
    constant Last_CMD     : std_logic_vector(15 downto 0) := x"3030"; -- Final command

    -- Clocking Wizard signals
    signal clk_out1      : std_logic;  -- Generated clock from Clocking Wizard
    signal clk_out2      : std_logic;  -- Generated clock from Clocking Wizard
    signal clk_ms      : std_logic;  -- Generated clock from Clocking Wizard
    signal clk_locked    : std_logic;  -- Clock stable signal
    
    -- Assume the command format for GPIO and duration is "G2X10", where 'X' separates GPIO and duration
    constant GPIO_CMD_PREFIX : std_logic_vector(0 downto 0) := "0"; -- ASCII for 'G'01000111
    constant ADC_CMD_PREFIX : std_logic_vector(0 downto 0) := "1"; -- ASCII for 'P'01000001
    signal duration : integer := 0;  -- Store the duration in seconds
    signal capture_time : integer := 0; -- Time counter for capture duration
    signal type_selected : std_logic_vector(1 downto 0);  -- Signal to store selected GPIO pin
    signal pin_selected : std_logic_vector(1 downto 0);  -- Signal to store selected GPIO pin
    signal pin_type     : std_logic_vector(1 downto 0);  -- 2 bits for pin type (G, P, A)
    signal IN_OUT : std_logic_vector(1 downto 0);
    signal pin_number   : std_logic_vector(1 downto 0);  -- 2 bits for pin number (0, 1, 2, etc.)
    signal pin_value    : std_logic_vector(11 downto 0);  -- 12 bits for pin value (0-4095)
    signal send_part_state : integer := 0;  -- State for which part to send
    signal pinconfig_num : integer :=0;
    signal set_pin_state : integer :=0;
    signal start_stop : std_logic;
    signal mosi_int  : std_logic;

begin

 spi_slave_inst : entity work.SPI_SLAVE
    generic map (
        WORD_SIZE => 16  -- 16 bits for receiving and sending data
    )
    port map (
        CLK      => CLK,
        RST      => RST,
        SCLK     => S_SCLK,
        CS_N     => S_CS_N,
        MOSI     => S_MOSI,
        MISO     => S_MISO,
        DIN      => DOUT_Data,  -- Send response
        DIN_VLD  => '1',        -- Data valid signal for response
        DIN_RDY  => DIN_RDY,    -- Data ready signal for response
        DOUT     => DIN_Data,   -- Received data from master
        DOUT_VLD => DIN_VLD     -- Data valid signal for received data
    );

  -- SPI Master Instance
    spi_master_inst: entity work.SPI_MASTER
        generic map (
            CLK_FREQ    => CLK_FREQ,
            SCLK_FREQ   => SCLK_FREQ,
            WORD_SIZE   => WORD_SIZE,
            SLAVE_COUNT => SLAVE_COUNT
        )
        port map (
            CLK      => CLK,
            RST      => RST,
            SCLK     => sclk_int,
            CS_N     => M_CS_N,
            MOSI     => mosi_int_DAC,
            MISO     => '0', -- No response from MCP4921
            DIN      => din,
            DIN_ADDR => current_slave,  -- Concatenate 'current_slave' with '0'
            DIN_LAST => din_last,
            DIN_VLD  => din_vld,
            DIN_RDY  => din_rdy,
            DOUT     => open,
            DOUT_VLD => open
        );

        -- Timestamp entity
    Timestamp : entity work.Timestamp
    port map (
        clk         => CLK,
        reset       => RST,
        timestamp   => Timestamp_ms,
        clk_1ms     => clk_ms,
        start_stop  => start_stop
    );
    
   process (CLK, RST)
    begin
        if RST = '1' then
            state_bit1 <= '0';
            state_bit2 <= '0';
        elsif rising_edge(CLK) then
            if DIN_VLD = '1' then
                Data_temp2 <= DIN_Data;
                if Data_temp2 = START_CMD then
                    state_bit1 <= '1';
                    state_bit2 <= '0';
                elsif Data_temp2 = STOP_CMD then
                    state_bit1 <= '0';
                    state_bit2 <= '1';
                elsif Data_temp2 = Last_CMD then
                    state_bit1 <= '0';
                    state_bit2 <= '0';
                end if;
            end if;
        end if;
    end process;
  -- Process CLK managing state transitions
    process (CLK, RST)
    begin
        if RST = '1' then
            current_state <= IDLE; -- Start in IDLE state
        elsif rising_edge(CLK) then
            case current_state is
                when IDLE =>
                    if state_bit1 = '1' and state_bit2 = '0' then
                        next_state <= PREPARING;
                    elsif state_bit1 = '0' and state_bit2 = '1' then
                        next_state <= STOPPED;
                    else
                        next_state <= IDLE;
                    end if;

                when PREPARING =>
                    -- Transition to RUNNING when Switch1 is active
                    -- Parse the command for GPIO selection
                    if Switch(0) = '1' then
                        next_state <= RUNNING;
                    elsif state_bit1 = '0' and state_bit2 = '0' then
                        next_state <= IDLE;
                    else
                        next_state <= PREPARING;
                    end if;

                when RUNNING =>
                    if Switch(0) = '0' then
                        next_state <= STOPPED;
                    elsif state_bit1 = '0' and state_bit2 = '0' then
                        next_state <= IDLE;
                    else
                        next_state <= RUNNING; -- Stay in RUNNING
                    end if;

                when STOPPED =>
                    if state_bit1 = '0' and state_bit2 = '1' then
                        next_state <= STOPPED;
                    elsif state_bit1 = '0' and state_bit2 = '0' then
                        next_state <= IDLE; -- Return to IDLE after stopping
                    end if;

                when others =>
                    next_state <= IDLE; -- Default case to avoid latches
            end case;

            -- Update the current state
            current_state <= next_state;

        end if;
    end process;
  -- Process for managing DOUT based on the current state
process (CLK, RST)
begin
    if RST = '1' then
        DOUT_VLD <= '0'; -- No valid data initially
        temp_pointer <= 0; -- Reset the pointer
    elsif rising_edge(CLK) then
     -- Count up to 1 ms (assuming clk_ms is 1 MHz, i.e., 1 clock = 1 us)
        if ms_counter < 100000 then  -- 1000 clock cycles for 1 ms
            ms_counter <= ms_counter + 1;  -- Increment counter
        else
           ms_trigger <= '1';  -- Trigger the 1 ms event
           ms_counter <= 0;    -- Reset the counter for the next interval
        end if;
        case current_state is
            when IDLE =>
                --DOUT_VLD <= '1'; -- No valid data in IDLE
            when PREPARING =>
                 DOUT_VLD <= '1';   
                if DIN_VLD = '1'  then  -- Check for 'G' command
                if pinconfig_num <8 then
                    case set_pin_state is
                        when 0 =>
                            if Data_temp2(15) = '0' then
                                if Data_temp2(14)='0' then
                                    case Data_temp2(13 downto 12) is
                                    when "00" =>
                                         Pinconfig(pinconfig_num)(31)<= '0';
                                         Pinconfig(pinconfig_num)(30)<= '0';
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when "01" =>
                                         Pinconfig(pinconfig_num)(31)<= '0';
                                         Pinconfig(pinconfig_num)(30)<= '0';
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when "10" =>
                                         Pinconfig(pinconfig_num)(31)<= '0';
                                         Pinconfig(pinconfig_num)(30)<= '0';
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when "11" =>
                                         Pinconfig(pinconfig_num)(31)<= '0';
                                         Pinconfig(pinconfig_num)(30)<= '0';
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when others =>
                                        DOUT_Data <= x"726A"; -- Indicate PREPARING
                                    end case;    
                                elsif Data_temp2(14)='1' then
                                        case Data_temp2(13 downto 12) is
                                    when "00" =>
                                         Pinconfig(pinconfig_num)(31)<= Data_temp2(15);
                                         Pinconfig(pinconfig_num)(30)<= Data_temp2(14);
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when "01" =>
                                         Pinconfig(pinconfig_num)(31)<= Data_temp2(15);
                                         Pinconfig(pinconfig_num)(30)<= Data_temp2(14);
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when "10" =>
                                         Pinconfig(pinconfig_num)(31)<= Data_temp2(15);
                                         Pinconfig(pinconfig_num)(30)<= Data_temp2(14);
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when "11" =>
                                         Pinconfig(pinconfig_num)(31)<= Data_temp2(15);
                                         Pinconfig(pinconfig_num)(30)<= Data_temp2(14);
                                         Pinconfig(pinconfig_num)(29 downto 28)<= Data_temp2(13 downto 12);
                                         Pinconfig(pinconfig_num)(27 downto 16)<= Data_temp2(11 downto 0);
                                    when others =>
                                        DOUT_Data <= x"726A"; -- Indicate PREPARING
                                    end case;    
                                else
                                
                                end if;
                            elsif Data_temp2(15) = '1' then
                                Pinconfig(pinconfig_num)(15)<= '1';
                            else
                                DOUT_Data <= x"726A"; -- Indicate PREPARING
                            end if;
                            set_pin_state <= 1;  -- Move to next state to send the next part
                        when 1 =>
                            set_pin_state <= 0;  -- Move to next state to send the last par
                        when others =>
                            DOUT_Data <= (others => '0');  -- Default case
                    end case;
                        pinconfig_num <= pinconfig_num+1;
                    else 
                        DOUT_Data <= x"4675"; -- Indicate PREPARING
                    end if;
                end if;
             when RUNNING =>
              if ms_trigger = '1' then  -- Only execute logic every 1 ms
                    ms_trigger <= '0';  -- Reset the trigger
                if temp_pointer <= 1999 then  -- Adjusting for 48-bit data storage
                    -- Store selected GPIO status and Timestamp_ms
                    start_stop<='1';
                if type_selected = "01" then
                    -- Prepare pin type, number, and value based on GPIO selection
                    case pin_selected is
                        when "00" => 
                            pin_type <= "01";  -- GPIO type
                            pin_number <= "01"; -- GPIO1
                            pin_value <= "000000000000"; -- Assign GPIO1 value (Replace with actual value)
                        when "01" => 
                            pin_type <= "01";  -- PWM type
                            pin_number <= "10"; -- GPIO2
                            pin_value <=(11 downto 1 => '0', 0 => GPIO_OUT(0)) ; -- Assign GPIO2 value (Replace with actual value)
                        when others => 
                            pin_type <= "01";  -- Analog type (default)
                            pin_number <= "10"; -- GPIO3 (assuming you have at least 3 pins)
                            pin_value <= "XXXXXXXXXXXX"; -- Assign Analog value (Replace with actual value)
                    end case;

                    -- Store pin type, pin number, pin value, and timestamp into BRAM
                                              
                  Data_BRAM(temp_pointer)(47 downto 46) <= pin_type;
                  Data_BRAM(temp_pointer)(45 downto 44) <= pin_number;
                  Data_BRAM(temp_pointer)(43 downto 32) <= pin_value;
                  Data_BRAM(temp_pointer)(31 downto 0)  <= Timestamp_ms;
                    temp_pointer <= temp_pointer + 1;  -- Move to the next space in BRAM
                 elsif type_selected = "10" then
                    -- Prepare pin type, number, and value based on GPIO selection
                    case pin_selected is
                        when "00" => 
                            pin_type <= "00";  -- GPIO type
                            pin_number <= "00"; -- GPIO1
                            pin_value <= "XXXXXXXXXXXX"; -- Assign GPIO1 value (Replace with actual value)
                        when "01" => 
                            pin_type <= "01";  -- PWM type
                            pin_number <= "01"; -- GPIO2
                            pin_value <= "XXXXXXXXXXXX"; -- Assign GPIO2 value (Replace with actual value)
                        when others => 
                            pin_type <= "10";  -- Analog type (default)
                            pin_number <= "10"; -- GPIO3 (assuming you have at least 3 pins)
                            pin_value <= "XXXXXXXXXXXX"; -- Assign Analog value (Replace with actual value)
                    end case;

                    -- Store pin type, pin number, pin value, and timestamp into BRAM
                    Data_BRAM(temp_pointer) <= pin_type & pin_number & pin_value & Timestamp_ms;  -- Concatenate and store
                    temp_pointer <= temp_pointer + 1;  -- Move to the next space in BRAM
                  elsif type_selected = "11" then
                     -- Prepare pin type, number, and value based on GPIO selection
                    case pin_selected is
                        when "00" => 
                            pin_type <= "11";  -- GPIO type
                            pin_number <= "01"; -- GPIO1
                            pin_value <= "XXXXXXXXXXXX"; -- Assign GPIO1 value (Replace with actual value)
                        when "01" => 
                            pin_type <= "11";  -- PWM type
                            pin_number <= "01"; -- GPIO2
                            pin_value <= "XXXXXXXXXXXX"; -- Assign GPIO2 value (Replace with actual value)
                        when others => 
                            pin_type <= "11";  -- Analog type (default)
                            pin_number <= "10"; -- GPIO3 (assuming you have at least 3 pins)
                            pin_value <= "XXXXXXXXXXXX"; -- Assign Analog value (Replace with actual value)
                    end case;

                    -- Store pin type, pin number, pin value, and timestamp into BRAM
                    Data_BRAM(temp_pointer) <= pin_type & pin_number & pin_value & Timestamp_ms;  -- Concatenate and store
                    temp_pointer <= temp_pointer + 1;  -- Move to the next space in BRAM
                end if ;
                    -- Update the pointer to the next position
                    
                    --DOUT_Data <= x"7373"; -- Acknowledge data received
                    DOUT_VLD <= '1'; -- Indicate valid data to be sent
                else
                    --DOUT_Data <= x"0000"; -- Indicate storage is full or inactive
                    start_stop<='0';
                    DOUT_VLD <= '0'; -- No valid data to send 
                end if;
                end if;
    when STOPPED =>
                if DIN_VLD = '1' and Data_temp2 = STOP_CMD then  -- Check if STOP_CMD is received
                    --DOUT_VLD <= '1';  -- Indicate valid data to be sent
                    -- Data is sent sequentially in 16-bit chunks
                   if read_pointer <= temp_pointer then
                    -- Extract the 48-bit data from BRAM
                    -- Read data from BRAM
                    case send_part_state is
                        when 0 =>
                            DOUT_Data <= Data_BRAM(read_pointer)(47 downto 32);  -- Send first 16 bits
                            send_part_state <= 1;  -- Move to next state to send the next part
                        when 1 =>
                            DOUT_Data <= Data_BRAM(read_pointer)(31 downto 16);  -- Send second 16 bits
                            send_part_state <= 2;  -- Move to next state to send the last part
                        when 2 =>
                            DOUT_Data <= Data_BRAM(read_pointer)(15 downto 0);  -- Send third 16 bits
                            send_part_state <= 0;  -- Reset to first part for next cycle
                            read_pointer <= read_pointer + 1;  -- Move to the next data
                        when others =>
                            DOUT_Data <= (others => '0');  -- Default case
                    end case;

                    DOUT_VLD <= '1';  -- Indicate valid data being sent
                else
                    read_pointer <= 0;
                    temp_pointer<=0;
                    DOUT_Data<=x"726A";
                    DOUT_VLD <= '0'; -- No valid data to send if STOP_CMD is not received
                end if;
              end if;
            -- Handle unexpected states (optional)
            when others =>
                --DOUT_Data_temp <= x"3333";
                DOUT_VLD <= '0'; -- Default case
        end case;
    end if;
end process;    
    -- GPIO and LED outputs
end Behavioral;
