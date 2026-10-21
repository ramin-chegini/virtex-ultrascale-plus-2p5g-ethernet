----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08/11/2024 02:08:47 PM
-- Design Name: 
-- Module Name: axi_ethernet_0_top - Behavioral
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

-- Active hierarchy: custom 64-bit packet engine <-> TEMAC FIFO wrapper <->
-- 8-bit GMII <-> 2.5 Gb/s PCS/PMA <-> SFP serial lane. Historical RGMII/GTX
-- names and commented examples do not select the physical interface.
-- Reg_pack_comint and generated TEMAC example support are external dependencies;
-- see README.md and docs/INTEGRATION.md before recreating a Vivado project.
library ieee;
use ieee.std_logic_1164.all ;
use ieee.std_logic_arith.all ;
use ieee.std_logic_unsigned.all ;
use ieee.std_logic_misc.all ;
library unisim;
use unisim.vcomponents.all;
--use work.ALL;
use work.Reg_pack_comint.ALL;

entity axi_ethernet_0_top is
    port (
        -- asynchronous reset
        glbl_rst                      : in  std_logic;
        Soft_Reset                  : in  std_logic;
        independent_clock_bufg        : in  std_logic;

        sfp_txn             : out std_logic;
        sfp_txp             : out std_logic;
                            
        sfp_rxn             : in std_logic;
        sfp_rxp             : in std_logic;
                            
        mgt_clk_p           : in std_logic;
        mgt_clk_n           : in std_logic;
        
        C156_25M_Clk_Comint : out std_logic;
--        txC156_25M_Clk_Comint       : out std_logic; 
        rxC156_25M_Clk_Comint       : out std_logic;         
        mmcm_locked_out : out std_logic;

      -- clock from internal phy
--       gtx_clk                       : in  std_logic;
      
--      -- GMII Interface
--      -----------------

--      gmii_txd                      : out std_logic_vector(7 downto 0);
--      gmii_tx_en                    : out std_logic;
--      gmii_tx_er                    : out std_logic;
--      gmii_rxd                      : in  std_logic_vector(7 downto 0);
--      gmii_rx_dv                    : in  std_logic;
--      gmii_rx_er                    : in  std_logic;      

      speedis100                    : out std_logic;
      speedis10100                  : out std_logic;
      
      LED1                          : out std_logic;

--      clk_100MHz                  : in std_logic; 
--      Spi_clk                     : out std_logic; 
      
      -- Payload and CMD_* are sampled in wr_clk; the active payload path is 64 bits.
      -- wr_ready is driven by this core despite its legacy inout declaration.
      wr_ready                    : inout std_logic;
      wr_clk                      : in  std_logic;
      wr_en                       : in  std_logic;
      wr_last                     : in  std_logic;
      wr_data                     : in  std_logic_vector(Bus_width-1 downto 0);
      -- data from the user bus    
      -- rd_ready is a packet event from the RX domain, not a FIFO-not-empty flag.
      -- rd_en/rd_data/rd_data_count belong to rd_clk; see integration CDC notes.
      rd_ready                    : out std_logic;
      rd_clk                      : in  std_logic;
      rd_en                       : in  std_logic;
      rd_data                     : inout  std_logic_vector(7 downto 0); 
      rd_data_count               : out  std_logic_vector(11 downto 0); 
      data_len                    : out std_logic_vector(15 downto 0) ;
      
      CMD_CODE                    : in std_logic_vector(15 downto 0);
      CMD_length                  : in std_logic_vector(15 downto 0);
      CMD_en                      : in std_logic; 
      
      TRMOUT_clk                       : out std_logic;  
      TRMOUT_EN                       : out std_logic;  
      TRMOUT_Addr                     : out std_logic_vector(7 downto 0);
      TRMOUT_Data                     : out std_logic_vector(63 downto 0);
                                     
      TRMIN_clk                        : in std_logic;  
      TRMIN_EN                        : in std_logic;  
      TRMIN_Addr                      : in std_logic_vector(7 downto 0);
      TRMIN_Data                      : in std_logic_vector(63 downto 0);    
      -- control register
      command_updates              :out std_logic_vector(NOofreg-1  downto 0);   
      command_registers            :out std_logic_reg_array(NOofreg-1 downto 0);  
      status_registers             :in std_logic_reg_array(NOofreg-1 downto 0); 
      read_only_regs               :in  std_logic_vector(NOofreg-1 downto 0);      
      
      -- Serialised statistics vectors
      --------------------------------
      tx_statistics_s               : out std_logic;
      rx_statistics_s               : out std_logic;

      -- Serialised Pause interface controls
      --------------------------------------
      pause_req_s                   : in  std_logic;

      -- Main example design controls
      -------------------------------
      mac_speed                     : in  std_logic_vector(1 downto 0);
      
      update_speed                  : in  std_logic;
      config_board                  : in  std_logic;
      --serial_command                : in  std_logic;  -- tied to pause_req_s
--      serial_response               : out std_logic;
--      gen_tx_data                   : in  std_logic;
--      chk_tx_data                   : in  std_logic;
      reset_error                   : in  std_logic;
      frame_error                   : out std_logic;
      frame_errorn                  : out std_logic;
      activity_flash                : out std_logic;
      activity_flashn               : out std_logic

    );
end axi_ethernet_0_top;

