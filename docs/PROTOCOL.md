# Layer-2 Application Protocol

This document records the format visible in the supplied RTL. Numeric values from the missing shared packages and host-software behavior are not assumed. Use the tested host implementation or a known-good capture as the compatibility reference.

## Active transmit layout

MAC-facing data is 64 bits wide. Byte lane 0 is `tdata(7 downto 0)`; the TX concatenations place each intended first wire byte in that lane. The packet engine uses a fixed 96-bit address header:

```vhdl
MAC_Header := x"FFFFFFFFFFFF5A0102030405";
```

| Byte position | Field | Value / source |
| --- | --- | --- |
| 0-5 | Destination MAC | `FF:FF:FF:FF:FF:FF` |
| 6-11 | Source MAC | `5A:01:02:03:04:05` |
| 12-13 | Application size | `pkt_size`, most significant byte first, with the mask described below |
| 14-15 | Application command | `Cmd_CODE_reg`, most significant byte first |
| Following bytes | Data / control body | Payload FIFO words or register/terminal response data |
| Final 8-byte beat | Application footer | `00 16 00 00 00 00 00 00` |

Preamble, FCS and physical encoding belong to the MAC/PCS path; the footer above is application data, not an Ethernet FCS. The complete custom MAC support and its effective configuration are needed to determine all MAC-level insertion and length settings.

The second-beat construction applies `or x"00000080"` to the concatenation of command-low, command-high, size-low and size-high before appending the remaining source-MAC bytes. With the existing lane order, this forces bit 7 of the **high size byte** to one, equivalent to `pkt_size or 0x8000` in the wire field. For example, a requested size of `0x0040` produces size bytes `80 40`. This behavior was preserved during documentation. The RX code does not visibly clear that bit when loading `Pack_Size`; compatibility must follow the original peer protocol rather than silently masking the value in a new implementation.

The TX `DEST_ADDR` and `SRC_ADDR` generics do not control the actual address bytes in this implementation: `MAC_Header` does. The wrapper's default `DEST_ADDR=00:11:0A:6C:4A:A8` therefore does not replace the broadcast destination on outgoing frames. The wrapper's `SRC_ADDR` is used as the incoming local destination filter.

The size/command occupy a custom layout starting at the normal Ethernet length/type position. No standard EtherType or IP/UDP header is constructed by this packet engine. The active assignments do not insert a VLAN tag despite retained VLAN-related generics.

## Command codes

The high byte of each command is `HPR_ID`; its definition is not included in this repository.

| Symbol | Expression in RTL | Observed routing |
| --- | --- | --- |
| `DATA_CODE` | `HPR_ID & x"81"` | RX data body is written to the external receive FIFO |
| `WR_REG_CODE` | `HPR_ID & x"82"` | RX updates command-register storage |
| `RD_REG_CODE` | `HPR_ID & x"83"` | RX requests a register read and queues a TX readback response |
| `WR_TRM_CODE` | `HPR_ID & x"84"` | RX emits a terminal write; TX also uses this code for queued terminal messages |
| `RD_TRM_CODE` | `HPR_ID & x"85"` | Constant declared in RX; no corresponding read handler is implemented in the supplied logic |
| `FOOTER_CODE` | `x"0016"` | TX application footer marker |

Terminal-originated TX commands and remote register-read responses use a queued length of `0x0040`. External payload commands supply their own `CMD_length`. The TX's active default maximum is `0x2100` (8448); that limit alone does not establish the effective MAC MTU or maximum working frame size.

## Receive parsing

The RX pipeline reverses each MAC word into a most-significant-byte-first parser word and delays data and control through registers. It captures a 48-bit destination MAC, then the size and command from the second header word. The active bridge maps the RX destination generic to its `SRC_ADDR`, whose default is `5A:01:02:03:04:05`.

Matching DATA commands populate the 64-to-8-bit FIFO. Matching control commands produce register or terminal strobes at the end of the decoded frame. The parser uses fixed byte counters in eight-byte steps. It does not validate the TX footer marker, and the top does not forward an RX `TUSER` error indication into this decoder.

The local destination comparison does not accept arbitrary broadcast frames as local commands. A compatible peer should use the configured local MAC for commands directed to this core. The RX/TX defaults are asymmetric: TX sends broadcast; RX filters on its local MAC.

## Register and terminal body

The receive decoder captures the control body across two 64-bit words:

```text
First body word:  address, data[63:56], data[55:48], ..., data[15:8]
Second body word: data[7:0], remaining bytes
```

This corresponds to one address byte followed by eight register/terminal data bytes, with the most significant data byte first. The TX response uses its existing concatenations to emit an address and 64-bit value in the control body, along with zero fill. Padding placement, frame length and the size mask must remain consistent with the tested peer; this source archive does not contain a standalone host encoder/decoder.

Register addresses are eight bits at the interface, while the instantiated bank decodes entries 0 through 127. No application-specific address map is supplied: the meaning of each command/status register is assigned by the surrounding system.

## Register-bank behavior

- Writes update `command_registers` for the decoded address.
- `read_only_regs(i)='0'` selects command storage on a read.
- `read_only_regs(i)='1'` selects `status_registers(i)` on a read; it does not block writes to command storage.
- Reads pass through a registered pipeline and return a valid strobe, `RD_val`, to the TX response path.
- `command_updates` is pipelined from the falling edge of the decoded write strobe.
- The active bank reset is tied low; command storage has no reset initialization in this source.

## Host integration requirements

Use the original `HPR_ID`, the local MAC, the complete frame layout and the tested aligned length convention. Payload words are reversed by the TX concatenation, and receive words pass through both the parser reversal and an asymmetric FIFO; preserve the byte order expected by the original application.

There are no sequence numbers, retransmission state machine, host driver, packet-capture fixture, or general IP transport implementation in the supplied application RTL. Any such behavior in the tested system belongs to the surrounding application and is not defined by this archive.
