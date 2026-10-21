--------------------------------------------------------------------------------
-- Title      : CDC Sync Block
-- Project    : Tri-Mode Ethernet MAC
--------------------------------------------------------------------------------
-- File       : ethernet_mac_RGMII_syncer_level.vhd
-- Author     : Xilinx Inc.
--------------------------------------------------------------------------------
-- Description: Used on signals crossing from one clock domain to another, this
--              is a multiple flip-flop pipeline, with all flops placed together
--              into the same slice.  Thus the routing delay between the two is
--              minimum to safe-guard against metastability issues.
-- -----------------------------------------------------------------------------
-- (c) Copyright 2004-2013 Xilinx, Inc. All rights reserved.
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


library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

-- Three destination-clock register stages for slowly changing control levels.
-- For WIDTH > 1 this does not guarantee atomic bus capture; hold the source
-- stable around an update. It is not a pulse synchronizer or payload FIFO.
-- This entity name differs from the TEMAC synchronizer used by the active top.
entity ethernet_mac_RGMII_syncer_level is
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

  attribute dont_touch : string;
  attribute dont_touch of  ethernet_mac_RGMII_syncer_level : entity is "yes";

end ethernet_mac_RGMII_syncer_level;  

architecture rtl of ethernet_mac_RGMII_syncer_level is 

  signal  dataout_reg : std_logic_vector(WIDTH-1 downto 0);
  signal  meta_nxt    : std_logic_vector(WIDTH-1 downto 0);
  signal  dataout_nxt : std_logic_vector(WIDTH-1 downto 0);

  signal  meta        : std_logic_vector(WIDTH-1 downto 0);
  signal  meta2       : std_logic_vector(WIDTH-1 downto 0);

  attribute async_reg : string;
  attribute async_reg of dataout_reg  : signal is "true";
  attribute async_reg of meta         : signal is "true";
  attribute async_reg of meta2        : signal is "true";

begin

  meta_nxt <= datain;

  process(clk)
  begin
    if(rising_edge(clk)) then
      if(reset = '1') then 
        meta  <= (others => RESET_VALUE);
        meta2 <= (others => RESET_VALUE);
      else
        meta  <= meta_nxt;
        meta2 <= meta;
      end if;
    end if;
  end process;

  dataout_nxt <= meta2;

  process(clk)
  begin
    if(rising_edge(clk)) then
      if(reset = '1') then
        dataout_reg <= (others => RESET_VALUE);
      else
        dataout_reg <= dataout_nxt;
      end if;
    end if;
  end process;

  dataout <= dataout_reg;

end rtl;