architecture wrapper of axi_ethernet_0_top is


    constant      mtrlb_en_cs_offload           :  std_logic_vector(1 downto 0)  := "00"  ;
    constant      mtrlb_config_dest_addr        :  std_logic_vector(47 downto 0)  := x"DA0102030405"   ;
    constant      mtrlb_config_src_addr         :  std_logic_vector(47 downto 0)  := x"5A0102030405"   ;
    constant      mtrlb_config_vlan_id          :  std_logic_vector(11 downto 0)  := x"000"            ;
    constant      mtrlb_config_vlan_priority    :  std_logic_vector(2 downto 0)  :=  "000"            ;
    constant      mtrlb_config_ip_dest_addr     :  std_logic_vector(31 downto 0)  := x"DA060708"       ;
    constant      mtrlb_config_ip_src_addr      :  std_logic_vector(31 downto 0)  := x"5A060708"       ;
    constant      mtrlb_config_tcp_dest_port    :  std_logic_vector(15 downto 0)  := x"DA09"           ;
    constant      mtrlb_config_tcp_src_port     :  std_logic_vector(15 downto 0)  := x"5A09"           ;
    constant      mtrlb_config_udp_dest_port    :  std_logic_vector(15 downto 0)  := x"DA0A"           ;
    constant      mtrlb_config_udp_src_port     :  std_logic_vector(15 downto 0)  := x"5A0A"           ;
    constant      mtrlb_config_min_size         :  std_logic_vector(15 downto 0)  := x"0040"           ;
    constant      mtrlb_config_max_size         :  std_logic_vector(15 downto 0)  := x"4000"           ;
    constant      mtrlb_da_sa_swap_en           :  std_logic  := '0'               ;

   component tri_mode_ethernet_mac_internal_fifo_block
   port(
      gtx_clk                    : in  std_logic;
      -- asynchronous reset
      glbl_rstn                  : in  std_logic;
      rx_axi_rstn                : in  std_logic;
      tx_axi_rstn                : in  std_logic;


      -- Receiver Statistics Interface
      -----------------------------------------
      rx_mac_aclk                : out std_logic;
      rx_reset                   : out std_logic;
      rx_statistics_vector       : out std_logic_vector(27 downto 0);
      rx_statistics_valid        : out std_logic;

      -- Receiver (AXI-S) Interface
      ------------------------------------------
      rx_fifo_clock              : in  std_logic;
      rx_fifo_resetn             : in  std_logic;
      rx_axis_fifo_tready        : in  std_logic;
      rx_axis_fifo_tvalid        : out std_logic;
      
      rx_axis_fifo_tdata         : out std_logic_vector(63 downto 0);
      rx_axis_fifo_tkeep         : out std_logic_vector(7 downto 0);
      
      rx_axis_fifo_tlast         : out std_logic;

      -- Transmitter Statistics Interface
      --------------------------------------------
      tx_mac_aclk                : out std_logic;
      tx_reset                   : out std_logic;
      tx_ifg_delay               : in  std_logic_vector(7 downto 0);
      tx_statistics_vector       : out std_logic_vector(31 downto 0);
      tx_statistics_valid        : out std_logic;

      -- Transmitter (AXI-S) Interface
      ---------------------------------------------
      tx_fifo_clock              : in  std_logic;
      tx_fifo_resetn             : in  std_logic;
      tx_axis_fifo_tready        : out std_logic;
      tx_axis_fifo_tvalid        : in  std_logic;
      
      tx_axis_fifo_tdata         : in  std_logic_vector(63 downto 0);
      tx_axis_fifo_tkeep         : in  std_logic_vector(7 downto 0);
      
      tx_axis_fifo_tlast         : in  std_logic;

      -- MAC Control Interface
      --------------------------
      pause_req                  : in  std_logic;
      pause_val                  : in  std_logic_vector(15 downto 0);

      -- GMII Interface
      -------------------
      gmii_txd                  : out std_logic_vector(7 downto 0);
      gmii_tx_en                : out std_logic;
      gmii_tx_er                : out std_logic;
      gmii_rxd                  : in  std_logic_vector(7 downto 0);
      gmii_rx_dv                : in  std_logic;
      gmii_rx_er                : in  std_logic;
      speedis100                : out std_logic;
      speedis10100              : out std_logic;

      -- Configuration Vector
      -------------------------
      rx_configuration_vector    : in  std_logic_vector(79 downto 0);
      tx_configuration_vector    : in  std_logic_vector(79 downto 0)
   );
   end component;

  ------------------------------------------------------------------------------
  -- Component Declaration for the basic pattern generator
  ------------------------------------------------------------------------------

  component tri_mode_ethernet_mac_internal_basic_pat_gen_2g5
    generic(
      DEST_ADDR                  : std_logic_vector(47 downto 0)  := x"DA0102030405";
      SRC_ADDR                   : std_logic_vector(47 downto 0)  := x"5A0102030405";
      MAX_SIZE                   : std_logic_vector(15 downto 0)  := x"01F4";
      MIN_SIZE                   : std_logic_vector(15 downto 0)  := x"0040";
      ENABLE_VLAN                : boolean                        := FALSE;
      VLAN_ID                    : std_logic_vector(11 downto 0)  := x"002";
      VLAN_PRIORITY              : std_logic_vector(2 downto 0)   := "010"
    );
    port(
      axi_tclk                     : in  std_logic;
      axi_tresetn                  : in  std_logic;
      check_resetn                 : in  std_logic;
  
      enable_pat_gen               : in  std_logic;
      enable_pat_chk               : in  std_logic;
  
      -- Data from the RX data path
      rx_axis_tready               : out std_logic;
      rx_axis_tvalid               : in  std_logic;
      rx_axis_tdata                : in  std_logic_vector(31 downto 0);
      rx_axis_tlast                : in  std_logic;
      rx_axis_tkeep                : in  std_logic_vector(3 downto 0);
      rx_axis_tuser                : in  std_logic;
      -- Data to the TX data path
      tx_axis_tready               : in  std_logic;
      tx_axis_tvalid               : out std_logic;
      tx_axis_tdata                : out std_logic_vector(31 downto 0);
      tx_axis_tlast                : out std_logic;
      tx_axis_tkeep                : out std_logic_vector(3 downto 0);
  
      frame_error                  : out std_logic;
      activity_flash               : out std_logic
     );
  end component;

   

  ------------------------------------------------------------------------------
  -- Component Declaration for the Config Vector State machine
  ------------------------------------------------------------------------------

   component tri_mode_ethernet_mac_internal_config_vector_sm
   port (
      gtx_clk                   : in  std_logic;
      gtx_resetn                : in  std_logic;

      mac_speed                 : in  std_logic_vector(1 downto 0);
      update_speed              : in  std_logic;

      rx_configuration_vector   : out std_logic_vector(79 downto 0);
      tx_configuration_vector   : out std_logic_vector(79 downto 0)
   );
   end component;

  ------------------------------------------------------------------------------
  -- Component declaration for the synchroniser
  ------------------------------------------------------------------------------
  component tri_mode_ethernet_mac_internal_sync_block
  port (
     clk                        : in  std_logic;
     data_in                    : in  std_logic;
     data_out                   : out std_logic
  );
  end component;

  component tri_mode_ethernet_mac_internal_syncer_level is
  generic (
    WIDTH       : integer   := 1;
    RESET_VALUE : std_logic := '1'
   );
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
  
    datain    : in  std_logic_vector(WIDTH-1 downto 0);
    dataout   : out std_logic_vector(WIDTH-1 downto 0)
  );
  end component;
  ------------------------------------------------------------------------------
  -- Component declaration for the clocking logic
  ------------------------------------------------------------------------------
  component tri_mode_ethernet_mac_internal_example_design_clocks is
   port (
   -- clocks
   gtx_clk                    : in std_logic;
   
   axi_lite_clk               : in std_logic;
   
   -- clock outputs
   gtx_clk_bufg               : out std_logic;
   
   s_axi_aclk                 : out std_logic
   );
   end component;
   
 COMPONENT gig_ethernet_pcs_pma_0
  PORT (
    gtrefclk_p : IN STD_LOGIC;
    gtrefclk_n : IN STD_LOGIC;
    gtrefclk_out : OUT STD_LOGIC;
    txn : OUT STD_LOGIC;
    txp : OUT STD_LOGIC;
    rxn : IN STD_LOGIC;
    rxp : IN STD_LOGIC;
    independent_clock_bufg : IN STD_LOGIC;
    userclk_out : OUT STD_LOGIC;
    userclk2_out : OUT STD_LOGIC;
    rxuserclk_out : OUT STD_LOGIC;
    rxuserclk2_out : OUT STD_LOGIC;
    gtpowergood : OUT STD_LOGIC;
    resetdone : OUT STD_LOGIC;
    pma_reset_out : OUT STD_LOGIC;
    mmcm_locked_out : OUT STD_LOGIC;
    gmii_txd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    gmii_tx_en : IN STD_LOGIC;
    gmii_tx_er : IN STD_LOGIC;
    gmii_rxd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    gmii_rx_dv : OUT STD_LOGIC;
    gmii_rx_er : OUT STD_LOGIC;
    gmii_isolate : OUT STD_LOGIC;
    configuration_vector : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
    status_vector : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    reset : IN STD_LOGIC;
    signal_detect : IN STD_LOGIC 
  );
