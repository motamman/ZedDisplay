// Single source of truth for chart plotter base map configuration.
// Used by: chart_plotter_tool.dart, chart_plotter_configurator.dart,
// and chart_webview.dart (JS side via injection).

const baseMapNames = <String, String>{
  'carto_voyager': 'CartoDB Voyager',
  'carto_dark': 'CartoDB Dark Matter',
  'carto_light': 'CartoDB Positron',
  'esri_ocean': 'Esri Ocean',
  'esri_satellite': 'Esri Satellite',
};

const baseMapDescriptions = <String, String>{
  'carto_voyager': 'Street map with muted colors, good under S-57 charts',
  'carto_dark': 'Dark street map, best contrast for night use',
  'carto_light': 'Light minimal map, clean background for chart overlays',
  'esri_ocean': 'Ocean bathymetry with seafloor shading and labels',
  'esri_satellite': 'Aerial/satellite imagery',
};

const baseMapUrls = <String, String>{
  'carto_voyager': 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
  'carto_dark': 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
  'carto_light': 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
  'esri_ocean': 'https://server.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Base/MapServer/tile/{z}/{y}/{x}',
  'esri_satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
};
