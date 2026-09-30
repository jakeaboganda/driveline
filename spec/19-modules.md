---
title: Modules, catalogs, and the lockfile
section: 19
version: 0.256
status: draft
normative: true
depends_on: [12-grammar.md, 15-manifest.md, 16-static-semantics.md, 18-run-record.md]
---

# 19. Modules, Catalogs, and the Lockfile

A module is a `.dline` file in the `ModuleFile` form of [§12](12-grammar.md): imports and declarations, with no scenario. A catalog is a module, or a directory of modules, that holds shared declarations, such as a fleet of `vehicle_spec`s, `object_spec`s, components, and `fn`s. A scenario uses a catalog through `use`, the same way it uses components. A lockfile pins the content of every file that a scenario resolves, so a changed catalog cannot silently change a run.

## 19.1 Modules

1. **Import Resolution:** `use a::…::b::{N_1, …, N_k}` with a first segment other than `std` resolves relative to the directory of the importing file. If the file `a/…/b.dline` exists, each $N_i$ names a top-level declaration of that module. Otherwise each $N_i$ is a native library component with the manifest `a/…/b/N_i.dcm.json` ([§15.2](15-manifest.md)). A missing file or name, or a module file and a manifest directory that both exist, is a compile-time error.
2. **Relative Paths:** Every relative path in a file, including an import, a `from_fmu` path, a `load_xodr` path, and a Tier 3 `uri`, resolves against the directory of the file that contains it.
3. **Names:** An imported name joins the File scope of the importing file ([§16.4](16-static-semantics.md)) under its own name, with that scope's rules. The body of an imported `component` or `fn` resolves its names in the module that declares it, before any substitution. A module exports every top-level declaration it contains and nothing it imports, so its own imports reach only the module itself.
4. **Compilation:** The compiler checks each module once, with the rules of [§16](16-static-semantics.md) that apply to declarations. A cycle of imports is a compile-time error.

## 19.2 Lockfile

The resolved inputs of a scenario are the files that the compiler reads for it, other than the scenario file itself: each module, each manifest, each native library, each FMU, the map, and each Tier 3 deck whose `uri` is a file path, that is, has no RFC 3986 scheme.

1. **Location and Form:** The lockfile is next to the scenario file, named as the scenario file with `.lock` appended. It is one UTF-8 JSON object with the single member `files`, an array with one entry `{ "path": string, "sha256": string }` per resolved input. `path` is relative to the scenario file's directory, with `/` separators, and lexically normalized: no empty or `.` segments, and `..` only as leading segments. Symbolic links are not resolved, and each normalized path has one entry. `sha256` is the lowercase hexadecimal SHA-256 of the file's bytes. Entries are sorted by `path`, compared as UTF-8 bytes. The compiler writes the object in the encoding of [§18.1](18-run-record.md), followed by `\n`.
2. **Checking:** If the lockfile exists, the compiler compares it with the resolved inputs. A resolved input with no entry, an entry with no resolved input, or a different hash is a compile-time error. If the lockfile does not exist, the compiler writes it.
3. **Run Record:** The run record header lists the same entries in the same order ([§18](18-run-record.md)).
