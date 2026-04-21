# Chart Plotter V3 — Sprite Atlas Report

Status: decision pending. Written 2026-04-21.

## 1. Why this matters

V3 renders S-57 nautical chart features by running each feature through the s52_dart engine, which emits a list of S-52 drawing instructions per feature. Three of those instructions reference a symbol/pattern by name:

- `SY(NAME)` — a point symbol (buoy icon, light flare, landmark glyph, etc.)
- `AP(NAME)` — an area pattern tile (hatch, stipple, anchorage fill)
- `LC(NAME)` — a complex line pattern (arrow stamps along a channel, cable zigzag, navarea-boundary dash-with-symbols)

Each of those names is resolved against a **sprite atlas** — a single PNG file plus a JSON index describing each sprite's rect within the PNG and its pivot point. If the name isn't in the atlas, the painter silently renders nothing (or, for `SY`, a 2 px CHBLK fallback dot).

Our atlas today is `assets/charts/sprite.{png,json}`. It contains ~150 sprites. The S-52 Presentation Library defines ~1180 symbols across all colour schemes. The gap is the source of most "missing chart features" the user sees.

## 2. Impact — what doesn't render today

Pulled from the V3 class-by-zoom inventory on `~/.signalk/charts-simple/01CGD_ENCs.mbtiles` (LI Sound NOAA ENC, 500 tiles sampled per zoom). Classes below have at least one referenced sprite missing from our atlas.

| Class   | Missing sprites | What the user loses |
|---|---|---|
| DAYMAR  | 7  | Daymarks / daybeacons — a primary US inland/ICW channel marker |
| RECTRC  | 6  | Recommended track arrows + pattern (z=13+) |
| DWRTCL  | 5  | Deep-water route centerlines |
| OBSTRN  | 3  | Some obstruction symbol variants (render as fallback dots) |
| FERYRT  | 3  | Ferry route stamps |
| VEGATN  | 3  | Vegetation pattern fills |
| M_QUAL  | 7  | CATZOC quality stars (important — drives trust in soundings) |
| FAIRWY  | 1  | Fairway centerline arrows |
| RESARE  | 2  | Restricted-area boundary patterns |
| DMPGRD  | 1  | Dumping ground boundary pattern |
| BOYLAT  | 1  | Some lateral-buoy variants |
| BCNSPP  | 1  | Special-purpose beacon variants |
| CBLSUB  | 1  | Submarine-cable zigzag |
| LNDRGN  | 1  | Land-region pattern |
| PRCARE  | 1  | Precautionary-area boundary |
| PIPSOL  | 2  | Submarine-pipeline pattern |
| PIPARE  | 2  | Pipeline-area boundary |
| ISTZNE  | 1  | Inshore traffic zone pattern |
| UNSARE  | 1  | Unsurveyed-area pattern |
| TOWERS  | 1  | Tower landmark variant |
| SBDARE  | 1  | Seabed-nature variants |
| SNDWAV  | 2  | Sand-wave pattern |
| MARCUL  | 1  | Marine-farm boundary |
| LOCMAG  | 1  | Local magnetic anomaly |
| NEWOBJ  | 2  | Generic new-object fallback |
| TS_*/T_* | 1 each | Tidal stream/station glyphs (rare in NOAA cells) |
| TSSLPT  | 1  | TSS lane-part arrow |

Net effect: ~25 object classes whose lookups match cleanly but whose referenced sprites are absent, causing either blank renders or fallback-dot renders for features the user actually cares about.

## 3. What the atlas format expects

Current `assets/charts/sprite.json` is keyed by sprite ID; each entry holds `x`, `y`, `width`, `height`, `pivotX`, `pivotY`. The paired `sprite.png` is a single raster with all sprites packed. `s52_dart`'s `SpriteAtlas.fromJson()` reads this format. Any backfill must produce the same shape (or we change the consumer).

## 4. Candidate sprite sources

Full research transcript is in the session; summarised table:

| Source | License | Format | Coverage | Names match S-52? | Recommended? |
|---|---|---|---|---|---|
| **OpenCPN `data/s57data/`** | GPL-2.0 | `chartsymbols.xml` (~1180 symbol/pattern/line-style defs with rect + pivot) + `rastersymbols-{day,dusk,dark}.png` | All 5 S-52 colour schemes | Yes — exact S-52 IDs | **Yes (primary candidate)** |
| erkswede/colors_and_symbols | GPL-2.0 (OpenCPN fork) | Same as OpenCPN | Nordic recolour, subset | Yes | Alt palette only |
| SMAC-M (LarsSchy) | MIT (but assets derive from OpenCPN) | MapServer mapfiles | Derived | Derived | No — MIT label doesn't launder OpenCPN's GPL |
| Freeboard-SK | Apache-2.0 | Rendering code only | No assets | n/a | No — no sprites shipped |
| wdantuma/s57-tiler | Unclear | Tile builder | n/a | n/a | No |
| OpenSeaMap renderer | CC/GPL | SVG | One style | **No** — uses human names (`Light_House.svg`) not S-52 IDs | No — would require hand-mapping ~600 IDs |
| OpenSeaMap-vector | CC0 | SVG from OSM tags | OSM style | No | No — different paradigm |
| **IHO S-52 PresLib official** | IHO copyright, **no redistribution** | Normative PDF | Authoritative | Yes | No — license blocks use |
| GDAL `s57data` | MIT | CSVs | Attributes only, no symbols | n/a | No |

