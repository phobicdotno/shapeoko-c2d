# The `.c2d` container, in depth

Everything in the modern (CC v7/v8) SQLite `.c2d` file **except** the drawing
elements and toolpaths — plus the legacy JSON format's document header.
All observations verified empirically against a build-843 file
(`Shapeoko-XXL-Wasteboard_v8.c2d`, saved by Carbide Create on Windows) and
cross-checked with Carbide Create 853.

## Database-level facts

| Property | Value |
|---|---|
| Format | SQLite 3, `page_size` 4096, encoding UTF-8 |
| `application_id` / `user_version` | 0 / 0 (CC does not stamp them — you cannot identify a `.c2d` by application_id; sniff the schema instead) |
| `journal_mode` | delete |
| Schema objects | 6 tables, no views, no triggers, only the implicit `sqlite_autoindex_*` PK indexes |

Tables: `metadata`, `params`, `items`, `sqlar`, `log`, `sqlite_sequence`.

## `metadata`

```sql
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)
```

**Empty in every file observed.** Reserved/vestigial — document-level settings
live in `params` instead.

## `params` — the document header

```sql
CREATE TABLE params(key TEXT PRIMARY KEY, value TEXT)
```

All values are stored as text; numbers use `.` decimal separator regardless of
locale. All lengths are **millimetres**, even when the UI displays inches.
Full key set with observed values (build 843):

| Key | Observed | Meaning |
|---|---|---|
| `width` | `825.5` | Stock width, mm |
| `height` | `774.7` | Stock height, mm |
| `thickness` | `19.05` | Stock thickness, mm |
| `material` | `Any` | Material preset name |
| `machine` | `Shapeoko 5 Pro` | Machine preset name |
| `machine_type` | `Shapeoko` | Machine family |
| `zero_x`, `zero_y`, `zero_z` | `0.0` | Job zero relative to bottom-left / top of stock, mm |
| `retract` | `2.54` | Retract/safety height, mm |
| `display_mm` | `0` | UI unit toggle: `1` = mm, `0` = inch. Storage stays mm either way |
| `grid_enabled` | `1` | Grid on/off |
| `grid_spacing` | `5.0` | Grid pitch, mm |
| `version` | `100` | Document format version |
| `build_num` | `843` | CC build that saved the file |
| `minimum_build_num` | `810` | **Load gate**: older CC builds refuse to open the file |
| `minimum_carbide_motion_version` | `565` | Minimum Carbide Motion build for the embedded G-code |
| `requires_pro` | `0` | `1` if the design uses Pro-only features |
| `num_toolpaths` | `1` | Count of toolpath rows in `items` — keep consistent when editing |
| `active_layer` | `` (empty) | UUID of the active drawing layer (`''` = DEFAULT) |
| `tiling_enabled` | `0` | Tiling (oversized-job splitting) on/off |
| `tile_margin_x` | `25.4` | Tiling margin, mm |
| `tile_overlap_y` | `12.7` | Tile overlap, mm |
| `tile_height` | `508.0` | Tile height, mm |
| `tile_current_index` | `0` | Currently selected tile |
| `background_visible` | `0` | Tracing-background image on/off |
| `background_rotation` | `0.0` | Background transform (degrees) |
| `background_scale` | `1.0` | Background transform |
| `background_position_x` / `_y` | `0.0` | Background transform, mm |
| `background_opacity` | `0.5` | Background render opacity 0–1 |
| `show_notes` | `1` | Show the notes panel (content lives in `sqlar/notes.txt`) |

## `items` — the object store (non-graphic rows)

```sql
CREATE TABLE items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT UNIQUE,   -- "{guid}" for real objects; the literal string 'MODEL' for the model row
  name TEXT,          -- debugging label: 'circle', 'path', 'pocket_toolpath', 'DEFAULT', ''
  type TEXT,          -- 'layer' | 'element' | 'toolpath' | 'toolpath_group' | 'model'
  version TEXT,       -- payload schema tag: 'J1' (JSON v1) for all but the model row ('model_2')
  sz INT,             -- uncompressed payload size in bytes
  data BLOB           -- zlib-compressed payload (header 78 01; no Qt qCompress prefix)
)
```

`sqlite_sequence` holds the `items` AUTOINCREMENT high-water mark — SQLite
maintains it automatically on INSERT; no need to touch it.

### `type='layer'` (version `J1`)

One row per drawing layer; zlib-decompresses to:

```json
{
  "blue": 0, "green": 0, "red": 0,
  "locked": false, "visible": true,
  "name": "DEFAULT",
  "uuid": ""
}
```

The DEFAULT layer has empty `uuid` and its `items.uuid` column is empty too.
Every element embeds a full copy of its layer object (denormalized).

### `type='toolpath_group'` (version `J1`)

Organizational folder for toolpaths in the CC sidebar:

```json
{
  "enabled": true,
  "expanded": true,
  "name": "Group 1",
  "uuid": "{452de396-...}"
}
```

Note there is **no child list** — toolpaths do not reference their group in the
group blob, so a group row can safely outlive its toolpaths (verified: CC 853
opens a file with an empty group).

### `type='model'` (version `model_2`) — the 3D heightmap slot

Exactly one row, `uuid='MODEL'`, `name=''`. The payload is **binary, not JSON**
(the only non-JSON item payload). For an empty model it is 52 bytes:

