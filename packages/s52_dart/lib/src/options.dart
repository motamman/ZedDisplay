import 'enums.dart';

/// User-tunable S-52 presentation options. Matches the control knobs
/// the IHO S-52 presentation library exposes to a mariner plus the few
/// engineering defaults used by the OpenCPN-derived asset bundle.
///
/// Depths are in the chart's native SI unit (metres). Callers that
/// display depths in feet/fathoms convert at render time via
/// [depthConversionFactor] — the S-52 logic always operates in metres.
class S52Options {
  const S52Options({
    this.shallowDepth = 2,
    this.safetyDepth = 3,
    this.deepDepth = 6,
    this.graphicsStyle = S52GraphicsStyle.paper,
    this.boundaries = S52Boundaries.plain,
    this.colorCount = 4,
    this.colorTable = S52ColorScheme.dayBright,
    this.otherLayers = const [
      'SOUNDG',
      'OBSTRN',
      'UWTROC',
      'WRECKS',
      'DEPCNT',
    ],
    this.depthUnit = 'm',
    this.depthConversionFactor = 1.0,
    this.displayCategory = S52DisplayCategory.standard,
    this.selectedSafeContour = 1000,
    this.currentResolution = 0,
  });

  /// Shallow-water depth threshold (m). Areas shallower than this use
  /// the shallowest colour band. Matches OpenCPN's `S52_SHALLOW`.
  final double shallowDepth;

  /// Safety contour depth (m). Contours at or shallower than this are
  /// rendered with the thick "safety" line. Matches `S52_SAFETY`.
  final double safetyDepth;

  /// Deep-water depth threshold (m). Areas deeper than this use the
  /// deep colour band. Matches `S52_DEEP`.
  final double deepDepth;

  /// Paper vs simplified symbology. Determines which lookup table
  /// variant the engine prefers for point features.
  final S52GraphicsStyle graphicsStyle;

  /// Plain vs symbolised boundaries. Determines which lookup table
  /// variant the engine prefers for area boundaries.
  final S52Boundaries boundaries;

  /// Depth colour band count — 2 or 4. Four-band schemes (VS/MS/MD/DW)
  /// are standard; two-band schemes merge the middle bands.
  final int colorCount;

  /// Active S-52 colour scheme — day/dusk/night/white-back.
  final S52ColorScheme colorTable;

  /// Object-class codes that participate in the OTHER display category
  /// by default. Kept configurable so consumers can promote or demote
  /// layers relative to the default set.
  final List<String> otherLayers;

  /// Display-unit label for depth values the renderer writes to the
  /// screen (soundings, contour labels). Not used by CS procedures
  /// themselves but passed through for rendering adapters.
  final String depthUnit;

  /// Multiplicative factor to convert metres to [depthUnit] at render
  /// time. A renderer typically formats `valueM * factor` with
  /// [depthUnit]. Set 1.0 for metres; ~3.281 for feet; 0.547 for
  /// fathoms.
  final double depthConversionFactor;

  /// Active display-category filter — controls which lookup rows are
  /// allowed through. STANDARD passes DISPLAYBASE+STANDARD; OTHER
  /// passes all three.
  final S52DisplayCategory displayCategory;

  /// The depth value of the user's selected safety contour in metres.
  /// DEPCNT02 highlights contours whose `VALDCO` equals this value.
  ///
  /// Default 1000 m mirrors Freeboard-SK's init value — effectively
  /// disables highlighting because no real chart contour hits 1000 m.
  /// A renderer can pre-walk its features and override this via
  /// [copyWith] to the smallest `VALDCO >= safetyDepth` it finds, for
  /// proper S-52 behaviour.
  final double selectedSafeContour;

  /// Current map resolution in metres-per-pixel. Used by SOUNDG02 to
  /// decide whether to format soundings with decimal tenths (zoomed
  /// in) or whole metres (zoomed out). Default 0 = "not provided";
  /// procedures fall back to the zoomed-out rendering.
  final double currentResolution;

  /// Returns a copy with any subset of fields overridden.
  S52Options copyWith({
    double? shallowDepth,
    double? safetyDepth,
    double? deepDepth,
    S52GraphicsStyle? graphicsStyle,
    S52Boundaries? boundaries,
    int? colorCount,
    S52ColorScheme? colorTable,
    List<String>? otherLayers,
    String? depthUnit,
    double? depthConversionFactor,
    S52DisplayCategory? displayCategory,
    double? selectedSafeContour,
    double? currentResolution,
  }) =>
      S52Options(
        shallowDepth: shallowDepth ?? this.shallowDepth,
        safetyDepth: safetyDepth ?? this.safetyDepth,
        deepDepth: deepDepth ?? this.deepDepth,
        graphicsStyle: graphicsStyle ?? this.graphicsStyle,
        boundaries: boundaries ?? this.boundaries,
        colorCount: colorCount ?? this.colorCount,
        colorTable: colorTable ?? this.colorTable,
        otherLayers: otherLayers ?? this.otherLayers,
        depthUnit: depthUnit ?? this.depthUnit,
        depthConversionFactor:
            depthConversionFactor ?? this.depthConversionFactor,
        displayCategory: displayCategory ?? this.displayCategory,
        selectedSafeContour: selectedSafeContour ?? this.selectedSafeContour,
        currentResolution: currentResolution ?? this.currentResolution,
      );
}

/// Paper-chart vs simplified point-symbol style.
enum S52GraphicsStyle { paper, simplified }

/// Plain vs symbolised area-boundary style.
enum S52Boundaries { plain, symbolised }

/// Active S-52 colour scheme.
enum S52ColorScheme { dayBright, dayWhiteBack, dusk, night }
