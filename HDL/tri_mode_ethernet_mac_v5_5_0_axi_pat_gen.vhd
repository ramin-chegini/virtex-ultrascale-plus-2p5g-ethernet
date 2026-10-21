-- Command-driven Layer-2 frame transmitter with asynchronous input queues.
-- The active interface accepts complete 64-bit words; TKEEP is always x"FF".
-- Shared protocol constants come from external Reg_pack_comint/DF_pack packages.
library ieee;
use ieee.std_logic_1164.all ;
use ieee.std_logic_arith.all ;
use ieee.std_logic_unsigned.all ;
use ieee.std_logic_misc.all ;
library unisim;
use unisim.vcomponents.all;
use ieee.numeric_std;
use work.Reg_pack_comint.ALL;
use work.DF_pack.ALL;
--use work.SEK7_pack.ALL;

entity tri_mode_ethernet_mac_v5_5_0_axi_pat_gen is
   generic (
      DEST_ADDR            : bit_vector(47 downto 0) ;
      SRC_ADDR             : bit_vector(47 downto 0) := X"5a0102030405";
      MAX_SIZE             : std_logic_vector(15 downto 0) := X"2100";
      
      MIN_SIZE             : std_logic_vector(15 downto 0) := X"0040";
      ENABLE_VLAN          : boolean := false;
      VLAN_ID              : bit_vector(11 downto 0) := X"002";
      VLAN_PRIORITY        : bit_vector(2 downto 0) := "010"
   );
   port (
      axi_tclk             : in  std_logic;
      axi_treset          : in  std_logic;
      Soft_reset          : in  std_logic;
      speed                : in  std_logic_vector(1 downto 0);
      speed_value                : in  std_logic_vector(7 downto 0);
--      stat_tx_packet_small  : in std_logic ;
--      stat_tx_packet_large  : in std_logic;
--      stat_tx_unicast       : in std_logic;
--      stat_tx_multicast     : in std_logic;
--      stat_tx_broadcast     : in std_logic;
--      stat_tx_vlan          : in std_logic;
--      stat_tx_frame_error   : in std_logic;
      wr_ready                : out  std_logic;
      wr_clk                  : in  std_logic;
      wr_en                   : in  std_logic;
      wr_last                   : in  std_logic;
      wr_data                 : in std_logic_vector(63 downto 0);

      CMD_CODE                :   in std_logic_vector(15 downto 0);
      CMD_length              :   in std_logic_vector(15 downto 0);
--      CMD_clk                 :   in std_logic;                     
      CMD_en                  :   in std_logic; 

      Soft_CMD_CODE                :   in std_logic_vector(15 downto 0);
      Soft_CMD_length              :   in std_logic_vector(15 downto 0);
      Soft_CMD_clk                 :   in std_logic;                     
      Soft_CMD_en                  :   in std_logic; 
       
      RD_REG                  : in  std_logic;
      Reg_Addr                : in std_logic_vector(7 downto 0) ; 
      Reg_Data                : in std_logic_vector(63 downto 0) ; 
       
      TRM_clk                 : in  std_logic;
      RD_TRM                  : in  std_logic;
      TRM_Addr                : in std_logic_vector(7 downto 0) ; 
      TRM_Data                : in std_logic_vector(63 downto 0) ;       
--
      tdata_t                 : out std_logic_vector(63 downto 0);
      tkeep_t                 : out std_logic_vector(7 downto 0);
      tvalid_t                : out std_logic;
      tlast_t                 : out std_logic;
      tready                  : in  std_logic                   
   );
end tri_mode_ethernet_mac_v5_5_0_axi_pat_gen;

architecture rtl of tri_mode_ethernet_mac_v5_5_0_axi_pat_gen is

COMPONENT fifo_generator_4DB_2
  PORT (
    rst : IN STD_LOGIC;
    wr_clk : IN STD_LOGIC;
    rd_clk : IN STD_LOGIC;
    din : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    wr_en : IN STD_LOGIC;
    rd_en : IN STD_LOGIC;
    dout : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    full : OUT STD_LOGIC;
    almost_full : OUT STD_LOGIC;
    empty : OUT STD_LOGIC;
    almost_empty : OUT STD_LOGIC;
    rd_data_count : OUT STD_LOGIC_VECTOR(14 DOWNTO 0);
    wr_data_count : OUT STD_LOGIC_VECTOR(14 DOWNTO 0);
    wr_rst_busy : OUT STD_LOGIC;
    rd_rst_busy : OUT STD_LOGIC 
  );
