// S-57 Mapbox GL Style for MapLibre GL.
//
// Color palette ported from Freeboard-SK DAY_BRIGHT scheme.
// Layer styling based on IHO S-52 presentation library (simplified).
//
// Reference: freeboard-sk/src/app/modules/map/ol/lib/charts/s57Style.ts

/// Builds a complete MapLibre GL Style JSON with OSM base, OpenSeaMap overlay,
/// and S-57 vector chart layers with nautical symbology.
///
/// [charts] — list of chart metadata maps from SignalK resources API.
///   Each must have 'id', 'url' (tile URL template), 'minzoom', 'maxzoom'.
/// [baseUrl] — SignalK server base URL (e.g. 'http://192.168.1.100:3000').
/// [authToken] — JWT token for tile authentication (appended as query param).
/// Auth is handled via MapLibre's setCustomHeaders, not in tile URLs.
Map<String, dynamic> buildChartPlotterStyle({
  required List<Map<String, dynamic>> charts,
  required String baseUrl,
}) {
  // Build sources
  final sources = <String, dynamic>{
    // OSM disabled for starvation test
    // 'osm': {
    //   'type': 'raster',
    //   'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
    //   'tileSize': 256,
    //   'attribution': '© OpenStreetMap contributors',
    // },
    // OpenSeaMap disabled — too many raster requests starve S-57 vector tile loading
    // 'openseamap': {
    //   'type': 'raster',
    //   'tiles': ['https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png'],
    //   'tileSize': 256,
    // },
  };

  // Add S-57 vector sources
  for (final chart in charts) {
    final id = chart['id'] as String;
    final chartUrl = chart['url'] as String?;
    if (chartUrl == null) continue;
    final tileUrl = '$baseUrl$chartUrl';
    final minZ = chart['minzoom'] as int? ?? 9;
    final maxZ = chart['maxzoom'] as int? ?? 16;
    sources['s57-$id'] = {
      'type': 'vector',
      'tiles': [tileUrl],
      'minzoom': minZ,
      'maxzoom': maxZ,
    };
  }

  // Collect S-57 source IDs
  final s57Sources =
      charts.where((c) => c['url'] != null).map((c) => 's57-${c['id']}');

  // Build layers
  final layers = <Map<String, dynamic>>[
    // Background
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': 'rgba(212,234,238,1)'},
    },
    // OSM base disabled for starvation test
    // {
    //   'id': 'osm-base',
    //   'type': 'raster',
    //   'source': 'osm',
    //   'paint': {'raster-opacity': 1.0},
    // },
  ];

  // Add S-57 layers per source (fill layers first, then lines, then symbols)
  for (final src in s57Sources) {
    layers.addAll(_s57FillLayers(src));
  }

  // OpenSeaMap overlay disabled — raster requests starve S-57 vector tile loading
  // layers.add({
  //   'id': 'openseamap-overlay',
  //   'type': 'raster',
  //   'source': 'openseamap',
  //   'paint': {'raster-opacity': 1.0},
  // });

  for (final src in s57Sources) {
    layers.addAll(_s57LineLayers(src));
  }
  for (final src in s57Sources) {
    layers.addAll(_s57SymbolLayers(src));
  }

  return {
    'version': 8,
    'id': 'chart-plotter',
    'name': 'Chart Plotter',
    'sources': sources,
    'layers': layers,
  };
}

// =============================================================================
// S-57 Fill layers
// =============================================================================

