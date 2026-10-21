--------------------------------------------------------------------------------
-- File       : ethernet_mac_RGMII_basic_pat_gen.vhd
-- Author     : Xilinx Inc.
-- -----------------------------------------------------------------------------
-- (c) Copyright 2010 Xilinx, Inc. All rights reserved.
--
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and
-- international copyright and other intellectual property
-- laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Xilinx products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- -----------------------------------------------------------------------------
-- Description:  This module allows either a user side loopback, with address swapping,
-- OR the generation of simple packets.  The selection being controlled by a top level input
-- which can be sourced fdrom a DIP switch in hardware.
-- The packet generation is controlled by simple parameters giving the ability to set the DA,
-- SA amd max/min size packets.  The data portion of each packet is always a simple
-- incrementing pattern.
-- When configured to loopback the first 12 bytes of the packet are accepted and then the
-- packet is output with/without address swapping.  Currently, this is hard wired in the address
-- swap logic.
--
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use work.Reg_pack_comint.ALL;
library unisim;
use unisim.vcomponents.all;

-- Application packet bridge retained under its original example-design name.
-- TX and RX use separate MAC FIFO clocks; asynchronous IP FIFOs carry payloads
-- and responses between these domains and the external user clocks.
entity ethernet_mac_RGMII_basic_pat_gen is
   generic (
      DEST_ADDR                  : bit_vector(47 downto 0) := X"00110A6C4AA8";
      SRC_ADDR                   : bit_vector(47 downto 0) := X"5a0102030405";
      MAX_SIZE                   : unsigned(15 downto 0) := X"2100";
      MIN_SIZE                   : unsigned(15 downto 0) := X"0032";
      ENABLE_VLAN                : boolean := false;
      VLAN_ID                    : bit_vector(11 downto 0) := X"002";
      VLAN_PRIORITY              : bit_vector(2 downto 0) := "010"
   );
   port (
    axi_tclk                     : in  std_logic;
    axi_rclk                     : in  std_logic;
    axi_tresetn                  : in  std_logic;
    Soft_Reset                  : in  std_logic;
--    check_resetn                 : in  std_logic;

    --enable_pat_gen               : in  std_logic;
--    enable_pat_chk               : in  std_logic;
--    enable_address_swap          : in  std_logic;
    speed                        : in  std_logic_vector(1 downto 0);
    ----------------------------------------------------------------------
--    stat_tx_packet_small         : in std_logic ;
--    stat_tx_packet_large         : in std_logic;
--    stat_tx_unicast              : in std_logic;
--    stat_tx_multicast            : in std_logic;
--    stat_tx_broadcast            : in std_logic;
--    stat_tx_vlan                 : in std_logic;
--    stat_tx_frame_error          : in std_logic;
    ----------------------------------------------------------------------
--    Soft_reset                   : in  std_logic;
    -- data from the user bus
    wr_ready                        : inout std_logic;
    wr_clk                          : in  std_logic;
    wr_en                           : in  std_logic;
    wr_last                         : in  std_logic;
    wr_data                         : in  std_logic_vector(63 downto 0);
    -- data from the user bus    
    rd_ready                        : out std_logic;
    rd_clk                          : in  std_logic;
    rd_en                           : in  std_logic;
    rd_data                         : out  std_logic_vector(7 downto 0); 
    rd_data_count                   : out  std_logic_vector(11 downto 0); 
    data_len                        : out std_logic_vector(15 downto 0) ;
    
    CMD_CODE                        : in std_logic_vector(15 downto 0);
    CMD_length                      : in std_logic_vector(15 downto 0);
--    CMD_clk                         : in std_logic;                     
    CMD_en                          : in std_logic; 

    TRMOUT_clk                       : out std_logic;  
    TRMOUT_EN                       : out std_logic;  
    TRMOUT_Addr                     : out std_logic_vector(7 downto 0);
    TRMOUT_Data                     : out std_logic_vector(63 downto 0);
                                   
    TRMIN_clk                        : in std_logic;  
    TRMIN_EN                        : in std_logic;  
    TRMIN_Addr                      : in std_logic_vector(7 downto 0);
    TRMIN_Data                      : in std_logic_vector(63 downto 0);
 
    -- control register
    command_updates                 : out std_logic_vector(NOofreg-1  downto 0);   
    command_registers               : out std_logic_reg_array(NOofreg-1 downto 0);  
    status_registers                : in std_logic_reg_array(NOofreg-1 downto 0); 
    read_only_regs                  : in  std_logic_vector(NOofreg-1 downto 0); 
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
    -- data from the RX data path
    rx_axis_tdata                : in  std_logic_vector(63 downto 0);
    rx_axis_tkeep                : in  std_logic_vector(7 downto 0);
    rx_axis_tvalid               : in  std_logic;
    rx_axis_tlast                : in  std_logic;
    rx_axis_tuser                : in  std_logic;
    rx_axis_tready               : out std_logic;
    -- data TO the TX data path
    tx_axis_tdata                : out std_logic_vector(63 downto 0);
    tx_axis_tkeep                : out std_logic_vector(7 downto 0);
    tx_axis_tvalid               : out std_logic;
    tx_axis_tlast                : out std_logic;
    tx_axis_tready               : in  std_logic;

    frame_error                  : out std_logic;
    activity_flash               : out std_logic
   );