END COMPONENT;
   -- State machine
   type state_typ is    (IDLE,
                         HEADER,
                         HEADER2,
                         CODE,
                         SIZE,
                         SET_DATA,
                         FOOTER,
                         OVERHEAD);

   function Sel (Cond : boolean; A,B : integer) return integer is
     begin
         if Cond then 
            return A;
         else
            return B;
         end if;
   end function Sel;


   -- work out the adjustment required to get the right packet size.               
   constant PKT_ADJUST        : integer := Sel(ENABLE_VLAN,22,18);

   -- generate the vlan fields
   constant VLAN_HEADER       : bit_vector(31 downto 0) := X"8100" & VLAN_PRIORITY & '0' & VLAN_ID;

   -- generate the require header count compare
   constant HEADER_LENGTH     : integer := Sel(ENABLE_VLAN,15,15);

   -- generate the required bandwidth controls based on speed
   -- we want to use less than 100% bandwidth to avoid loopback overflow 
   constant BW_1G             : integer := 230;
   constant BW_100M           : integer := 23;
   constant BW_10M            : integer := 2;

   signal next_gen_state      : state_typ;
   signal gen_state           : state_typ;

--   signal byte_count          : unsigned(11 downto 0);
   signal byte_count          : STD_LOGIC_VECTOR(15 downto 0);
   signal header_count        : STD_LOGIC_VECTOR(3 downto 0);
   signal footer_count        : STD_LOGIC_VECTOR(3 downto 0);
   signal overhead_count      : STD_LOGIC_VECTOR(4 downto 0);
   signal pkt_size            : STD_LOGIC_VECTOR(15 downto 0);
   signal lut_data,lut_data_int            : std_logic_vector(63 downto 0);
   signal tvalid_int          : std_logic;
   
   -- rate control signals
   signal basic_rc_counter    : STD_LOGIC_VECTOR(7 downto 0);
   signal add_credit          : std_logic;
   signal credit_count        : STD_LOGIC_VECTOR(12 downto 0);

   signal treset          : std_logic;
   
   constant dummy               : bit_vector(47 downto 0) := (others => '0');
   
   signal TRIG0       : std_logic_vector(15 downto 0);
   signal TRIG1       : std_logic_vector(15 downto 0);
   signal TRIG2       : std_logic_vector(15 downto 0);
   signal TRIG3       : std_logic_vector(15 downto 0);
   signal TRIG4       : std_logic_vector(15 downto 0);
   signal TRIG5       : std_logic_vector(15 downto 0);
   signal TRIG6       : std_logic_vector(15 downto 0);
   signal TRIG7       : std_logic_vector(31 downto 0);
   signal TRIG8       : std_logic_vector(31 downto 0);
   signal probe0       : std_logic_vector(0 downto 0);
   signal probe1       : std_logic_vector(0 downto 0);
   signal probe2       : std_logic_vector(0 downto 0);
   signal probe6       : std_logic_vector(0 downto 0);
   signal probe7       : std_logic_vector(0 downto 0);
   signal probe8       : std_logic_vector(0 downto 0);
   signal probe5       : STD_LOGIC_VECTOR(63 DOWNTO 0); 
   signal rd_data_count         : std_logic_vector(14 downto 0);
   signal CONTROL0              : std_logic_vector(35 downto 0);
   signal wr_data_count         : std_logic_vector(14 downto 0);
   signal Blank_count         : std_logic_vector(15 downto 0);
   signal dout                  : std_logic_vector(63 downto 0);
   signal empty                 : std_logic;
   signal full                  : std_logic;
   signal almost_full           : std_logic;
   signal rd_en                 : std_logic;

   constant FOOTER_CODE         : std_logic_vector(15 downto 0) := X"0016" ;
