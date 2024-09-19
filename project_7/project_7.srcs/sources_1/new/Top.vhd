library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    Port (
        CLK      : in  std_logic;       -- system clock
        RST      : in  std_logic;       -- high active synchronous reset
        -- SPI Interface
        SCLK     : in  std_logic;
        CS_N     : in  std_logic;
        MOSI     : in  std_logic;
        MISO     : out std_logic;
        LED1     : out std_logic;
        LED2     : out std_logic;
        LED3     : out std_logic
    );
end entity;

architecture Behavioral of TOP is

    -- Signals for interfacing with the SPI_SLAVE module
    signal DIN_Data     : std_logic_vector(15 downto 0); -- 16 bits for received data
    signal DIN_VLD      : std_logic;
    signal DIN_RDY      : std_logic := '1';  -- Always ready to receive
    signal DOUT_Data    : std_logic_vector(15 downto 0); -- 16 bits for response
    signal DOUT_VLD     : std_logic;

    -- Temporary signal to store the data received from the master
    signal Data_temp    : std_logic_vector(6000 downto 0);
    signal Data_temp2    : std_logic_vector(15 downto 0);
    signal temp_pointer : integer := 0;
    
    -- Signals for detecting the "start" command
    signal start_received : std_logic := '0'; -- Indicates if "start" has been received
    signal byte_counter   : integer := 0; -- Counter for how many parts of "start" are received

    -- Define the 16-bit chunks of the "start" signal       0111001001110100
    constant START_CMD1 : std_logic_vector(15 downto 0) := "0111001101110100"; -- ASCII for 'st'
    constant START_CMD2 : std_logic_vector(15 downto 0) := "0110000101110010"; -- ASCII for 'ar'
    constant START_CMD3 : std_logic_vector(15 downto 0) := "0111010000000000"; -- ASCII for 't' (padded with zeroes)

    -- Clocking Wizard signals
    signal clk_out      : std_logic;  -- Generated clock from Clocking Wizard
    signal clk_locked   : std_logic;  -- Clock stable signal

begin

    -- Instantiate the Clocking Wizard
    clk_wiz_inst : entity work.clk_wiz_0
    port map (
        clk_in1    => CLK,        -- Basys3's 100 MHz clock input
        reset      => RST,        -- Reset input
        clk_out1   => clk_out,    -- Output clock (e.g., 50 MHz)
        locked     => clk_locked  -- Clock locked signal
    );
    
    -- Instantiate the SPI_SLAVE module with 16-bit word size
    spi_slave_inst : entity work.SPI_SLAVE
    generic map (
        WORD_SIZE => 16  -- 16 bits for receiving and sending data
    )
    port map (
        CLK      => clk_out,
        RST      => RST,
        SCLK     => SCLK,
        CS_N     => CS_N,
        MOSI     => MOSI,
        MISO     => MISO,
        DIN      => DOUT_Data,  -- Send response
        DIN_VLD  => '1',   -- Data valid signal for response
        DIN_RDY  => DIN_RDY,    -- Data ready signal for response
        DOUT     => DIN_Data,   -- Received data from master
        DOUT_VLD => DIN_VLD     -- Data valid signal for received data
    );

    -- Process for handling received data and detecting the "start" command
    process (clk_out, RST)
    begin
        if RST = '1' then
            DOUT_Data <= (others => '0');
            DOUT_VLD <= '0'; -- No valid data initially
            Data_temp <= (others => '0'); -- Clear the temporary data storage
            temp_pointer <= 0;  -- Reset the pointer
            start_received <= '0'; -- Reset start received flag
            byte_counter <= 0;  -- Reset the byte counter
        elsif rising_edge(clk_out) then
            if DIN_VLD = '1' then
                -- Check if the "start" command has been received
                    -- Check each part of the "start" sequence
                    Data_temp2 <= DIN_Data;
                    case byte_counter is
                        when 0 =>
                            if Data_temp2 = START_CMD1 then
                                byte_counter <= 1; -- Proceed to check the next part of "start"
                                LED1 <= '1';
                            else
                                DOUT_Data <= "1111111111111110"; -- Send an error response
                                LED1 <= '1';
                                LED2 <= '0';
                                LED3 <= '1';
                            end if;
                        when 1 =>
                            if Data_temp2 = START_CMD2 then
                                byte_counter <= 2; -- Proceed to check the final part of "start"
                                DOUT_Data <= "0110000101110010"; -- Acknowledge the start
                                LED2 <= '1';
                            else
                                byte_counter <= 0; -- Reset if wrong data received
                                LED1 <= '0';
                                LED2 <= '1';
                                LED3 <= '0';
                                DOUT_Data <=DIN_Data;
                            end if;
                        when 2 =>
                            if Data_temp2 = START_CMD3 then
                                LED3 <= '1'; -- Full "start" command received
                                DOUT_Data <= "0111010000000000"; -- Acknowledge the start
                                
                            else
                                byte_counter <= 0; -- Reset if wrong data received
                                LED1 <= '0';
                                LED2 <= '1';
                                LED3 <= '1';
                                DOUT_Data <=DIN_Data;
                            end if;
                        when others =>
                              LED1 <= '0';
                              LED2 <= '0';
                              LED3 <= '0';
                              DOUT_Data <= "0000000000000001";
                              byte_counter <= 0;
                              DOUT_Data <=DIN_Data;
                    end case;
                DOUT_VLD <= '1'; -- Indicate valid data to be sent
            else
                DOUT_VLD <= '0'; -- Deassert the DOUT_VLD signal if no valid data
            end if;
        end if;
    end process;
end Behavioral;
