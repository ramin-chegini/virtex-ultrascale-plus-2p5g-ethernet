-- Layer-2 command decoder and 64-to-8-bit payload receive bridge.
-- Parsing uses the existing fixed word layout and local destination MAC match;
-- this block is not a general IP/UDP parser. See docs/PROTOCOL.md for details.
library ieee;
use ieee.std_logic_1164.all ;
use ieee.std_logic_arith.all ;
use ieee.std_logic_unsigned.all ;
use ieee.std_logic_misc.all ;
library unisim;
use unisim.vcomponents.all;
use ieee.numeric_std;
--use work.Reg_pack.ALL;
use work.DF_pack.ALL;
--use work.SEK7_pack.ALL;
use  work.Reg_pack_comint.ALL;

entity tri_mode_ethernet_mac_v5_5_0_rx is
generic (
      DEST_ADDR                  : bit_vector(47 downto 0) := X"5a0102030405"
      
   );
   port (
    axi_tclk                        : in  std_logic;
    axi_treset                     : in  std_logic;
    
    -- data from the RX FIFO
    rx_axis_fifo_tdata              : in  std_logic_vector(63 downto 0);
    rx_axis_fifo_tkeep              : in  std_logic_vector(7 downto 0);
    rx_axis_fifo_tvalid             : in  std_logic;
    rx_axis_fifo_tlast              : in  std_logic;
    rx_axis_fifo_tready             : out std_logic;
  
    data_len                        : out std_logic_vector(15 downto 0) ;
    rd_data_count                   : out std_logic_vector(11 downto 0) ;
    rx_data                         : out std_logic_vector(7 downto 0) ;
    rx_rd_en                        : in std_logic;
    rx_data_ready                   : out std_logic;
    rx_clk                          : in std_logic;

    Soft_Cmd_CODE               : out  std_logic_vector(15 downto 0);
    Soft_Cmd_length             : out  std_logic_vector(15 downto 0);
    Soft_CMD_wr_en              : out  std_logic;
    Soft_CMD_clk                : out  std_logic;
    
    TRM_clk                      : out std_logic; 
    WR_TRM                      : out std_logic; 
    TRM_Addr                    : out std_logic_vector(7 downto 0) ; 
    TRM_Data                    : out std_logic_vector(63 downto 0) ;  
                                 
    RD_Reg                      : out std_logic; 
    WR_Reg                      : out std_logic; 
    Reg_Addr                    : out std_logic_vector(7 downto 0) ; 
    Reg_Data                    : out std_logic_vector(63 downto 0)                          
    
  );
end tri_mode_ethernet_mac_v5_5_0_rx;
 
architecture rtl of tri_mode_ethernet_mac_v5_5_0_rx is
    type wr_state_typ is    (IDLE_W,      
                            WRITE_HEADER, 
                            WRITE_SIZE,  
                            WRITE_HEADER2,
                            WRITE_CODE,
                            WRITE, 
                            WRITE_FOOTER);
                            
 COMPONENT Receiver_DATA_RAM
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END COMPONENT;                                

----------
 signal RX_wea   :  STD_LOGIC_VECTOR(0 DOWNTO 0);
 signal RX_addra :  STD_LOGIC_VECTOR(10 DOWNTO 0);
 signal RX_dina  :  STD_LOGIC_VECTOR(7 DOWNTO 0);
-- signal TX_addrb :  STD_LOGIC_VECTOR(10 DOWNTO 0);
-- signal TX_doutb :  STD_LOGIC_VECTOR(7 DOWNTO 0);
----------
   signal next_wr_state             : wr_state_typ;
   signal wr_state                  : wr_state_typ;

   signal rx_axis_fifo_tvalid_reg,rx_axis_fifo_tvalid_reg2   : std_logic;
   signal rx_axis_fifo_tlast_reg    : std_logic;
   signal wr_count                  : std_logic_vector(15 downto 0);
   signal fifo_full                 : std_logic;