--   constant DATA_CODE           : std_logic_vector(15 downto 0) := X"0001" or HDR_ID;
   constant WR_REG_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"82";
   constant RD_REG_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"83";
   constant WR_TRM_CODE         : std_logic_vector(15 downto 0) := HPR_ID & X"84";
    
    signal Working_signal        : std_logic;
    signal REG_tx                : std_logic;
    signal DATA_tx                : std_logic;
    signal tlast                : std_logic;
    signal tvalid               : std_logic;
    signal tdata                : std_logic_vector(63 downto 0);
    signal tkeep                : std_logic_vector(3 downto 0);
    signal state_cap            : std_logic_vector(3 downto 0);
    signal next_state_cap       : std_logic_vector(3 downto 0);
    signal Reg_Data_R           : std_logic_vector(63 downto 0);
    signal Reg_Addr_R           : std_logic_vector(7 downto 0);
    signal Cmd_FIFO_dout           : std_logic_vector(15 downto 0);
    signal Soft_Cmd_FIFO_dout           : std_logic_vector(15 downto 0);
    signal TRM_Cmd_FIFO_dout           : std_logic_vector(15 downto 0);
    signal Length_FIFO_dout           : std_logic_vector(15 downto 0);
    signal Soft_Length_FIFO_dout           : std_logic_vector(15 downto 0);
    signal TRM_Length_FIFO_dout           : std_logic_vector(15 downto 0);
    signal CMD_count           : std_logic_vector(4 downto 0);
    signal Soft_CMD_count           : std_logic_vector(4 downto 0);
    signal TRM_CMD_count           : std_logic_vector(4 downto 0);
    signal register_data_fifo_dout           : std_logic_vector(31 downto 0);
    signal register_data_fifo_din           : std_logic_vector(63 downto 0);
    signal TRM_register           : std_logic_vector(63 downto 0);
    signal TRM_Addr_R           : std_logic_vector(7 downto 0);
    
    signal almost_full_DataFifo, empty_DataFifo : std_logic;
    signal CMD_rd_en : std_logic;
    signal Soft_CMD_rd_en : std_logic;
    signal TRM_CMD_rd_en , TRM_CMD_rd_en_d : std_logic;
    signal RD_REG_d : std_logic;
    signal transfer_end : std_logic;
    signal Cmd_CODE_reg     : std_logic_vector(15 downto 0);
    signal Length_CODE_reg  : std_logic_vector(15 downto 0);
    signal transfer_start : std_logic;
    signal Read_CMD_FIFO,Read_CMD_FIFO_d : std_logic;
    signal Read_TRM_CMD_FIFO,Read_TRM_CMD_FIFO_d : std_logic;
    signal Soft_Read_CMD_FIFO,Soft_Read_CMD_FIFO_d : std_logic;
    signal WR_REG_en : std_logic;
    signal CMD_rd_en_FIFO,CMD_rd_en_d : std_logic;
    signal Soft_CMD_rd_en_FIFO,Soft_CMD_rd_en_d : std_logic;
    signal overflow       : STD_LOGIC_VECTOR(15 downto 0);
    signal Rd_ready, AUTO_RST ,wr_en_latch: std_logic;
    signal count_wclk,count_rclk         : std_logic_vector(32 downto 0);
    signal Counter_arr :STD_LOGIC_VECTOR(63 downto 0);
    signal douta_Head :STD_LOGIC_VECTOR(127 downto 0) := x"ffffffffffff0011_0a6c4aa908060001";
    signal douta :STD_LOGIC_VECTOR(63 downto 0) ;
    signal parity : STD_LOGIC_VECTOR(2 downto 0);
    -- Actual transmitted addresses are fixed here: broadcast DA, local SA.
    -- Changing DEST_ADDR/SRC_ADDR generics alone does not change this header.
    constant MAC_Header : std_logic_vector(95 downto 0) := x"FFFFFFFFFFFF5A0102030405";
    signal almost_full_ch1  : std_logic;
    signal almost_empty_ch1 : std_logic;
    constant WR_TRM_CODE1         : std_logic_vector(15 downto 0) := X"0040";   
begin
 --
