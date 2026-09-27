---
title: Status codes and error handling
section: 14
version: 0.53
status: draft
normative: true
depends_on: [06-lifecycle.md, 07-fmu-packaging.md]
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
| `-4` | `DL_STATUS_ERR_UNSUPPORTED_MODE` | A component received a `lon_mode`, `lat_mode`, or `valid_mask` combination that it does not implement. |
| `-5` | `DL_STATUS_ERR_STATE` | A `dl_*` function was called in a lifecycle state where [§6](06-lifecycle.md) does not allow it. |

## 14.2 Runtime Handling

1. **Warnings:** The runtime records the warning with the tick, the component instance name, and the call or rule that produced it. The run continues.
2. **Errors:** When a `dl_*` call returns an error, or the runtime detects an error itself, the runtime stops the run. It finishes no further phase. It calls `dl_terminate` and then `dl_free_instance`, or `fmi3Terminate` and `fmi3FreeInstance` for FMUs, on every instance that is not `Terminated`, in descending `actor_id` order, and reports the error with the tick, the instance name, and the call. A run that stops this way has failed. Its last committed World state is the state after the last completed Phase 4.
3. **Output Validation:** After each `dl_do_step`, the runtime checks every output frame. A field whose `valid_mask` bit is set must be finite. `throttle` and `brake` must lie in $[0, 1]$, and `steering_wheel_norm` must lie in $[-1, 1]$. Every `KinematicState` field must be finite. A failed check is `DL_STATUS_ERR_NUMERIC`, handled as an error.
4. **Report Format:** Each report has the fields `tick`, `sim_time_ns`, `severity` (`warning` or `error`), `code` (a `dl_status_t` name), `instance` (the name passed to `dl_instantiate`), and `detail` (text). The transport and file format of reports are implementation-defined.
