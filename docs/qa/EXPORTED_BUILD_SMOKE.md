# Smoke testing: editor vs. headless vs. exported binary

Three separate, non-overlapping smoke layers exist for this project. Don't confuse them.

## 1. Editor / headless source smoke — `tools/bootstrap.sh`

Runs `godot4 --headless --path game --script res://tests/smoke_test.gd` against the **editable project source** (`res://` resolves to files on disk, not a package). ~200 assertions, one block per implementation prompt (P00-P47). This is the primary correctness suite and the release-candidate quality gate.

This only proves the *logic* is correct against source. It does **not** prove the exported/packaged build works — see below.

## 2. Why the exported binary needs its own, different check

Godot's `--script <path>` CLI flag only works when Godot is pointed at an editable project directory via `--path`. Run the *same* flag against a packaged/exported binary and it is silently ignored — the engine always falls back to `run/main_scene`, and a `--headless` run with no scene-driven quit condition then hangs forever with zero output (reproduced: `./alignment_pending.x86_64 --headless --script res://tests/smoke_test.gd` hung indefinitely with 0 bytes of output on both `template_release` and `template_debug` exports of this project). This is a real Godot engine constraint, not a project bug — an exported game has no general "run an arbitrary script from the CLI" capability, debug or release.

## 3. Exported-build smoke — `--qa-exported-smoke`

Because of (2), the packaged binary has to check itself. `src/boot/boot.gd` looks for `--qa-exported-smoke` in `OS.get_cmdline_user_args()` before routing to the main menu; if present, it runs `tests/exported_build_smoke.gd` in-process and quits with exit code 0 (pass) or 1 (fail) instead of showing the menu.

This deliberately does **not** re-run all ~200 source assertions — those are exhaustively covered by layer 1 already. It only checks what can differ between "loaded from `res://` on disk" and "loaded from an embedded `.pck`":

- every expected autoload singleton is present in the packaged tree;
- every `res://src/data/*.gd` catalog script (walked via `DirAccess`, not hardcoded, so it can't silently stop covering new catalogs) loads from the package;
- `main_menu`, `settings`, `campaign`, and `hud` scenes instantiate from the package;
- settings persist through a real `user://` save/load round-trip inside a packaged build;
- a manual campaign save persists through a real `user://` save/load round-trip inside a packaged build.

### Running it

```bash
tools/export_release.sh   # builds + packages + runs this check automatically as a gate
```

or manually, against an already-exported Linux binary:

```bash
./dist/linux/alignment_pending.x86_64 \
  --headless --display-driver headless --audio-driver Dummy -- --qa-exported-smoke
echo "exit code: $?"   # 0 = pass, 1 = fail
```

The `--` before `--qa-exported-smoke` matters: it's what makes Godot classify the flag as a user arg (`OS.get_cmdline_user_args()`) instead of trying to parse it as an engine flag.

Windows: same idea, `alignment_pending.exe --qa-exported-smoke` (no `--display-driver headless`/`--audio-driver Dummy` needed/available on Windows the way they are on Linux headless CI — run it windowed, or minimized, on an actual Windows machine; this has not been run on real Windows yet, see `KNOWN_ISSUES.md`).

### Result as of this pass

Ran against the Linux release export produced by `tools/export_release.sh`, commit at the time of writing: **all checks passed, exit code 0.** See the command's own transcript in this branch's development log; re-run it yourself with the command above to reproduce.

## 4. What's still not covered by anything automated

- Real interactive input (mouse/keyboard/controller) driving the UI inside a packaged build — everything above exercises the packaged code paths programmatically, not by simulating clicks.
- Windows runtime validation — the `.exe` is built and packaged (`tools/export_release.sh` cross-exports it from Linux using the official Windows export templates) but has never been *run* on Windows. Needs a real Windows machine; tracked in `KNOWN_ISSUES.md`.
- Audio output on real hardware (headless runs use the `Dummy` audio driver).
