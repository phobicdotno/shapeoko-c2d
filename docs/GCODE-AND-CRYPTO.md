# G-code output, the Carbide Motion handoff, and encrypted assets

Findings from the Carbide Create **build 853** macOS binary (`Carbide Create.app/
Contents/MacOS/Carbide Create`, a Qt6 Mach-O) and its bundled `Resources/`.
This documents *behaviour and formats* for interoperability — no proprietary
source or keys are reproduced here.

## Two separate g-code paths (this is the important one)

Carbide Create produces toolpath g-code in two different places, and they are
**not** the same artifact:

1. **`gcode.egc` inside the `.c2d`** — an *encrypted* cache of the computed
   program, stored in the `sqlar` table (magic `CCV1…`). This is what protects
   the toolpath output at rest inside a saved design file.
2. **The actual machine handoff — plaintext.** When you cut or export, CC writes
   ordinary g-code. The binary contains `sendToCarbideMotion`, a temp file
   `tmp_gcode_%1.nc`, a `/fromCarbideMotion.nc` exchange file, a
   `SaveGcodeDialog`, and the file filter `GCode files (*.nc *.txt *.tap)`.

**Consequence:** you never need to decrypt `gcode.egc`. The program that reaches
Carbide Motion (and the machine) is plain `.nc` g-code. A third-party tool can
emit standard `.nc` and either hand it to Carbide Motion or stream it straight to
the GRBL controller — no `.egc`, no Carbide Motion required.

### Caveat: loading a `.c2d` *directly* into Carbide Motion (verified 2026-09)

Carbide Motion (build ≥ 565, per the `minimum_carbide_motion_version` param) can
open a `.c2d` file directly — and when it does, the *only* thing it uses is the
`sqlar` `gcode.egc` blob. A generated `.c2d` with a blank/empty `gcode.egc`
(the write recipe in [FORMAT.md](FORMAT.md) blanks it) opens **perfectly in
Carbide Create** — all geometry renders, toolpaths recalculate — but Carbide
Motion reports it as **not a valid file**.

Two fixes:

1. **Open the file in Carbide Create and hit Save once.** CC regenerates
   `gcode.egc` (and `all.svg`/`preview.svg`) from the recalculated toolpaths.
   The file then loads in Carbide Motion.
2. Skip CM's `.c2d` path entirely: export/emit plain `.nc` and load that.

A `.c2d` with **zero toolpaths** gets no `gcode.egc` row at all when CC saves it
— that's normal, and such a file is design-only by definition.

The `gcode.egc` blob is stored **uncompressed** in `sqlar` (`sz == length(data)`),
magic `CCV1`, followed by encrypted bytes.

## The post-processor system

CC drives output through **JavaScript post-processors** (a small JS engine calls
hooks `onOpen`, `onClose`, `onLinear`, `onRapid`, `onSpindleSpeed`, `onSection`,
`onComment`, `onTerminate`; output via `writeLn` / `writeBlock`). Four posts ship
in build 853:

| Post | `extension` | Vendor | For |
|---|---|---|---|
| **GRBL** | `nc` | Generic | any GRBL machine |
| **Basic G-code** | `nc` | Carbide 3D | minimal generic |
| **Carbide 3D Shapeoko** | `nc` | Carbide 3D | Shapeoko (BitSetter/manual tool changes) |
| **Carbide 3D Nomad Pro** | `nc` | Carbide 3D | Nomad (automatic tool changer) |

### The GRBL dialect (behaviour, for a compatible emitter)

Enough to write byte-compatible output without their script:

- **Units/mode:** `G90` absolute always; then `G21` (mm) or `G20` (inch) from an
  `outputMetric` flag.
- **Number formatting is modal** — a coordinate word is emitted **only when its
  value changes** from the last block (per-axis "last output" memory). Precision:
  **3 decimals in mm, 4 in inch**; feed `F` **1 decimal**; spindle `S` and tool
  `T` integer.
- **Motion:** rapids `G0`, feeds `G1`, each block built as
  `G<0|1> [X..] [Y..] [Z..] [F..]` with only the changed words present.
- **Plunge guard:** after a Z-home move the next motion outputs X/Y first
  (a "preposition for plunge" comment), then plunges — avoids diagonal ramp into
  stock.
- **Spindle:** `M03` + `S<rpm>` to start (S only re-sent on change), `M05` to
  stop; modal `spindle` state prevents redundant `M03`.
- **Tool change (GRBL post):** spindle off, then a pause line
  `M0 ;T<n>` (comment carries the tool number) — i.e. `M0` program-pause for a
  manual change. (The Shapeoko post differs — BitSetter probing; the Nomad post
  uses an ATC.)
- **Comments:** truncated to ~12 chars and wrapped in `( … )`.
- **Program end:** `M05` (if spindle on) then `M02`.

That is the entire contract a Tier-2 CAM emitter must satisfy to feed a Shapeoko
through the GRBL path.

## CAM internals (from C++ symbols)

The mangled symbol table shows the toolpath engine's shape (useful for modelling
our own CAM): a `CADDoc` document; a `CMove` base with `CXYRapidMove`,
`CPlungeMove`, `CRetractMove` subclasses; a `ClearanceLinker` / `link_method`
that stitches cut moves with safe-Z retracts (`outputSafeZ`, comment "Move to
safe Z to avoid workholding"); per-type toolpath classes (`KeyholeToolpath`,
etc.); and a threaded compute layer (`mc::ThreadPool`, `mc::parallel_for`,
`mc::async_task_loop`) — matching the bundled `QtConcurrent`. So a toolpath =
computed into a list of typed moves, linked with clearance retracts, then handed
to the active post-processor for text output.

## Encrypted assets (documented, not defeated)

Two proprietary assets are encrypted; the design `.c2d` geometry is **not**.

- **`Resources/ccpro.db`** (~55 MB) — the tool library / material & feed-speed
  database. It is **SQLite encrypted with the SQLite Encryption Extension (SEE)**,
  codec **`see-aes256-ofb`** (AES-256, OFB mode). CC opens it read-only via the
  URI `ccpro.db?mode=ro` and keys it with `sqlite3_key_v2`. Entropy is a flat
  8.0 bits/byte, as expected. The key lives in the binary; this repo does **not**
  extract or publish it.
- **`gcode.egc`** — the encrypted toolpath cache described above.

**Why this doesn't matter for a clean-room tool:** every toolpath in a `.c2d`
already embeds its complete `tool` object (geometry, feeds, speeds — see
[GEOMETRY-TOOLPATHS.md](GEOMETRY-TOOLPATHS.md)), so the tool catalog in `ccpro.db`
is not needed to read, edit, or re-cut a design. Build your own tool library.

## Net picture for a Linux/independent workflow

```
 design .c2d  ──►  your CAM  ──►  GRBL post  ──►  plain .nc  ──►  GRBL controller
 (plaintext,      (compute        (documented      (/dev/ttyACM* ·  /dev/cu.usbmodem*)
  fully mapped)    moves)          above)           or hand to Carbide Motion)
```

No `.egc`, no `ccpro.db`, no Carbide Motion in the critical path.