END COMPONENT;

--COMPONENT gig_ethernet_pcs_pma_0
--  PORT (
--    gtrefclk_p : IN STD_LOGIC;
--    gtrefclk_n : IN STD_LOGIC;
--    gtrefclk_out : OUT STD_LOGIC;
--    txn : OUT STD_LOGIC;
--    txp : OUT STD_LOGIC;
--    rxn : IN STD_LOGIC;
--    rxp : IN STD_LOGIC;
--    independent_clock_bufg : IN STD_LOGIC;
--    userclk_out : OUT STD_LOGIC;
--    userclk2_out : OUT STD_LOGIC;
--    rxuserclk_out : OUT STD_LOGIC;
--    rxuserclk2_out : OUT STD_LOGIC;
--    gtpowergood : OUT STD_LOGIC;
--    resetdone : OUT STD_LOGIC;
--    pma_reset_out : OUT STD_LOGIC;
--    mmcm_locked_out : OUT STD_LOGIC;
--    gmii_txd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
--    gmii_tx_en : IN STD_LOGIC;
--    gmii_tx_er : IN STD_LOGIC;
--    gmii_rxd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
--    gmii_rx_dv : OUT STD_LOGIC;
--    gmii_rx_er : OUT STD_LOGIC;
--    gmii_isolate : OUT STD_LOGIC;
--    configuration_vector : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
--    an_interrupt : OUT STD_LOGIC;
--    an_adv_config_vector : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
--    an_restart_config : IN STD_LOGIC;
--    status_vector : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
--    reset : IN STD_LOGIC;
--    signal_detect : IN STD_LOGIC 
--  );
--END COMPONENT;
  ------------------------------------------------------------------------------
  -- Component declaration for the reset logic
  ------------------------------------------------------------------------------
  component tri_mode_ethernet_mac_internal_example_design_resets is
  port (
     -- clocks
     s_axi_aclk                 : in std_logic;
     gtx_clk                    : in std_logic;


     -- asynchronous resets
     glbl_rst                   : in std_logic;
     reset_error                : in std_logic;
     Soft_Reset                : in std_logic;
     rx_reset                   : in std_logic;
     tx_reset                   : in std_logic;

     -- asynchronous reset output
  
     glbl_rst_intn              : out std_logic;
   -- synchronous reset outputs
   
     
     axi_lite_resetn            : out std_logic := '0';
     
     vector_resetn              : out std_logic := '0';
     chk_resetn                 : out std_logic := '0'
   );
   end component;
   signal clkgen_gtx_clk           : std_logic;
   signal pause_req_s_sync_axilite_clk       : std_logic;
   signal update_speed_sync_axilite_clk      : std_logic;
   
   signal pause_req_s_sync_gtx_clk           : std_logic;
   signal mac_speed_sync_gtx_clk             : std_logic_vector(1 downto 0);
   signal update_speed_sync_gtx_clk          : std_logic;
   signal config_board_sync_gtx_clk          : std_logic;
   
   
   signal gen_tx_data_sync_gtx_clk           : std_logic;
   signal chk_tx_data_sync_gtx_clk           : std_logic;
   
   signal s_axi_reset                        : std_logic;
   signal mac_speed_sync_axilite_clk         : std_logic_vector(1 downto 0);
   signal gen_tx_data_sync_axilite_clk       : std_logic;
   signal chk_tx_data_sync_axilite_clk       : std_logic;
   


   -- example design clocks
   signal Proc_Clk_300M_bufg                       : std_logic;
   signal Proc_Clk_50M_bufg                       : std_logic;
   signal clk_20M_bufg                       : std_logic;
   signal gtx_clk_bufg                       : std_logic;
   signal gtx_rclk_bufg                       : std_logic;
   signal refclk_bufg                        : std_logic;
   signal s_axi_aclk                         : std_logic;
   
   signal rx_mac_aclk                        : std_logic;
   signal tx_mac_aclk                        : std_logic;
   signal phy_resetn_int                     : std_logic;
   -- resets (and reset generation)
   signal vector_resetn                      : std_logic;
   signal chk_resetn                         : std_logic;
   
   signal gtx_resetn                         : std_logic;
   
   signal rx_reset                           : std_logic;
   signal tx_reset                           : std_logic;

   signal dcm_locked                         : std_logic;
   signal glbl_rst_int                       : std_logic;
   signal phy_reset_count                    : unsigned(5 downto 0) := (others => '0');
   signal glbl_rst_intn                      : std_logic;


   -- USER side RX AXI-S interface
   signal rx_fifo_clock                      : std_logic;
   signal rx_fifo_resetn                     : std_logic;
   signal pause_req : std_logic;
   signal pause_val : std_logic_vector(15 downto 0);