end ethernet_mac_RGMII_basic_pat_gen;

architecture rtl of ethernet_mac_RGMII_basic_pat_gen is

   attribute DowngradeIPIdentifiedWarnings: string;
   attribute DowngradeIPIdentifiedWarnings of rtl : architecture is "yes";

   ------------------------------------------------------------------------------
   -- Component Declaration for the ethernet_mac_RGMII_axi_pipe
   ------------------------------------------------------------------------------
   component ethernet_mac_RGMII_axi_pipe
   port (
      axi_tclk                         : in  std_logic;
      axi_tresetn                      : in  std_logic;

      rx_axis_fifo_tdata_in            : in  std_logic_vector(7 downto 0);
      rx_axis_fifo_tvalid_in           : in  std_logic;
      rx_axis_fifo_tlast_in            : in  std_logic;
      rx_axis_fifo_tready_in           : out std_logic;

      rx_axis_fifo_tdata_out           : out std_logic_vector(7 downto 0);
      rx_axis_fifo_tvalid_out          : out std_logic;
      rx_axis_fifo_tlast_out           : out std_logic;
      rx_axis_fifo_tready_out          : in  std_logic
   );
   end component;

   ------------------------------------------------------------------------------
   -- Component Declaration for the ethernet_mac_RGMII_axi_mux
   ------------------------------------------------------------------------------
   component ethernet_mac_RGMII_axi_mux
   port (
      mux_select                 : in  std_logic;

      -- mux inputs
      tdata0                     : in  std_logic_vector(7 downto 0);
      tvalid0                    : in  std_logic;
      tlast0                     : in  std_logic;
      tready0                    : out std_logic;

      tdata1                     : in  std_logic_vector(7 downto 0);
      tvalid1                    : in  std_logic;
      tlast1                     : in  std_logic;
      tready1                    : out std_logic;

      -- mux outputs
      tdata                      : out std_logic_vector(7 downto 0);
      tvalid                     : out std_logic;
      tlast                      : out std_logic;
      tready                     : in  std_logic
   );
   end component;

   ------------------------------------------------------------------------------
   -- Component Declaration for the ethernet_mac_RGMII_axi_pat_gen
   ------------------------------------------------------------------------------
   component ethernet_mac_RGMII_axi_pat_gen
   generic (
      DEST_ADDR                  : bit_vector(47 downto 0) := X"00110A6C4AA8";
      SRC_ADDR                   : bit_vector(47 downto 0) := X"5a0102030405";
      MAX_SIZE                   : unsigned(15 downto 0) := X"01f4";
      MIN_SIZE                   : unsigned(15 downto 0) := X"0040";
      ENABLE_VLAN                : boolean := false;
      VLAN_ID                    : bit_vector(11 downto 0) := X"002";
      VLAN_PRIORITY              : bit_vector(2 downto 0) := "010"
   );
   port (
      axi_tclk                   : in  std_logic;
      axi_tresetn                : in  std_logic;

      --enable_pat_gen             : in  std_logic;
      speed                      : in  std_logic_vector(1 downto 0);

      tdata                      : out std_logic_vector(7 downto 0);
      tvalid                     : out std_logic;
      tlast                      : out std_logic;
      tready                     : in  std_logic
   );
   end component;

   ------------------------------------------------------------------------------
   -- Component Declaration for the ethernet_mac_RGMII_axi_pat_check
   ------------------------------------------------------------------------------
   component ethernet_mac_RGMII_axi_pat_check
   generic (
      DEST_ADDR                  : bit_vector(47 downto 0) := X"00110A6C4AA8";
      SRC_ADDR                   : bit_vector(47 downto 0) := X"5a0102030405";
      MAX_SIZE                   : unsigned(11 downto 0) := X"1f4";
      MIN_SIZE                   : unsigned(11 downto 0) := X"040";
      ENABLE_VLAN                : boolean := false;
      VLAN_ID                    : bit_vector(11 downto 0) := X"002";
      VLAN_PRIORITY              : bit_vector(2 downto 0) := "010"
   );
   port (
      axi_tclk                   : in  std_logic;
      axi_tresetn                : in  std_logic;

--      enable_pat_chk             : in  std_logic;
      speed                      : in  std_logic_vector(1 downto 0);

      tdata                      : in  std_logic_vector(7 downto 0);
      tvalid                     : in  std_logic;
      tlast                      : in  std_logic;
      tready                     : in  std_logic;
      tuser                      : in  std_logic;

      frame_error                : out std_logic;
      activity_flash             : out std_logic
   );
   end component;

   ------------------------------------------------------------------------------
   -- Component Declaration for the ethernet_mac_RGMII_address_swap
   ------------------------------------------------------------------------------
   component ethernet_mac_RGMII_address_swap
   port (
    axi_tclk                        : in  std_logic;
    axi_tresetn                     : in  std_logic;

--    enable_address_swap             : in  std_logic;

    -- data from the RX FIFO
    rx_axis_fifo_tdata              : in  std_logic_vector(7 downto 0);
    rx_axis_fifo_tvalid             : in  std_logic;
    rx_axis_fifo_tlast              : in  std_logic;
    rx_axis_fifo_tready             : out std_logic;
    -- data TO the tx fifo
    tx_axis_fifo_tdata              : out std_logic_vector(7 downto 0);
    tx_axis_fifo_tvalid             : out std_logic;
    tx_axis_fifo_tlast              : out std_logic;
    tx_axis_fifo_tready             : in std_logic

  );
  end component;


  ------------------------------------------------------------------------------
  -- Component declaration for the synchroniser
  ------------------------------------------------------------------------------
  component ethernet_mac_RGMII_sync_block
  port (
     clk                        : in  std_logic;
     data_in                    : in  std_logic;
     data_out                   : out std_logic
  );
  end component;

  component ethernet_mac_RGMII_syncer_level is
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

   signal rx_axis_fifo_tdata_int      : std_logic_vector(7 downto 0);
   signal rx_axis_fifo_tvalid_int     : std_logic;
   signal rx_axis_fifo_tlast_int      : std_logic;
   signal rx_axis_fifo_tready_int     : std_logic;
   signal rx_axis_tready_lcl          : std_logic;

   signal pat_gen_tdata               : std_logic_vector(7 downto 0);
   signal pat_gen_tvalid              : std_logic;
   signal pat_gen_tlast               : std_logic;
   signal pat_gen_tready              : std_logic;
   signal pat_gen_tready_int          : std_logic;

   signal mux_tdata                   : std_logic_vector(7 downto 0);
   signal mux_tvalid                  : std_logic;
   signal mux_tlast                   : std_logic;
   signal mux_tready                  : std_logic;

   signal tx_axis_as_tdata            : std_logic_vector(7 downto 0);
   signal tx_axis_as_tvalid           : std_logic;
   signal tx_axis_as_tlast            : std_logic;
   signal tx_axis_as_tready           : std_logic;


   signal axi_tx_treset               : std_logic;
   signal check_rx_reset              : std_logic;
   signal speed_sync_tx_clk           : std_logic_vector(1 downto 0);
   signal speed_sync_rx_clk           : std_logic_vector(1 downto 0);
   signal enable_pat_gen_sync_tx_clk  : std_logic;
   signal enable_pat_chk_sync_rx_clk  : std_logic;

   signal RD_Reg,WR_Reg          : std_logic;
   signal reset                     : std_logic;
   signal Reg_Addr                : std_logic_vector(7 downto 0);    
   signal reg_data_RD,reg_data_WR               : std_logic_vector(63 downto 0);   
   signal reg_RD_val               : std_logic;   

   signal Soft_Cmd_CODE      : std_logic_vector(15 downto 0);
   signal Soft_Cmd_length    : std_logic_vector(15 downto 0);
   signal Soft_CMD_wr_en     : std_logic;
   signal Soft_CMD_clk       : std_logic;

   signal Cmd_CODE_int     : std_logic_vector(15 downto 0);
   signal Cmd_length_int    : std_logic_vector(15 downto 0);
   signal CMD_en_int     : std_logic;
   signal CMD_clk_int       : std_logic;