--   signal wr_slot                   : unsigned(2 downto 0);
--   signal wr_addr                   : unsigned(2 downto 0);
--   signal dia                       : std_logic_vector(8 downto 0);
--   signal doa                       : std_logic_vector(8 downto 0);
--   signal wea                       : std_logic;

   signal Pack_Size                  : std_logic_vector(15 downto 0);
   signal probe1                  : std_logic_vector(47 downto 0);
   signal probe4                  : std_logic_vector(0 downto 0);
   signal probe5                  : std_logic_vector(0 downto 0);
   signal probe6                  : std_logic_vector(0 downto 0);
   signal probe1_rx_pat                  : std_logic_vector(0 downto 0);
   signal probe2_rx_pat                  : std_logic_vector(0 downto 0);
   signal probe3_rx_pat                  : std_logic_vector(0 downto 0);
   signal probe4_rx_pat                  : std_logic_vector(0 downto 0);
   signal probe2_code                  : std_logic_vector(0 downto 0);
   signal probe3_code                  : std_logic_vector(0 downto 0);
   signal rx_axis_fifo_tready_int   : std_logic;
   
   signal new_packet_start         : std_logic;
   signal rd_count_2               : std_logic;
   signal rd_count_4               : std_logic;
   signal rd_count_6               : std_logic;
   signal rd_count_8               : std_logic;
   signal rd_count_10              : std_logic;
   signal wr_data_count            : std_logic_vector(8 downto 0);
   signal wr_data ,wr_data_reg     : std_logic_vector(63 downto 0);
   signal Reg_Addr_c               : std_logic_vector(7 downto 0);
   signal fifo_data                : std_logic_vector(7 downto 0);
   signal wr_data_fifo             : std_logic_vector(63 downto 0);
   signal read_state_cap           : std_logic_vector(3 downto 0);
   signal write_state_cap          : std_logic_vector(3 downto 0);
   signal empty                 : std_logic;
   signal full                  : std_logic;
   signal almost_full           : std_logic;
   signal wr_en                 : std_logic;
   signal reg_cmd                 : std_logic;
   signal CODE       : std_logic_vector(15 downto 0);
   signal register_data       : std_logic_vector(71 downto 0);
   signal WR_Reg_c,RD_Reg_c ,WR_TRM_c      : std_logic;
   signal MAC_ADDR                  : std_logic_vector (47 downto 0) ;
   constant DATA_CODE           : std_logic_vector(15 downto 0) := HPR_ID & X"81";
   constant WR_REG_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"82";
   constant RD_REG_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"83";
   constant WR_TRM_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"84";
   constant RD_TRM_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"85";
   attribute Mark_debug : string;
   attribute keep : string;
--   attribute mark_debug of RX_addra,RX_wea,RX_dina     : signal is "true"; 
--   attribute mark_debug of wr_data_count, full, wr_en     : signal is "true"; 
--   attribute mark_debug of write_state_cap     : signal is "true"; 
   attribute mark_debug of wr_count     : signal is "true"; 
   attribute mark_debug of Pack_Size     : signal is "true"; 
   attribute mark_debug of wr_data,wr_data_fifo  , fifo_data   ,rx_data_ready  : signal is "true"; 
--   attribute mark_debug of register_data     : signal is "true"; 
--   attribute mark_debug of RD_Reg_c , WR_Reg_c , reg_cmd      : signal is "true"; 
--   attribute mark_debug of wr_state      : signal is "true"; 
   attribute mark_debug of CODE      : signal is "true"; 
   
   signal state_test    : std_logic_vector(2 downto 0);
   
begin
   TRM_clk <= axi_tclk;
   Soft_CMD_clk <= axi_tclk;
   rx_axis_fifo_tready <= rx_axis_fifo_tready_int;
   rx_axis_fifo_tready_int <= '0' when fifo_full = '1' else '1';
   --Soft_CMD_clk <= axi_tclk ;
 -- Convert MAC byte lanes to the parser's most-significant-byte-first words.
 -- This two-register path is paired with the delayed valid/last controls below.
 process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then  
            wr_data_reg(63 downto 56) <= rx_axis_fifo_tdata(7  downto 0);     
            wr_data_reg(55 downto 48) <= rx_axis_fifo_tdata(15 downto 8);     
            wr_data_reg(47 downto 40) <= rx_axis_fifo_tdata(23 downto 16);     
            wr_data_reg(39 downto 32) <= rx_axis_fifo_tdata(31 downto 24); 
            wr_data_reg(31 downto 24) <= rx_axis_fifo_tdata(39 downto 32); 
            wr_data_reg(23 downto 16) <= rx_axis_fifo_tdata(47 downto 40); 
            wr_data_reg(15 downto 8)  <= rx_axis_fifo_tdata(55 downto 48); 
            wr_data_reg(7  downto 0)  <= rx_axis_fifo_tdata(63 downto 56); 
            
            wr_data <= wr_data_reg;    
      end if;
   end process;

       wr_state_cap_p : process(wr_state)
                     begin
                        case wr_state is
                           when IDLE_W =>
                                 write_state_cap <= (others => '0');
                          when WRITE_HEADER =>
                                write_state_cap <= x"1";
                          when WRITE_SIZE =>
                                write_state_cap <= x"2";
                          when WRITE_HEADER2 =>
                                 write_state_cap <= x"3";
                          when WRITE_CODE =>
                                 write_state_cap <= x"4";
                          when WRITE =>
                                 write_state_cap <= x"5";
                          when WRITE_FOOTER =>
                                 write_state_cap <= x"6";
                          when others =>
                                write_state_cap <= x"7";
              end case;
        end process; 
        
       rx_data <= fifo_data;
   -- Asynchronous 64-bit write / 8-bit read FIFO. Its almost-full flag applies
   -- backpressure to the MAC FIFO; rd_data_count is in the external read domain.
   DATA_OUT_FIFO :entity work.Data_Receiver_FIFO_orihard
    PORT MAP (
      rst => axi_treset,
      wr_clk => axi_tclk,
      rd_clk => rx_clk,
      din => wr_data_fifo,
      wr_en => wr_en,
      rd_en => rx_rd_en,
      dout => fifo_data,
      full => full,
      almost_full => fifo_full,

      empty => OPEN,
      almost_empty => empty,
      rd_data_count => rd_data_count,
      wr_data_count => wr_data_count
    );