--   signal rx_axis_tdata_32                 : std_logic_vector(31 downto 0);
   signal rx_axis_tdata                 : std_logic_vector(31 downto 0);
   signal rx_axis_tvalid                : std_logic;
   signal rx_axis_tlast                 : std_logic;
   signal rx_axis_tready                : std_logic;
   signal Rx_axis_tkeep                :  std_logic_vector(3 downto 0);
   
  signal int_frame_error                     : std_logic;
  signal int_activity_flash                  : std_logic;
   -- USER side TX AXI-S interface
--   signal tx_fifo_clock                      : std_logic;
--   signal tx_fifo_resetn                     : std_logic;
   signal tx_axis_tdata                 : std_logic_vector(31 downto 0);
   signal tx_axis_tvalid                : std_logic;
   signal tx_axis_tlast                 : std_logic;
   signal tx_axis_tready                : std_logic;
   signal enable_address_swap           : std_logic := '1';
   
    signal axi_lite_resetn : std_logic;
    signal s_axi_araddr    : std_logic_vector(17 downto 0);
    signal s_axi_arready   : std_logic;
    signal s_axi_arvalid   : std_logic;
    signal s_axi_awaddr    : std_logic_vector(17 downto 0);
    signal s_axi_awready   : std_logic;
    signal s_axi_awvalid   : std_logic;
    signal s_axi_bready    : std_logic;
    signal s_axi_bresp     : std_logic_vector(1 downto 0);
    signal s_axi_bvalid    : std_logic;
    signal s_axi_rdata     : std_logic_vector(31 downto 0);
    signal s_axi_rready    : std_logic;
    signal s_axi_rresp     : std_logic_vector(1 downto 0);
    signal s_axi_rvalid    : std_logic;
    signal s_axi_wdata     : std_logic_vector(31 downto 0);
    signal s_axi_wready    : std_logic;
    signal s_axi_wvalid    : std_logic;
    signal sys_out_rst    : std_logic;
    signal gtx_clk    : std_logic;
 
    signal tx_axis_tkeep : std_logic_vector(3 downto 0); 
    signal tx_axis_mac_tdata : std_logic_vector(31 downto 0); 
    signal tx_axis_mac_tlast : std_logic;
    signal tx_axis_mac_tready: std_logic;
    signal tx_axis_mac_tuser : std_logic;
    signal tx_axis_mac_tvalid: std_logic;
    signal rx_axis_mac_tdata : std_logic_vector(7 downto 0);
    signal rx_axis_mac_tlast : std_logic;
    signal rx_axis_mac_tuser : std_logic;
    signal rx_axis_mac_tvalid: std_logic;
    
    signal ref_clk_50_bufg: std_logic;
    signal axi_lite_clk: std_logic;
    signal axi_rclk: std_logic;
    signal soft_rst: std_logic;
    signal axis_rstn: std_logic;
    signal rx_clk_lan,tx_clk_lan: std_logic;
 
    signal signal_detect : std_logic := '1'; 
    signal status_vector : std_logic_vector(15 downto 0);
    signal loopback_master_slaven, slvlb_en_l2_addr_swap, mtrlb_en_packet_gen, mtrlb_en_packet_chk, mtrlb_en_pkt_drop_chk, mtrlb_reset_error : std_logic;
    signal pat_chk_ctrl, ex_des_cl, ex_des_blink_on_tx : std_logic ;
    signal mtrlb_line_speed : std_logic_vector(1 downto 0);
    signal mtrlb_select_packet_type : std_logic_vector(4 downto 0);
   
    signal stat_tx_packet_small :  STD_LOGIC;
    signal stat_tx_packet_large :  STD_LOGIC;
    signal stat_tx_unicast :  STD_LOGIC;
    signal stat_tx_multicast :  STD_LOGIC;
    signal stat_tx_broadcast :  STD_LOGIC;
    signal stat_tx_vlan :  STD_LOGIC;
    signal stat_tx_frame_error :  STD_LOGIC;     
    signal ctl_tx_test_pattern_en :  STD_LOGIC;     
   
   signal gmii_txd_int                       : std_logic_vector(7 downto 0);
   signal gmii_tx_en_int                     : std_logic;
   signal gmii_tx_er_int                     : std_logic;
   signal gmii_rxd_int                       : std_logic_vector(7 downto 0);
   signal gmii_rx_dv_int                     : std_logic;
   signal gmii_rx_er_int                     : std_logic;
   signal rx_configuration_vector           : std_logic_vector(79 downto 0);
   signal tx_configuration_vector           : std_logic_vector(79 downto 0);
 -- USER side RX AXI-S interface