List<Map<String, dynamic>> _s57FillLayers(String src) => [
      // SEAARE — semi-transparent so OSM shows through
      {
        'id': '$src-seaare',
        'type': 'fill',
        'source': src,
        'source-layer': 'SEAARE',
        'paint': {'fill-color': 'rgba(212,234,238,0.5)'},
      },
      // DEPARE — depth gradient using data-driven color
      // TEMPORARY: using very distinct colors to verify rendering
      {
        'id': '$src-depare',
        'type': 'fill',
        'source': src,
        'source-layer': 'DEPARE',
        'paint': {
          'fill-color': [
            'step',
            ['to-number', ['get', 'DRVAL1'], 0],
            'rgba(102,178,255,1)',   // < 2m: dark blue (shallow)
            2, 'rgba(145,200,255,1)', // 2-3m: medium blue
            3, 'rgba(190,220,245,1)', // 3-6m: light blue
            6, 'rgba(225,240,250,1)', // >= 6m: very light blue (deep)
          ],
          'fill-opacity': 0.7,
        },
      },
      // DRGARE
      {
        'id': '$src-drgare',
        'type': 'fill',
        'source': src,
        'source-layer': 'DRGARE',
        'paint': {'fill-color': 'rgba(131,178,149,0.5)'},
      },
      // LNDARE — land is opaque, covers water
      {
        'id': '$src-lndare',
        'type': 'fill',
        'source': src,
        'source-layer': 'LNDARE',
        'paint': {'fill-color': 'rgba(201,185,122,0.9)'},
      },
      // BUAARE
      {
        'id': '$src-buaare',
        'type': 'fill',
        'source': src,
        'source-layer': 'BUAARE',
        'paint': {'fill-color': 'rgba(201,185,122,1)', 'fill-opacity': 0.8},
      },
      // LAKARE
      {
        'id': '$src-lakare',
        'type': 'fill',
        'source': src,
        'source-layer': 'LAKARE',
        'paint': {'fill-color': 'rgba(152,197,242,1)'},
      },
      // RIVERS
      {
        'id': '$src-rivers',
        'type': 'fill',
        'source': src,
        'source-layer': 'RIVERS',
        'paint': {'fill-color': 'rgba(152,197,242,1)'},
      },
      // CANALS
      {
        'id': '$src-canals',
        'type': 'fill',
        'source': src,
        'source-layer': 'CANALS',
        'paint': {'fill-color': 'rgba(152,197,242,1)'},
      },
      // FAIRWY
      {
        'id': '$src-fairwy',
        'type': 'fill',
        'source': src,
        'source-layer': 'FAIRWY',
        'paint': {'fill-color': 'rgba(211,166,233,0.2)'},
      },
      // RESARE
      {
        'id': '$src-resare',
        'type': 'fill',
        'source': src,
        'source-layer': 'RESARE',
        'paint': {'fill-color': 'rgba(211,166,233,0.15)'},
      },
      // ACHARE
      {
        'id': '$src-achare',
        'type': 'fill',
        'source': src,
        'source-layer': 'ACHARE',
        'paint': {'fill-color': 'rgba(211,166,233,0.15)'},
      },
      // TSSLPT
      {
        'id': '$src-tsslpt',
        'type': 'fill',
        'source': src,
        'source-layer': 'TSSLPT',
        'paint': {'fill-color': 'rgba(211,166,233,0.2)'},
      },
      // OBSTRN (area)
      {
        'id': '$src-obstrn-fill',
        'type': 'fill',
        'source': src,
        'source-layer': 'OBSTRN',
        'paint': {'fill-color': 'rgba(115,182,239,0.5)'},
      },
    ];

// =============================================================================
// S-57 Line layers
// =============================================================================