begin

-- External CMD_* uses wr_clk. Register readbacks enter through Soft_CMD_clk;
-- terminal messages enter through TRMIN_clk. TX arbitration is inside this block.
output_tx_inst :entity work.tri_mode_ethernet_mac_v5_5_0_axi_pat_gen
       generic map (
          DEST_ADDR                 => DEST_ADDR,
          SRC_ADDR                  => SRC_ADDR,
--          MAX_SIZE                  => x"2000", 
--          MIN_SIZE                  => x"", 
          ENABLE_VLAN               => ENABLE_VLAN,
          VLAN_ID                   => VLAN_ID,
          VLAN_PRIORITY             => VLAN_PRIORITY
       )
       port map (
            axi_tclk                      => axi_tclk,
            axi_treset                    => reset,
            Soft_reset                    => Soft_reset,

            speed                         => speed,
            speed_value                   => X"FF",

            wr_ready                      => wr_ready,
            wr_clk                        => wr_clk,
            wr_en                         => wr_en,
            wr_last                       => wr_last,
            wr_data                       => wr_data,
            
            TRM_clk                       => TRMIN_clk,
            RD_TRM                        => TRMIN_EN,
            TRM_Addr                      => TRMIN_Addr,
            TRM_Data                      => TRMIN_Data,

            RD_Reg                        =>  reg_RD_val, 
            Reg_Addr                      =>  Reg_Addr, 
            reg_data                      =>  reg_data_RD ,

            CMD_CODE                      => CMD_CODE   ,
            CMD_length                    => CMD_length ,
            CMD_en                        => CMD_en     ,
            
            Soft_CMD_CODE                 => Soft_CMD_CODE    , 
            Soft_CMD_length               => Soft_CMD_length ,
            Soft_CMD_clk                  => Soft_CMD_clk    ,
            Soft_CMD_en                   => Soft_CMD_wr_en,

            tdata_t                       => tx_axis_tdata,
            tkeep_t                       => tx_axis_tkeep,
            tvalid_t                      => tx_axis_tvalid,
            tlast_t                       => tx_axis_tlast,
            tready                        => tx_axis_tready
      
--            stat_tx_packet_small   => stat_tx_packet_small    ,
--            stat_tx_packet_large   => stat_tx_packet_large    ,
--            stat_tx_unicast        => stat_tx_unicast         ,
--            stat_tx_multicast      => stat_tx_multicast       ,
--            stat_tx_broadcast      => stat_tx_broadcast       ,
--            stat_tx_vlan           => stat_tx_vlan            ,
--            stat_tx_frame_error    => stat_tx_frame_error     
   );

   -- Incoming destination matching uses this bridge's SRC_ADDR (local MAC).
   input_rx_inst :entity work.tri_mode_ethernet_mac_v5_5_0_rx
        generic map (
      DEST_ADDR                 =>  SRC_ADDR
      )  
   port map (
      axi_tclk                  => axi_rclk,
      axi_treset                => reset,

      rx_axis_fifo_tdata        => rx_axis_tdata,
      rx_axis_fifo_tkeep        => rx_axis_tkeep,
      rx_axis_fifo_tvalid       => rx_axis_tvalid,
      rx_axis_fifo_tlast        => rx_axis_tlast,
      rx_axis_fifo_tready       => rx_axis_tready,
      
      data_len                  =>  data_len,
      rd_data_count             =>  rd_data_count,
      rx_data                   =>  rd_data,
      rx_rd_en                  =>  rd_en,
      rx_data_ready             =>  rd_ready,
      rx_clk                    =>  rd_clk, 
 
      Soft_Cmd_CODE             =>  Soft_Cmd_CODE, 
      Soft_Cmd_length           =>  Soft_Cmd_length, 
      Soft_CMD_wr_en            =>  Soft_CMD_wr_en, 
      Soft_CMD_clk              =>  Soft_CMD_clk, 
      
      TRM_clk                   => TRMOUT_clk   ,
      WR_TRM                    => TRMOUT_EN   ,
      TRM_Addr                  => TRMOUT_Addr ,
      TRM_Data                  => TRMOUT_Data ,
     
      RD_Reg                    =>  RD_Reg, 
      WR_Reg                    =>  WR_Reg, 
      Reg_Addr                  =>  Reg_Addr, 
      reg_data                  =>  reg_data_WR 

   );
  