--   signal rx_fifo_clock                      : std_logic;
--   signal rx_fifo_resetn                     : std_logic;
   signal rx_axis_fifo_tdata                 : std_logic_vector(63 downto 0);
   
   signal rx_axis_fifo_tvalid                : std_logic;
   signal rx_axis_fifo_tlast                 : std_logic;
   signal rx_axis_fifo_tready                : std_logic;
   signal rx_axis_fifo_tkeep                 : std_logic_vector(7 downto 0);
   

   -- USER side TX AXI-S interface
   signal tx_fifo_clock                      : std_logic;
   signal tx_fifo_resetn                     : std_logic;
   signal tx_axis_fifo_tdata                 : std_logic_vector(63 downto 0);
   
   signal tx_axis_fifo_tvalid                : std_logic;
   signal tx_axis_fifo_tlast                 : std_logic;
   signal tx_axis_fifo_tready                : std_logic;
   signal tx_axis_fifo_tkeep                 : std_logic_vector(7 downto 0);   
   -- signal tie offs
   signal tx_ifg_delay                       : std_logic_vector(7 downto 0) := (others => '0');    -- not used in this example
 -- RX Statistics serialisation signals
   signal rx_statistics_valid                : std_logic;
   signal rx_statistics_valid_reg            : std_logic;
   signal rx_statistics_vector               : std_logic_vector(27 downto 0);
   signal rx_stats                           : std_logic_vector(27 downto 0);
   signal rx_stats_shift                     : std_logic_vector(29 downto 0);
   signal rx_stats_toggle                    : std_logic := '0';
   signal rx_stats_toggle_sync               : std_logic;
   signal rx_stats_toggle_sync_reg           : std_logic := '0';

   -- TX Statistics serialisation signals
   signal tx_statistics_valid                : std_logic;
   signal tx_statistics_valid_reg            : std_logic;
   signal tx_statistics_vector               : std_logic_vector(31 downto 0);
   signal tx_stats                           : std_logic_vector(31 downto 0);
   signal tx_stats_shift                     : std_logic_vector(33 downto 0);
   signal tx_stats_toggle                    : std_logic := '0';
   signal tx_stats_toggle_sync               : std_logic;
   signal tx_stats_toggle_sync_reg           : std_logic := '0';
   
   attribute DowngradeIPIdentifiedWarnings: string;
   attribute DowngradeIPIdentifiedWarnings of wrapper : architecture is "yes";
begin
rxC156_25M_Clk_Comint <= axi_rclk;  -- 
--txC156_25M_Clk_Comint <= tx_fifo_clock;

--C156_25M_Clk_Comint <= gtx_clk_bufg;
--Inst_gtx_Comint :entity work.gtx_Comint
--        Port map
--		(
--			reset    		 => sys_rst,
----			reset    		 => sys_out_rst,
--			refclk_p         => mgt_clk_p,
--			refclk_n    	 => mgt_clk_n,
--			clk_100MHz    	 => clk_100MHz,
----			clk_100MHz    	 => axi_lite_clk,
--			rx_clk_lan       => rx_clk_lan,
--			tx_clk_lan       => tx_clk_lan,
--			txp              => sfp_txp,
--            txn              => sfp_txn,
--            rxp              => sfp_rxp,
--            rxn              => sfp_rxn,
--			LOSS             => '0',
			
--			stat_tx_packet_small   => stat_tx_packet_small ,
--            stat_tx_packet_large   => stat_tx_packet_large ,
--            stat_tx_unicast        => stat_tx_unicast      ,
--            stat_tx_multicast      => stat_tx_multicast    ,
--            stat_tx_broadcast      => stat_tx_broadcast    ,
--            stat_tx_vlan           => stat_tx_vlan         ,
--            stat_tx_frame_error    => stat_tx_frame_error  ,  
--            ctl_tx_test_pattern_en    => ctl_tx_test_pattern_en  ,  
			
			
--			Tx_axis_tready   => tx_axis_tready, 
--			Tx_axis_aresetn  => not(sys_rst),
--			Tx_axis_tdata    => tx_axis_tdata,  
----			Tx_axis_tdata    => sTx_axis_tdata2,  
--			Tx_axis_tvalid   => tx_axis_tvalid, 
--			Tx_axis_tlast    => tx_axis_tlast,  
--			Tx_axis_tuser    => "0",  
--			Tx_axis_tkeep    => tx_axis_tkeep,  
--			Tx_ifg_delay     => x"0F", 
			  
--			Rx_axis_aresetn  => axi_lite_resetn,  
--			Rx_axis_tdata    => rx_axis_tdata,    
--			Rx_axis_tvalid   => rx_axis_tvalid,   
--			Rx_axis_tuser    => open,    
--			Rx_axis_tlast    => rx_axis_tlast,    
--			Rx_axis_tkeep    => Rx_axis_tkeep     
--		);

--ila_gtx_inst :entity work.ila_gtx
--PORT MAP (
--	clk => gtx_clk_bufg,

--	probe0 => gmii_txd_int,  
--	probe1(0) => gmii_tx_en_int, 
--	probe2(0) => gmii_tx_er_int,
--	probe3 => gmii_rxd_int,  
--	probe4(0) => gmii_rx_dv_int,
--	probe5(0) => gmii_rx_er_int
--);

-- This is the active serial PHY. The archived IP selects BASE-X at 2.5 Gb/s
-- with a 156.25 MHz reference; auto-negotiation is disabled in that archive.
gig_ethernet_pcs_pma_inst : gig_ethernet_pcs_pma_0
  PORT MAP (
    gtrefclk_p => mgt_clk_p,
    gtrefclk_n => mgt_clk_n,
    
    gtrefclk_out => open,
    
    txn => sfp_txn,
    txp => sfp_txp,
    rxn => sfp_rxn,
    rxp => sfp_rxp,
    
    independent_clock_bufg => independent_clock_bufg,
    
    userclk_out => axi_lite_clk,--C156_25M_Clk_Comint,--156_250_000MHz
    userclk2_out => gtx_clk_bufg,--open,--312_500_000MHz
    
    rxuserclk_out => axi_rclk,
    rxuserclk2_out => gtx_rclk_bufg,
    
    gtpowergood => open,
    resetdone => open,
    pma_reset_out => open,
    mmcm_locked_out => mmcm_locked_out,
    
    gmii_txd    => gmii_txd_int,
    gmii_tx_en  => gmii_tx_en_int,
    gmii_tx_er  => gmii_tx_er_int,
    gmii_rxd    => gmii_rxd_int,
    gmii_rx_dv  => gmii_rx_dv_int,
    gmii_rx_er  => gmii_rx_er_int,
    gmii_isolate => open,
    
    configuration_vector => (others => '0'),
--    an_interrupt => open,
--    an_adv_config_vector => (others => '0'),
--    an_restart_config => '0',
    
    status_vector => open,--status_vector,
    
    reset => glbl_rst,
    -- Module loss-of-signal is not wired into this wrapper.
    signal_detect => '1'
  );
   -- Synchronize DIP Switch inputs to respective clock domains
  pause_req_s_gtx_sync_inst: tri_mode_ethernet_mac_internal_sync_block  
  port map(
     clk      => gtx_clk_bufg,
     data_in  => pause_req_s,
     data_out => pause_req_s_sync_gtx_clk
  );

  mac_speed_gtx_sync: tri_mode_ethernet_mac_internal_syncer_level
  generic map(
    WIDTH  => 2
   ) 
  port map(
    clk       => gtx_clk_bufg,
    reset     =>   '0',
    datain    => mac_speed,
    dataout   => mac_speed_sync_gtx_clk
  );

  

  
  update_speed_axilite_sync_inst: tri_mode_ethernet_mac_internal_sync_block  port map(
     clk      => s_axi_aclk,
     data_in  => update_speed,
     data_out => update_speed_sync_axilite_clk
  );

  update_speed_gtx_sync_inst: tri_mode_ethernet_mac_internal_sync_block  port map(
     clk      => gtx_clk_bufg,
     data_in  => update_speed,
     data_out => update_speed_sync_gtx_clk
  );

  config_board_gtx_sync_inst: tri_mode_ethernet_mac_internal_sync_block  port map(
     clk      => gtx_clk_bufg,
     data_in  => config_board,
     data_out => config_board_sync_gtx_clk
  );
  

   
  s_axi_reset <= not vector_resetn;
  mac_speed_axilite_sync: tri_mode_ethernet_mac_internal_syncer_level 
  generic map(
    WIDTH  => 2
   ) 
  port map(
    clk     => s_axi_aclk,
    reset   => s_axi_reset,
    datain  => mac_speed,
    dataout => mac_speed_sync_axilite_clk
  );