-- Inst_blk_mem_TRM_MacAddr :entity  work.blk_mem_TRM_MacAddr
--  PORT MAP (
--    clka => axi_tclk,
--    addra(0) => header_count(0),
--    douta => douta
--  );
 
 tlast_t   <=  tlast ; 
 tvalid_t  <=  tvalid;
 tdata_t   <=  tdata;
 tvalid    <=  tvalid_int;
 -- Reverse byte lanes for MAC transmission. Beat 1 carries SA[15:0], size
 -- and command; the literal OR mask below sets bit 7 of the size high byte.
 -- Preserve this wire-format detail when implementing a host-side decoder.
 tdata     <=   ----------------------------first 8Byte
                lut_data(7 downto 0)&lut_data(15 downto 8)&lut_data(23 downto 16)&lut_data(31 downto 24) &
                lut_data(39 downto 32)&lut_data(47 downto 40)&lut_data(55 downto 48)&lut_data(63 downto 56)  when (header_count = 0 ) else
--               ----------------------------second 8Byte
                ((Cmd_CODE_reg(7 downto 0) & Cmd_CODE_reg(15 downto 8) & pkt_size(7 downto 0) & pkt_size(15 downto 8))or(x"00000080")) &
                lut_data(39 downto 32)&lut_data(47 downto 40)&lut_data(55 downto 48)&lut_data(63 downto 56)  when (header_count = 1 ) else
                ----------------------------last 8Byte
                (x"000000000000" & FOOTER_CODE(7 downto 0) & FOOTER_CODE(15 downto 8)  )       when (header_count = 3) else  
                ----------------------------reg bytes
                Reg_Data_R(23 downto 16) & Reg_Data_R(31 downto 24) & Reg_Data_R(39 downto 32) & Reg_Data_R(47 downto 40)  &
                Reg_Data_R(55 downto 48) & Reg_Data_R(63 downto 56)& Reg_Addr_R & x"00"        when (Cmd_CODE_reg = RD_REG_CODE and byte_count=x"010") else 
              
                x"000000000000" & Reg_Data_R(7 downto 0) & Reg_Data_R(15 downto 8)             when (Cmd_CODE_reg = RD_REG_CODE and byte_count=x"008") else 
                ----------------------------Terminals bytes
                (TRM_register(23 downto 16) & TRM_register(31 downto 24) & TRM_register(39 downto 32) & TRM_register(47 downto 40))  &  
                (TRM_register(55 downto 48) & TRM_register(63 downto 56) & TRM_Addr_R & x"00" ) when (Cmd_CODE_reg = WR_TRM_CODE and byte_count=x"010") else 
                (x"000000000000" & TRM_register(7 downto 0) & TRM_register(15 downto 8))              when (Cmd_CODE_reg = WR_TRM_CODE and byte_count=x"008") else                
               ----------------------------Data bytes
                dout(7 downto 0)&dout(15 downto 8)&dout(23 downto 16)&dout(31 downto 24) & 
                dout(39 downto 32)&dout(47 downto 40)&dout(55 downto 48)&dout(63 downto 56);
                 
