library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.MATH_REAL.ALL;
entity TOP_module is
Port (
        CLK       : in  std_logic;  -- System clock
        RST       : in  std_logic;  -- Reset signal
        --SPI_interface SLAVE
        S_MISO      : out  std_logic;  -- Slave to master data
        S_MOSI      : in std_logic;  -- Master to slave data
        S_SCLK      : in std_logic;  -- SPI clock
        S_CS_N      : in std_logic;  -- Chip select signal
        --INPUT_PIN
        GPIO_IN1     : out std_logic;
        GPIO_IN2     : out std_logic;
        --OUTPUT PIN
        GPIO_OUT1     : in std_logic;
        GPIO_OUT2     : in std_logic;
        GPIO_OUT3     : in std_logic;
        GPIO_OUT4     : in std_logic;
        GPIO_OUT5     : in std_logic;
        GPIO_OUT6     : in std_logic;
        GPIO_OUT7     : in std_logic;
        GPIO_OUT8     : in std_logic;
        PWM_OUT1     : in std_logic;
        PWM_OUT2     : in std_logic;
        PWM_OUT3     : in std_logic;
        PWM_OUT4     : in std_logic;
 
       --Signal with pi
       Switch1     : in std_logic;
       Switch2     : out std_logic;
       --State
       LED_State1 : out std_logic;
       LED_State2 : out std_logic;
       LED_State3 : out std_logic;
       LED_GPIO1 : out std_logic;
       LED_GPIO2 : out std_logic;
       LED_GPIO3 : out std_logic;
       LED_GPIO4 : out std_logic;
       LED_GPIO5 : out std_logic;
       LED_GPIO6 : out std_logic;
       LED_GPIO7 : out std_logic;
       LED_GPIO8 : out std_logic
    );
end TOP_module;