--  gen_tx_data_axilite_sync_inst: tri_mode_ethernet_mac_internal_sync_block  
--  port map(
--     clk      => s_axi_aclk,
--     data_in  => gen_tx_data,
--     data_out => gen_tx_data_sync_axilite_clk
--  );

--  chk_tx_data_axilite_sync_inst: tri_mode_ethernet_mac_internal_sync_block  
--  port map(
--     clk      => s_axi_aclk,
--     data_in  => chk_tx_data,
--     data_out => chk_tx_data_sync_axilite_clk
--  );

--  gen_tx_data_gtx_sync_inst: tri_mode_ethernet_mac_internal_sync_block  port map(
--     clk      => gtx_clk_bufg,
--     data_in  => gen_tx_data,
--     data_out => gen_tx_data_sync_gtx_clk
--  );

--  chk_tx_data_gtx_sync_inst: tri_mode_ethernet_mac_internal_sync_block  port map(
--     clk      => gtx_clk_bufg,
--     data_in  => chk_tx_data,
--     data_out => chk_tx_data_sync_gtx_clk
--  );

   frame_error  <= int_frame_error;
   frame_errorn <= not int_frame_error;
   activity_flash  <= int_activity_flash;
   activity_flashn <= not int_activity_flash;

--   capture_board_modea : process (gtx_clk_bufg)
--   begin
--      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         if config_board_sync_gtx_clk = '1' then
--            enable_address_swap  <= gen_tx_data;
--         end if;
--      end if;
--   end process capture_board_modea;


--   serial_response <= '0';

  
  -- Clock logic assumes 312.5MHz is available for gtx_clk and 150 MHz is available for AXI4-Lite clock
 
  example_clocks : tri_mode_ethernet_mac_internal_example_design_clocks
   port map (
      gtx_clk          => '0',--gtx_clk,
      
      axi_lite_clk     => axi_lite_clk,
      
      -- clock outputs
      gtx_clk_bufg     => open,--gtx_clk_bufg,
      s_axi_aclk       => s_axi_aclk
   );

   

   -- generate the user side clocks for the axi fifos
   
   -- When data-rate is 2.5Gb/s, the FIFO's user side interface 
   -- is clocked by AXI4-Lite clock
   -- Keep the PCS-derived TX and RX clock domains distinct. Signal names alone
   -- are not a timing specification; use the restored project's IP constraints.
   tx_fifo_clock <= s_axi_aclk;
   rx_fifo_clock <= axi_rclk; 
   

   ------------------------------------------------------------------------------
   -- Pipeline the gmii_tx outputs - this is only necessary for the example design
   -- and can be removed when connected internally
   ------------------------------------------------------------------------------

--   gmii_pipe : process (gtx_clk_bufg)
--   begin
--     if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--       gmii_txd        <= gmii_txd_int;
--       gmii_tx_en      <= gmii_tx_en_int;
--       gmii_tx_er      <= gmii_tx_er_int;
       
--       gmii_rxd_int    <= gmii_rxd;
--       gmii_rx_dv_int  <= gmii_rx_dv;
--       gmii_rx_er_int  <= gmii_rx_er;
--     end if;
--   end process gmii_pipe;


  ------------------------------------------------------------------------------
  -- Generate resets required for the fifo side signals etc
  ------------------------------------------------------------------------------

   example_resets : tri_mode_ethernet_mac_internal_example_design_resets
   port map (
      -- clocks
      s_axi_aclk       => s_axi_aclk,
      gtx_clk          => gtx_clk_bufg,

      -- asynchronous resets
      glbl_rst         => glbl_rst,
      reset_error      => reset_error,
      Soft_Reset      => Soft_Reset,
      rx_reset         => rx_reset,
      tx_reset         => tx_reset,

      -- asynchronous reset output
  
      glbl_rst_intn    => glbl_rst_intn,
      -- synchronous reset outputs
   
      
      axi_lite_resetn  => axi_lite_resetn,
      
      vector_resetn    => vector_resetn,
      chk_resetn       => chk_resetn
   );

   -- generate the user side resets for the axi fifos
   
   tx_fifo_resetn <= axi_lite_resetn;
   rx_fifo_resetn <= axi_lite_resetn;
   

  ------------------------------------------------------------------------------
  -- Serialize the stats vectors
  -- This is a single bit approach, retimed onto gtx_clk
  -- this code is only present to prevent code being stripped..
  ------------------------------------------------------------------------------

  -- RX STATS

  -- first capture the stats on the appropriate clock