List<Map<String, dynamic>> _s57LineLayers(String src) => [
      // LNDARE outline
      {
        'id': '$src-lndare-line',
        'type': 'line',
        'source': src,
        'source-layer': 'LNDARE',
        'paint': {'line-color': 'rgba(139,102,31,1)', 'line-width': 1},
      },
      // COALNE
      {
        'id': '$src-coalne',
        'type': 'line',
        'source': src,
        'source-layer': 'COALNE',
        'paint': {'line-color': 'rgba(82,90,92,1)', 'line-width': 2},
      },
      // SLCONS
      {
        'id': '$src-slcons',
        'type': 'line',
        'source': src,
        'source-layer': 'SLCONS',
        'paint': {'line-color': 'rgba(82,90,92,1)', 'line-width': 2},
      },
      // DEPCNT
      {
        'id': '$src-depcnt',
        'type': 'line',
        'source': src,
        'source-layer': 'DEPCNT',
        'paint': {'line-color': 'rgba(125,137,140,1)', 'line-width': 1},
      },
      // DRGARE outline
      {
        'id': '$src-drgare-line',
        'type': 'line',
        'source': src,
        'source-layer': 'DRGARE',
        'paint': {
          'line-color': 'rgba(163,180,183,1)',
          'line-width': 1,
          'line-dasharray': [4, 2]
        },
      },
      // FAIRWY line
      {
        'id': '$src-fairwy-line',
        'type': 'line',
        'source': src,
        'source-layer': 'FAIRWY',
        'paint': {
          'line-color': 'rgba(197,69,195,0.6)',
          'line-width': 1,
          'line-dasharray': [6, 3]
        },
      },
      // RESARE line
      {
        'id': '$src-resare-line',
        'type': 'line',
        'source': src,
        'source-layer': 'RESARE',
        'paint': {
          'line-color': 'rgba(197,69,195,1)',
          'line-width': 2,
          'line-dasharray': [6, 3]
        },
      },
      // ACHARE line
      {
        'id': '$src-achare-line',
        'type': 'line',
        'source': src,
        'source-layer': 'ACHARE',
        'paint': {
          'line-color': 'rgba(211,166,233,1)',
          'line-width': 2,
          'line-dasharray': [6, 3]
        },
      },
      // TSSBND
      {
        'id': '$src-tssbnd',
        'type': 'line',
        'source': src,
        'source-layer': 'TSSBND',
        'paint': {'line-color': 'rgba(197,69,195,1)', 'line-width': 2},
      },
      // NAVLNE
      {
        'id': '$src-navlne',
        'type': 'line',
        'source': src,
        'source-layer': 'NAVLNE',
        'paint': {
          'line-color': 'rgba(125,137,140,1)',
          'line-width': 1,
          'line-dasharray': [8, 4]
        },
      },
      // CBLSUB
      {
        'id': '$src-cblsub',
        'type': 'line',
        'source': src,
        'source-layer': 'CBLSUB',
        'paint': {
          'line-color': 'rgba(197,69,195,0.7)',
          'line-width': 1,
          'line-dasharray': [4, 4]
        },
      },
      // CBLOHD
      {
        'id': '$src-cblohd',
        'type': 'line',
        'source': src,
        'source-layer': 'CBLOHD',
        'paint': {
          'line-color': 'rgba(197,69,195,0.7)',
          'line-width': 1,
          'line-dasharray': [4, 4]
        },
      },
      // PIPSOL
      {
        'id': '$src-pipsol',
        'type': 'line',
        'source': src,
        'source-layer': 'PIPSOL',
        'paint': {
          'line-color': 'rgba(197,69,195,0.5)',
          'line-width': 1,
          'line-dasharray': [6, 2]
        },
      },
      // BRIDGE
      {
        'id': '$src-bridge',
        'type': 'line',
        'source': src,
        'source-layer': 'BRIDGE',
        'paint': {'line-color': 'rgba(82,90,92,1)', 'line-width': 3},
      },
      // RDOCAL
      {
        'id': '$src-rdocal',
        'type': 'line',
        'source': src,
        'source-layer': 'RDOCAL',
        'paint': {
          'line-color': 'rgba(197,69,195,1)',
          'line-width': 1,
          'line-dasharray': [4, 2]
        },
      },
    ];

// =============================================================================
// S-57 Symbol layers
// =============================================================================