--    CMD_CODE_int   <= CMD_CODE     when Soft_CMD_wr_en ='0' else Soft_Cmd_CODE;  
--    CMD_length_int <= CMD_length   when Soft_CMD_wr_en ='0' else Soft_Cmd_length;
--    CMD_clk_int    <= CMD_clk      when Soft_CMD_wr_en ='0' else (Soft_CMD_clk) ; 
--    CMD_en_int     <= CMD_en       when Soft_CMD_wr_en ='0' else '1' ;   

    reset <= not (axi_tresetn);
    
   -- The active bank has 128 x 64-bit entries in axi_rclk. Reset is tied low;
   -- do not assume global/soft reset clears command register contents.
   Config_Register_install :entity work.Config_Register_Comint 
     generic map( Width => 64, num_reg => 128	) 
   	 Port map( clk => axi_rclk,
              Reset => '0',
              RegData_RD  => reg_data_RD,
              RD_val  => reg_RD_val,
              RegData_WR  => reg_data_WR,
              RegAddr  => Reg_Addr,
              read_only_regs    => read_only_regs,-- X"000000000000000000000000000000000000000000000000000000000000000" & "0001",
              command_registers => command_registers,
              status_registers  => status_registers,
              command_updates   => command_updates,
              RD => RD_Reg,
              WR => WR_Reg);

end rtl;
