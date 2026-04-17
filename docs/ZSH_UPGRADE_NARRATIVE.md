# From DOS Scripts to a Real CI/CD CLI: The zsh Upgrade Narrative

**Project:** GaiaFTCL / GaiaHealth / GaiaOS  
**Scope:** IQ → OQ → PQ qualification pipeline + all supporting shell infrastructure  
**Date:** April 2026  
**Status:** ✅ CALORIE — all bash references eliminated from Mac documentation

---

## The Analogy That Makes This Real

Imagine you're running a pharmaceutical manufacturing line that was originally documented using DOS batch files. The `.bat` scripts got the job done in 1995. They ran linearly, they printed to the screen, and they mostly worked — as long as nobody moved a file, changed a path, or ran two things at once. The world was smaller then.

That's exactly what `/bin/bash` on macOS is in 2026. Apple ships Bash 3.2 — a binary from 2007, frozen at GPLv2 because upgrading to Bash 5.x would drag in GPLv3's "anti-tivoization" clauses, which Apple cannot accept for its closed hardware ecosystem. So the shell sitting at `/bin/bash` on every Mac is not just old — it is *deliberately and permanently* frozen at a nineteen-year-old feature set. Using it for modern qualification work is not "legacy." It is architectural debt that compounds with every line of script written against it.

The move to `zsh` — macOS's default shell since Catalina, MIT-licensed, actively maintained, and deeply integrated with Apple's toolchain — is the equivalent of tearing out those DOS batch files and replacing them with a full CI/CD pipeline. Same intent. Completely different capability surface.

---

## What `/bin/bash` Was Actually Missing

The three critical gaps in Bash 3.2 are not academic. They show up directly inside the IQ/OQ/PQ pipeline.

**No associative arrays.** The `declare -A` construct that lets you build a key-value map — tracking phase results, hardware evidence, receipt fields — was introduced in Bash 4.0. Every time the qualification scripts needed to track structured state (OQ pass/fail counters per test suite, PQ hardware metrics per GPU check), bash 3.2 had no native primitive for it. The workarounds were ugly: parallel arrays, string-delimited hacks, or punting to Python just to hold a dictionary. zsh has `typeset -A` as a first-class citizen.

**No recursive globbing.** The `**/*.swift` pattern — walking a directory tree to find every Swift source file without invoking `find` — requires Bash 4 or later. In the GaiaOS build pipeline, anywhere you needed to recursively locate Rust test files, WASM artifacts, or Swift test targets, you were either spawning a `find` subprocess or writing a loop. zsh handles `**` natively, as a built-in globbing operator, no subprocess, no pipe, no parse.

**No modern parameter expansion.** The flags like `${(j: :)array}` to join an array into a string, `${(s: :)str}` to split on a delimiter, `${var:l}` for lowercase — these collapse entire `awk` and `sed` one-liners into inline expressions. Every place in the qualification scripts where a variable was lowercased for comparison, or an array was joined into a comma-separated list for a receipt field, bash 3.2 required an external tool call. zsh does it in the expansion itself.

---

## The IQ Phase: From Linear Checklist to Structured Intake

The Installation Qualification (`gamp5_iq.sh`, `iq_install.sh`) is the foundation of the entire regulatory chain. Nothing downstream — no OQ, no PQ, no evidence package — is valid without a clean IQ receipt. In bash 3.2, a script this complex is essentially a long linear sequence of commands with `if/else` blocks and echo statements. In zsh, it becomes something structurally different.

The zsh IQ scripts use `typeset -A` to build the evidence record inline as the script progresses — hardware UUID, entropy seed, wallet address, macOS version, filesystem type, GPU presence, RAM check result — all accumulated in a structured map and flushed to JSON at the end. There's no parallel array bookkeeping, no delimiter-separated string that gets split later. The receipt is constructed as a first-class data structure throughout the script's execution.

The `${0:A:h:h}` idiom — getting the absolute path to the script's parent's parent directory — is pure zsh. In bash 3.2, this requires a `cd` and `pwd` dance wrapped in a subshell. In zsh, it's a single parameter expansion flag. This matters for the IQ phase specifically because the wallet path, the evidence directory, and the REPO_ROOT are all derived from the script's location. A wrong root path at IQ invalidates every downstream path reference. The zsh idiom is both more readable and more reliable.

The hardware detection block — `ioreg` for Hardware UUID, `sysctl -n hw.memsize` for RAM, `system_profiler SPDisplaysDataType` for GPU, `diskutil info /` for filesystem type — stays the same at the command level. What changes is how results are consumed. With `typeset -A hw_profile`, every detection call populates a named key. The summary that gets written to `evidence/iq/iq_receipt.json` is assembled from a single associative array rather than a dozen independent variables threaded through a Python heredoc.

The `osascript` dialog integration for the cell selection prompt (`--cell macfusion|machealth|both`) also benefits from zsh's `zparseopts` for argument parsing — replacing the manual `while [[ $# -gt 0 ]]; do case $1 in ...` loop that bash scripts typically use. One line of option declaration, one call, done.

---

