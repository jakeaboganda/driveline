---
title: Component manifests and packaging
section: 15
version: 0.118
status: draft
normative: true
depends_on: [00-conformance.md, 03-vehicle-parameters.md, 07-fmu-packaging.md, 10-composition.md, 12-grammar.md, 17-standard-library.md]
---

# 15. Component Manifests and Packaging

A manifest tells the compiler and the runtime what a library component is: its ports, output type, cardinality, required tier, parameters, and the modes it implements. The compiler type-checks library components against their manifests. It never inspects binaries.

## 15.1 Where Signatures Come From

| Component Kind | Signature Source |
| :--- | :--- |
| Declared in the scenario with a `step` block | The `component` declaration. No manifest. |
| Mode B FMU (`from_fmu` with `bind_inputs` or `bind_outputs`) | The `component` declaration. No manifest. |
| Mode A FMU (`from_fmu` without bind blocks) | `extra/org.driveline.dcm/manifest.json` inside the `.fmu` ([§7](07-fmu-packaging.md)). |
| Native library component | `<Name>.dcm.json` next to the shared library. |
| Standard library component (`std::...`) | The signatures in [§17](17-standard-library.md). |

A component whose signature comes from its declaration is `OneToOne` and reads no Tier 3 deck. A component with a `step` block reads `lon_mode` and `lat_mode` itself, so no mode list applies. Every input port of a Mode B declaration must be a `SliceBuffer`, because `bind_inputs` reads only buffers and `own_state` ([§7](07-fmu-packaging.md)). A checkpoint input on a Mode B declaration is a compile-time error.

A Mode A declaration in the scenario must match its manifest. The declared ports, output type, and `required_tier` must equal the manifest's. A mismatch is a compile-time error.

## 15.2 Native Library Packaging

* One shared library holds exactly one component. It exports every function prototyped in [`abi/driveline_abi.h`](../abi/driveline_abi.h) under that exact name, with C linkage.
* The library file is `<Name>.so` on Linux, `<Name>.dylib` on macOS, or `<Name>.dll` on Windows, and its manifest is `<Name>.dcm.json` in the same directory.
* `use a::b::{Name}` with a first segment other than `std` resolves to `a/b/<Name>.dcm.json`, relative to the directory of the scenario file. A missing manifest is a compile-time error.

## 15.3 Manifest Format

A manifest is one UTF-8 JSON object with these members. Every member is required unless the table says otherwise.

| Member | JSON Type | Meaning |
| :--- | :--- | :--- |
| `abi_version` | string | ABI version that the component implements, in the form `"<major>.<minor>"`. It must equal the runtime's ABI version, or the reference is a compile-time error. |
| `name` | string | Component name. It must equal `<Name>`. |
| `stage` | integer | `1`, `2`, or `3` ([§0](00-conformance.md)). It must agree with `output`. |
| `cardinality` | string | `OneToOne`, `OneToMany`, or `ManyToMany` ([§10](10-composition.md)). |
| `required_tier` | integer | `0`, `1`, or `2` ([§3.1](03-vehicle-parameters.md)). |
| `inputs` | array | Input ports in declaration order. Each is `{ "name": string, "type": string }`. `type` uses the `TypeSpec` syntax of [§12](12-grammar.md), for example `"SliceBuffer<RadarSlice, 8>"` or `"IntentFrame"`. |
| `output` | string | Output type in `TypeSpec` syntax. |
| `parameters` | array | Each is `{ "name": string, "type": "f64" \| "i64" \| "Time", "unit": string, "default": number or null }`. `unit` is a `UnitExpr` of [§12](12-grammar.md), or `"1"` for dimensionless. A `null` default makes the parameter mandatory at the call site. |
| `lon_modes` | array of strings | `lon_mode` values that the component implements. Optional. The default is empty. |
| `lat_modes` | array of strings | `lat_mode` values that the component implements. Optional. The default is empty. |
| `deck_types` | array of strings | Tier 3 `deck_type` values that the component reads ([§3.1](03-vehicle-parameters.md)). Optional. The default is empty. |

## 15.4 Parameter Passing

At each call site, the compiler checks every named argument that is not an input port against `parameters`. An unknown name, a missing mandatory parameter, or a unit whose dimension differs from `unit` is a compile-time error. The runtime passes each parameter through `dl_set_parameters` in SI units. An `f64` parameter becomes `type = 0` with the SI value. An `i64` parameter becomes `type = 1`. A `Time` parameter becomes `type = 1` with the value in nanoseconds. A declared component's `Bool` parameter becomes `type = 1` with 0 or 1, and an enum parameter becomes `type = 1` with the enum's numeric value.