**Only OpenCPN covers the ~1180 S-52 IDs with authoritative pivots, multiple colour schemes, and names that match the engine's lookups one-for-one.** Nothing else is close.

## 5. License analysis — OpenCPN GPL-2.0

OpenCPN ships under GPL-2.0. There is no separate LGPL exception for `data/s57data/`. A few relevant points:

1. `packages/s52_dart/LICENSE-NOTICES` originally claimed OpenCPN data was LGPL. That was incorrect and was corrected to GPL-2.0 in this PR.

2. Shipping the assets as runtime resources loaded by a Dart application likely qualifies as "mere aggregation" in the FSF's reading of GPL-2 §2, but this is a grey area — appellate courts have not consistently ruled on whether loading GPL data at runtime creates a derivative work. Safest legal posture: treat the chart-plotter-bound app as GPL-compatible and ship the OpenCPN notice + `COPYING.gplv2` alongside the atlas.

3. App Store policy: Apple has historically allowed GPL-2 apps but has also rejected specific apps that bundle GPL-2 code where the TOS conflict was found material. This is a project-level business decision, not a rendering decision.

4. Fair alternative: attribute OpenCPN conspicuously (About screen + a LICENSES bundle the user can view), ship `COPYING.gplv2` with the atlas, and document in the project README that the chart-rendering assets are GPL-2 while the app code remains under whatever ZedDisplay chooses.

## 6. Recommended path (assuming GPL-2.0 is acceptable)

Steps, in order:

1. **Correct the license notice.** ~~Update `packages/s52_dart/LICENSE-NOTICES` (the LGPL→GPL-2 correction for OpenCPN data).~~ **Done in this PR.**

2. **Vendor the source files.**
   - Copy `chartsymbols.xml` to `packages/s52_dart/third_party/opencpn/chartsymbols.xml`
   - Copy `rastersymbols-day.png` to the same directory.
   - Copy OpenCPN's `COPYING.gplv2` to `packages/s52_dart/third_party/opencpn/COPYING.gplv2`
   - Add an attribution README pointing at the OpenCPN repo and commit hash.

3. **Write a converter** (`packages/s52_dart/tool/build_sprite_atlas.dart`) that:
   - Parses `chartsymbols.xml` (the schema is well-documented — `<symbol name="X"><bitmap width="w" height="h"><graphics-location x="xx" y="yy"/><pivot x="px" y="py"/></bitmap></symbol>` for the key elements).
   - Emits `assets/charts/sprite.json` in our current schema.
   - Copies the PNG straight through as `assets/charts/sprite.png`.
   - Optionally regenerates alternate colour-scheme atlases (dusk, dark) into separate files for future night-mode support.

4. **Run the converter as part of `flutter pub get`** (via a pre-build hook or a one-off script the developer runs on upgrade).

5. **Verify** by re-running the inventory script and confirming every `partial(N miss)` row becomes `yes`.

6. **Add UI affordance** for the future: make the sprite atlas the *day* atlas today, plan a layer-switcher for dusk/night when the chart plotter needs it (not blocking).

Estimated effort: converter is ~200 lines of Dart (XML parsing + JSON emission). License-notice update is trivial. Total: half a day of focused work plus the testing cycle.

## 7. Fallback if GPL-2.0 is rejected

Hand-author SVGs from the S-52 specification for the ~50 most commonly-referenced missing symbols. The S-52 PresLib is a public spec (the normative document is IHO copyright, but drawing a buoy from the documented shape and colour is not copyright-derivative). This path:

- Covers the highest-impact symbols first (DAYMAR, CATZOC stars, RECTRC arrows, OBSTRN variants).
- Is clean-room from IHO text and could be licensed however ZedDisplay prefers.
- Leaves long-tail symbols (~500 of them) unfixed indefinitely.
- Multi-day art task — much longer than the OpenCPN converter path.

Not recommended unless GPL is a hard block.

## 8. Open questions for the project owner

- Is GPL-2.0 acceptable for the runtime assets? (If the app is not itself GPL, see section 5.)
- If night/dusk modes are planned, should we ship all three PNG variants now, or only day and defer the others?
- Does the converter run at developer-build time, or do we check the generated `sprite.{png,json}` into git and treat the generator as a one-off? (Checking in is simpler; regenerating on every upgrade is cleaner.)

## 9. References

- OpenCPN repo: https://github.com/OpenCPN/OpenCPN
- OpenCPN `chartsymbols.xml`: https://github.com/OpenCPN/OpenCPN/blob/master/data/s57data/chartsymbols.xml
- OpenCPN COPYING.gplv2: https://github.com/OpenCPN/OpenCPN/blob/master/COPYING.gplv2
- IHO S-52 PresLib Ed 4.0.3 (reference only): https://iho.int/uploads/user/pubs/standards/s-52/S-52%20PresLib%20Ed%204.0.3%20Part%20I%20Addendum_Clean.pdf
- Current atlas consumers: `packages/s52_dart/lib/src/sprite.dart`, `packages/s52_dart/lib/src/lookup.dart`

## 10. Related code

- `lib/widgets/tools/chart_plotter_v3_tool.dart:1985` — `_paintFeature` SY fallback (2 px CHBLK dot when atlas lookup fails)
- `lib/widgets/tools/chart_plotter_v3_tool.dart` — `_paintLineComplex` / `_paintAreaPattern` — silent returns when pattern missing
- `packages/s52_dart/lib/src/sprite.dart` — `SpriteAtlas.fromJson` consumer
- `assets/charts/sprite.json` — current atlas index (~150 entries)
- `assets/charts/sprite.png` — current atlas PNG