--instance_rx_pat : entity work.ila_fifo_rx_pat
-- PORT MAP (
--	clk => axi_tclk,

--	probe0 => wr_data_fifo, 
--	probe1(0) => wr_en,    
--	probe2(0) => rx_rd_en,  
--	probe3(0) => fifo_full, 
--	probe4(0) => axi_treset,
--	probe5 => wr_data_count,
--	probe6 => wr_data_count
--);  
--    rx_data_ready <=not empty;
    
-- Receiver_DATA_RAM_U0 : Receiver_DATA_RAM
--  PORT MAP (
--    clka    => axi_tclk,
--    wea     => RX_wea,
--    addra   => RX_addra,
--    dina    => RX_dina,
    
--    clkb    => rx_clk,
--    addrb   => rx_addr,
--    doutb   => rx_data
--  );
    
--    RX_wea <= Conv_std_logic_vector(wr_en,1);
    
    
   -- capture a new packet starting as we only want to start taking it once the read side is idle
   new_pkt_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then
        
         if axi_treset = '1' then
            new_packet_start <= '0';
--         elsif (wr_state = IDLE_W and rx_axis_fifo_tvalid = '1' and rx_axis_fifo_tvalid_reg = '0') or (wr_state = IDLE_W and rx_axis_fifo_tvalid = '1' and rx_axis_fifo_tlast_reg = '1') then
         elsif (wr_state = IDLE_W and rx_axis_fifo_tvalid = '1' and rx_axis_fifo_tvalid_reg = '0')  then
            new_packet_start <= '1';
         elsif  wr_state /= IDLE_W then
            new_packet_start <= '0';
         end if;
      end if;
   end process new_pkt_p;

   -- Write interface
   reg_axi_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         rx_axis_fifo_tvalid_reg <= rx_axis_fifo_tvalid;
         rx_axis_fifo_tvalid_reg2 <= rx_axis_fifo_tvalid_reg;
         rx_axis_fifo_tlast_reg <= rx_axis_fifo_tlast;
      end if;
   end process reg_axi_p;

   -- simple write state machine
   next_wr_s : process(Pack_Size,wr_state, rx_axis_fifo_tlast_reg,  wr_count, rx_axis_fifo_tlast, 
                        new_packet_start)
   begin
      next_wr_state <= wr_state;
      case wr_state is
         -- detect a rising edge on TVALID OR TLAST on previous cycle AND TVALID
         when IDLE_W =>
--            state_test <= "000";
            if (new_packet_start = '1')  then
               next_wr_state <= WRITE_HEADER;
            end if;
         when WRITE_HEADER =>
--            state_test <= "001";
            if wr_count = 8 and rx_axis_fifo_tvalid_reg = '1' then
               next_wr_state <= WRITE;
            elsif rx_axis_fifo_tlast_reg = '1' and rx_axis_fifo_tvalid_reg = '1' then
               next_wr_state <= IDLE_W;
            end if;
         when WRITE =>
--            state_test <= "010";
            if ((wr_count - X"08") >= Pack_Size) then
                next_wr_state <= WRITE_FOOTER;
            elsif rx_axis_fifo_tlast_reg = '1' and rx_axis_fifo_tvalid_reg = '1' then
               next_wr_state <= IDLE_W; 
            end if;
         when WRITE_FOOTER =>
            if ((wr_count- X"10" ) >= Pack_Size) then