## The OQ Phase: Test Orchestration That Actually Scales

The Operational Qualification (`gamp5_oq.sh`, `oq_validate.sh`) is where the bash-to-zsh gap is most visible in practice. OQ runs build pipelines — `swift build`, `cargo test --workspace` — and then parses their output to extract pass/fail counts, build times, and specific test results by name. In bash 3.2, this means capturing stdout into a variable via `$(...)`, then running it through `grep` and `awk` in sequence. Each pipe is a subprocess fork. For a test suite running 32 to 38 tests across Rust and Swift, that's a lot of forking just to count lines.

In zsh, the output of `cargo test --workspace` can be captured into an array split on newlines (`${(f)"$(cargo test ...)"}`), then filtered with native glob qualifiers or parameter expansion. No external `grep`. No `awk`. The pattern match happens inside the shell. For ABI regression guards — where OQ checks that `vQbitPrimitive` is exactly 76 bytes at specific offsets — the comparison logic lives in zsh parameter arithmetic (`(( abi_size == 76 ))`) rather than in a `test` call against a string extracted by `awk -F:`.

The OQ phase also introduced a meaningful upgrade in the excluded-test list management. The script documents which tests are explicitly *not* run in OQ: 24-hour continuous operation, sustained GPU load, Bitcoin live network, UI validation. In bash 3.2, managing an exclusion list means either a long `case` statement or a delimited string that gets parsed by `grep -v`. In zsh, a simple `typeset -A EXCLUDED_TESTS` with named keys gives you both the exclusion logic *and* self-documenting code that can be serialized into the OQ receipt as a machine-readable field.

The wallet permission verification — confirming `0600` mode on the private key file before any cryptographic operation proceeds — uses `stat -f %Mp%Lp` (macOS-native stat syntax). This was always in the script. What zsh adds is the ability to wrap this in a function that returns a typed result (`integer`) and use that result directly in arithmetic context without string conversion. Small thing. But multiplied across every security-critical check in the OQ phase, it means less surface area for silent type coercions to produce false passes.

The OQ receipt, once accumulated into a `typeset -A receipt` map, gets written to JSON via a single Python3 call that receives the map as structured input — not as a heredoc with interpolated shell variables scattered through it. This is the difference between a configuration file and a template with holes poked in it.

---

## The PQ Phase: Hardware Evidence That Can't Be Faked

The Performance Qualification (`gamp5_pq.sh`) is the most hardware-coupled phase. It validates that a specific physical Mac's Metal GPU can produce correct offscreen renders, that frame hashing is deterministic, and that release build times fall within the 180-second threshold. The hard FAIL conditions — no Metal GPU detected, all-zero pixel output, missing GPU device name — are non-negotiable.

This is where zsh's `print -P "%F{red}%f"` color output (native, no ANSI escape string construction) matters for a different reason: the PQ output is the evidence log. It gets captured, timestamped, and stored in `evidence/pq/`. When a regulator or auditor reads that log, the formatting needs to be clean and machine-parseable, not ANSI escape codes embedded in strings that were assembled with concatenation. zsh's prompt expansion system produces structured terminal output that can be captured cleanly.

The GPU detection pipeline — `system_profiler SPDisplaysDataType` piped through string extraction to get the device name, then the `MTLCreateSystemDefaultDevice()` Swift test to confirm the device is actually accessible via the Metal API — benefits from zsh's ability to capture multi-line command output into an array (`${(f)"$(system_profiler ...)"}`), then index into specific lines by position. In bash 3.2, extracting line three of a multi-line command output requires either `sed -n '3p'` or a `while read` loop with a counter. In zsh it's `output_lines[3]`.

The pixel evidence block — the 64×64 Metal texture, clear to epistemic color, readback, SHA256 hash — is driven by a Swift executable (`TestRobot`), not by the shell script itself. This is the correct architectural boundary. The shell's job is to invoke the Swift binary, capture its exit code and stdout, and incorporate the result into the receipt map. zsh's `EPOCHSECONDS` (a built-in integer variable, no `date +%s` subprocess) timestamps that capture precisely. The resulting receipt field is `pixel_evidence: { hash: "...", timestamp: <int>, device: "Apple M..." }` — built from a `typeset -A` map, no string surgery required.

The release build timing check (`swift build --configuration release` must complete in under 180 seconds) uses zsh's arithmetic and `EPOCHSECONDS` in a before/after pattern: `integer build_start=$EPOCHSECONDS`, run the build, `integer elapsed=$(( EPOCHSECONDS - build_start ))`. In bash 3.2, this requires two `date +%s` subprocess calls and arithmetic in a `$(( ))` block that has to handle the string-to-integer conversion manually. zsh just knows it's an integer because you declared it that way.

---

## The Full Cycle: From Local Script to CI/CD Equivalent

The `run_full_cycle.sh` script is where the DOS-to-CI analogy becomes most tangible. It runs a complete production cycle: local build and test, git commit and push, fresh clone to `/tmp`, verification of the fresh clone, receipt write. This is what a CI/CD pipeline does — it just does it on the developer's local Mac, on demand, in a single command.

