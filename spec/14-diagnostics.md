---
title: Status codes and error handling
section: 14
version: 0.246
status: draft
normative: true
depends_on: [05-checkpoints.md, 06-lifecycle.md, 07-fmu-packaging.md, 09-abi.md, 10-composition.md, 11-execution.md]
---

# 14. Status Codes and Error Handling

`dl_status_t` in [`abi/driveline_abi.h`](../abi/driveline_abi.h) is the only list of status names. Components return these codes from `dl_*` calls, and the runtime uses the same names in its reports. A negative code is an error. A positive code is a warning.

## 14.1 Status Codes

| Code | Name | Returned or Reported When |
| :--- | :--- | :--- |
| `0` | `DL_STATUS_OK` | The call succeeded. |
| `2` | `DL_STATUS_WARN_FMU_COLD_SPLICE` | The runtime spliced a Mode B FMU without a current warm start ([§7](07-fmu-packaging.md)). |
| `3` | `DL_STATUS_WARN_TRIM_MISMATCH` | A Stage 2 output differs from its latched trim frame, or a component cannot re-trim ([§6.2](06-lifecycle.md)). |
| `-1` | `DL_STATUS_ERR_INVALID_ARG` | A parameter, descriptor, or frame is invalid, or `abi_version` or `struct_size` does not match. |
| `-2` | `DL_STATUS_ERR_TIER_MISSING` | The actor's `vehicle_spec` lacks a tier that the component requires. |
| `-3` | `DL_STATUS_ERR_NUMERIC` | A computation produced a non-finite value, or a trim or steady-state solve has no solution. |
| `-4` | `DL_STATUS_ERR_UNSUPPORTED_MODE` | A component received a mode that it does not implement ([§5](05-checkpoints.md)). |
| `-5` | `DL_STATUS_ERR_STATE` | A `dl_*` function was called in a lifecycle state where [§6](06-lifecycle.md) does not allow it. |
| `-6` | `DL_STATUS_ERR_FMU` | An FMI call returned `fmi3Discard`, `fmi3Error`, or `fmi3Fatal` or a null instance, a step set `terminateSimulation` or `earlyReturn`, or a Mode A `fmi3Binary` output does not have the size of its struct ([§7](07-fmu-packaging.md)). The runtime reports it. Components never return it. |

## 14.2 Runtime Handling

1. **Warnings:** The runtime records the warning with the tick, the component instance name, and the call or rule that produced it. The run continues.
2. **Errors:** When a `dl_*` call returns an error, an FMI call fails (`DL_STATUS_ERR_FMU`), or the runtime detects an error itself, the runtime stops the run. It finishes no further phase. If several calls fail, as can happen when Phase 2 runs in parallel, the reported error is the first failing call in the order of [§11](11-execution.md). The run's reports are exactly those that sequential execution in that order produces up to and including that error, and reports from calls after it are discarded. It reports the error with the tick, the instance name, and the call, and then runs teardown. A run that stops this way has failed. Its last committed World state is the state after the last completed Phase 4, including a splice window's committed state update if the runtime had written it ([§10.4](10-composition.md)). A run that fails during cold init has no committed state.
3. **Teardown:** Every run ends with teardown, whether it succeeds or fails. The runtime visits instances in descending `actor_id` order, with a group sorted by its smallest member, and within one actor or group in the reverse of Phase 2 order, physics first, with per-actor instances in reverse `bind` order. For each instance in turn, it calls `dl_terminate` if the state allows it ([§6.1](06-lifecycle.md)), and then `dl_free_instance` if the instance is not `Uninstantiated`. FMUs get the [§7.2](07-fmu-packaging.md) mappings of `dl_terminate` and `dl_free_instance`. An error during teardown is reported, and teardown continues. It does not change whether the run succeeded.
4. **Output Validation:** After each `dl_do_step`, and after each `fmi3DoStep` once the outputs are read, the runtime checks every output frame. First, every mode field must hold one of its listed values, or `NONE` where [§5](05-checkpoints.md) allows it, and every count that the frame's modes use (`num_waypoints`, `num_traj_points`) must be at most 64, and every `char[N]` field that the modes use must hold a null within its $N$ bytes with valid UTF-8 before it ([§9.1](09-abi.md)), and a failure is `DL_STATUS_ERR_INVALID_ARG`. Then every field that the frame's modes use must be finite, where for `path_points` and `trajectory` only the entries below the count are checked, except that a field that its mode makes a bound may be `+INFINITY` ([§5](05-checkpoints.md)), and every `KinematicState` field that physics fills must be finite. A failed check is `DL_STATUS_ERR_NUMERIC`, handled as an error. Then the runtime applies the frame validity rules of [§5](05-checkpoints.md), including the `NONE` rules for the output's declared type, and a failure is `DL_STATUS_ERR_INVALID_ARG`.
5. **Report Format:** A report made during cold init carries tick 0, and one made in a splice window carries the tick after the window, each with `sim_time_ns` equal to that tick's time. A teardown report carries the same tick and time as the error that ended the run, or, after a successful run, the tick whose Phase 4 ended it. Each report has the fields `tick`, `sim_time_ns`, `severity` (`warning` or `error`), `code` (a `dl_status_t` name), `instance` (the name passed to `dl_instantiate`, or empty for an error that the runtime detects outside any component call, such as an infeasible steady state or a numeric error in a condition), and `detail` (text). The transport and file format of reports are implementation-defined.