--            state_test <= "011";   
                next_wr_state <= IDLE_W;
            elsif (rx_axis_fifo_tlast_reg = '1' and rx_axis_fifo_tvalid_reg = '1')  then
               next_wr_state <= IDLE_W;
            end if;
        when others =>
--            state_test <= "111";
            next_wr_state <= IDLE_W;      
      end case;
   end process;
   
   wr_state_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if axi_treset = '1' then
            wr_state <= IDLE_W;
         else
            wr_state <= next_wr_state;
         end if;
      end if;
   end process wr_state_p;

   
  --load packet size  
  -- Size and command are the final four bytes of the second 64-bit header word.
  Pack_Size_p : process (axi_tclk)
  begin
     if axi_tclk'event and axi_tclk = '1' then
        if axi_treset = '1' then
           Pack_Size <= (others => '0');
           CODE <= (others => '0');
        elsif (wr_state = WRITE_HEADER ) then
            Pack_Size <= wr_data_reg(31 downto 16);
            CODE      <= wr_data_reg(15 downto 0);
        end if;
     end if;
  end process Pack_Size_p;
--load data code  
--  data_code_p : process (axi_tclk)
--  begin
--     if axi_tclk'event and axi_tclk = '1' then
--        if axi_treset = '1' then
--           CODE <= (others => '0');
--        elsif ( wr_state = WRITE_CODE ) then
--           CODE <= CODE(7 downto 0) & wr_data;     
--        end if;
--     end if;
--  end process data_code_p; 
  
--load MAC ADDR  
MAC_addr_p : process (axi_tclk)
 begin
    if axi_tclk'event and axi_tclk = '1' then
       if axi_treset = '1' then
          MAC_ADDR               <= (others => '0');
       elsif (wr_count = 8) then
          MAC_ADDR <=  wr_data(63 downto 16) ;  
      --  elsif (wr_state = WRITE_Header and wr_count = 16) then
      --     MAC_ADDR(15 downto 0)  <=  wr_data(31 downto 16) ;               
       end if;
    end if;
end process MAC_addr_p; 
  

reg_data_wr_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then  
         
         WR_Reg   <= WR_Reg_c; 
         RD_Reg   <= RD_Reg_c; 
         Reg_Data <= register_data(63 downto 0);
         Reg_Addr <= Reg_Addr_c; 
         
         WR_TRM   <= WR_TRM_c; 
         TRM_Addr <= Reg_Addr_c; 
         TRM_Data <= register_data(63 downto 0);

         if axi_treset = '1'  then
                register_data <= (others => '0');
                Reg_Addr_c      <= (others => '0');
         elsif (wr_count = 24) then
                Reg_Addr_c                 <= wr_data(63 downto 56);     
                register_data(63 downto 8) <= wr_data(55 downto 0);    
         elsif ( wr_count = 32) then
                register_data(7 downto 0)  <= wr_data(63 downto 56);                            
         end if;
      end if;
end process reg_data_wr_p;  
--   Reg_Data <= register_data(63 downto 0);-- when CODE = WR_REG_CODE else (others => 'Z');
--   TRM_Data <= register_data(63 downto 0);-- when CODE = WR_TRM_CODE else (others => 'Z');
   --Reg_Addr <= register_data(71 downto 64);
   
  
   -- generate a write count to control where the data is written
   wr_count_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if axi_treset = '1' then
            wr_count <= (others => '0');
         else 
            if  (wr_state = IDLE_W and next_wr_state = WRITE_HEADER)  then
               wr_count <= X"0008";
            elsif wr_state /= IDLE_W and rx_axis_fifo_tvalid_reg = '1'  then
               wr_count <= wr_count + X"8";
            elsif next_wr_state = IDLE_W  then
               wr_count <= (others => '0');    
            end if;
         end if;
      end if;
   end process wr_count_p;

   -- generate a write enable 
   -- rx_data_ready reports completion (or the full condition) in axi_tclk.
   -- It is not a persistent indication that the byte FIFO contains unread data.
   wr_en_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         
         if axi_treset = '1' then
             wr_en <= '0';
             rx_data_ready <= '0';
             wr_data_fifo <= (others =>'0');
             data_len <= (others =>'0');
         else 
                wr_data_fifo <= wr_data_reg;
                if MAC_ADDR = To_StdLogicVector(DEST_ADDR) then
                    if (wr_state = WRITE  and CODE = DATA_CODE) then
                       wr_en <= '1';
                       rx_data_ready <= '0';
                       data_len <= Pack_Size;
                    elsif (wr_state = WRITE_FOOTER and CODE = DATA_CODE) or fifo_full = '1'  then
                       wr_en <= '0';
                       rx_data_ready <= '1';
                    elsif (wr_state = IDLE_W) then
                       wr_en <= '0';
                       rx_data_ready <= '0';
                    else
                       rx_data_ready <= '0';
                    end if;
                else
                    wr_en <= '0';
                    rx_data_ready <= '0';
