# Elements & toolpaths: the `J1` payloads

Decoded from a Carbide Create **build 853** file containing every element type and
every toolpath type the UI offers (`samples/` holds the raw JSON of each).
Complements [FORMAT.md](FORMAT.md), which covers the container.

## Elements (`items.type = 'element'`, version `J1`)

Five `geometryType` values exist: `circle`, `rectangle`, `regular_polygon`,
`path`, `text`. All share `id` (`"{uuid}"`), `group_id` (array of group uuids,
empty when ungrouped), an embedded `layer` object, and `tabs`.

### The shared point model (all except `text`)

Geometry is a closed bezier path over parallel arrays:

| Key | Meaning |
|---|---|
| `points` | anchor points `[x,y]` |
| `cp1`, `cp2` | bezier control points for the segment *arriving at* each anchor |
| `point_type` | per-anchor: `0` = first point, `1` = line segment, `3` = bezier segment, `4` = closing point |
| `smooth` | per-anchor smooth-node flag (0/1) |
| `behavior` | shape class: `0` path · `1` rectangle · `2` regular_polygon · `3` circle |

**Coordinate space differs by shape:** `circle`, `rectangle` and
`regular_polygon` store `points`/`cp1`/`cp2` **relative to `center`**
(`position` == `center`, absolute mm); a `path` stores **absolute**
coordinates and keeps `position` at `[0, 0]`.

### Per-type extras

| Type | Extra keys | Notes |
|---|---|---|
| `circle` | `radius` | control points at κ = 0.5522847498307936 · r |
| `rectangle` | `width`, `height`, `corner_type`, `radius` | `corner_type`: `0` square · `1` fillet · `2` chamfer (line segments) · `3` inverted fillet · `4` dogbone · `5` T-bone. `radius` = corner radius (present, default 6.35, even for square) |
| `regular_polygon` | `num_sides`, `radius`, `rotation` | vertices on the circumradius; CC will happily save a degenerate `radius: 0` one |
| `path` | — | the free-form/boolean-result shape; also what curves become |
| `text` | see below | no `behavior`, no point model |

### `text`

Text keeps both the *source* (editable) and the *rendered outlines*:

| Key | Example | Meaning |
|---|---|---|
| `text` | `"PhobicDotNo"` | the string |
| `font` | `"Helvetica-Regular"` | face name |
| `qtfont` | `"Helvetica,100,-1,5,400,0,…"` | full Qt `QFont::toString()` descriptor |
| `font_height` | `30` | mm |
| `spacing` | `1` | letter-spacing factor |
| `alignment` | `0` | justification |
| `arc_enabled`, `arc_radius`, `arc_center`, `arc_angle_offset`, `arc_text_on_bottom` | | text-on-arc settings |
| `transform` | `[1,0,0, 0,1,0, 450,606,1]` | row-major 3×3; translation in elements 6,7 |
| `rendered` | array of contours | **pre-flattened glyph outlines**: each contour is an array of `[x,y]` points (no beziers — already linearized), in local space, placed by `transform` |

Because `rendered` ships the outlines, a parser can draw text without any font
machinery — and it's why a text element weighs ~170 KB.

## Toolpaths (`items.type = 'toolpath'`, version `J1`)

Seven `type` values: `pocket_toolpath`, `contour`, `cutout`,
`drilling_toolpath`, `keyhole_toolpath`, `advanced_vcarve_toolpath`,
`texture_toolpath`. (The `items.name` column mirrors the type.)

### Common keys

`name`, `uuid`, `enabled`, `type`, `version: 1`,
`elements` (array of `{"uuid": "{…}"}` references to elements),
`tool` (fully embedded — see below), `speeds` (`feedrate`, `plungerate`, `rpm`,
mm/min), `toolpath_group` (uuid of the group row), `toolpath_layers` (array),
`automatic_parameters` (UI "use recommended settings" flag),
`start_depth` / `end_depth`.

### ⚠ Depth sign convention changed between builds

- **build 843** wrote depths as **negative-down strings**: `"end_depth": "-19.126"`
- **build 853** writes **positive-down strings**: `"end_depth": "2.540"`

Both are strings; `cutout.cut_depth` is a bare number. Target the convention of
the build that will open the file.

### Per-type fields

| Type | Unique keys (observed values) |
|---|---|
| `pocket_toolpath` | `stepdown`, `stepover`, `stock_to_leave`, `tolerance`, `angle`, `enable_ramping`, `ramp_angle`, `enable_rest`, `rest_diameter` |
| `contour` | `ofset_dir` *(sic — Carbide's typo)*: `-1` inside / `1` outside / `0` on the line; `climb`, `tab_height`, `tab_width`, `ignore_tabs`, `stepdown`, `stepover`, `stock_to_leave`, `tolerance` |
| `cutout` | `cut_depth` (number), `break_through`, `depth_per_pass`, `slot_depth_per_pass`, `path_type`, `flip_inside_outside`, `tab_height`, `tab_width`, `ignore_tabs`, `enable_finishing`, `finish_doc`, `finish_speeds`, `enable_finish_allowance` |
| `drilling_toolpath` | `drill_type` (`0` = plunge), `peck_distance`, `stepdown`, `stock_to_leave` — targets circle elements, drills at their centers |
| `keyhole_toolpath` | `angle` (slot direction, degrees), `length` (slot length, mm) |
| `advanced_vcarve_toolpath` | two tools: `tool` (the V-bit) + `tool_pocket`, with parallel `speeds_pocket`, `stepdown_pocket`, `stepover_pocket`, `stock_to_leave_pocket`; `pocket_enabled`, `pocket_first`, `inlay_enabled`, `link_type`, `link_uuid` |
| `texture_toolpath` | `min_depth`/`max_depth`, `min_length`/`max_length`, `min_overlap`/`max_overlap`, `stepover_variation`, `angle` — no stepdown/ramping |

### The embedded `tool` object

Toolpaths carry the complete tool definition — no external tool-library
dependency:

```json
{
  "angle": 45,            // V-bit included angle; 0 for end mills
  "corner_radius": 0,     // ball/bull nose radius
  "diameter": 12.7,
  "display_mm": false,
  "finish_allowance": 0.508,
  "flutes": 3,
  "length": 19.05,        // cutting length
  "model": "201",
  "name": "#201 End Mill (1/4\")",
  "number": 201,
  "overall_length": 3.175,
  "plungerate": 381,
  "read_only": true,      // true = Carbide library tool
  "slot_depth": 1.524, "slot_feedrate": 2286, "slot_rpm": 18000,
  "surfacing_feedrate": 2540, "surfacing_rpm": 18000, "surfacing_stepover": 20,
  "type": 2,              // 0 = flat end mill, 2 = V-bit (ball presumed 1)
  "url": "https://shop.carbide3d.com/…",
  "uuid": "{00000000-0000-0000-0000-000000000000}",
  "vendor": "Carbide 3D"
}
```

### Groups

`toolpath_group` items are pure folders (`name`, `uuid`, `enabled`, `expanded`)
with **no child list** — membership lives on each toolpath's `toolpath_group`
key. CC opens files with empty groups without complaint.

## Practical notes for writers

1. Every `elements[].uuid` must resolve to an element row, and
   `params.num_toolpaths` must equal the toolpath row count.
2. Depths: match the sign convention of the target build (see above), and keep
   them **strings** (except `cut_depth`).
3. A hand-built pocket toolpath with an embedded tool, verified working in
   CC 853, is generated by `tools/New-C2d-18Holes.ps1`'s sibling logic — see the
   repo history for the 6mm variant.