-- tkeep_t   <=  x"03" when (header_count = 3) else x"FF" ; 
 -- Footer is a full eight-byte beat: 0x0016 marker followed by six zero bytes
 -- in wire order. Payload lengths must follow the existing eight-byte alignment.
 tkeep_t   <=  x"FF" ; 
 tlast <=  '1' when  (header_count = 3) else '0' ;                 
 rd_en <= tready when ((Cmd_CODE_reg /= RD_REG_CODE ) and (Cmd_CODE_reg /= WR_TRM_CODE ) and (header_count =1 or (header_count =2 and byte_count > x"000"))) else 
          '1' when treset = '1' else
          '0';
          
 treset <= axi_treset or Soft_reset ;


 command_FIFO :entity work.fifo_generator_v9_3_1_orihard
  PORT MAP (
    rst => treset,
    wr_clk => wr_clk,
    rd_clk => axi_tclk,
    din => CMD_CODE,
    wr_en => CMD_en,
    rd_en => CMD_rd_en,
    dout => Cmd_FIFO_dout,
    full => open,
    empty => open,
    rd_data_count => CMD_count,
    wr_data_count => open
  ); 

   length_FIFO :entity work.fifo_generator_v9_3_1_orihard
   PORT MAP (
     rst => treset,
     wr_clk => wr_clk,
     rd_clk => axi_tclk,
     din => CMD_length,
     wr_en => CMD_en,
     rd_en => CMD_rd_en,
     dout => Length_FIFO_dout,
     full => open,
     empty => open,
     rd_data_count => open,
     wr_data_count => open
   );
   Soft_command_FIFO :entity work.fifo_generator_v9_3_1_orihard
    PORT MAP (
      rst => treset,
      wr_clk => Soft_CMD_clk,
      rd_clk => axi_tclk,
      din => Soft_CMD_CODE,
      wr_en => RD_REG,
      rd_en => Soft_CMD_rd_en,
      dout => Soft_Cmd_FIFO_dout,
      full => open,
      empty => open,
      rd_data_count => Soft_CMD_count,
      wr_data_count => open
    ); 
  
     Soft_length_FIFO :entity work.fifo_generator_v9_3_1_orihard
     PORT MAP (
       rst => treset,
       wr_clk => Soft_CMD_clk,
       rd_clk => axi_tclk,
       din => Soft_CMD_length,
       wr_en => RD_REG,
       rd_en => Soft_CMD_rd_en,
       dout => Soft_Length_FIFO_dout,
       full => open,
       empty => open,
       rd_data_count => open,
       wr_data_count => open
     );    
   
  TRM_command_FIFO :entity work.fifo_generator_v9_3_1_orihard
      PORT MAP (
        rst => treset,
        wr_clk => TRM_clk,
        rd_clk => axi_tclk,
        din    => WR_TRM_CODE,
        wr_en => RD_TRM,
        rd_en => TRM_CMD_rd_en,
        dout => TRM_Cmd_FIFO_dout,
        full => open,
        empty => open,
        rd_data_count => TRM_CMD_count,
        wr_data_count => open
      ); 
    
       TRM_length_FIFO :entity work.fifo_generator_v9_3_1_orihard
       PORT MAP (
         rst => treset,
         wr_clk => TRM_clk,
         rd_clk => axi_tclk,
         din => WR_TRM_CODE1,
--         din => x"0040",
         wr_en => RD_TRM,
         rd_en => TRM_CMD_rd_en,
         dout => TRM_Length_FIFO_dout,
         full => open,
         empty => open,
         rd_data_count => open,
         wr_data_count => open
       );
        
   register_data_fifo_b :entity work.register_data_fifo_orihard_2
     PORT MAP (
       rst => treset,
       wr_clk => Soft_CMD_clk,
       rd_clk => axi_tclk,
       din => Reg_Data,
       wr_en => RD_REG,
       rd_en => Soft_CMD_rd_en,
       dout => Reg_Data_R ,
       full => open,
       empty => open
     );
   register_CMD_addr_fifo_b :entity work.register_addr_fifo_orihard
       PORT MAP (
         rst => treset,
         wr_clk => Soft_CMD_clk,
         rd_clk => axi_tclk,
         din    => Reg_Addr,
         wr_en  => RD_REG,
         rd_en  => Soft_CMD_rd_en,
         dout   => Reg_Addr_R ,
         full   => open,
         empty   => open
       );     

   register_TRM_data_fifo_b :entity work.register_data_fifo_orihard_2
       PORT MAP (
         rst => treset,
         wr_clk => TRM_clk,
         rd_clk => axi_tclk,
         din    => TRM_Data,
         wr_en  => RD_TRM,
         rd_en  => TRM_CMD_rd_en,
         dout   => TRM_register ,
         full   => open,
         empty   => open
       );  
   register_TRM_addr_fifo_b :entity work.register_addr_fifo_orihard
       PORT MAP (
         rst => treset,
         wr_clk => TRM_clk,
         rd_clk => axi_tclk,
         din    => TRM_Addr,
         wr_en  => RD_TRM,
         rd_en  => TRM_CMD_rd_en,
         dout   => TRM_Addr_R ,
         full   => open,
         empty   => open
       ); 
       
  -- 64-bit dual-clock payload FIFO. Writes are not internally gated by ready;
  -- the producer must observe Wr_Ready and leave room for flag latency.
  DATA_IN_FIFO :fifo_generator_4DB_2
     PORT MAP (
       rst => treset,
       wr_clk => Wr_clk,
       rd_clk => axi_tclk,
       din => wr_data,
       wr_en => wr_en,
       rd_en => Rd_en,
       dout => dout,
       full => open,
       almost_full => almost_full_ch1,
       almost_empty => almost_empty_ch1,
       empty => open,
       rd_data_count => rd_data_count,
       wr_data_count => wr_data_count
     );     
     Wr_Ready <=   not(almost_full_ch1);
     Rd_ready <=   not(almost_empty_ch1);
          