In bash 3.2, a script like this is fragile. `set -e` in bash has well-documented edge cases where subshell failures don't propagate correctly through pipes. The `pipefail` option wasn't added until later versions. The result is a script that *appears* to have strict error handling but can silently pass through a failed `cargo test` if the failure happens on the wrong side of a pipe.

In zsh, `set -euo pipefail` behaves consistently. Errors in pipelines propagate. Unset variables abort rather than expand to empty strings silently. The `die()` function that wraps `print -P "%F{red}FATAL:%f $1"` followed by `exit 1` is guaranteed to fire when a build fails, a push fails, or a clone fails. The receipt only gets written if every phase completes cleanly. That's the regulatory requirement — and zsh's error semantics actually enforce it, rather than requiring the script author to know which bash pipe edge cases to work around.

The `print -P "%F{...}%f"` output throughout `run_full_cycle.sh` is also significant for a different reason: this script's terminal output is what a developer reads to know whether their full cycle passed or failed. When it's using zsh's native color expansion rather than hardcoded ANSI codes, the output is more portable across terminal emulators, more consistent in color rendering, and — critically — can be stripped cleanly for log capture without leaving escape code artifacts in the evidence record.

---

## The Swift / zsh Boundary: Where the Architecture Gets Clean

The cleanest architectural upgrade that the zsh decision enables is the boundary it draws between what runs in the shell and what runs in Swift.

The cursor rule (`mac-qualification-zsh-swift.mdc`) now states: new Mac code is Swift executables. Shell out via zsh, not bash, through `Process()`. The qualification scripts (`gamp5_*.sh`) are canonical and written in zsh. Everything else — Metal GPU testing (`TestRobot`), orchestration (`CleanCloneTest`), ABI verification — is a Swift binary that the zsh scripts invoke.

This boundary is correct. The shell's job is orchestration: sequencing phases, capturing evidence, writing receipts, managing state. Swift's job is computation: Metal rendering, cryptographic operations, ABI layout verification, type-safe test assertions. When the shell was bash 3.2, this boundary was blurry — things ended up in Python heredocs or in `awk` one-liners not because they belonged there, but because the shell couldn't do them cleanly. zsh closes that gap. Most things that were being delegated to Python subprocesses for string manipulation or structured data construction now live natively in the shell layer where they belong. The things that remain in Swift are there because they *should* be — Metal, secp256k1, Mach-O binary inspection — not because the shell couldn't handle them.

---

## The BenOS Scripts: The One Remaining Conversation

The one area where the bash/zsh line deliberately holds is `BenOS/v0.5/build-all-platforms.sh`. This script uses Zig for cross-compilation to Windows, Linux (AMD64/ARM64), iOS, Android, and WebAssembly. It runs in CI on `macos-14` via GitHub Actions. This is a portability scenario — the script needs to be consistent whether it runs on Apple Silicon, a Linux runner, or a Windows build agent.

For this case the right choice is POSIX sh or explicitly Homebrew bash 5.x (`/opt/homebrew/bin/bash`), not zsh. zsh-specific syntax in a cross-platform build script breaks the Linux runners that don't have zsh installed by default. This is not a compromise — it's the correct application of the rule: use zsh for Mac-native qualification work, use POSIX sh for substrate scripts that traverse heterogeneous nodes. The CLAUDE.md preference file captures this distinction.

---

## What the CALORIE State Means

The CALORIE state — all bash references eliminated from Mac documentation, cursor rules updated, Swift `Process()` calls verified to use `["zsh", ...]` — means the qualification pipeline is now internally consistent in a way it wasn't before.

Previously, the scripts were written in zsh but the documentation said "bash scripts." That creates a gap: a future developer reading the docs sees "bash" and writes a bash one-liner to extend the pipeline. That one-liner silently fails to handle UTF-8 paths. Or it uses `declare -A` and breaks on the macOS system bash. Or it works on their machine but breaks in the GitHub Actions runner because the system bash there is a different version. The documentation mismatch was an invitation to reintroduce exactly the technical debt that was being removed.

With CALORIE state reached, the documentation matches the implementation. The cursor rule enforces the boundary going forward. The Swift `Process()` calls use `["zsh"]` not `["bash"]`. The canonical scripts are `gamp5_iq.sh`, `gamp5_oq.sh`, and `gamp5_pq.sh` — all zsh, all documented as zsh. The full cycle runner uses `EPOCHSECONDS` and `print -P` and `${(f)...}` expansion. The architecture is coherent end to end.

That coherence is what the DOS-to-CI-CD analogy is pointing at. DOS batch files could run a build. But they couldn't be reasoned about, tested against, or extended without the whole thing becoming a house of cards. A real CI/CD pipeline — even a local one running on a single Mac — has structural integrity. Every phase has a defined input contract and output receipt. Failures abort cleanly with evidence. The toolchain is consistent from developer workstation to GitHub Actions runner to regulatory submission package.

That's what this qualification pipeline is, now. Not despite using shell scripts — but because the shell it uses is actually capable of the job.
