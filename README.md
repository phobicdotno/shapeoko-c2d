# shapeoko-c2d

Reverse-engineering notes on Carbide Create's `.c2d` file format, plus a working
generator that builds valid modern-format files from scratch — used here to put the
Shapeoko 3 XXL baseplate's 18 mounting holes into a CNC-ready design file.

Verified against **Carbide Create build 853** (August 2026).

**→ [docs/FORMAT.md](docs/FORMAT.md)** — deep dive into everything that is *not*
geometry or toolpaths: pragmas, all 32 `params` keys, the `sqlar` embedded files
(including the `CCV1` encrypted-G-code container), the binary `model_2` heightmap
layout, `log`/`metadata`, and the legacy `DOCUMENT_VALUES` header.

**→ [docs/GEOMETRY-TOOLPATHS.md](docs/GEOMETRY-TOOLPATHS.md)** — all five element
types (`circle`, `rectangle`, `regular_polygon`, `path`, `text`) and all seven
toolpath types with their fields, the shared bezier point model, the embedded
tool object, and the depth-sign convention change between builds 843 and 853.
Raw specimen JSON for every type lives in [`samples/`](../samples/).

**→ [docs/GCODE-AND-CRYPTO.md](docs/GCODE-AND-CRYPTO.md)** — from the Carbide
Create binary: the two g-code paths (encrypted `gcode.egc` cache vs. the
**plaintext `.nc`** that actually reaches Carbide Motion / the machine), the GRBL
post-processor dialect documented for a compatible emitter, the CAM engine's move
architecture, and the encrypted assets (`ccpro.db` is SEE `aes256-ofb`) — noted,
not defeated, because every toolpath already embeds its own tool.

## The two `.c2d` formats

Contrary to what several sites claim, the *older* format is the readable one:

| Era | Format | Identify by |
|---|---|---|
| CC ≤ v6 (build ~316) | **Plain indented JSON** | file starts with `{` |
| CC v7/v8 (build 843+) | **SQLite 3 database** | file starts with `SQLite format 3` |

CC 853 opens its own SQLite files and (some) legacy JSON files, but it **rejected a
hand-built legacy-JSON file** in our testing. If you're generating `.c2d`
programmatically, target the SQLite format.

## Old format (JSON)

Top-level keys: `CIRCLE_OBJECTS`, `CURVE_OBJECTS`, `RECT_OBJECTS`,
`REGULAR_POLYGON_OBJECTS`, `TEXT_OBJECTS`, `TOOLPATH_GROUP_OBJECTS`,
`DOCUMENT_VALUES`.

A circle is minimal:

```json
{
  "group_id": [],
  "id": "{uuid}",
  "position": [x_mm, y_mm],
  "radius": r_mm
}
```

`DOCUMENT_VALUES` carries `WIDTH`, `HEIGHT`, `THICKNESS`, `MACHINE`, `MATERIAL`,
`ZERO_X/Y/Z`, `build_num`, etc. Origin is the board's bottom-left corner, units mm.