--                    wr_data_fifo <= (others =>'0');
                end if;
         end if;
      end if;
   end process wr_en_p;
     
   reg_wr_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then   
         if axi_treset = '1' then
             reg_cmd <= '0';
             WR_Reg_c <= '0';
             RD_Reg_c <= '0';
         else 
             if MAC_ADDR = To_StdLogicVector(DEST_ADDR) then
                if (wr_state = WRITE_FOOTER and next_wr_state = IDLE_W )  then
                    if CODE = WR_REG_CODE then
                        WR_Reg_c <= '1';
                    elsif CODE = RD_REG_CODE then
                        RD_Reg_c <= '1';
                    end if;
                    reg_cmd <= '0';
                else
                   reg_cmd <= '0';
                   WR_Reg_c <= '0';
                   RD_Reg_c <= '0';
                end if;
            else 
              reg_cmd <= '0';
              WR_Reg_c <= '0';
              RD_Reg_c <= '0';
            end if;
         end if;
      end if;
   end process reg_wr_p;

-- A remote register read queues a 0x0040-length response for the TX engine.
code_wr_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then   
         if axi_treset = '1' then
            Soft_Cmd_CODE <= (others=> '0');
            Soft_Cmd_length <= (others=> '0');
            Soft_CMD_wr_en <= '0';
         elsif (MAC_ADDR = To_StdLogicVector(DEST_ADDR) and wr_state = WRITE_FOOTER and next_wr_state = IDLE_W and (CODE = RD_REG_CODE )) then
            Soft_Cmd_CODE   <= CODE;
            Soft_Cmd_length <= x"0040";
            Soft_CMD_wr_en <= '1';
         else
            Soft_CMD_wr_en <= '0';
        end if;
     end if;
end process  code_wr_p;


   TRM_reg_wr_p : process (axi_tclk)
begin
   if axi_tclk'event and axi_tclk = '1' then   
      if axi_treset = '1' then
          WR_TRM_c <= '0';
      else 
          if MAC_ADDR = To_StdLogicVector(DEST_ADDR) then
             if (wr_state = Write_FOOTER and next_wr_state = IDLE_W )  then
                 if CODE = WR_TRM_CODE then
                     WR_TRM_c <= '1';
                 end if;
             else
                WR_TRM_c <= '0';
             end if;
         else 
           WR_TRM_c <= '0';
         end if;
      end if;
   end if;
end process TRM_reg_wr_p;
  
--comint_rx : entity work.ila_3
--PORT MAP (
--	clk => axi_tclk,

--	probe0    => MAC_ADDR, 
--	probe1    => write_state_cap(2 downto 0), 
--	probe2    => wr_count, 
--	probe3    => wr_data, 
--	probe4(0) => WR_Reg_c,            
--	probe5(0) => rx_axis_fifo_tvalid,
--	probe6    => register_data,        
--	probe7    => Pack_Size,        
--	probe8    => CODE,         
--	probe9(0) => wr_en,         
--	probe10(0)=> rx_axis_fifo_tlast,         
--	probe11   => Reg_Addr_c ,        
--	probe12   => rx_axis_fifo_tkeep         
--);   
----probe1 <= CONV_STD_LOGIC_VECTOR(DEST_ADDR,48);
--probe4(0) <= rx_rd_en; 
--probe5(0) <= rx_axis_fifo_tvalid;
--probe6(0) <= axi_treset;
   

--instance_ila_code : entity work.ila_code
--PORT MAP (
--	clk => axi_tclk,

--	probe0 => Pack_Size, 
--	probe1 => CODE, 
--	probe2 => probe2_code, 
--	probe3 => probe3_code, 
--	probe4 => state_test,
--	probe5 => register_data
--);

--probe2_code(0) <= WR_Reg_c;
--probe3_code(0) <= rx_axis_fifo_tlast_reg;
   
end rtl;