-- DATA_IN_FIFO :entity work.Double_Buffer_deck 
--       Port map( reset => treset,--AUTO_RST,
              
--              Wr_clk      =>    wr_clk ,
--              Wr_en       =>    wr_en,
--              Wr_last     =>    wr_last,
--              Wr_Data     =>    wr_data,
--              Wr_Ready    =>    Wr_Ready,

--              Rd_clk      =>    axi_tclk,
--              Rd_en       =>    Rd_en,
--              RD_Data     =>    dout,
--              Rd_ready    =>    Rd_ready
--              );
   
    -- Idle arbitration priority: terminal, register response, external payload.
    -- Code/length queues are paired; keep both fields stable on the write strobe.
    CMD_Fetch_p : process (axi_tclk,treset)
        begin
          if treset='1' then
              CMD_rd_en <= '0';
              Read_CMD_FIFO <= '0';
              Soft_Read_CMD_FIFO <= '0';
              Soft_CMD_rd_en <= '0';
              Read_TRM_CMD_FIFO <= '0';
         elsif axi_tclk'event and axi_tclk = '1' then 
                if gen_state = IDLE and TRM_CMD_count > 0 and Read_TRM_CMD_FIFO = '0' and Read_CMD_FIFO = '0' and Soft_Read_CMD_FIFO ='0' then
                    TRM_CMD_rd_en     <= '1';
                    Read_TRM_CMD_FIFO <= '1';                     
                elsif gen_state = IDLE and Soft_CMD_count > 0  and Read_TRM_CMD_FIFO = '0' and Read_CMD_FIFO = '0' and Soft_Read_CMD_FIFO ='0' then
                    Soft_CMD_rd_en     <= '1';
                    Soft_Read_CMD_FIFO <= '1';
                elsif gen_state = IDLE and CMD_count > 0  and Read_TRM_CMD_FIFO = '0' and  Read_CMD_FIFO = '0' and Soft_Read_CMD_FIFO ='0' and Rd_ready='1' then
                    CMD_rd_en     <= '1';
                    Read_CMD_FIFO <= '1';
                elsif  gen_state = OVERHEAD then
                    TRM_CMD_rd_en      <= '0';
                    Read_CMD_FIFO      <= '0';
                    Read_TRM_CMD_FIFO  <= '0';
                    Soft_Read_CMD_FIFO <= '0';
                    CMD_rd_en <= '0';
                    Soft_CMD_rd_en <= '0';                 
                else
                    Read_CMD_FIFO      <= Read_CMD_FIFO;
                    Read_TRM_CMD_FIFO  <= Read_TRM_CMD_FIFO;
                    Soft_Read_CMD_FIFO <= Soft_Read_CMD_FIFO;
                    CMD_rd_en          <= '0';
                    Soft_CMD_rd_en     <= '0';         
                    TRM_CMD_rd_en      <= '0';         
                end if;
         end if;
       end process CMD_Fetch_p;
       
       process (axi_tclk,treset)
           begin
            if treset='1' then
                Cmd_CODE_reg <= (others => '0');
                Length_CODE_reg <= (others => '0');
                CMD_rd_en_d      <= '0';
                Soft_CMD_rd_en_d <= '0';
                TRM_CMD_rd_en_d  <= '0';
            elsif axi_tclk'event and axi_tclk = '1' then 
                CMD_rd_en_d      <= CMD_rd_en;
                Soft_CMD_rd_en_d <= Soft_CMD_rd_en;
                TRM_CMD_rd_en_d  <= TRM_CMD_rd_en;
               if (Soft_CMD_rd_en_d = '1' ) then
                   Length_CODE_reg <= Soft_Length_FIFO_dout;
                   Cmd_CODE_reg    <= Soft_Cmd_FIFO_dout;
               ELSIF (CMD_rd_en_d ='1') then
                   Length_CODE_reg <= Length_FIFO_dout;
                   Cmd_CODE_reg    <= Cmd_FIFO_dout;    
               ELSIF (TRM_CMD_rd_en_d='1') then
                   Length_CODE_reg <= TRM_Length_FIFO_dout;
                   Cmd_CODE_reg    <= TRM_Cmd_FIFO_dout;          
               END IF; 
            end if;   
       end process;

       process (axi_tclk,treset)
           begin
            if treset='1' then
                transfer_end <= '0';
            elsif axi_tclk'event and axi_tclk = '1' then        
               if gen_state = IDLE and Read_TRM_CMD_FIFO = '0' and Read_CMD_FIFO = '0' and Soft_Read_CMD_FIFO ='0' then
                   transfer_end <= '0';
               elsif  gen_state = FOOTER   then
                   transfer_end <= '1';                   
               end if;
            end if;
        end process ; 
     
       CMD_decode_p : process (axi_tclk,treset)
           begin
               if treset='1' then
                    transfer_start <= '0';
               elsif axi_tclk'event and axi_tclk = '1' then
                    if ((CMD_rd_en_d = '1' or TRM_CMD_rd_en_d = '1' or Soft_CMD_rd_en_d = '1') and (transfer_start = '0'))  then
                        transfer_start <= '1';                                      
                    elsif  transfer_end= '1' then                 
                        transfer_start <= '0';
                    end if;
               end if;
          end process CMD_decode_p;       
  
   -- need a packet counter - max size limited to 11 bits
   byte_count_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1' then
            byte_count <= (others => '0');
         elsif ((header_count = 1 or header_count = 2) and byte_count >= X"008" and tready = '1')  then
            byte_count <= byte_count - X"008";  
         elsif header_count = 0 then
            byte_count <= pkt_size;
         end if;
      end if;
   end process byte_count_p;

   -- need a smaller count to manage the header insertion
   header_count_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1' then
            header_count <= (others => '0');
         elsif  ((gen_state = HEADER or byte_count = X"000") and tvalid_int= '1')and (tready = '1') then
            header_count <= header_count + 1;
         elsif (tvalid_int = '0') then
            header_count <= (others => '0');
         end if;
      end if;
   end process header_count_p;
   
   
   -- need a smaller count to manage the overhead
   overhead_count_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1' then
            overhead_count <= (others => '0');
         elsif gen_state = OVERHEAD and overhead_count /= "00000" and tready = '1' then
            overhead_count <= overhead_count - "00001";
         elsif gen_state = IDLE then
            overhead_count <= "00010"; -- 24 in decimal
         end if;
      end if;
   end process overhead_count_p;

   -- need a smaller count to manage the header insertion
   -- adjust parameter values by 18 to allow for header and crc
   -- so the pkt_size can be sued directly in the size field
   -- Oversized ordinary requests are clamped to MAX_SIZE. The overflow value
   -- is recorded here but this implementation does not schedule another frame.
   pkt_size_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1' then
            pkt_size <= (others => '0');
            overflow <= (others => '0');
         elsif gen_state = HEADER  then
             if Cmd_CODE_reg = RD_REG_CODE  then
                 pkt_size <= Length_CODE_reg;
                 overflow <= (others => '0');
             elsif Cmd_CODE_reg = WR_TRM_CODE  then
                 pkt_size <= Length_CODE_reg;
                 overflow <= (others => '0');    
             else
                if (unsigned(Length_CODE_reg) > unsigned(MAX_SIZE)) then
                   pkt_size <= (MAX_SIZE);
                   overflow <= (Length_CODE_reg) - (MAX_SIZE) ;
                else
                   pkt_size <= (Length_CODE_reg);
                   overflow <= (others => '0');
                end if;
             end if;
         end if;
      end if;
   end process pkt_size_p;