For *reading* this format, see also [ClayJarCom/ImportC2D](https://github.com/ClayJarCom/ImportC2D)
(Inkscape import extension; geometry only, no toolpaths).

## Modern format (SQLite container)

Tables:

| Table | Contents |
|---|---|
| `params` | key/value document settings: `width`, `height`, `thickness`, `num_toolpaths`, `machine`, `machine_type`, `material`, `version`, `build_num`, `minimum_build_num`, `minimum_carbide_motion_version`, `requires_pro`, `active_layer`, `display_mm`, `grid_enabled`, `grid_spacing`, `zero_x`, `zero_y`, `zero_z`, `retract`, `tiling_enabled`, `tile_margin_x`, `tile_overlap_y`, `tile_height`, `tile_current_index`, `background_visible`, `background_rotation`, `background_scale`, `background_position_x`, `background_position_y`, `background_opacity`, `show_notes` |
| `items` | one row per design object: `uuid`, `name`, `type` (`layer` \| `element` \| `toolpath` \| `toolpath_group` \| `model`), `version` (`J1`), `sz`, `data` |
| `sqlar` | auxiliary files: `preview.svg`, `all.svg`, `gcode.egc`, `background.png`, `notes.txt` |
| `metadata`, `log` | bookkeeping |

### Blob encoding

`items.data` is **plain zlib** (header bytes `78 01` / `78 9C` — no Qt `qCompress`
4-byte length prefix). The `sz` column must equal the **uncompressed byte length**.
Decompressed, every element is JSON.

### Element JSON (circle)

The modern format stores circles as full bezier paths: a `center`, five anchor
`points` (relative to center: `(-r,0) (0,r) (r,0) (0,-r) (-r,0)` plus a `(0,0)`
terminator), and `cp1`/`cp2` control-point arrays using the standard circle
approximation constant **κ = 0.5522847498307936 · r**. Also present: `behavior: 3`,
`geometryType: "circle"`, `point_type: [0,3,3,3,3,4]`, `smooth: [1,1,1,1,1,1]`,
an embedded `layer` object, `group_id`, `id` (`"{uuid}"`), `position`, `radius`,
`tabs: []`.

### Recipe for generating a valid file

1. **Clone an existing v8 `.c2d`** as a template (guarantees every structural
   detail CC expects).
2. `DELETE FROM items WHERE type IN ('element','toolpath')`; clear `log`.
3. `UPDATE params` — board `width`/`height`/`thickness`, `num_toolpaths = 0`.
4. Blank stale renders: `UPDATE sqlar SET sz=0, data=x'' WHERE name IN ('all.svg','preview.svg','gcode.egc')`.
5. `INSERT` your elements: fresh `{uuid}`, `type='element'`, `version='J1'`,
   `sz = len(json)`, `data = zlib(json)`.

`tools/New-C2d-18Holes.ps1` implements this end-to-end in Windows PowerShell 5.1
with **no dependencies** — SQLite access is P/Invoke against the OS-bundled
`C:\Windows\System32\winsqlite3.dll` (`tools/winsqlite.cs`), and the zlib stream is
built as `78 9C` + .NET raw-deflate + big-endian Adler-32.

## The 18 baseplate mounting holes

Extracted from the vector layer of Carbide 3D's official drawing
[`S3_XXL_Wasteboard.pdf`](https://carbide3d.com/files/S3_XXL_Wasteboard.pdf)
(sheet 1, scale 0.70866 pt/mm, cross-checked against the ordinate dimensions).
Spec: **Ø5.08 mm (0.20″) thru, ⌴ Ø12.70 mm (0.50″) × 6.35 mm deep**, 18 places,
on the assembled 1066.8 × 1003.3 mm two-half wasteboard, origin front-left:

| Row | Y (mm) | X positions (mm) |
|---|---|---|
| Front | 15.00 | 25.4 · 127.0 · 482.6 · 584.2 · 939.8 · 1041.4 |
| Front-inner | 476.25 | 76.2 · 533.4 · 990.6 |
| Back-inner | 527.05 | 76.2 · 533.4 · 990.6 |
| Back | 988.30 | 25.4 · 127.0 · 482.6 · 584.2 · 939.8 · 1041.4 |

`files/Shapeoko-3-XXL-Baseplate-18-Mounting-Holes-No-Path.c2d` is the generated result — each hole a
concentric counterbore + through-hole circle pair, no toolpaths (add your own in CC).
Opens cleanly in Carbide Create 853.

## Caveats

- Not affiliated with Carbide 3D; the format is proprietary and undocumented, so
  details may change between builds. Everything here was verified empirically on
  build 843 files and build 853 software.
- The `model` row payload is only partially mapped (empty-heightmap header decoded;
  files with actual 3D model data not yet observed).
