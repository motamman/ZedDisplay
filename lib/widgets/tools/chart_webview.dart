import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// OpenLayers WebView for chart rendering + navigation overlays.
///
/// Chart rendering: S-57 vector tiles via Freeboard-SK's rendering pipeline.
/// Navigation overlays: own vessel, heading/COG lines, view modes.
/// Future: AIS targets, active route, multiple chart sources.
class ChartWebView extends StatefulWidget {
  final String baseUrl;
  final String? authToken;
  final void Function(WebViewController controller)? onReady;
  final void Function(bool autoFollow, {bool? autoZoom})? onAutoFollowChanged;
  final void Function(String vesselId)? onAISVesselClick;

  const ChartWebView({
    super.key,
    required this.baseUrl,
    this.authToken,
    this.onReady,
    this.onAutoFollowChanged,
    this.onAISVesselClick,
  });

  @override
  State<ChartWebView> createState() => _ChartWebViewState();
}

class _ChartWebViewState extends State<ChartWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    // Load all pre-extracted assets
    final spriteJson = await rootBundle.loadString('assets/charts/sprite.json');
    final spriteBytes = await rootBundle.load('assets/charts/sprite.png');
    final spritePngB64 = base64Encode(spriteBytes.buffer.asUint8List());
    final lookupsJson =
        await rootBundle.loadString('assets/charts/s57_lookups.json');
    final colorsJson =
        await rootBundle.loadString('assets/charts/s57_colors.json');

    final tileUrl =
        '${widget.baseUrl}/plugins/signalk-charts-provider-simple/01CGD_ENCs/{z}/{x}/{y}';
    final authToken = widget.authToken ?? '';

    final html = _buildHtml(
      tileUrl: tileUrl,
      authToken: authToken,
      spriteJson: spriteJson,
      spritePngB64: spritePngB64,
      lookupsJson: lookupsJson,
      colorsJson: colorsJson,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FeatureClick', onMessageReceived: _onFeatureClick)
      ..addJavaScriptChannel('MapReady', onMessageReceived: _onMapReady)
      ..addJavaScriptChannel('ViewState', onMessageReceived: _onViewState)
      ..addJavaScriptChannel('AISVesselClick', onMessageReceived: _onAISVesselClick)
      ..loadHtmlString(html);

    if (mounted) setState(() => _loading = false);
  }

  void _onMapReady(JavaScriptMessage message) {
    widget.onReady?.call(_controller);
  }

  void _onViewState(JavaScriptMessage message) {
    final data = jsonDecode(message.message) as Map<String, dynamic>;
    if (data.containsKey('autoFollow')) {
      final autoZoom = data['autoZoom'] as bool?;
      widget.onAutoFollowChanged?.call(data['autoFollow'] as bool, autoZoom: autoZoom);
    }
  }

  void _onAISVesselClick(JavaScriptMessage message) {
    widget.onAISVesselClick?.call(message.message);
  }

  void _onFeatureClick(JavaScriptMessage message) {
    final data = jsonDecode(message.message) as Map<String, dynamic>;
    final layer = data['layer'] as String? ?? 'Unknown';
    final props = data['properties'] as Map<String, dynamic>? ?? {};
    final lngLat = data['lngLat'] as List?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeaturePopover(
        layerCode: layer,
        properties: props,
        lngLat: lngLat,
      ),
    );
  }

  String _buildHtml({
    required String tileUrl,
    required String authToken,
    required String spriteJson,
    required String spritePngB64,
    required String lookupsJson,
    required String colorsJson,
  }) {
    // The HTML contains the complete S-57 rendering engine ported from Freeboard.
    // OpenLayers replaces MapLibre GL JS. The S57Service and S57Style classes
    // are direct ports of Freeboard's TypeScript, using pre-parsed JSON instead
    // of runtime XML parsing.
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <script src="https://cdn.jsdelivr.net/npm/ol@10.7.0/dist/ol.js"></script>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@10.7.0/ol.css">
  <style>
    body { margin:0; overflow:hidden; }
    #map { width:100%; height:100vh; }
  </style>
</head>
<body>
<div id="map"></div>
<script>
// =========================================================================
// Pre-loaded data from Flutter assets
// =========================================================================
const SPRITE_META = $spriteJson;
const SPRITE_PNG_B64 = '$spritePngB64';
const LOOKUP_DATA = $lookupsJson;
const COLOR_TABLE = $colorsJson;
const TILE_URL = '$tileUrl';
const AUTH_TOKEN = '$authToken';

// =========================================================================
// Land extent cache — top-level so S57Style.getStyle can access it
// =========================================================================
const _landExtents = [];
const _landExtentKeys = new Set();

// =========================================================================
// S57Service — ported from Freeboard s57.service.ts
// =========================================================================
class S57Service {
  constructor() {
    this.chartSymbols = new Map();
    this.lookups = LOOKUP_DATA.lookups;
    this.lookupStartIndex = new Map(Object.entries(LOOKUP_DATA.lookupStartIndex).map(([k,v]) => [k, v]));
    this.colors = COLOR_TABLE;
    this.styles = {};
    this.chartSymbolsImage = null;
    this.options = {
      shallowDepth: 2, safetyDepth: 3, deepDepth: 6,
      graphicsStyle: 'Paper', boundaries: 'Plain',
      colors: 4, colorTable: 0,
      otherLayers: ['SOUNDG','OBSTRN','UWTROC','WRECKS','DEPCNT'],
      depthUnit: 'm',
    };
    this.attMatch = /([A-Za-z0-9]{6})([0-9,?]*)/;

    // Load sprite metadata
    for (const [name, meta] of Object.entries(SPRITE_META)) {
      this.chartSymbols.set(name, {
        image: null,
        width: meta.width, height: meta.height,
        pivotX: meta.pivotX || 0, pivotY: meta.pivotY || 0,
        originX: meta.originX || 0, originY: meta.originY || 0,
        locationX: meta.x, locationY: meta.y,
      });
    }
  }

  async loadSpriteSheet() {
    const img = new Image();
    img.src = 'data:image/png;base64,' + SPRITE_PNG_B64;
    await img.decode();
    this.chartSymbolsImage = img;

    // Pre-extract ALL sprite images synchronously so they're ready
    // before OpenLayers calls getSymbol() during rendering.
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    let count = 0;
    for (const [name, symbol] of this.chartSymbols) {
      canvas.width = symbol.width;
      canvas.height = symbol.height;
      ctx.clearRect(0, 0, symbol.width, symbol.height);
      ctx.drawImage(img, symbol.locationX, symbol.locationY,
        symbol.width, symbol.height, 0, 0, symbol.width, symbol.height);
      symbol.image = new Image(symbol.width, symbol.height);
      symbol.image.src = canvas.toDataURL();
      count++;
    }
    console.log('Pre-extracted ' + count + ' sprite images');
  }

  getColor(name) {
    return this.colors[name];
  }

  getStyle(key) { return this.styles[key]; }
  setStyle(key, style) { this.styles[key] = style; }

  getLookup(index) { return this.lookups[index]; }

  getSymbol(key) {
    const icon = this.chartSymbols.get(key);
    if (icon && this.chartSymbolsImage) {
      if (!icon.image) {
        icon.image = new Image(icon.width, icon.height);
        const canvas = document.createElement('canvas');
        canvas.width = icon.width;
        canvas.height = icon.height;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(this.chartSymbolsImage,
          icon.locationX, icon.locationY, icon.width, icon.height,
          0, 0, icon.width, icon.height);
        icon.image.src = canvas.toDataURL();
      }
      return icon;
    }
    return null;
  }

  propertyCompare(a, b) {
    const t = typeof a;
    if (t === 'number') return a - parseInt(b);
    if (t === 'string') return a.localeCompare(b);
    return -1;
  }

  selectLookup(feature) {
    const props = feature.getProperties();
    const properties = {};
    Object.keys(props).forEach(k => { properties[k.toUpperCase()] = props[k]; });

    const geometry = feature.getGeometry();
    const name = properties['LAYER'];
    if (!name) return -1;
    const geomType = geometry.getType();

    let lookupTable = 1; // PAPER_CHART
    let type = 0; // POINT
    if (geomType === 'Polygon' || geomType === 'MultiPolygon') {
      type = 2; // AREA
    } else if (geomType === 'LineString' || geomType === 'MultiLineString') {
      type = 1; // LINES
    }

    if (type === 0) {
      lookupTable = this.options.graphicsStyle === 'Paper' ? 1 : 0;
    } else if (type === 1) {
      lookupTable = 2; // LINES
    } else {
      lookupTable = this.options.boundaries === 'Plain' ? 3 : 4;
    }

    let best = -1;
    const startIndex = this.lookupStartIndex.get(
      lookupTable + ',' + name.toUpperCase() + ',' + type
    );

    if (startIndex !== undefined) {
      let idx = startIndex;
      let lup = this.lookups[idx];
      let lmatch = 0;

      while (lup &&
        lup.name.toUpperCase() === name.toUpperCase() &&
        lup.geometryType === type &&
        lup.lookupTable === lookupTable
      ) {
        let nmatch = 0;
        const attrKeys = Object.keys(lup.attributes);
        attrKeys.forEach(k => {
          const v = lup.attributes[k];
          const parts = this.attMatch.exec(v);
          if (!parts) return;
          const key = parts[1].toUpperCase();
          const value = parts[2].toUpperCase();
          if (value === ' ') { nmatch++; return; }
          if (value === '?') return;
          if (this.propertyCompare(properties[key], value) === 0) {
            nmatch++;
          }
        });

        if (attrKeys.length === nmatch && nmatch > lmatch) {
          best = idx;
          lmatch = nmatch;
        }
        idx++;
        lup = this.lookups[idx];
      }

      if (best === -1) {
        idx = startIndex;
        lup = this.lookups[idx];
        while (lup &&
          lup.name.toUpperCase() === name.toUpperCase() &&
          lup.geometryType === type &&
          lup.lookupTable === lookupTable
        ) {
          if (Object.keys(lup.attributes).length === 0) {
            best = idx;
            break;
          }
          idx++;
          lup = this.lookups[idx];
        }
      }
    }
    return best;
  }
}

// =========================================================================
// S57Style — ported from Freeboard s57Style.ts
// =========================================================================
const LOOKUPINDEXKEY = '_lupIndex';

class S57Style {
  constructor(s57Service) {
    this.s57Service = s57Service;
    this.selectedSafeContour = 1000;
    this.currentResolution = 0;
    this.instructionMatch = /([A-Z][A-Z])\\((.*)\\)/;
  }

  getSymbolStyle(symbolName) {
    const symbol = this.s57Service.getSymbol(symbolName);
    if (symbol) {
      return new ol.style.Style({
        image: new ol.style.Icon({
          img: symbol.image,
          width: symbol.width,
          height: symbol.height,
          anchor: [symbol.pivotX, symbol.pivotY],
          anchorXUnits: 'pixels',
          anchorYUnits: 'pixels',
          declutterMode: 'none',
        }),
      });
    }
    return null;
  }

  getTextStyle(params) {
    let textBaseline = 'middle';
    let offsetY = 0;
    if (params[1] === '3') { textBaseline = 'top'; offsetY = 15; }
    else if (params[1] === '1') { textBaseline = 'bottom'; offsetY = -15; }
    let textAlign = 'left';
    let offsetX = 15;
    if (params[0] === '2') { textAlign = 'right'; offsetX = -15; }
    else if (params[0] === '1') { textAlign = 'center'; offsetX = 0; }

    const style = new ol.style.Style({
      text: new ol.style.Text({
        textAlign, textBaseline, scale: 1.5,
        offsetX, offsetY,
      }),
    });
    style.setZIndex(99);
    return style;
  }

  getTextStyleTXStyle(props, params) {
    const parts = params.split(',');
    return this.getTextStyle(parts.slice(1));
  }

  getTextStyleTXText(props, params) {
    const parts = params.split(',');
    return props[parts[0]];
  }

  stripQuotes(text) {
    return text.substring(1, text.length - 1);
  }

  getTextStyleTEText(props, params) {
    const parts = params.split(',');
    const text = props[this.stripQuotes(parts[1])];
    const format = this.stripQuotes(parts[0]);
    if (!text || !format) return null;
    return format.replace(/%[0-9]*.?[0-9]*l?[sfd]/, text);
  }

  getTextStyleTEStyle(props, params) {
    const parts = params.split(',');
    return this.getTextStyle(parts.slice(2));
  }

  getAreaStyle(colorName) {
    const color = this.s57Service.getColor(colorName);
    if (color) return new ol.style.Style({ fill: new ol.style.Fill({ color }) });
    return null;
  }

  getLineStyle(params) {
    const parts = params.split(',');
    const color = this.s57Service.getColor(parts[2]);
    const width = parseInt(parts[1]);
    let lineDash = null;
    if (parts[0] === 'DASH') lineDash = [4, 4];
    else if (parts[0] === 'DOTT') lineDash = [2, 4];
    return new ol.style.Style({
      stroke: new ol.style.Stroke({ color, width, lineDash }),
    });
  }

  // --- CS() conditional symbols (ported verbatim from s57Style.ts) ---

  GetCSLIGHTS05(feature) {
    let rs = null;
    const p = feature.getProperties();
    if (p.COLOUR) {
      const vals = String(p.COLOUR).split(',');
      if (vals.length === 1) {
        if (vals[0]==='3') rs='SY(LIGHTS11)';
        else if (vals[0]==='4') rs='SY(LIGHTS12)';
        else if (vals[0]==='1'||vals[0]==='6'||vals[0]==='13') rs='SY(LIGHTS13)';
      } else if (vals.length === 2) {
        if (vals.includes('1')&&vals.includes('3')) rs='SY(LIGHTS11)';
        else if (vals.includes('1')&&vals.includes('4')) rs='SY(LIGHTS12)';
      }
    }
    return rs ? [rs] : [];
  }

  GetCSTOPMAR01(feature) {
    const p = feature.getProperties();
    if (!p.TOPSHP) return ['SY(QUESMRK1)'];
    const layer = p.layer || '';
    const floating = layer==='LITFLT'||layer==='LITVES'||layer.startsWith('BOY');
    const topshp = typeof p.TOPSHP === 'number' ? p.TOPSHP : parseInt(p.TOPSHP);
    const fMap = {1:'TOPMAR02',2:'TOPMAR04',3:'TOPMAR10',4:'TOPMAR12',5:'TOPMAR13',
      6:'TOPMAR14',7:'TOPMAR65',8:'TOPMAR17',9:'TOPMAR16',10:'TOPMAR08',
      11:'TOPMAR07',12:'TOPMAR14',13:'TOPMAR05',14:'TOPMAR06',17:'TMARDEF2',
      18:'TOPMAR10',19:'TOPMAR13',20:'TOPMAR14',21:'TOPMAR13',22:'TOPMAR14',
      23:'TOPMAR14',24:'TOPMAR02',25:'TOPMAR04',26:'TOPMAR10',27:'TOPMAR17',
      28:'TOPMAR18',29:'TOPMAR02',30:'TOPMAR17',31:'TOPMAR14',32:'TOPMAR10',33:'TMARDEF2'};
    const nMap = {1:'TOPMAR22',2:'TOPMAR24',3:'TOPMAR30',4:'TOPMAR32',5:'TOPMAR33',
      6:'TOPMAR34',7:'TOPMAR85',8:'TOPMAR86',9:'TOPMAR36',10:'TOPMAR28',
      11:'TOPMAR27',12:'TOPMAR14',13:'TOPMAR25',14:'TOPMAR26',15:'TOPMAR88',
      16:'TOPMAR87',17:'TMARDEF1',18:'TOPMAR30',19:'TOPMAR33',20:'TOPMAR34',
      21:'TOPMAR33',22:'TOPMAR34',23:'TOPMAR34',24:'TOPMAR22',25:'TOPMAR24',
      26:'TOPMAR30',27:'TOPMAR86',28:'TOPMAR89',29:'TOPMAR22',30:'TOPMAR86',
      31:'TOPMAR14',32:'TOPMAR30',33:'TMARDEF1'};
    const sym = (floating ? fMap : nMap)[topshp] || (floating ? 'TMARDEF2' : 'TMARDEF1');
    return ['SY(' + sym + ')'];
  }

  GetSeabed01(drval1, drval2) {
    let r = ['AC(DEPIT)'];
    if (drval1 >= 0 && drval2 > 0) r = ['AC(DEPVS)'];
    const o = this.s57Service.options;
    if (o.colors === 2) {
      if (drval1 >= o.safetyDepth && drval2 > o.safetyDepth) r = ['AC(DEPDW)'];
    } else {
      if (drval1 >= o.shallowDepth && drval2 > o.shallowDepth) r = ['AC(DEPMS)'];
      if (drval1 >= o.safetyDepth && drval2 > o.safetyDepth) r = ['AC(DEPMD)'];
      if (drval1 >= o.deepDepth && drval2 > o.deepDepth) r = ['AC(DEPDW)'];
    }
    return r;
  }

  getCSDEPARE01(feature) {
    const p = feature.getProperties();
    let drval1 = parseFloat(p.DRVAL1); if (isNaN(drval1)) drval1 = -1;
    let drval2 = parseFloat(p.DRVAL2); if (isNaN(drval2)) drval2 = drval1 + 0.01;
    let r = this.GetSeabed01(drval1, drval2);
    if (parseInt(p.OBJL) === 46) { // DRGARE
      r.push('AP(DRGARE01)'); r.push('LS(DASH,1,CHGRF)');
    }
    return r;
  }

  GetCSDEPCNT02(feature) {
    const p = feature.getProperties();
    const r = [];
    let depth = -1;
    if (parseInt(p.OBJL) === 42 && feature.getGeometry().getType() === 'LineString') {
      depth = parseFloat(p.DRVAL1) || 0;
    } else {
      depth = parseFloat(p.VALDCO) || -1;
    }
    if (depth < this.s57Service.options.safetyDepth) {
      r.push('LS(SOLD,1,DEPCN)'); return r;
    }
    const quapos = parseFloat(p.QUAPOS) || 0;
    if (p.QUAPOS && quapos > 2 && quapos < 10) {
      r.push(depth === this.selectedSafeContour ? 'LS(DASH,2,DEPSC)' : 'LS(DASH,1,DEPCN)');
    } else {
      r.push(depth === this.selectedSafeContour ? 'LS(SOLD,2,DEPSC)' : 'LS(SOLD,1,DEPCN)');
    }
    return r;
  }

  GetCSOBSTRN04(feature) {
    const r = [];
    const p = feature.getProperties();
    const gt = feature.getGeometry().getType();
    const layer = p.layer || '';
    const valsou = p.VALSOU !== undefined ? parseFloat(p.VALSOU) : NaN;
    const watlev = p.WATLEV ? parseInt(p.WATLEV) : 0;
    const safety = this.s57Service.options.safetyDepth;

    if (gt === 'Point') {
      if (!isNaN(valsou)) {
        if (valsou <= 0) r.push(layer==='UWTROC'?'SY(UWTROC04)':'SY(OBSTRN11)');
        else if (valsou <= safety) r.push('SY(DANGER51)');
        else r.push(layer==='UWTROC'?'SY(UWTROC03)':'SY(OBSTRN01)');
      } else {
        if (watlev===1||watlev===2) r.push(layer==='UWTROC'?'SY(UWTROC04)':'SY(OBSTRN11)');
        else if (watlev===4||watlev===5) r.push(layer==='UWTROC'?'SY(UWTROC03)':'SY(OBSTRN03)');
        else r.push(layer==='UWTROC'?'SY(UWTROC03)':'SY(OBSTRN01)');
      }
    } else if (gt === 'LineString') {
      r.push(!isNaN(valsou)&&valsou<=safety ? 'LS(DOTT,2,CHBLK)' : 'LS(DASH,2,CHBLK)');
    } else {
      if (watlev===1||watlev===2) { r.push('AC(CHBRN)'); r.push('LS(SOLD,2,CSTLN)'); }
      else if (watlev===4) { r.push('AC(DEPIT)'); r.push('LS(DASH,2,CSTLN)'); }
      else { r.push('AC(DEPVS)'); r.push('LS(DOTT,2,CHBLK)'); }
    }
    return r;
  }

  GetCSWRECKS02(feature) {
    const r = [];
    const p = feature.getProperties();
    const gt = feature.getGeometry().getType();
    const valsou = p.VALSOU !== undefined ? parseFloat(p.VALSOU) : NaN;
    const watlev = p.WATLEV ? parseInt(p.WATLEV) : 0;
    const catwrk = p.CATWRK ? parseInt(p.CATWRK) : 0;
    const safety = this.s57Service.options.safetyDepth;

    if (gt === 'Point') {
      if (!isNaN(valsou)) {
        if (valsou <= 0) r.push('SY(WRECKS01)');
        else if (valsou <= safety) r.push('SY(DANGER51)');
        else r.push('SY(WRECKS05)');
      } else {
        if (catwrk===1) r.push('SY(WRECKS05)');
        else if (catwrk===2) r.push('SY(WRECKS01)');
        else if (watlev===1||watlev===2||watlev===3) r.push('SY(WRECKS01)');
        else if (watlev===4||watlev===5) r.push('SY(WRECKS05)');
        else r.push('SY(WRECKS01)');
      }
    } else {
      if (watlev===1||watlev===2) { r.push('AC(CHBRN)'); r.push('LS(SOLD,2,CSTLN)'); }
      else if (watlev===4) { r.push('AC(DEPIT)'); r.push('LS(DASH,2,CSTLN)'); }
      else { r.push('AC(DEPVS)'); r.push('LS(DOTT,2,CHBLK)'); }
    }
    return r;
  }

  GetCSSOUNDG02(feature) {
    const r = [];
    const p = feature.getProperties();
    let depth = parseFloat(p.DEPTH);
    if (isNaN(depth)) depth = parseFloat(p.VALSOU);
    if (isNaN(depth)) return r;
    if (this.s57Service.options.depthUnit === 'ft') depth *= 3.28084;
    const sign = depth < 0 ? '-' : '';
    const abs = Math.abs(depth);
    let str;
    if (this.s57Service.options.depthUnit === 'ft') {
      str = sign + Math.round(abs);
    } else {
      const showTenths = this.currentResolution < 5;
      if (showTenths) {
        const rounded = Math.round(abs * 10) / 10;
        str = sign + (rounded % 1 === 0 ? rounded.toFixed(0) : rounded.toFixed(1));
      } else {
        str = sign + Math.round(abs);
      }
    }
    p._SOUNDG_WHOLE = str;
    r.push('TX(_SOUNDG_WHOLE,1,2,2)');
    return r;
  }

  GetCSRESTRN01(feature) {
    const r = [];
    const p = feature.getProperties();
    if (!p.RESTRN) return r;
    const vals = String(p.RESTRN).split(',').map(v => parseInt(v));
    if (vals.includes(1)||vals.includes(2)) r.push('SY(ACHRES51)');
    if (vals.includes(3)||vals.includes(4)) r.push('SY(FSHRES51)');
    if (vals.includes(5)||vals.includes(6)) r.push('SY(FSHRES71)');
    if (vals.includes(7)||vals.includes(8)||vals.includes(14)) r.push('SY(ENTRES51)');
    if (vals.includes(9)||vals.includes(10)) r.push('SY(DRGARE51)');
    if (vals.includes(11)||vals.includes(12)) r.push('SY(DIVPRO51)');
    if (vals.includes(13)) r.push('SY(ENTRES61)');
    if (vals.includes(27)) r.push('SY(ENTRES71)');
    if (r.length === 0) r.push('SY(ENTRES61)');
    return r;
  }

  GetCSRESARE02(feature) {
    return ['LS(DASH,2,CHMGD)', ...this.GetCSRESTRN01(feature)];
  }

  GetCSSLCONS03(feature) {
    const r = [];
    const p = feature.getProperties();
    const gt = feature.getGeometry().getType();
    const quapos = parseFloat(p.QUAPOS) || 0;
    const bquapos = !!p.QUAPOS;

    if (gt === 'Point') {
      if (bquapos && quapos >= 2 && quapos < 10) r.push('SY(LOWACC01)');
    } else {
      if (gt === 'Polygon') r.push('AP(CROSSX01)');
      if (bquapos && quapos >= 2 && quapos < 10) {
        r.push('LC(LOWACC01)');
      } else {
        const condtn = parseInt(p.CONDTN) || 0;
        if (p.CONDTN && (condtn === 1 || condtn === 2)) {
          r.push('LS(DASH,1,CSTLN)');
        } else {
          const catslc = parseInt(p.CATSLC) || 0;
          if (p.CATSLC && (catslc===6||catslc===15||catslc===16)) {
            r.push('LS(SOLD,4,CSTLN)');
          } else {
            const watlev = parseInt(p.WATLEV) || 0;
            if (p.WATLEV && watlev === 2) r.push('LS(SOLD,2,CSTLN)');
            else if (p.WATLEV && (watlev===3||watlev===4)) r.push('LS(DASH,2,CSTLN)');
            else r.push('LS(SOLD,2,CSTLN)');
          }
        }
      }
    }
    return r;
  }

  evalCS(feature, instruction) {
    const parts = this.instructionMatch.exec(instruction);
    if (!parts || parts.length < 2) return [];
    switch (parts[2]) {
      case 'LIGHTS05': return this.GetCSLIGHTS05(feature);
      case 'DEPCNT02': return this.GetCSDEPCNT02(feature);
      case 'DEPARE01': case 'DEPARE02': return this.getCSDEPARE01(feature);
      case 'TOPMAR01': return this.GetCSTOPMAR01(feature);
      case 'SLCONS03': return this.GetCSSLCONS03(feature);
      case 'SOUNDG02': return this.GetCSSOUNDG02(feature);
      case 'OBSTRN04': return this.GetCSOBSTRN04(feature);
      case 'WRECKS02': return this.GetCSWRECKS02(feature);
      case 'RESTRN01': return this.GetCSRESTRN01(feature);
      case 'RESARE01': case 'RESARE02': return this.GetCSRESARE02(feature);
      default: return [];
    }
  }

  // Main style function — called per feature
  getStylesFromRules(lup, feature) {
    const styles = [];
    if (!lup) return styles;
    const properties = feature.getProperties();
    const instructions = lup.instruction.split(';');

    // Pre-process CS() conditionals
    for (let i = 0; i < instructions.length; i++) {
      if (instructions[i].startsWith('CS')) {
        const conditionals = this.evalCS(feature, instructions[i]);
        instructions.splice(i, 1, ...conditionals);
      }
    }

    instructions.forEach(instruction => {
      const parts = this.instructionMatch.exec(instruction);
      if (!parts || parts.length < 2) return;
      let style = null;
      const cacheKey = parts[1] + '_' + parts[2];
      const isText = parts[1] === 'TX' || parts[1] === 'TE';

      if (!isText) style = this.s57Service.getStyle(cacheKey);

      if (!style) {
        switch (parts[1]) {
          case 'SY': style = this.getSymbolStyle(parts[2]); break;
          case 'AC': style = this.getAreaStyle(parts[2]); break;
          case 'TX': style = this.getTextStyleTXStyle(properties, parts[2]); break;
          case 'TE': style = this.getTextStyleTEStyle(properties, parts[2]); break;
          case 'LS': style = this.getLineStyle(parts[2]); break;
        }
        if (!isText && style) this.s57Service.setStyle(cacheKey, style);
      }

      if (style) {
        if (parts[1] === 'TE') {
          const t = this.getTextStyleTEText(properties, parts[2]);
          if (t) style.getText().setText(t);
        }
        if (parts[1] === 'TX') {
          const t = this.getTextStyleTXText(properties, parts[2]);
          if (t) style.getText().setText(String(t));
        }
        styles.push(style);
      }
    });
    return styles;
  }

  // Layer ordering (s57Style.ts:1049-1069)
  layerOrder(feature) {
    const layer = feature.getProperties().layer;
    switch (layer) {
      case 'SEAARE': return 2;
      case 'DEPARE': return 3;
      case 'DEPCNT': return 4;
      case 'LNDARE': return 5;
      case 'BUAARE': return 6;
      case 'SOUNDG': return 7;
      default: return 99;
    }
  }

  updateSafeContour(feature) {
    const p = feature.getProperties();
    if (p.DRVAL1) {
      const v = parseFloat(p.DRVAL1);
      if (v >= this.s57Service.options.safetyDepth && v < this.selectedSafeContour)
        this.selectedSafeContour = v;
      return v;
    }
    if (p.VALDCO) {
      const v = parseFloat(p.VALDCO);
      if (v >= this.s57Service.options.safetyDepth && v < this.selectedSafeContour)
        this.selectedSafeContour = v;
      return v;
    }
    return 0;
  }

  // Render order comparator (s57Style.ts:1096-1132)
  renderOrder = (f1, f2) => {
    const l1 = this.layerOrder(f1), l2 = this.layerOrder(f2);
    const o1 = this.updateSafeContour(f1), o2 = this.updateSafeContour(f2);
    let li1 = f1[LOOKUPINDEXKEY], li2 = f2[LOOKUPINDEXKEY];
    if (li1 === undefined) { li1 = this.s57Service.selectLookup(f1); f1[LOOKUPINDEXKEY] = li1; }
    if (li2 === undefined) { li2 = this.s57Service.selectLookup(f2); f2[LOOKUPINDEXKEY] = li2; }
    if (l1 !== l2) return l1 - l2;
    if (li1 >= 0 && li2 >= 0) {
      const c1 = this.s57Service.getLookup(li1).displayPriority;
      const c2 = this.s57Service.getLookup(li2).displayPriority;
      if (c1 !== c2) return c1 - c2;
    }
    if (o1 !== o2) return o1 - o2;
    return 0;
  };

  // Main entry — called by OpenLayers per feature (s57Style.ts:1134-1154)
  getStyle = (feature, resolution) => {
    this.currentResolution = resolution;
    let lupIndex = feature[LOOKUPINDEXKEY];
    if (lupIndex === undefined || lupIndex === null) {
      lupIndex = this.s57Service.selectLookup(feature);
      feature[LOOKUPINDEXKEY] = lupIndex;
    }
    if (lupIndex >= 0) {
      const lup = this.s57Service.getLookup(lupIndex);
      // Cache LNDARE extents for land proximity detection
      if (lup.name === 'LNDARE') {
        const ext = feature.getGeometry().getExtent();
        const key = Math.round(ext[0]/100) + ',' + Math.round(ext[1]/100);
        if (!_landExtentKeys.has(key)) {
          _landExtentKeys.add(key);
          _landExtents.push(ext);
        }
      }
      const cat = lup.displayCategory;
      if (cat === 0 || cat === 1 || cat === 3 ||
          this.s57Service.options.otherLayers.includes(lup.name)) {
        const styles = this.getStylesFromRules(lup, feature);
        return styles;
      }
    }
    return null;
  };
}

// =========================================================================
// Map setup — ported from vectorLayerStyleFactory.ts
// =========================================================================
async function initMap() {
  const s57Service = new S57Service();
  await s57Service.loadSpriteSheet();
  console.log('S57Service ready: ' + s57Service.chartSymbols.size + ' symbols');

  const s57Style = new S57Style(s57Service);

  // Base map — CartoDB Voyager
  const cartoLayer = new ol.layer.Tile({
    source: new ol.source.XYZ({
      url: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
      attributions: '&copy; CARTO &copy; OSM',
    }),
    opacity: 0.6,
  });

  // S-57 vector tile layer
  const s57Layer = new ol.layer.VectorTile({
    declutter: true,
    source: new ol.source.VectorTile({
      url: TILE_URL,
      format: new ol.format.MVT(),
      tileSize: 256,
      minZoom: 9,
      maxZoom: 16,
      tileLoadFunction: (tile, url) => {
        tile.setLoader((extent, resolution, projection) => {
          fetch(url, {
            headers: AUTH_TOKEN ? {'Authorization': 'Bearer ' + AUTH_TOKEN} : {},
          })
          .then(r => r.arrayBuffer())
          .then(data => {
            const format = tile.getFormat();
            const features = format.readFeatures(data, {
              extent, featureProjection: projection,
            });
            tile.setFeatures(features);
          })
          .catch(() => tile.setFeatures([]));
        });
      },
    }),
    style: s57Style.getStyle,
    renderOrder: s57Style.renderOrder,
    preload: 1,
    minZoom: 9,
    maxZoom: 23,
  });

  // Create map
  const map = new ol.Map({
    target: 'map',
    layers: [cartoLayer, s57Layer],
    view: new ol.View({
      center: ol.proj.fromLonLat([-74.01, 40.67]),
      zoom: 14,
    }),
    controls: ol.control.defaults.defaults().extend([
      new ol.control.Zoom(),
    ]),
  });

  // Click handler → Flutter JavaScriptChannel
  // Clickable layers — exact match to Freeboard S57_CLICKABLE_LAYERS
  const CLICKABLE = new Set([
    'LIGHTS','BOYLAT','BOYCAR','BOYISD','BOYSAW','BOYSPP',
    'BCNLAT','BCNCAR','BCNISD','BCNSAW','BCNSPP','TOPMAR',
    'RTPBCN','RDOSTA','RADSTA','FOGSIG','LITFLT','LITVES',
    'OBSTRN','UWTROC','WRECKS',
    'LNDMRK','SLCONS','BRIDGE','OFSPLF','PILBOP',
    'CRANES','GATCON','MORFAC','BERTHS','HRBFAC','SMCFAC',
    'CBLSUB','CBLOHD','PIPSOL','PIPOHD',
    'CGUSTA','RSCSTA','SISTAT','SISTAW',
    'DISMAR','CURENT','FSHFAC','CONVYR',
    'RESARE','ACHARE',
  ]);
  map.on('singleclick', (e) => {
    let aisFeature = null;
    let s57Feature = null;
    map.forEachFeatureAtPixel(e.pixel, (feature) => {
      if (feature.get('isAIS') && !aisFeature) {
        aisFeature = feature;
      }
      const props = feature.getProperties();
      if (props.layer && CLICKABLE.has(props.layer) && !s57Feature) {
        s57Feature = feature;
      }
    });
    // AIS tap takes priority
    if (aisFeature && window.AISVesselClick) {
      AISVesselClick.postMessage(aisFeature.get('vesselId'));
      return;
    }
    if (s57Feature && window.FeatureClick) {
      const props = s57Feature.getProperties();
      const coord = ol.proj.toLonLat(e.coordinate);
      const msg = JSON.stringify({
        layer: props.layer || 'unknown',
        properties: Object.fromEntries(
          Object.entries(props).filter(([k]) => k !== 'geometry' && k !== '_lupIndex')
        ),
        lngLat: [coord[0], coord[1]],
      });
      FeatureClick.postMessage(msg);
    }
  });

  // =========================================================================
  // Shared vessel icon — SVG chevron with stern notch
  // =========================================================================
  const _svgCache = {};
  function _svgDataUrl(key, svgStr) {
    if (!_svgCache[key]) {
      _svgCache[key] = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgStr);
    }
    return _svgCache[key];
  }

  // Moving vessel — pointed chevron with stern notch
  function vesselSvgSrc(fillHex, alpha, strokeCol) {
    const key = 'v_' + fillHex + '_' + alpha + '_' + (strokeCol || 'd');
    const sc = strokeCol || 'rgba(0,0,0,0.6)';
    const fc = hexToRgba(fillHex, alpha);
    return _svgDataUrl(key,
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="24" viewBox="0 0 16 24">' +
      '<path d="M8 1 L2 19 L5.5 16.5 L8 21 L10.5 16.5 L14 19 Z" ' +
      'fill="' + fc + '" stroke="' + sc + '" stroke-width="0.8" stroke-linejoin="round"/>' +
      '</svg>'
    );
  }

  // Moored — circle with blue horizontal band (matches AIS tracker mooring buoy)
  function mooredSvgSrc(fillHex, alpha) {
    const key = 'm_' + fillHex + '_' + alpha;
    const fc = hexToRgba(fillHex, alpha);
    return _svgDataUrl(key,
      '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 100 100">' +
      '<defs><clipPath id="c"><circle cx="50" cy="50" r="45"/></clipPath></defs>' +
      '<circle cx="50" cy="50" r="45" fill="' + fc + '" stroke="#888" stroke-width="1.5"/>' +
      '<rect x="0" y="38" width="100" height="24" fill="#1565C0" clip-path="url(#c)"/>' +
      '<circle cx="50" cy="50" r="45" fill="none" stroke="#666" stroke-width="1"/>' +
      '</svg>'
    );
  }

  // Anchored — anchor symbol
  function anchorSvgSrc(fillHex, alpha) {
    const key = 'a_' + fillHex + '_' + alpha;
    const fc = hexToRgba(fillHex, alpha);
    return _svgDataUrl(key,
      '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24">' +
      '<circle cx="12" cy="5" r="2.5" fill="none" stroke="' + fc + '" stroke-width="1.8"/>' +
      '<line x1="12" y1="7.5" x2="12" y2="21" stroke="' + fc + '" stroke-width="2" stroke-linecap="round"/>' +
      '<line x1="5" y1="14" x2="19" y2="14" stroke="' + fc + '" stroke-width="2" stroke-linecap="round"/>' +
      '<path d="M6 21 C6 17 12 13 12 13 C12 13 18 17 18 21" fill="none" stroke="' + fc + '" stroke-width="1.8" stroke-linecap="round"/>' +
      '</svg>'
    );
  }

  function hexToRgba(hex, a) {
    const r = parseInt(hex.slice(1,3),16);
    const g = parseInt(hex.slice(3,5),16);
    const b = parseInt(hex.slice(5,7),16);
    return 'rgba('+r+','+g+','+b+','+a+')';
  }

  // =========================================================================
  // Navigation overlay layers
  // =========================================================================
  const vesselSource = new ol.source.Vector();
  map.addLayer(new ol.layer.Vector({ source: vesselSource, zIndex: 200 }));

  const vesselFeature = new ol.Feature();
  const headingFeature = new ol.Feature();
  const cogFeature = new ol.Feature();
  vesselSource.addFeatures([vesselFeature, headingFeature, cogFeature]);

  let _autoFollow = true;
  let _autoZoom = true;
  let _viewMode = 'north-up';
  let _lastHeading = 0;
  let _lastPos = null;
  let _programmaticMove = false;
  let _lastResolution = map.getView().getResolution();

  // Disable auto-follow on user drag
  map.on('pointerdrag', () => {
    if (_autoFollow) {
      _autoFollow = false;
      if (window.ViewState) {
        ViewState.postMessage(JSON.stringify({ autoFollow: false, autoZoom: _autoZoom }));
      }
    }
  });

  // Disable auto-zoom on user pinch/scroll zoom
  map.getView().on('change:resolution', () => {
    if (!_programmaticMove && _autoZoom) {
      _autoZoom = false;
      if (window.ViewState) {
        ViewState.postMessage(JSON.stringify({ autoFollow: _autoFollow, autoZoom: false }));
      }
    }
  });

  window.updateVesselPosition = function(lat, lon, headingRad, cogRad, sogMs) {
    const pos = ol.proj.fromLonLat([lon, lat]);
    _lastPos = pos;
    _lastHeading = headingRad || 0;

    // Vessel marker — SVG chevron, white stroke to distinguish from AIS
    vesselFeature.setGeometry(new ol.geom.Point(pos));
    vesselFeature.setStyle(new ol.style.Style({
      image: new ol.style.Icon({
        src: vesselSvgSrc('#2196f3', 0.9, 'rgba(255,255,255,0.9)'),
        rotation: _lastHeading,
        rotateWithView: true,
        anchor: [0.5, 0.5],
        scale: 1.6,
      }),
    }));

    // Heading line (solid blue, ~800m in EPSG:3857)
    if (headingRad != null) {
      const hEnd = [
        pos[0] + Math.sin(headingRad) * 800,
        pos[1] + Math.cos(headingRad) * 800,
      ];
      headingFeature.setGeometry(new ol.geom.LineString([pos, hEnd]));
      headingFeature.setStyle(new ol.style.Style({
        stroke: new ol.style.Stroke({ color: 'rgba(33, 150, 243, 0.7)', width: 2 }),
      }));
    }

    // COG vector (dashed orange, 3-min projection)
    if (cogRad != null && sogMs != null && sogMs > 0.1) {
      const cogLen = Math.max(sogMs * 180, 200);
      const cEnd = [
        pos[0] + Math.sin(cogRad) * cogLen,
        pos[1] + Math.cos(cogRad) * cogLen,
      ];
      cogFeature.setGeometry(new ol.geom.LineString([pos, cEnd]));
      cogFeature.setStyle(new ol.style.Style({
        stroke: new ol.style.Stroke({
          color: 'rgba(255, 152, 0, 0.8)', width: 2, lineDash: [8, 4],
        }),
      }));
    } else {
      cogFeature.setGeometry(null);
    }

    // Auto-follow: center + optional auto-zoom
    if (_autoFollow) {
      const view = map.getView();
      _programmaticMove = true;

      if (_autoZoom && sogMs > 0.3) {
        // Check land proximity first — overrides 30-min zoom if land is near
        let nearestLand = Infinity;
        if (sogMs > 0.5) {
          for (let i = 0; i < _landExtents.length; i++) {
            const ext = _landExtents[i];
            const dx = Math.max(ext[0] - pos[0], 0, pos[0] - ext[2]);
            const dy = Math.max(ext[1] - pos[1], 0, pos[1] - ext[3]);
            const dist = Math.hypot(dx, dy);
            if (dist < nearestLand) nearestLand = dist;
          }
        }

        const landThreshold = sogMs * 900; // 15 min at current speed
        let bufferDist;
        if (nearestLand < landThreshold && nearestLand < Infinity) {
          // Land nearby — zoom tighter to show coastline
          bufferDist = Math.max(nearestLand * 1.3, 300);
        } else {
          // Default 30-min projected area
          bufferDist = Math.max(sogMs * 1800, 500);
        }

        const extent = [pos[0] - bufferDist, pos[1] - bufferDist, pos[0] + bufferDist, pos[1] + bufferDist];
        const fitOpts = { duration: 0, maxZoom: 16, minZoom: 10 };
        if (_viewMode === 'heading-up') fitOpts.rotation = -_lastHeading;
        view.fit(extent, fitOpts);
      } else {
        view.setCenter(pos);
        if (_viewMode === 'heading-up') {
          view.setRotation(-_lastHeading);
        }
      }

      _programmaticMove = false;
    }
  };

  window.setViewMode = function(mode) {
    _viewMode = mode;
    const view = map.getView();
    if (mode === 'north-up') {
      view.animate({ rotation: 0, duration: 300 });
    } else if (mode === 'heading-up' && _lastHeading) {
      view.animate({ rotation: -_lastHeading, duration: 300 });
    }
  };

  window.setAutoFollow = function(enabled) {
    _autoFollow = enabled;
    _autoZoom = enabled; // re-engage auto-zoom with auto-follow
    if (enabled && _lastPos) {
      _programmaticMove = true;
      const opts = { center: _lastPos, duration: 500 };
      if (_viewMode === 'heading-up') opts.rotation = -_lastHeading;
      map.getView().animate(opts, function() { _programmaticMove = false; });
    }
    if (window.ViewState) {
      ViewState.postMessage(JSON.stringify({ autoFollow: enabled, autoZoom: enabled }));
    }
  };

  // =========================================================================
  // AIS targets layer
  // =========================================================================
  const aisSource = new ol.source.Vector();
  map.addLayer(new ol.layer.Vector({ source: aisSource, zIndex: 150 }));

  // Ship type → hex color (matches AIS tracker MarineTraffic convention)
  function shipTypeColor(type, aisClass) {
    if (type == null) return aisClass === 'A' ? '#bdbdbd' : '#9e9e9e';
    if (type === 36) return '#9c27b0'; // sailing
    switch (Math.floor(type / 10)) {
      case 1: case 2: return '#00bcd4'; // fishing, towing
      case 3: return '#ffc107'; // special craft
      case 4: case 5: return '#009688'; // HSC
      case 6: return '#2196f3'; // passenger
      case 7: return '#388e3c'; // cargo
      case 8: return '#795548'; // tanker
      default: return '#9e9e9e';
    }
  }

  function freshnessAlpha(status, lastSeenMs) {
    if (status === 'confirmed') return 1.0;
    if (status === 'unconfirmed') return 0.5;
    if (status === 'lost' || status === 'remove') return 0.2;
    if (!lastSeenMs) return 0.2;
    const age = (Date.now() - lastSeenMs) / 60000;
    if (age < 3) return 1.0;
    if (age < 10) return 0.7;
    return 0.3;
  }

  function isStale(status, lastSeenMs) {
    if (status === 'lost' || status === 'remove') return true;
    if (!lastSeenMs) return true;
    return (Date.now() - lastSeenMs) / 60000 >= 10;
  }

  window.updateAISVessels = function(jsonStr) {
    aisSource.clear();
    const vessels = JSON.parse(jsonStr);
    const features = [];

    for (const v of vessels) {
      const pos = ol.proj.fromLonLat([v.lon, v.lat]);
      const hex = shipTypeColor(v.shipType, v.aisClass);
      const alpha = freshnessAlpha(v.aisStatus, v.lastSeen);
      const stale = isStale(v.aisStatus, v.lastSeen);
      const fill = new ol.style.Fill({ color: hexToRgba(hex, alpha) });
      const stroke = new ol.style.Stroke({ color: '#ffffff', width: 1.5 });
      const rotation = v.hdgRad != null ? v.hdgRad : (v.cogRad != null ? v.cogRad : 0);

      // Icon shape by nav state
      let shape;
      if (v.navState === 'moored') {
        shape = new ol.style.Icon({
          src: mooredSvgSrc(hex, alpha),
          anchor: [0.5, 0.5],
        });
      } else if (v.navState === 'anchored') {
        shape = new ol.style.Icon({
          src: anchorSvgSrc(hex, alpha),
          anchor: [0.5, 0.5],
        });
      } else if (v.sogMs != null && v.sogMs < 0.1) {
        shape = new ol.style.Circle({ radius: 5, fill: fill, stroke: stroke });
      } else {
        shape = new ol.style.Icon({
          src: vesselSvgSrc(hex, alpha),
          rotation: rotation,
          rotateWithView: true,
          anchor: [0.5, 0.5],
          scale: 1.2,
        });
      }

      const styles = [new ol.style.Style({ image: shape })];

      // Stale: red X
      if (stale) {
        styles.push(new ol.style.Style({
          text: new ol.style.Text({
            text: '\\u2715', scale: 1.5,
            fill: new ol.style.Fill({ color: 'rgba(255,0,0,0.8)' }),
          }),
        }));
      }

      // Name label — only at higher zoom (resolution < 20 m/px ≈ zoom 13+)
      if (v.name && map.getView().getResolution() < 20) {
        styles.push(new ol.style.Style({
          text: new ol.style.Text({
            text: v.name, scale: 1.0, offsetY: -18,
            fill: new ol.style.Fill({ color: hexToRgba(hex, Math.max(alpha, 0.8)) }),
            stroke: new ol.style.Stroke({ color: 'rgba(0,0,0,0.5)', width: 1 }),
          }),
        }));
      }

      const mf = new ol.Feature({ geometry: new ol.geom.Point(pos), vesselId: v.id, isAIS: true });
      mf.setStyle(styles);
      features.push(mf);

      // COG projection line + dots
      if (v.projections && v.projections.length > 0 && v.sogMs > 0.1) {
        const coords = [pos];
        for (const p of v.projections) coords.push(ol.proj.fromLonLat([p.lon, p.lat]));
        const lf = new ol.Feature({ geometry: new ol.geom.LineString(coords) });
        lf.setStyle(new ol.style.Style({
          stroke: new ol.style.Stroke({
            color: hexToRgba(hex, alpha * 0.6), width: 2, lineDash: [4, 4],
          }),
        }));
        features.push(lf);

        const dotR = [3, 4, 6, 8];
        v.projections.forEach(function(p, i) {
          const df = new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([p.lon, p.lat])) });
          df.setStyle(new ol.style.Style({
            image: new ol.style.Circle({
              radius: i < dotR.length ? dotR[i] : 4,
              fill: new ol.style.Fill({ color: hexToRgba(hex, alpha * 0.7) }),
              stroke: new ol.style.Stroke({ color: '#000', width: 0.5 }),
            }),
          }));
          features.push(df);
        });
      }
    }
    aisSource.addFeatures(features);
  };

  // =========================================================================
  // Active route layer
  // =========================================================================
  const routeSource = new ol.source.Vector();
  map.addLayer(new ol.layer.Vector({ source: routeSource, zIndex: 100 }));

  window.updateRoute = function(jsonStr) {
    routeSource.clear();
    if (!jsonStr || jsonStr === 'null') return;
    const data = JSON.parse(jsonStr);
    const coords = data.coords;
    const names = data.names;
    const activeIdx = data.activeIndex;
    if (!coords || coords.length < 2) return;

    const mapCoords = coords.map(function(c) { return ol.proj.fromLonLat(c); });

    // Full route polyline
    const routeLine = new ol.Feature({ geometry: new ol.geom.LineString(mapCoords) });
    routeLine.setStyle(new ol.style.Style({
      stroke: new ol.style.Stroke({ color: 'rgba(255,255,255,0.4)', width: 3 }),
    }));
    routeSource.addFeature(routeLine);

    // Active leg highlight (previous → next waypoint)
    if (activeIdx != null && activeIdx > 0 && activeIdx < coords.length) {
      const legLine = new ol.Feature({
        geometry: new ol.geom.LineString([mapCoords[activeIdx - 1], mapCoords[activeIdx]]),
      });
      legLine.setStyle(new ol.style.Style({
        stroke: new ol.style.Stroke({ color: 'rgba(76,175,80,0.9)', width: 4 }),
      }));
      routeSource.addFeature(legLine);
    }

    // Waypoint markers
    var res = map.getView().getResolution();
    coords.forEach(function(c, i) {
      var isNext = (i === activeIdx);
      var isPast = (activeIdx != null && i < activeIdx);
      var pt = new ol.Feature({ geometry: new ol.geom.Point(mapCoords[i]) });
      var styles = [new ol.style.Style({
        image: new ol.style.Circle({
          radius: isNext ? 8 : 5,
          fill: new ol.style.Fill({
            color: isNext ? 'rgba(76,175,80,0.9)' : isPast ? 'rgba(255,255,255,0.3)' : 'rgba(255,255,255,0.7)',
          }),
          stroke: new ol.style.Stroke({ color: isNext ? '#fff' : '#666', width: isNext ? 2 : 1 }),
        }),
      })];
      var name = names && names[i] ? names[i] : '';
      if (name && (isNext || (!isPast && res < 20))) {
        styles.push(new ol.style.Style({
          text: new ol.style.Text({
            text: name, scale: isNext ? 1.1 : 0.9, offsetY: -16,
            fill: new ol.style.Fill({ color: isNext ? '#4caf50' : 'rgba(255,255,255,0.7)' }),
            stroke: new ol.style.Stroke({ color: 'rgba(0,0,0,0.5)', width: 1 }),
          }),
        }));
      }
      pt.setStyle(styles);
      routeSource.addFeature(pt);
    });
  };

  console.log('Map initialized with OpenLayers + S57 + overlays');
  if (window.MapReady) MapReady.postMessage('ready');
}