lut_data <= MAC_Header(95 downto 32)                          when header_count(1 downto 0)= "00" else
            MAC_Header(31 downto 0)& MAC_Header(31 downto 0)  when header_count(1 downto 0)= "01" ;


   -- first we need an always active counter to provide the credit control
   basic_count_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1'  then
            basic_rc_counter <= (others => '1');
         else
            basic_rc_counter <= basic_rc_counter + X"01";
         end if;
      end if;
   end process basic_count_p;

   -- now we need to set the compare level depending upon the selected speed
   -- the credits are applied using a simple less-than check
   gen_inc_control_p : process (axi_tclk)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if    speed = "01" then
--            if basic_rc_counter < X"E6" then  -- decimal 230
            if basic_rc_counter < X"E6" then  -- decimal 230
               add_credit        <= '1';
            else
               add_credit        <= '0';
            end if;
         elsif speed = "10" then
            if basic_rc_counter < X"17" then  -- decimal 23
               add_credit        <= '1';
            else
               add_credit        <= '0';
            end if;
         elsif speed = "00" then
            if basic_rc_counter < X"02" then
               add_credit        <= '1';
            else
               add_credit        <= '0';
            end if;
         elsif speed = "11" then
--               if basic_rc_counter < (speed_value) then
                  add_credit        <= '1';