--   capture_rx_stats : process (rx_mac_aclk)
--   begin
--      if rx_mac_aclk'event and rx_mac_aclk = '1' then
--         rx_statistics_valid_reg <= rx_statistics_valid;
--         if rx_statistics_valid_reg = '0' and rx_statistics_valid = '1' then
--            rx_stats        <= rx_statistics_vector;
--            rx_stats_toggle <= not rx_stats_toggle;
--         end if;
--      end if;
--   end process capture_rx_stats;

--   rx_stats_sync : tri_mode_ethernet_mac_internal_sync_block
--   port map (
--      clk              => gtx_clk_bufg,
--      data_in          => rx_stats_toggle,
--      data_out         => rx_stats_toggle_sync
--   );

--   reg_rx_toggle : process (gtx_clk_bufg)
--   begin
--      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         rx_stats_toggle_sync_reg <= rx_stats_toggle_sync;
--      end if;
--   end process reg_rx_toggle;

   -- when an update is rxd load shifter (plus start/stop bit)
   -- shifter always runs (no power concerns as this is an example design)
--   gen_shift_rx : process (gtx_clk_bufg)
--   begin
--      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         if (rx_stats_toggle_sync_reg xor rx_stats_toggle_sync) = '1' then
--            rx_stats_shift <= '1' & rx_stats &  '1';
--         else
--            rx_stats_shift <= rx_stats_shift(28 downto 0) & '0';
--         end if;
--      end if;
--   end process gen_shift_rx;

--   rx_statistics_s <= rx_stats_shift(29);

  -- TX STATS

  -- first capture the stats on the appropriate clock
--   capture_tx_stats : process (tx_mac_aclk)
--   begin
--      if tx_mac_aclk'event and tx_mac_aclk = '1' then
--         tx_statistics_valid_reg <= tx_statistics_valid;
--         if tx_statistics_valid_reg = '0' and tx_statistics_valid = '1' then
--            tx_stats        <= tx_statistics_vector;
--            tx_stats_toggle <= not tx_stats_toggle;
--         end if;
--      end if;
--   end process capture_tx_stats;

--   tx_stats_sync : tri_mode_ethernet_mac_internal_sync_block
--   port map (
--      clk              => gtx_clk_bufg,
--      data_in          => tx_stats_toggle,
--      data_out         => tx_stats_toggle_sync
--   );

--   reg_tx_toggle : process (gtx_clk_bufg)
--   begin
--      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         tx_stats_toggle_sync_reg <= tx_stats_toggle_sync;
--      end if;
--   end process reg_tx_toggle;

   -- when an update is txd load shifter (plus start bit)
   -- shifter always runs (no power concerns as this is an example design)
--   gen_shift_tx : process (gtx_clk_bufg)
--   begin
--      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         if (tx_stats_toggle_sync_reg /= tx_stats_toggle_sync) then
--            tx_stats_shift <= '1' & tx_stats & '1';
--         else
--            tx_stats_shift <= tx_stats_shift(32 downto 0) & '0';
--         end if;
--      end if;
--   end process gen_shift_tx;

--   tx_statistics_s <= tx_stats_shift(33);

  ------------------------------------------------------------------------------
  -- DESerialize the Pause interface
  -- This is a single bit approachtimed on gtx_clk
  -- this code is only present to prevent code being stripped..
  ------------------------------------------------------------------------------
  -- the serialised pause info has a start bit followed by the quanta and a stop bit
  -- capture the quanta when the start bit hits the msb and the stop bit is in the lsb
--   gen_shift_pause : process (gtx_clk_bufg)
--   begin
--      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         pause_shift <= pause_shift(17 downto 0) & pause_req_s_sync_gtx_clk;
--      end if;
--   end process gen_shift_pause;

   -- Pause generation is disabled in the active implementation.
   grab_pause : process (gtx_clk_bufg)
   begin
      if gtx_clk_bufg'event and gtx_clk_bufg = '1' then
--         if (pause_shift(18) = '0' and pause_shift(17) = '1' and pause_shift(0) = '1') then
--            pause_req <= '1';
--            pause_val <= pause_shift(16 downto 1);
--         else
            pause_req <= '0';
            pause_val <= (others => '0');
--         end if;
      end if;
   end process grab_pause;



  ------------------------------------------------------------------------------
  -- Instantiate the Config vector controller Controller
  ----------------------------------------------------------------------------
  config_vector_controller : tri_mode_ethernet_mac_internal_config_vector_sm
    port map (
      
       gtx_clk                      => s_axi_aclk,
       
       gtx_resetn                   => vector_resetn,

   
       mac_speed                    => mac_speed_sync_axilite_clk,
       update_speed                 => update_speed_sync_axilite_clk,
       

       rx_configuration_vector      => rx_configuration_vector,
       tx_configuration_vector      => tx_configuration_vector
   );


   ------------------------------------------------------------------------------
   -- Instantiate the TRIMAC core FIFO Block wrapper
   ------------------------------------------------------------------------------
   trimac_fifo_block : tri_mode_ethernet_mac_internal_fifo_block
    port map (
       gtx_clk                      => gtx_clk_bufg,
       
       
       -- asynchronous reset
        glbl_rstn                   => glbl_rst_intn,
        rx_axi_rstn                 => '1',
        tx_axi_rstn                 => '1',


       -- Receiver Statistics Interface
       -----------------------------------------
       rx_mac_aclk                  => open,--rx_mac_aclk,
       rx_reset                     => open,--rx_reset,
       rx_statistics_vector         => open,--rx_statistics_vector,
       rx_statistics_valid          => open,--rx_statistics_valid,

       -- Receiver => AXI-S Interface
       ------------------------------------------
       rx_fifo_clock                => rx_fifo_clock,
       rx_fifo_resetn               => rx_fifo_resetn,
       rx_axis_fifo_tready          => rx_axis_fifo_tready,
       rx_axis_fifo_tvalid          => rx_axis_fifo_tvalid,
       rx_axis_fifo_tdata           => rx_axis_fifo_tdata,
       rx_axis_fifo_tlast           => rx_axis_fifo_tlast,
       rx_axis_fifo_tkeep           => rx_axis_fifo_tkeep,
       
       -- Transmitter Statistics Interface
       --------------------------------------------
       tx_mac_aclk                  => tx_mac_aclk,
       tx_reset                     => tx_reset,
       tx_ifg_delay                 => tx_ifg_delay,
       tx_statistics_vector         => tx_statistics_vector,
       tx_statistics_valid          => tx_statistics_valid,

       -- Transmitter => AXI-S Interface
       ---------------------------------------------
       tx_fifo_clock                => tx_fifo_clock,
       tx_fifo_resetn               => tx_fifo_resetn,
       tx_axis_fifo_tready          => tx_axis_fifo_tready,
       tx_axis_fifo_tvalid          => tx_axis_fifo_tvalid,
       tx_axis_fifo_tdata           => tx_axis_fifo_tdata,
       tx_axis_fifo_tlast           => tx_axis_fifo_tlast,
       tx_axis_fifo_tkeep           => tx_axis_fifo_tkeep,
       
       -- MAC Control Interface
       --------------------------
       pause_req                    => pause_req,
       pause_val                    => pause_val,

       -- GMII Interface
       -------------------
       gmii_txd                     => gmii_txd_int,
       gmii_tx_en                   => gmii_tx_en_int,
       gmii_tx_er                   => gmii_tx_er_int,
       gmii_rxd                     => gmii_rxd_int,
       gmii_rx_dv                   => gmii_rx_dv_int,
       gmii_rx_er                   => gmii_rx_er_int,
       speedis100                   => speedis100,
       speedis10100                 => speedis10100,
       -- Configuration Vector
       -------------------------
       rx_configuration_vector      => rx_configuration_vector,
       tx_configuration_vector      => tx_configuration_vector
   );

