---
title: C-ABI
section: 9
version: 0.4
status: draft
normative: true
depends_on: [05-checkpoints.md, 04-perception.md]
---

# 9. Normative C-ABI Header (`driveline_abi.h`)

All structs in `driveline_abi.h` use fixed-width types and explicit padding, so the compiler inserts no padding. Data structs contain no pointers: vehicle parameters, sensor slices, checkpoint frames, `dl_route_t`, and `dl_init_context_t`. Their layout is identical on 32-bit and 64-bit targets, and Mode A FMUs exchange them byte for byte ([§7](07-fmu-packaging.md)). Call descriptors (`dl_slice_buffer_view_t`, `dl_batch_step_io_t`, `dl_membership_change_t`, `dl_structural_config_t`) and the callback table contain pointers. They are valid only inside one process.

The normative header is [`abi/driveline_abi.h`](../abi/driveline_abi.h). This section does not copy it.