| Offset | Type | Observed | Meaning |
|---|---|---|---|
| 0 | int64 LE | `2` | Format version (matches the `model_2` tag) |
| 8 | double LE | `0.7991287…` | Cell size, mm/cell |
| 16 | double LE | `1.0` | Unknown (scale?) |
| 24 | double LE | `0.0` | Unknown (offset x?) |
| 32 | double LE | `0.0` | Unknown (offset y?) |
| 40 | int32 LE | `1033` | Grid columns — `cols × cell ≈ params.width` (1033 × 0.79913 = 825.5 ✓) |
| 44 | int32 LE | `969` | Grid rows — `rows × cell ≈ params.height` (≈ 774.4 ✓) |
| 48 | int32 LE | `0` | Height-sample payload length (0 = no 3D model) |

A file with actual 3D modeling (CC Pro) presumably follows the header with
`cols × rows` height samples; not yet observed.

## `sqlar` — embedded auxiliary files

```sql
CREATE TABLE sqlar(name TEXT PRIMARY KEY, mode INT, mtime INT, sz INT, data BLOB)
```

This is the standard [SQLite Archive](https://sqlite.org/sqlar.html) layout,
with one Carbide quirk: where stock sqlar uses raw deflate, **CC compresses with
zlib** (`78 01` header). The sqlar convention still applies:

- `sz == length(data)` → stored **uncompressed**
- `sz > length(data)` → stored **zlib-compressed**, `sz` = original size
- `mode` = `33188` (octal `100644`) for every row; `mtime` = save timestamp

Observed rows:

| Name | Stored | Contents |
|---|---|---|
| `preview.svg` | zlib | SVG render of the design. Canvas in px at ~3.78 px/mm (96 dpi): 825.5 mm board → `width="3120px"` |
| `all.svg` | zlib | Same SVG (identical bytes in the observed file); presumably design-only vs. with-toolpaths renders can differ |
| `background.png` | raw, 0 bytes | The tracing background image (empty when unused) |
| `notes.txt` | raw, 0 bytes | The document notes panel text (see `params.show_notes`) |
| `debug.txt` | raw | Save-environment breadcrumb — literally: `OS: Windows` / `CC Build: 843` |
| `gcode.egc` | raw | **Pre-generated G-code in Carbide's encrypted `.egc` container**: magic bytes `CCV1`, then high-entropy (encrypted/obfuscated) data. This is what Carbide Motion runs; the encryption is why you can't extract plain G-code from a `.c2d`. Regenerated by CC on save |

When editing a file programmatically, blank the render/G-code rows
(`UPDATE sqlar SET sz=0, data=x'' WHERE name IN ('all.svg','preview.svg','gcode.egc')`) —
CC regenerates them and you avoid shipping stale toolpaths to Carbide Motion.

## `log`

```sql
CREATE TABLE log(id INTEGER PRIMARY KEY AUTOINCREMENT,
                 time INT DEFAULT CURRENT_TIMESTAMP, type TEXT, name TEXT, data TEXT)
```

Event/bookkeeping log. Empty in the observed file; safe to clear.

## Legacy JSON format: `DOCUMENT_VALUES`

The old (CC ≤ v6) plain-JSON `.c2d` keeps its document header in a single
`DOCUMENT_VALUES` object. Full key set (from a build-316 file):

| Key | Example | Notes |
|---|---|---|
| `WIDTH`, `HEIGHT` | `787.4` | Stock size, mm |
| `THICKNESS` | `19.177` | mm |
| `MACHINE` | `"Shapeoko XXL"` | |
| `MATERIAL` | `"MDF"` | |
| `RETRACT` | `10` | mm |
| `ZERO_X`, `ZERO_Y`, `ZERO_Z` | `0` / `787.4` / `0` | Job zero; note `ZERO_Y = HEIGHT` means top-left zero |
| `DISPLAYMM` | `false` | UI unit toggle |
| `grid_enabled`, `grid_spacing` | `true`, `5.0038` | |
| `build_num` | `316` | Saving build |
| `version` | `1` | Format version |
| `BACKGROUND_IMAGE` | `"AAAAAA=="` | Base64 (4 zero bytes when unused) |
| `BACKGROUND_OPACITY` | `0.5` | |
| `BACKGROUND_POSITION_X`, `_Y` | `0` | |
| `BACKGROUND_ROTATION`, `BACKGROUND_SCALE` | `0`, `1` | |
| `BACKGROUND_VISIBLE` | `false` | |

The mapping old → new is nearly 1:1 (`WIDTH`→`params.width`, `DISPLAYMM`→`display_mm`,
`BACKGROUND_*`→`background_*`) with the newer keys (`machine_type`, tiling,
`requires_pro`, minimum-version gates, `num_toolpaths`, `active_layer`,
`show_notes`) having no legacy counterpart.

## Practical rules for programmatic edits

1. Respect the load gates: keep `minimum_build_num` ≤ the CC build that will open
   the file, and bump nothing you don't understand.
2. Keep `num_toolpaths` equal to `COUNT(*) FROM items WHERE type='toolpath'`.
3. `sz` must equal the uncompressed payload length for every `items`/`sqlar` blob.
4. Blank `preview.svg` / `all.svg` / `gcode.egc` rather than leaving them stale.
5. Leave the `MODEL` row and layer row alone unless you know why you're touching them.