--ila_gtx_fifo_instance : Entity work.ila_gtx_fifo
--PORT MAP (
--	clk => tx_fifo_clock,
--	probe0(0) => rx_axis_fifo_tready, 
--	probe1(0) => rx_axis_fifo_tvalid, 
--	probe2 => rx_axis_fifo_tdata,  
--	probe3 => rx_axis_fifo_tkeep,  
--	probe4(0) => rx_axis_fifo_tlast,  
--	probe5(0) => tx_axis_fifo_tready,  
--	probe6(0) => tx_axis_fifo_tvalid,  
--	probe7 => tx_axis_fifo_tdata,   
--	probe8 => tx_axis_fifo_tkeep,  
--	probe9(0) => tx_axis_fifo_tlast  
--);


ctl_tx_test_pattern_en <= '0';--command_registers(2)(0);
   
 -- The legacy "pat_gen" block now routes application payloads, remote register
 -- access and terminal messages. Its active MAC-side streams are 64 bits wide.
 basic_pat_gen_inst : entity work.ethernet_mac_RGMII_basic_pat_gen
   port map (
       axi_tclk                     => tx_fifo_clock,
       axi_rclk                     => rx_fifo_clock,
       axi_tresetn                  => glbl_rst_intn,
       Soft_Reset                  => Soft_Reset,

       speed                        => "11",
--------------------------------------------------------------------------
       wr_ready                     => wr_ready,
       wr_clk                       => wr_clk,
       wr_en                        => wr_en,
       wr_last                      => wr_last,
       wr_data                      => WR_data, 
  
       rd_ready                     => rd_ready,       
       rd_clk                       => rd_clk,       
       rd_en                        => rd_en,         
       rd_data                      => rd_data, 
       rd_data_count                => rd_data_count , 
       data_len                     => data_len , 
  
       CMD_CODE                     => CMD_CODE,
       CMD_length                   => CMD_length,
--       CMD_clk                      => wr_clk,
       CMD_en                       => CMD_en,
       
       TRMOUT_clk                   => TRMOUT_clk   ,
       TRMOUT_EN                    => TRMOUT_EN   ,
       TRMOUT_Addr                  => TRMOUT_Addr ,
       TRMOUT_Data                  => TRMOUT_Data ,
                                 
       TRMIN_clk                     => TRMIN_clk    ,
       TRMIN_EN                     => TRMIN_EN    ,
       TRMIN_Addr                   => TRMIN_Addr  ,
       TRMIN_Data                   => TRMIN_Data  ,
             
       command_updates              => command_updates,
       command_registers            => command_registers,
       status_registers             => status_registers,
       read_only_regs               => read_only_regs,
-------------------------------------------------------------------------
--       rx_axis_tdata                => rx_axis_tdata ,
--       rx_axis_tvalid               => rx_axis_tvalid,
--       rx_axis_tlast                => rx_axis_tlast ,
--       rx_axis_tuser                => '0',
--       rx_axis_tready               => rx_axis_tready,

       rx_axis_tdata                => rx_axis_fifo_tdata ,
       rx_axis_tkeep                => rx_axis_fifo_tkeep ,
       rx_axis_tvalid               => rx_axis_fifo_tvalid,
       rx_axis_tlast                => rx_axis_fifo_tlast ,
       rx_axis_tuser                => '0',
       rx_axis_tready               => rx_axis_fifo_tready,

--       tx_axis_tdata                => tx_axis_tdata  ,
--       tx_axis_tvalid               => tx_axis_tvalid,
--       tx_axis_tlast                => tx_axis_tlast  ,
--       tx_axis_tready               => tx_axis_tready,
--       tx_axis_tkeep                => tx_axis_tkeep,
       tx_axis_tdata                => tx_axis_fifo_tdata  ,
       tx_axis_tvalid               => tx_axis_fifo_tvalid,
       tx_axis_tlast                => tx_axis_fifo_tlast  ,
       tx_axis_tready               => tx_axis_fifo_tready,
       tx_axis_tkeep                => tx_axis_fifo_tkeep,       

       frame_error                  => open,--mtrlb_pktchk_error,
       activity_flash               => open--mtrlb_activity_flash
   );

--Comint_rxtx_test : entity work.ila_2
--PORT MAP (
--	clk => tx_clk_lan,
	
--	probe0(0) => rx_axis_tvalid, 
--	probe1    => rx_axis_tdata, 
--	probe2(0) => rx_axis_tready, 
--	probe3(0) => rx_axis_tlast,
	
--	probe4(0) => tx_axis_tvalid,
--	probe5    => tx_axis_tdata, 
--	probe6(0) => tx_axis_tready,
--	probe7(0) => tx_axis_tlast 
--);

end wrapper;