--               else
--                  add_credit        <= '0';
--               end if;
         end if;
      end if;
   end process gen_inc_control_p;

   -- basic credit counter - -ve value means do not send a frame

   -- simple state machine to control the data
   -- on the transition from IDLE we reset the counters and increment the packet size
   next_s : process(treset,transfer_start,gen_state,Footer_count,  header_count, tready, byte_count, tvalid_int, overhead_count, credit_count)
   begin
      next_gen_state <= gen_state;
      case gen_state is
         when IDLE =>
            if tvalid_int = '0'  then
                if transfer_start = '1' then
                    next_gen_state <= HEADER;
                end if;
            end if;
        when HEADER =>
            if (header_count = 1 and tready = '1') then
               next_gen_state <= SET_DATA;
            end if;
         when SET_DATA =>
            if byte_count = X"000" and tready = '1' then 
               next_gen_state <= FOOTER;
            end if;
        when FOOTER =>
            if tready = '1' then 
               next_gen_state <= OVERHEAD;
            end if;
        when OVERHEAD =>
            if overhead_count = "00000" and tready = '1' then  
               next_gen_state <= IDLE;
            end if;
        when others =>
            next_gen_state <= IDLE;
      end case;
   end process;

   state_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1' then
            gen_state <= IDLE;
         else 
            gen_state <= next_gen_state;
         end if;
      end if;
   end process state_p;
     
    
   valid_p : process (axi_tclk,treset)
   begin
      if axi_tclk'event and axi_tclk = '1' then
         if treset = '1' then
            tvalid_int <= '0';
         elsif gen_state = HEADER  then
            tvalid_int <= '1';
         elsif header_count = 3   then
            tvalid_int <= '0';
         end if;
      end if;
   end process valid_p;

--Ins_ila_tx_patgen : entity work.ila_tx_patgen_1
--PORT MAP (
--	clk => axi_tclk,

--	probe0(0)  => almost_full_ch1, 
--	probe1(0)  => almost_empty_ch1, 
--	probe2(0)  => tlast, 
--	probe3     => wr_data, 
--	probe4     => TRM_Addr_R, 
--	probe5     => probe5,
--	probe6(0)  => tvalid, 
--	probe7(0)  => CMD_rd_en,
--	probe8(0)  => CMD_en,
--	probe9     => header_count,
--	probe10    => tdata,
--	probe11    => dout,
--	probe12(0) => tready,
--	probe13(0) => wr_en ,
--	probe14(0) => Rd_en ,
--	probe15(0) => RD_REG      ,
--	probe16(0) => Soft_CMD_en    ,
--	probe17(0) => Soft_CMD_en    ,
--	probe18(0) => Soft_CMD_rd_en         ,
--	probe19(0) => Soft_CMD_rd_en  
--);   
probe5(31 downto 0)  <= ext(rd_data_count,32);
probe5(63 downto 32) <= ext(wr_data_count,32);


end rtl;
