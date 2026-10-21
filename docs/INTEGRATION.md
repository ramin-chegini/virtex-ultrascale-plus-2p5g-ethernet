# Integration Guide

## Required files from the original system

The supplied source is a subsystem archive. The following dependencies are not present as standalone definitions in `HDL/`, and the MAC container inspected during preparation does not include its example-support hierarchy:

| Dependency | Required by / reason |
| --- | --- |
| `Reg_pack_comint` | Top, bridge, register bank, TX/RX and legacy buffer; provides shared widths/types and potentially protocol constants |
| `DF_pack` | Active TX and RX import this package |
| `tri_mode_ethernet_mac_internal_fifo_block` | Active top; declared with 64-bit application streams |
| `tri_mode_ethernet_mac_internal_config_vector_sm` | Active MAC configuration-vector controller |
| `tri_mode_ethernet_mac_internal_sync_block` | Active top control synchronizers |
| `tri_mode_ethernet_mac_internal_syncer_level` | Active top multi-bit control synchronizers; the supplied `ethernet_mac_RGMII_syncer_level` has a different entity name |
| `tri_mode_ethernet_mac_internal_example_design_clocks` | Active TX/control clock support |
| `tri_mode_ethernet_mac_internal_example_design_resets` | Active reset support, including the custom `Soft_Reset` port |
| Board XDC and original project settings | Package pins, actual clock periods, timing exceptions and system integration |

Restore these files from the tested design. Regenerating a stock MAC example may help recover a reference, but it does not establish equivalence to the custom 64-bit FIFO wrapper or reset interface used here.

`Bus_width` must agree with the active 64-bit application path. `NOofreg` and `std_logic_reg_array` must agree with the bridge's explicit 128-entry, 64-bit register instantiation. `HPR_ID` is referenced by the protocol constants, but its value cannot be recovered from the supplied packages because those packages are absent. Do not substitute guessed package values.

## IP selection

| Container / configuration | Use in the inspected hierarchy |
| --- | --- |
| `gig_ethernet_pcs_pma_0.xcix` | Active serial PCS/PMA, 2.5 Gb/s BASE-X, 156.25 MHz reference |
| `tri_mode_ethernet_mac_internal.xcix` | MAC used through the missing custom FIFO/example wrapper |
| `fifo_generator_4DB_2.xcix` | TX payload FIFO: 64-bit in/out, 32768 write words |
| `Data_Receiver_FIFO_orihard.xcix` | RX payload FIFO: 64-bit input, 512 write words; 8-bit output, 4096 read words |
| `fifo_generator_v9_3_1_orihard.xcix` | TX command/length queues: 16-bit words, depth 32 |
| `register_data_fifo_orihard_2.xcix` | TX response/terminal data queues: 64-bit words, depth 32 |
| `register_addr_fifo_orihard_1.xcix` | Contains instance `register_addr_fifo_orihard`, used by TX address queues: 8-bit words, depth 32 |
| `fifo_generator_4DB.xci` | Legacy 8-to-32-bit FIFO used by `Double_Buffer_deck` |
| Other Ethernet, register, clock and ILA containers | Retained source inventory; not all are instantiated by the active hierarchy |

The address FIFO archive name ending in `_1` differs from its internal instance name. Import by the contained IP definition, rather than renaming the VHDL instance to match the filename. Avoid importing duplicate configurations for the same logical IP. Existing generated wrappers/stubs in `IP/` are reference artifacts; do not add both a stub and its implementation to the active synthesis fileset.

## Clock and reset mapping

| Signal / domain | Active connection |
| --- | --- |
| `mgt_clk_p/n` | PCS/PMA differential reference input; archive specifies 156.25 MHz |
| `independent_clock_bufg` | PCS/PMA independent support clock; archive specifies a 100 MHz DRP clock |
| `gtx_clk_bufg` | PCS `userclk2_out`, used on the GMII/MAC side |
| `axi_lite_clk` | PCS `userclk_out`, passed to the example clock-support block |
| `s_axi_aclk` / `tx_fifo_clock` | Example clock-support output; active TX application clock and configuration-controller clock |
| `axi_rclk` / `rx_fifo_clock` | PCS `rxuserclk_out`; active receive/parser/register domain |
| `rxC156_25M_Clk_Comint` | Direct export of `axi_rclk` |
| `wr_clk` | External payload and command FIFO write clock |
| `rd_clk` | External receive-byte FIFO read clock |
| `TRMIN_clk` | External terminal-message write clock |
| `TRMOUT_clk` | Export of the receive/parser clock |

