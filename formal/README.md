# Formal model

A Lean 4 model of parts of the Driveline specification. Each theorem checks a claim that the spec makes, and its doc comment cites the `docs/spec` line it covers.

Run `tools/setup-lean.sh` once to install the toolchain and build. After that, `lake build` in this directory re-checks every proof.

`tools/check_formal.py` bans the words `sorry`, `admit`, `native_decide`, `unsafe`, and `debug.skipKernelTC`, and lines that declare an `axiom`, anywhere in a `.lean` file, comments included. Do not write those words in comments.

| File | Spec | Proves |
| :--- | :--- | :--- |
| `Driveline/Lifecycle.lean` | §6.1, §10.4, §14.2 | The diagram agrees with the Allowed Calls table. The cold-init, splice, and re-trim call sequences are allowed. No instance steps before `dl_exit_init_mode`. Teardown frees every instance from any state without a forbidden call. |
