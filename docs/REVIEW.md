# Source Inspection Record

## Scope

The project owner identifies this as a hardware-tested 2.5 Gb/s Layer-2 Ethernet core for a Virtex UltraScale+ board using an SFP+ connection. Preparation for GitHub publication covered the nine application HDL files, the top-level connections, the available IP configurations, and repository contents.

No simulation, synthesis, implementation, timing analysis, bitstream generation, or new hardware measurements were performed. Hardware test date, board model, SFP module, peer configuration, test duration, error counts and measured throughput were not included. The project owner's hardware-test report is therefore kept separate from the source inspection.

## Confirmed from source and configuration

- The active physical path is `gig_ethernet_pcs_pma_0`, connected directly to the SFP differential ports. The `gtx_Comint` instance in the top is commented out.
- Both active Ethernet containers record a 2.5 Gb/s configuration. The PCS records a 156.25 MHz reference, GTY transceiver, disabled auto-negotiation, and Virtex UltraScale+ `xcvu9p` metadata.
- The active application/MAC FIFO connection is 64 bits wide. The external receive FIFO produces eight-bit data.
- TX arbitration includes terminal, register-response, and external payload queues. RX dispatch includes DATA, register read/write, and terminal write handling.
- The supplied MAC container does not include the example-support wrappers referenced by the top. Shared application packages, board constraints and the original project are also absent.

## Existing behavior documented without functional changes

| Observation | Documentation consequence |
| --- | --- |
| Fixed broadcast TX header and local RX MAC filter | Address generics are not described as a complete TX address configuration mechanism |
| Size bit 15 is forced high in the TX header | Wire-format detail is explicitly recorded for peer compatibility |
| Full-width `TKEEP` and eight-byte counters | Arbitrary partial-word lengths are not advertised |
| Ordinary oversized requests are clamped; no continuation scheduler found | Automatic segmentation is not advertised |
| Payload and command/terminal queues expose limited flow control | External producer scheduling remains part of system integration |
| RX packet event and length originate in parser clock domain | User-clock crossing is called out explicitly |
| Legacy diagnostic outputs are undriven or lack active producers | These outputs are not advertised as working link or error indicators |
| Pause generation is tied off; signal detection is tied high | These controls are described as currently wired |
| Register read-source mask does not suppress writes | The `read_only_regs` name is explained by actual code behavior |
| RX does not use a general keep/error/footer validation path | No general arbitrary-frame validation claim is made |

These are observations about the supplied snapshot, not a diagnosis of the original tested system. Missing support files can contain additional implementation details. Functional changes to these behaviors were outside the requested comment/documentation work.

## Repository preparation

English comments were added around the active architecture, clock domains, queue contracts, protocol packing, register behavior, and legacy modules. Existing vendor notices were retained. SHA-256 comparisons of the nonblank, non-comment source lines before and after editing matched for all nine HDL files, confirming that those source lines were preserved.

The repository includes documentation, the supplied HDL and IP source artifacts, and Git ignore/attribute rules. Local caches, lock files, checkpoints, and generated simulation netlists are excluded from version control. No project-wide license or GitHub remote is invented as part of this preparation.