Names containing `156_25M` are historical labels and do not independently establish the frequency of the connected signal. Derive actual periods and relationships from the restored IP support, generated constraints, and tested project. The `C156_25M_Clk_Comint` output has no active assignment in this snapshot.

`glbl_rst` is active high at the PCS/PMA and example reset support. The example support generates active-low `glbl_rst_intn`, `axi_lite_resetn`, `vector_resetn`, and `chk_resetn`. The application bridge inverts `axi_tresetn` for its internal active-high reset. The TX engine combines that reset with `Soft_Reset`; the example reset wrapper also receives `Soft_Reset`, but its implementation is absent. The register-bank reset is explicitly tied to zero, and command register storage has no reset assignment.

Use the original startup/reset sequence, with the required clocks running before traffic. `mmcm_locked_out` reports the PCS clock-support lock output. It is not a complete link-ready indication: PCS `resetdone` and `status_vector` are left open in the top.

## Transmit contract

Write payload words in `wr_clk` and observe `wr_ready`. The ready output is the inverse of the payload FIFO's almost-full flag; the FIFO write enable is connected directly to `wr_en`, without an internal ready gate. The top's `inout` declaration is a legacy interface choice: the surrounding design should consume this signal as a core output.

Present `CMD_CODE` and `CMD_length` together and pulse `CMD_en` in `wr_clk`. Both fields enter paired FIFOs. There is no command-ready output, and queue full flags are not exposed. The producer must limit outstanding commands using the tested system's scheduling. Payload commands are fetched only when the payload FIFO is not almost empty; this condition does not verify that an entire requested frame is buffered.

The active stream marks all eight bytes valid on every beat. Supply the existing protocol's aligned lengths; the counter advances in eight-byte steps and no general partial-word path is implemented. `wr_last` is passed into the TX block but is not used by its active logic. Frame boundaries come from commands and lengths.

Idle arbitration selects terminal messages first, then register-read responses, then external payload commands. Ordinary lengths above TX `MAX_SIZE=0x2100` are clamped. Although the difference is stored in `overflow`, no automatic follow-up frame is scheduled by the supplied logic.

## Receive contract

The RX payload FIFO crosses from the parser clock to `rd_clk` and outputs bytes. Read using `rd_en`, the available-count indication, and the original FIFO latency. The archived RX FIFO is configured as `Standard_FIFO`; it should not be treated as first-word fall-through.

`rd_ready` is generated by the parser as `rx_data_ready`. It is asserted during the DATA footer handling, and the same logic can assert it on a full condition. It is not a persistent FIFO-not-empty or error-free-packet indication. `data_len` is captured in that parser domain. When consuming these in `rd_clk`, use the original event synchronization and stable-data handshake; the top adds neither.

`rd_data_count` is a 12-bit IP count output. Its exact full-capacity behavior and read latency remain properties of the archived FIFO, rather than a separate guarantee from the application RTL. The parser supplies receive backpressure through the FIFO almost-full indication, but does not implement a general per-byte `TKEEP` decoder.

## Register and terminal contract

The register bank runs in `axi_rclk`. Keep `status_registers` coherent there and handle `command_updates` in that domain or cross it explicitly into the consuming logic. `read_only_regs` selects read data from command storage or external status; it does not inhibit writes to command storage.

`TRMIN_EN`, address and data enter paired TX queues in `TRMIN_clk`. The receiver emits `TRMOUT_EN`, address and data with `TRMOUT_clk`. Neither external terminal interface includes a ready signal. Register-read responses use the receive clock for their queue writes and the transmit clock for their queue reads.

## Retained control and diagnostic ports

The top synchronizes `mac_speed` and `update_speed` into example-support domains, but the application bridge's `speed` input is fixed to `"11"`. Preserve the original 2.5 Gb/s configuration rather than assuming that legacy speed ports implement a complete runtime rate-switching interface.

The active pause process drives request and value to zero. The serial pause decode and statistics serializers are commented out. `LED1`, `C156_25M_Clk_Comint`, `tx_statistics_s`, and `rx_statistics_s` have no active drivers in the supplied top. `frame_error` and `activity_flash` are assigned from internal signals that have no active producers. Their inverted counterparts inherit the same limitation. Do not use these outputs as validated health indicators without restoring their original support.

The PCS `signal_detect` input is tied high. SFP module presence, loss-of-signal, TX-disable, and management/I2C control are not implemented by this top-level interface; board-level logic must provide any required module control.