initMap().catch(e => console.error('Init failed:', e));
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Listener(
      onPointerDown: (_) {
        try { context.read<ValueNotifier<bool>>().value = true; } catch (_) {}
      },
      onPointerUp: (_) {
        try { context.read<ValueNotifier<bool>>().value = false; } catch (_) {}
      },
      onPointerCancel: (_) {
        try { context.read<ValueNotifier<bool>>().value = false; } catch (_) {}
      },
      child: WebViewWidget(controller: _controller),
    );
  }
}

// =============================================================================
// Feature Popover (bottom sheet) — unchanged from before
// =============================================================================

class _FeaturePopover extends StatelessWidget {
  final String layerCode;
  final Map<String, dynamic> properties;
  final List? lngLat;

  const _FeaturePopover({
    required this.layerCode,
    required this.properties,
    this.lngLat,
  });

  @override
  Widget build(BuildContext context) {
    final name = properties['OBJNAM'] as String? ??
        _objectClassNames[layerCode] ??
        layerCode;

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(name,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (properties['OBJNAM'] != null)
                      Text(_objectClassNames[layerCode] ?? layerCode,
                        style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
              if (lngLat != null && lngLat!.length == 2)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${(lngLat![1] as num).toStringAsFixed(5)}, ${(lngLat![0] as num).toStringAsFixed(5)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                ),
              const Divider(color: Colors.white24, height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _buildPropertyRows(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPropertyRows() {
    final rows = <Widget>[];
    for (final key in _displayOrder) {
      final val = properties[key];
      if (val == null || val.toString().isEmpty) continue;
      final label = _attributeLabels[key] ?? key;
      String display;
      if (_depthKeys.contains(key)) {
        final n = num.tryParse(val.toString());
        display = n != null ? '${n.toStringAsFixed(1)} m' : val.toString();
      } else if (_heightKeys.contains(key)) {
        final n = num.tryParse(val.toString());
        display = n != null ? '${n.toStringAsFixed(1)} m' : val.toString();
      } else if (key == 'SIGPER') {
        display = '${val}s';
      } else if (key == 'VALNMR') {
        display = '$val NM';
      } else if (key == 'CONRAD' || key == 'CONVIS') {
        display = val.toString() == '1' ? 'Yes' : 'No';
      } else {
        display = _decodeValue(key, val);
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100,
              child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
            Expanded(
              child: Text(display, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ],
        ),
      ));
    }
    return rows;
  }

  String _decodeValue(String key, dynamic val) {
    final table = _decodeTables[key];
    if (table == null) return val.toString();
    final parts = val.toString().split(',');
    final decoded = parts.map((p) => table[p.trim()] ?? p.trim());
    return decoded.join(', ');
  }

  static const _depthKeys = {'DEPTH', 'VALSOU', 'DRVAL1', 'DRVAL2', 'VALDCO'};
  static const _heightKeys = {'HEIGHT', 'VERLEN', 'HORLEN', 'HORWID'};

  static const _displayOrder = [
    'OBJNAM', 'NOBJNM', 'INFORM', 'NINFOM',
    'DEPTH', 'VALSOU', 'DRVAL1', 'DRVAL2', 'VALDCO',
    'CATWRK', 'CATOBS', 'WATLEV',
    'CATLAM', 'CATCAM', 'CATSPM', 'BOYSHP', 'BCNSHP', 'TOPSHP',
    'COLOUR', 'COLPAT', 'LITCHR', 'CATLIT', 'SIGPER', 'VALNMR',
    'HEIGHT', 'RESTRN', 'CONDTN', 'STATUS', 'CONRAD', 'CONVIS',
    'VERLEN', 'HORLEN', 'HORWID',
  ];

  static const _attributeLabels = {
    'OBJNAM': 'Name', 'NOBJNM': 'Local Name', 'INFORM': 'Information', 'NINFOM': 'Note',
    'DEPTH': 'Depth', 'VALSOU': 'Depth', 'DRVAL1': 'Min Depth', 'DRVAL2': 'Max Depth',
    'VALDCO': 'Contour Depth', 'CATWRK': 'Type', 'CATOBS': 'Type', 'WATLEV': 'Water Level',
    'CATLAM': 'Lateral', 'CATCAM': 'Cardinal', 'CATSPM': 'Purpose', 'BOYSHP': 'Shape',
    'BCNSHP': 'Shape', 'TOPSHP': 'Top Mark', 'COLOUR': 'Colour', 'COLPAT': 'Pattern',
    'LITCHR': 'Character', 'CATLIT': 'Category', 'SIGPER': 'Period', 'VALNMR': 'Range',
    'HEIGHT': 'Height', 'RESTRN': 'Restriction', 'CONDTN': 'Condition', 'STATUS': 'Status',
    'CONRAD': 'Radar Conspicuous', 'CONVIS': 'Visually Conspicuous',
    'VERLEN': 'Vertical Clearance', 'HORLEN': 'Length', 'HORWID': 'Width',
  };

  static const _objectClassNames = {
    'SOUNDG': 'Sounding', 'DEPCNT': 'Depth Contour', 'DEPARE': 'Depth Area',
    'DRGARE': 'Dredged Area', 'COALNE': 'Coastline', 'LNDARE': 'Land Area',
    'BUAARE': 'Built-up Area', 'LAKARE': 'Lake', 'RIVERS': 'River', 'CANALS': 'Canal',
    'SEAARE': 'Sea Area', 'LIGHTS': 'Light', 'BOYLAT': 'Lateral Buoy',
    'BOYCAR': 'Cardinal Buoy', 'BOYSAW': 'Safe Water Buoy', 'BOYSPP': 'Special Purpose Buoy',
    'BOYISD': 'Isolated Danger Buoy', 'BCNLAT': 'Lateral Beacon', 'BCNCAR': 'Cardinal Beacon',
    'BCNSPP': 'Special Purpose Beacon', 'BCNSAW': 'Safe Water Beacon',
    'BCNISD': 'Isolated Danger Beacon', 'TOPMAR': 'Topmark', 'DAYMAR': 'Daymark',
    'FOGSIG': 'Fog Signal', 'RTPBCN': 'Radar Transponder', 'RDOSTA': 'Radio Station',
    'RADSTA': 'Radar Station', 'LITFLT': 'Light Float', 'LITVES': 'Light Vessel',
    'WRECKS': 'Wreck', 'OBSTRN': 'Obstruction', 'UWTROC': 'Underwater Rock',
    'LNDMRK': 'Landmark', 'SLCONS': 'Shoreline Construction', 'BRIDGE': 'Bridge',
    'OFSPLF': 'Offshore Platform', 'PILBOP': 'Pilot Boarding Place', 'CRANES': 'Crane',
    'MORFAC': 'Mooring Facility', 'BERTHS': 'Berth', 'HRBFAC': 'Harbour Facility',
    'SMCFAC': 'Small Craft Facility', 'CBLSUB': 'Submarine Cable', 'CBLOHD': 'Overhead Cable',
    'PIPSOL': 'Submarine Pipeline', 'PIPOHD': 'Overhead Pipeline',
    'CGUSTA': 'Coast Guard Station', 'RSCSTA': 'Rescue Station',
    'SISTAT': 'Signal Station', 'SISTAW': 'Storm Signal Station',
    'DISMAR': 'Distance Mark', 'CURENT': 'Current', 'FSHFAC': 'Fishing Facility',
    'ACHARE': 'Anchorage Area', 'RESARE': 'Restricted Area', 'FAIRWY': 'Fairway',
    'TSSLPT': 'TSS Lane', 'TSSBND': 'TSS Boundary', 'NAVLNE': 'Navigation Line',
    'RECTRC': 'Recommended Track', 'GATCON': 'Gate', 'CONVYR': 'Conveyor',
    'PRDARE': 'Production Area', 'VEGATN': 'Vegetation', 'LNDRGN': 'Land Region',
    'DMPGRD': 'Dumping Ground', 'CBLARE': 'Cable Area', 'SPLARE': 'Sea-plane Landing Area',
  };

  static const _decodeTables = {
    'COLOUR': {'1':'White','2':'Black','3':'Red','4':'Green','5':'Blue','6':'Yellow','7':'Grey','8':'Brown','9':'Amber','10':'Violet','11':'Orange','12':'Magenta','13':'Pink'},
    'WATLEV': {'1':'Partly submerged','2':'Always dry','3':'Always under water','4':'Covers and uncovers','5':'Awash','6':'Subject to flooding','7':'Floating'},
    'CATOBS': {'1':'Snag/stump','2':'Wellhead','3':'Diffuser','4':'Crib','5':'Fish haven','6':'Foul area','7':'Foul ground','8':'Ice boom','9':'Ground tackle','10':'Boom'},
    'CATWRK': {'1':'Non-dangerous','2':'Dangerous','3':'Distributed remains','4':'Mast showing','5':'Hull showing'},
    'BOYSHP': {'1':'Conical (nun)','2':'Can (cylindrical)','3':'Spherical','4':'Pillar','5':'Spar','6':'Barrel','7':'Super-buoy','8':'Ice buoy'},
    'BCNSHP': {'1':'Stake/pole','2':'Withy','3':'Tower','4':'Lattice','5':'Pile','6':'Cairn','7':'Buoyant'},
    'CATLAM': {'1':'Port','2':'Starboard','3':'Preferred channel starboard','4':'Preferred channel port'},
    'CATCAM': {'1':'North','2':'East','3':'South','4':'West'},
    'CATLIT': {'1':'Directional','4':'Leading','5':'Aero','6':'Air obstruction','7':'Fog detector','8':'Flood','9':'Strip','10':'Subsidiary','11':'Spotlight','12':'Front','13':'Rear','14':'Lower','15':'Upper'},
    'LITCHR': {'1':'Fixed','2':'Flashing','3':'Long flashing','4':'Quick flashing','5':'Very quick flashing','6':'Ultra quick flashing','7':'Isophase','8':'Occulting','9':'Interrupted quick','10':'Interrupted very quick','11':'Morse code','12':'Fixed/flashing','25':'Quick + long flash','26':'VQ + long flash','27':'UQ + long flash','28':'Alternating','29':'Fixed & alternating flashing'},
    'CONDTN': {'1':'Under construction','2':'Ruined','3':'Under reclamation','5':'Planned'},
    'STATUS': {'1':'Permanent','2':'Occasional','3':'Recommended','4':'Not in use','5':'Intermittent','6':'Reserved','7':'Temporary','8':'Private','9':'Mandatory','11':'Extinguished','12':'Illuminated','13':'Historic','14':'Public','15':'Synchronized','16':'Watched','17':'Un-watched','18':'Doubtful'},
    'RESTRN': {'1':'Anchoring prohibited','2':'Anchoring restricted','3':'Fishing prohibited','4':'Fishing restricted','5':'Trawling prohibited','6':'Trawling restricted','7':'Entry prohibited','8':'Entry restricted','9':'Dredging prohibited','10':'Dredging restricted','11':'Diving prohibited','12':'Diving restricted','13':'No wake','14':'Area to be avoided','27':'Speed restricted'},
    'COLPAT': {'1':'Horizontal stripes','2':'Vertical stripes','3':'Diagonal stripes','4':'Squared','5':'Border stripes','6':'Single colour'},
    'TOPSHP': {'1':'Cone point up','2':'Cone point down','3':'Sphere','4':'Two spheres','5':'Cylinder','6':'Board','7':'X-shape','8':'Upright cross','9':'Cube point up','10':'Two cones point-to-point','11':'Two cones base-to-base','12':'Rhombus','13':'Two cones point up','14':'Two cones point down','33':'Flag'},
    'CATSPM': {'1':'Firing danger','2':'Target','3':'Marker ship','4':'Degaussing range','5':'Barge','6':'Cable','7':'Spoil ground','8':'Outfall','9':'ODAS','10':'Recording','11':'Seaplane anchorage','12':'Recreation zone','13':'Private','14':'Mooring','15':'LANBY','16':'Leading','17':'Measured distance','18':'Notice','19':'TSS','20':'No anchoring','21':'No berthing','22':'No overtaking','23':'No two-way traffic','24':'Reduced wake','25':'Speed limit','26':'Stop','27':'Warning','28':'Sound ship siren','39':'Environmental','45':'AIS','51':'No entry'},
  };
}