List<Map<String, dynamic>> _s57SymbolLayers(String src) => [
      // SOUNDG
      {
        'id': '$src-soundg',
        'type': 'symbol',
        'source': src,
        'source-layer': 'SOUNDG',
        'minzoom': 12,
        'layout': {
          'text-field': ['to-string', ['get', 'DEPTH']],
          'text-size': 10,
          'text-allow-overlap': true,
        },
        'paint': {
          'text-color': 'rgba(125,137,140,1)',
        },
      },
      // OBSTRN point
      {
        'id': '$src-obstrn-pt',
        'type': 'circle',
        'source': src,
        'source-layer': 'OBSTRN',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(7,7,7,1)',
          'circle-stroke-color': 'rgba(255,255,255,1)',
          'circle-stroke-width': 1,
        },
      },
      // UWTROC
      {
        'id': '$src-uwtroc',
        'type': 'circle',
        'source': src,
        'source-layer': 'UWTROC',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(7,7,7,1)',
          'circle-stroke-color': 'rgba(241,84,105,1)',
          'circle-stroke-width': 2,
        },
      },
      // WRECKS
      {
        'id': '$src-wrecks',
        'type': 'circle',
        'source': src,
        'source-layer': 'WRECKS',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(7,7,7,1)',
          'circle-stroke-color': 'rgba(241,84,105,1)',
          'circle-stroke-width': 2,
        },
      },
      // LIGHTS
      {
        'id': '$src-lights',
        'type': 'circle',
        'source': src,
        'source-layer': 'LIGHTS',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(244,218,72,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BOYLAT
      {
        'id': '$src-boylat',
        'type': 'circle',
        'source': src,
        'source-layer': 'BOYLAT',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(104,228,86,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BOYCAR
      {
        'id': '$src-boycar',
        'type': 'circle',
        'source': src,
        'source-layer': 'BOYCAR',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(7,7,7,1)',
          'circle-stroke-color': 'rgba(244,218,72,1)',
          'circle-stroke-width': 2,
        },
      },
      // BOYSAW
      {
        'id': '$src-boysaw',
        'type': 'circle',
        'source': src,
        'source-layer': 'BOYSAW',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(241,84,105,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BOYSPP
      {
        'id': '$src-boyspp',
        'type': 'circle',
        'source': src,
        'source-layer': 'BOYSPP',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(244,218,72,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BOYISD
      {
        'id': '$src-boyisd',
        'type': 'circle',
        'source': src,
        'source-layer': 'BOYISD',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(7,7,7,1)',
          'circle-stroke-color': 'rgba(241,84,105,1)',
          'circle-stroke-width': 2,
        },
      },
      // BCNLAT
      {
        'id': '$src-bcnlat',
        'type': 'circle',
        'source': src,
        'source-layer': 'BCNLAT',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(104,228,86,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BCNCAR
      {
        'id': '$src-bcncar',
        'type': 'circle',
        'source': src,
        'source-layer': 'BCNCAR',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(7,7,7,1)',
          'circle-stroke-color': 'rgba(244,218,72,1)',
          'circle-stroke-width': 2,
        },
      },
      // BCNSPP
      {
        'id': '$src-bcnspp',
        'type': 'circle',
        'source': src,
        'source-layer': 'BCNSPP',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(244,218,72,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BCNSAW
      {
        'id': '$src-bcnsaw',
        'type': 'circle',
        'source': src,
        'source-layer': 'BCNSAW',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(241,84,105,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // PILBOP
      {
        'id': '$src-pilbop',
        'type': 'circle',
        'source': src,
        'source-layer': 'PILBOP',
        'paint': {
          'circle-radius': 5,
          'circle-color': 'rgba(197,69,195,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // LNDMRK
      {
        'id': '$src-lndmrk',
        'type': 'circle',
        'source': src,
        'source-layer': 'LNDMRK',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(139,102,31,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // FOGSIG
      {
        'id': '$src-fogsig',
        'type': 'circle',
        'source': src,
        'source-layer': 'FOGSIG',
        'paint': {
          'circle-radius': 4,
          'circle-color': 'rgba(197,69,195,1)',
          'circle-stroke-color': 'rgba(7,7,7,1)',
          'circle-stroke-width': 1,
        },
      },
      // BERTHS label
      {
        'id': '$src-berths',
        'type': 'symbol',
        'source': src,
        'source-layer': 'BERTHS',
        'layout': {
          'text-field': ['get', 'OBJNAM'],
          'text-size': 10,
        },
        'paint': {'text-color': 'rgba(197,69,195,1)'},
      },
      // SEAARE label
      {
        'id': '$src-seaare-lbl',
        'type': 'symbol',
        'source': src,
        'source-layer': 'SEAARE',
        'minzoom': 14,
        'layout': {
          'text-field': ['get', 'OBJNAM'],
          'text-size': 11,
          'text-offset': [0, 1.2],
        },
        'paint': {
          'text-color': 'rgba(7,7,7,0.8)',
          'text-halo-color': 'rgba(255,255,255,0.8)',
          'text-halo-width': 1,
        },
      },
      // ACHARE label
      {
        'id': '$src-achare-lbl',
        'type': 'symbol',
        'source': src,
        'source-layer': 'ACHARE',
        'minzoom': 13,
        'layout': {
          'text-field': ['get', 'OBJNAM'],
          'text-size': 11,
          'text-offset': [0, 1.2],
        },
        'paint': {
          'text-color': 'rgba(7,7,7,0.8)',
          'text-halo-color': 'rgba(255,255,255,0.8)',
          'text-halo-width': 1,
        },
      },
      // RESARE label
      {
        'id': '$src-resare-lbl',
        'type': 'symbol',
        'source': src,
        'source-layer': 'RESARE',
        'minzoom': 13,
        'layout': {
          'text-field': ['get', 'OBJNAM'],
          'text-size': 11,
          'text-offset': [0, 1.2],
        },
        'paint': {
          'text-color': 'rgba(7,7,7,0.8)',
          'text-halo-color': 'rgba(255,255,255,0.8)',
          'text-halo-width': 1,
        },
      },
    ];
