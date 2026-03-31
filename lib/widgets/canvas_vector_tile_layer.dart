import 'dart:io';

import 'package:flutter/material.dart' hide Theme;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles/src/cache/cache.dart';
import 'package:vector_map_tiles/src/model/map_properties.dart';
import 'package:vector_map_tiles/src/widgets/map_tiles_layer.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

/// A VectorTileLayer that uses canvas rendering instead of Flutter GPU.
///
/// The upstream VectorTileLayer hardcodes the GPU path which requires
/// Vulkan Impeller. This widget uses the canvas path (MapTilesLayer)
/// which works on all devices including GLES.
class CanvasVectorTileLayer extends StatelessWidget {
  final TileProviders tileProviders;
  final Theme theme;
  final TileOffset tileOffset;
  final int concurrency;
  final int fileCacheMaximumSizeInBytes;
  final Duration fileCacheTtl;
  final Future<Directory> Function()? cacheFolder;

  const CanvasVectorTileLayer({
    super.key,
    required this.tileProviders,
    required this.theme,
    required this.tileOffset,
    this.concurrency = 4,
    this.fileCacheTtl = const Duration(days: 30),
    this.fileCacheMaximumSizeInBytes = 50 * 1024 * 1024,
    this.cacheFolder,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: MapTilesLayer(
        key: Key('s57_canvas_${theme.id}_${theme.version}'),
        mapProperties: MapProperties(
          tileProviders: tileProviders,
          theme: theme,
          tileOffset: tileOffset,
          concurrency: concurrency,
          cacheProperties: CacheProperties(
            fileCacheTtl: fileCacheTtl,
            fileCacheMaximumSizeInBytes: fileCacheMaximumSizeInBytes,
            cacheFolder: cacheFolder,
          ),
        ),
      ),
    );
  }
}
