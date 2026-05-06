import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Visible-attribution chrome for `flutter_map` widgets that render
/// OpenStreetMap or OpenSeaMap tiles. Both providers' usage policies
/// require persistent on-map credit; this widget is the canonical place
/// to add it so the wording stays consistent across the app.
///
/// Drop this into `FlutterMap.children` whenever a map renders the
/// `tile.openstreetmap.org` or `tiles.openseamap.org` URLs.
class MapAttribution extends StatelessWidget {
  const MapAttribution({
    super.key,
    this.osm = true,
    this.openSeaMap = false,
    this.alignment = AttributionAlignment.bottomRight,
  });

  final bool osm;
  final bool openSeaMap;
  final AttributionAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final sources = <SourceAttribution>[
      if (osm)
        TextSourceAttribution(
          '© OpenStreetMap contributors',
          onTap: () => _open('https://www.openstreetmap.org/copyright'),
        ),
      if (openSeaMap)
        TextSourceAttribution(
          'OpenSeaMap (CC BY-SA 2.0)',
          onTap: () => _open('https://www.openseamap.org/'),
        ),
    ];
    return RichAttributionWidget(
      alignment: alignment,
      attributions: sources,
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