architecture Behavioral of TOP_module is
    
    -- Signals for interfacing with the SPI_SLAVE module
    signal DIN_Data     : std_logic_vector(15 downto 0); -- 16 bits for received data
    signal DIN_VLD      : std_logic;
    signal DIN_RDY      : std_logic := '1';  -- Always ready to receive
    signal DOUT_Data    : std_logic_vector(15 downto 0); -- 16 bits for response
    signal Timestamp_ms : std_logic_vector(15 downto 0);
    signal input_Timestamp : std_logic_vector(15 downto 0);
    -- State encoding: IDLE = 00, PREPARING = 01, RUNNING = 10, STOPPED = 11
    type State_Type is (IDLE, PREPARING, RUNNING, STOPPED);
    signal current_state : State_Type := IDLE;
    signal next_state    : State_Type;
    
    -- Temporary signal to store the data received from the master
   -- Replace the large std_logic_vector with a BRAM-based storage
    type Data_Memory_OUTPUT is array (0 to 11,0 to 39) of std_logic_vector(31 downto 0);  -- 182 * 32-bit blocks
    type Data_sendout is array (0 to 479) of std_logic_vector(31 downto 0);
    type temp_pointers is array (0 to 11) of integer range 0 to 40;
    type input_pointer is array (0 to 1) of integer range 0 to 20;
    type PINCONFIG is array (0 to 7) of std_logic_vector(3 downto 0);  -- 182 * 32-bit blocks
    type input_config is array(0 to 1,0 to 19) of std_logic_vector(14 downto 0);
    signal OUTPUTS : PINCONFIG :=(others =>(others=>'0'));
    signal INPUT : input_config := (others =>(others =>(others => '0')));
    signal Data_BRAM_OUTPUTS : Data_Memory_OUTPUT := (others => (others => (others => '1')));  -- BRAM array to store timestamp and GPIO1 data
    signal Data_BRAM : Data_sendout := (others => (others => '0'));  -- BRAM array to store timestamp and GPIO data
    signal Data_temp2   : std_logic_vector(15 downto 0);
    signal input_pointers : input_pointer := (others => 0);
    signal read_input_pointers : input_pointer := (others => 0);
    signal temp_pointer : integer range 0 to 480 := 0;
    signal temp_pointer_s : temp_pointers :=(others => 0); 
    signal read_pointer : integer range 0 to 480 := 0;
    signal Capture_sucess : boolean := false;
    
    -- Signals for detecting the "start" and "stop" commands
    signal state_bit1 : std_logic := '0'; -- Indicates if "start" has been received
    signal state_bit2  : std_logic := '0'; 
    
    -- Commands
    constant START_CMD    : std_logic_vector(15 downto 0) := x"7374"; -- ASCII for 'st'
    constant STOP_CMD     : std_logic_vector(15 downto 0) := x"7265"; -- ASCII for 'rest'
    constant Last_CMD     : std_logic_vector(15 downto 0) := x"3030"; -- Final command

    -- Clocking Wizard signals
    signal clk_ms      : std_logic;  -- Generated clock from Clocking Wizard
    
    -- Assume the command format for GPIO and duration is "G2X10", where 'X' separates GPIO and duration   
    signal send_part_state : std_logic:= '0';  -- State for which part to send
    signal output_num : integer range 0 to 8 :=0;
    signal output_num_use : integer range 0 to 8 :=0;
    signal start_stop : std_logic;
    signal signal_in_GPIO : std_logic_vector(11 downto 0) :=(others=>'0'); -- Delayed version of signal_in
    signal current_GPIO : std_logic_vector(11 downto 0) :=(others=>'0'); -- Delayed version of signal_in
    signal previous_GPIO : std_logic_vector(11 downto 0) :=(others=>'0'); -- Delayed version of signal_in
    signal cap_sucess : std_logic_vector(11 downto 0) :=(others=>'0');
  
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
                elsif Data_temp2 = LAST_CMD then
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
                LED_State1<='1';
                LED_State2<='0';
                LED_State3<='0';
                    if state_bit1 = '1' and state_bit2 = '0' then
                        next_state <= PREPARING;
                    else
                        next_state <= IDLE;
                    end if;

                when PREPARING =>
                LED_State1<='0';
                LED_State2<='1';
                LED_State3<='0';
                
                    -- Transition to RUNNING when Switch1 is active
                    -- Parse the command for GPIO selection
                    if Switch1 = '1'and  DOUT_Data = x"636D" then
                        next_state <= RUNNING;
                    else
                        next_state <= PREPARING;
                    end if;

                when RUNNING =>
                LED_State1<='0';
                LED_State2<='0';
                LED_State3<='1';
                
                    if Capture_sucess = true then
                        next_state <= STOPPED;
                    elsif state_bit1 = '0' and state_bit2 = '0' then
                        next_state <= IDLE;
                    else
                        next_state <= RUNNING; -- Stay in RUNNING
                    end if;

                when STOPPED =>
                LED_State1<='1';
                LED_State2<='0';
                LED_State3<='1';
                    if state_bit1 = '0' and state_bit2 = '0' then
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
        temp_pointer <= 0; -- Reset the pointer
    elsif rising_edge(CLK) then
     -- Count up to 1 ms (assuming clk_ms is 1 MHz, i.e., 1 clock = 1 us)
        case current_state is
            when IDLE =>
                cap_sucess<=(others=>'0');
                read_pointer <= 0;
                temp_pointer<=0;
                output_num<=0;
                output_num_use<=0;
                temp_pointer_s <=(others => 0); 
                if Data_temp2 = START_CMD then    
                            DOUT_Data <= x"3032";      
                end if;
            when PREPARING =>
                if DIN_VLD = '1'  then  -- Check for 'G' command       
                if Data_temp2 = x"7373"then
                    DOUT_Data<=x"636D";
                end if;       
                if output_num < 8 then
                    if Data_temp2(15 downto 8) =x"47" then
                        case Data_temp2(7 downto 0) is 
                            when x"31" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="000";
                                 output_num_use<=output_num_use+1;
                            when x"32" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="001";
                                output_num_use<=output_num_use+1;
                            when x"33" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="010";

                                output_num_use<=output_num_use+1;
                            when x"34" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="011";

                                  output_num_use<=output_num_use+1;
                            when x"35" =>
                                OUTPUTS(output_num)(3)<='0';
                               OUTPUTS(output_num)(2 downto 0)<="100";

                                  output_num_use<=output_num_use+1;
                            when x"36" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="101";

                                 output_num_use<=output_num_use+1;
                            when x"37" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="110";
  
                                  output_num_use<=output_num_use+1;
                            when x"38" =>
                                OUTPUTS(output_num)(3)<='0';
                                OUTPUTS(output_num)(2 downto 0)<="111";
                                output_num_use<=output_num_use+1;       
                            when others =>
                            OUTPUTS(output_num)<="1111";                           
                         end case;
                         output_num<=output_num+1;
                    elsif Data_temp2(15 downto 8) =x"50" then
    
                        case Data_temp2(7 downto 0) is 
                            when x"31" =>
                             OUTPUTS(output_num)(3)<='1';
                             OUTPUTS(output_num)(2 downto 0)<="000";
                       
                             output_num_use<=output_num_use+1;
                            when x"32" =>
                             OUTPUTS(output_num)(3)<='1';
                             OUTPUTS(output_num)(2 downto 0)<="001";
                      
                            output_num_use<=output_num_use+1;
                            when x"33" =>
                             OUTPUTS(output_num)(3)<='1';
                            OUTPUTS(output_num)(2 downto 0)<="010";
                        
                            output_num_use<=output_num_use+1;
                            when x"34" =>
                             OUTPUTS(output_num)(3)<='1';
                            OUTPUTS(output_num)(2 downto 0)<="011";
                 
                            output_num_use<=output_num_use+1;
                            when others =>
                            OUTPUTS(output_num)<="1111";
                         end case;
                         output_num<=output_num+1;
                     elsif Data_temp2 = START_CMD then    
                      DOUT_Data <= x"0000";  
                      else 
                    end if;
                    else  
                    if input_pointers(1)>19 and input_pointers(0)>19 then
                        DOUT_Data <= x"636D";  
                    elsif Data_temp2(15) = '0' then
                        case Data_temp2(14) is
                        when '0'=>
                            INPUT(0,input_pointers(0))(14)<='1';
                            INPUT(0,input_pointers(0))(13 downto 0)<= Data_temp2(13 downto 0);
                            input_pointers(0)<=input_pointers(0)+1;
                        when '1'=>
                            INPUT(1,input_pointers(0))(14)<='1';
                            INPUT(1,input_pointers(1))<= Data_temp2(13 downto 0);
                            input_pointers(1)<=input_pointers(1)+1;
                        when others=>
                        end case;
                    else
                        case Data_temp2(14) is
                        when '0'=>
                            INPUT(0,input_pointers(0))(14)<='0';
                            INPUT(0,input_pointers(0))(13 downto 0)<= (others => '0');
                            input_pointers(0)<=input_pointers(0)+1;
                        when '1'=>
                        INPUT(1,input_pointers(0))(14)<='0';
                            INPUT(1,input_pointers(1))<=(others => '0');
                            input_pointers(1)<=input_pointers(1)+1;
                        when others=>
                        end case;
                    end if;
    
                  end if;
                 else 
                 end if;
             when RUNNING =>
                     if output_num_use > 0 then  -- Adjusting for 48-bit data storage  
                     start_stop<='1';
                      Capture_sucess<=false;
                      if  input_pointers(1)>read_input_pointers(1) or input_pointers(0)>read_input_pointers(0) then
                        for i in 0 to 1 loop
                            if INPUT(i,read_input_pointers(i))(14)='1' then
                                input_Timestamp(15 downto 13)<="000";
                                input_Timestamp(12 downto 0)<= INPUT(i,read_input_pointers(i))(12 downto 0);
                                if input_Timestamp = Timestamp_ms and i = 0 then    
                                   GPIO_IN1<= INPUT(i,read_input_pointers(i))(13);
                                   read_input_pointers(i)<=read_input_pointers(i)+1;
                                elsif input_Timestamp = Timestamp_ms and i = 1 then
                                   GPIO_IN2<= INPUT(i,read_input_pointers(i))(13);
                                   read_input_pointers(i)<=read_input_pointers(i)+1;
                                  
                                end if;
                            else
                                read_input_pointers(i)<=read_input_pointers(i)+1;
                            end if;
                        end loop;
                      end if;
                         for i in 0 to 7 loop
                            if OUTPUTS(i)(3)='0' then
                              if    OUTPUTS(i)(2 downto 0)="000" then
                                if temp_pointer_s(0) <= 39 then
                                        signal_in_GPIO(0)<=GPIO_OUT1; 
                                        current_GPIO(0)<=signal_in_GPIO(0);
                                        if current_GPIO(0) /= previous_GPIO(0)  then
                                           LED_GPIO1<=current_GPIO(0);
                                           previous_GPIO(0)<= current_GPIO(0);
                                           Data_BRAM_OUTPUTS(0,temp_pointer_s(0))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(0,temp_pointer_s(0))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(0,temp_pointer_s(0))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(0));
                                           Data_BRAM_OUTPUTS(0,temp_pointer_s(0))(15 downto 0)<= Timestamp_ms;   
                                           temp_pointer_s(0)<= temp_pointer_s(0)+1;  
                                        end if;
                                  else
                                  if cap_sucess(0) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(0)<='1';
                                  end if;
                                 end if;
                                elsif OUTPUTS(i)(2 downto 0)="001" then
                                 if temp_pointer_s(1) <=39 then
                                        signal_in_GPIO(1)<=GPIO_OUT2; 
                                        current_GPIO(1)<=signal_in_GPIO(1);
                                        if current_GPIO(1) /= previous_GPIO(1)  then
                                           LED_GPIO2<=current_GPIO(1);
                                           previous_GPIO(1)<= current_GPIO(1);
                                           Data_BRAM_OUTPUTS(1,temp_pointer_s(1))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(1,temp_pointer_s(1))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(1,temp_pointer_s(1))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(1));
                                           Data_BRAM_OUTPUTS(1,temp_pointer_s(1))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(1)<= temp_pointer_s(1)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(1) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(1)<='1';
                                   end if;
                                  end if;
                                  elsif OUTPUTS(i)(2 downto 0)="010" then
                                 if temp_pointer_s(2) <=39 then
                                        signal_in_GPIO(2)<=GPIO_OUT3; 
                                        current_GPIO(2)<=signal_in_GPIO(2);
                                        if current_GPIO(2) /= previous_GPIO(2)  then
                                           LED_GPIO3<=current_GPIO(2);
                                           previous_GPIO(2)<= current_GPIO(2);
                                           Data_BRAM_OUTPUTS(2,temp_pointer_s(2))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(2,temp_pointer_s(2))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(2,temp_pointer_s(2))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(2));
                                           Data_BRAM_OUTPUTS(2,temp_pointer_s(2))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(2)<= temp_pointer_s(2)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(2) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(2)<='1';
                                   end if;
                                  end if;
                                  elsif OUTPUTS(i)(2 downto 0)="011" then
                                 if temp_pointer_s(3) <=39 then
                                        signal_in_GPIO(3)<=GPIO_OUT4; 
                                        current_GPIO(3)<=signal_in_GPIO(3);
                                        if current_GPIO(3) /= previous_GPIO(3)  then
                                           LED_GPIO4<=current_GPIO(3);
                                           previous_GPIO(3)<= current_GPIO(3);
                                           Data_BRAM_OUTPUTS(3,temp_pointer_s(3))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(3,temp_pointer_s(3))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(3,temp_pointer_s(3))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(3));
                                           Data_BRAM_OUTPUTS(3,temp_pointer_s(3))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(3)<= temp_pointer_s(3)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(3) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(3)<='1';
                                   end if;
                                  end if;
                                  elsif OUTPUTS(i)(2 downto 0)="100" then
                                 if temp_pointer_s(4) <=39 then
                                        signal_in_GPIO(4)<=GPIO_OUT5; 
                                        current_GPIO(4)<=signal_in_GPIO(4);
                                        if current_GPIO(4) /= previous_GPIO(4)  then
                                           LED_GPIO5<=current_GPIO(4);
                                           previous_GPIO(4)<= current_GPIO(4);
                                           Data_BRAM_OUTPUTS(4,temp_pointer_s(4))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(4,temp_pointer_s(4))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(4,temp_pointer_s(4))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(4));
                                           Data_BRAM_OUTPUTS(4,temp_pointer_s(4))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(4)<= temp_pointer_s(4)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(4) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(4)<='1';
                                   end if;
                                  end if;
                                 elsif OUTPUTS(i)(2 downto 0)="101" then
                                 if temp_pointer_s(5) <=39 then
                                        signal_in_GPIO(5)<=GPIO_OUT6; 
                                        current_GPIO(5)<=signal_in_GPIO(5);
                                        if current_GPIO(5) /= previous_GPIO(5)  then
                                           LED_GPIO6<=current_GPIO(5);
                                           previous_GPIO(5)<= current_GPIO(5);
                                           Data_BRAM_OUTPUTS(5,temp_pointer_s(5))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(5,temp_pointer_s(5))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(5,temp_pointer_s(5))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(5));
                                           Data_BRAM_OUTPUTS(5,temp_pointer_s(5))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(5)<= temp_pointer_s(5)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(5) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(5)<='1';
                                   end if;
                                  end if;
                                   elsif OUTPUTS(i)(2 downto 0)="110" then
                                 if temp_pointer_s(6) <=39 then
                                        signal_in_GPIO(6)<=GPIO_OUT7; 
                                        current_GPIO(6)<=signal_in_GPIO(6);
                                        if current_GPIO(6) /= previous_GPIO(6)  then
                                           LED_GPIO7<=current_GPIO(6);
                                           previous_GPIO(6)<= current_GPIO(6);
                                           Data_BRAM_OUTPUTS(6,temp_pointer_s(6))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(6,temp_pointer_s(6))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(6,temp_pointer_s(6))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(6));
                                           Data_BRAM_OUTPUTS(6,temp_pointer_s(6))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(6)<= temp_pointer_s(6)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(6) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(6)<='1';
                                   end if;
                                  end if;
                                   elsif OUTPUTS(i)(2 downto 0)="111" then
                                 if temp_pointer_s(7) <=39 then
                                        signal_in_GPIO(7)<=GPIO_OUT8; 
                                        current_GPIO(7)<=signal_in_GPIO(7);
                                        if current_GPIO(7) /= previous_GPIO(7)  then
                                           LED_GPIO8<=current_GPIO(7);
                                           previous_GPIO(7)<= current_GPIO(7);
                                           Data_BRAM_OUTPUTS(7,temp_pointer_s(7))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(7,temp_pointer_s(7))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(7,temp_pointer_s(7))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(7));
                                           Data_BRAM_OUTPUTS(7,temp_pointer_s(7))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(7)<= temp_pointer_s(7)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(7) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(7)<='1';
                                   end if;
                                  end if;   
                                end if;
                                elsif OUTPUTS(i)(3)='1' then
                                if    OUTPUTS(i)(2 downto 0)="000" then
                                  if temp_pointer_s(8) <= 39 then
                                        signal_in_GPIO(8)<=PWM_OUT1; 
                                        current_GPIO(8)<=signal_in_GPIO(8);
                                        if current_GPIO(8) /= previous_GPIO(8)  then
                                           previous_GPIO(8)<= current_GPIO(8);
                                           Data_BRAM_OUTPUTS(8,temp_pointer_s(8))(31)<='1';
                                           Data_BRAM_OUTPUTS(8,temp_pointer_s(8))(30 downto 28)<="000";
                                           Data_BRAM_OUTPUTS(8,temp_pointer_s(8))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(8));
                                           Data_BRAM_OUTPUTS(8,temp_pointer_s(8))(15 downto 0)<= Timestamp_ms;   
                                           temp_pointer_s(8)<= temp_pointer_s(8)+1;  
                                        end if;
                                  else
                                    if cap_sucess(8) = '0' then
                                        output_num_use<=output_num_use-1;
                                        cap_sucess(8)<='1';
                                    end if;
                                  end if;
                                  elsif OUTPUTS(i)(2 downto 0)="001" then
                                 if temp_pointer_s(9) <=39 then
                                        signal_in_GPIO(9)<=PWM_OUT2; 
                                        current_GPIO(9)<=signal_in_GPIO(9);
                                        if current_GPIO(9) /= previous_GPIO(9)  then                                        
                                           previous_GPIO(9)<= current_GPIO(9);
                                           Data_BRAM_OUTPUTS(9,temp_pointer_s(9))(31)<='1';
                                           Data_BRAM_OUTPUTS(9,temp_pointer_s(9))(30 downto 28)<="001";
                                           Data_BRAM_OUTPUTS(9,temp_pointer_s(9))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(9));
                                           Data_BRAM_OUTPUTS(9,temp_pointer_s(9))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(9)<= temp_pointer_s(9)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(9) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(9)<='1';
                                   end if;
                                  end if;   
                                  elsif OUTPUTS(i)(2 downto 0)="010" then
                                 if temp_pointer_s(10) <=39 then
                                        signal_in_GPIO(10)<=PWM_OUT3; 
                                        current_GPIO(10)<=signal_in_GPIO(10);
                                        if current_GPIO(10) /= previous_GPIO(10)  then                                        
                                           previous_GPIO(10)<=current_GPIO(10);
                                           Data_BRAM_OUTPUTS(10,temp_pointer_s(10))(31)<=OUTPUTS(i)(3);
                                           Data_BRAM_OUTPUTS(10,temp_pointer_s(10))(30 downto 28)<=OUTPUTS(i)(2 downto 0);
                                           Data_BRAM_OUTPUTS(10,temp_pointer_s(10))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(10));
                                           Data_BRAM_OUTPUTS(10,temp_pointer_s(10))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(10)<= temp_pointer_s(10)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(10) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(10)<='1';
                                   end if;
                                  end if; 
                                  elsif OUTPUTS(i)(2 downto 0)="011" then
                                 if temp_pointer_s(11) <=39 then
                                        signal_in_GPIO(11)<=PWM_OUT4; 
                                        current_GPIO(11)<=signal_in_GPIO(11);
                                        if current_GPIO(11) /= previous_GPIO(11)  then
                                           LED_GPIO8 <= current_GPIO(11);  
                                           previous_GPIO(11) <= current_GPIO(11);
                                           Data_BRAM_OUTPUTS(11,temp_pointer_s(11))(31)<='1';
                                           Data_BRAM_OUTPUTS(11,temp_pointer_s(11))(30 downto 28)<="011";
                                           Data_BRAM_OUTPUTS(11,temp_pointer_s(11))(27 downto 16)<=(11 downto 1 => '0', 0 => previous_GPIO(11));
                                           Data_BRAM_OUTPUTS(11,temp_pointer_s(11))(15 downto 0)<= Timestamp_ms;        
                                           temp_pointer_s(11)<= temp_pointer_s(11)+1; 
                                        else
                                        end if;
                                  else
                                   if cap_sucess(11) = '0' then
                                    output_num_use<=output_num_use-1;
                                    cap_sucess(11)<='1';
                                   end if;
                                  end if;     
                              end if;
                            else
                            end if;
                       end loop; 
                else
                --cassssssss
                start_stop<='0';
                Capture_sucess<=true;
                end if;
    when STOPPED =>        
           if temp_pointer <= 479 then   
                  Switch2<='1';  
                  for i in 0 to 39 loop
                      Data_BRAM(12*i)<=Data_BRAM_OUTPUTS(0,i);
                      Data_BRAM((12*i)+1)<=Data_BRAM_OUTPUTS(1,i);
                      Data_BRAM((12*i)+2)<=Data_BRAM_OUTPUTS(2,i);
                      Data_BRAM((12*i)+3)<=Data_BRAM_OUTPUTS(3,i);
                      Data_BRAM((12*i)+4)<=Data_BRAM_OUTPUTS(4,i);
                      Data_BRAM((12*i)+5)<=Data_BRAM_OUTPUTS(5,i);
                      Data_BRAM((12*i)+6)<=Data_BRAM_OUTPUTS(6,i);
                      Data_BRAM((12*i)+7)<=Data_BRAM_OUTPUTS(7,i);
                      Data_BRAM((12*i)+8)<=Data_BRAM_OUTPUTS(8,i);
                      Data_BRAM((12*i)+9)<=Data_BRAM_OUTPUTS(9,i);
                      Data_BRAM((12*i)+10)<=Data_BRAM_OUTPUTS(10,i);
                      Data_BRAM((12*i)+11)<=Data_BRAM_OUTPUTS(11,i);
                      temp_pointer<=temp_pointer+12;
                  end loop;      
              else  
                  
              if DIN_VLD = '1' and Data_temp2 = STOP_CMD then  -- Check if STOP_CMD is received
                  if read_pointer < temp_pointer then    
                    case send_part_state is
                        when '0' =>
                            DOUT_Data <=  Data_BRAM(read_pointer)(31 downto 16);  -- Send first 16 bits
                            send_part_state <= '1';  -- Move to next state to send the next part
                        when '1' => 
                            DOUT_Data <=   Data_BRAM(read_pointer)(15 downto 0);  -- Send second 16 bits
                            send_part_state <= '0';  -- Reset to first part for next cycle
                            read_pointer <= read_pointer + 1;  -- Move to the next data      
                        when others =>
                           -- DOUT_Data <= (others => '1');  -- Default case
                    end case;
                else             
                    Switch2<='0';
                    DOUT_Data<=x"726A";
                    
                end if;
              end if;
           end if;
     when others =>
                DOUT_Data <= x"3333";
        end case;
    end if;
end process;  
end Behavioral;
