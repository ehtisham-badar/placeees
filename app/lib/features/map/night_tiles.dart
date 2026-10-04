import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/config.dart';

/// Base map. A configured dark style is used as-is; otherwise OSM tiles are recoloured to night.
class NightTiles extends StatelessWidget {
  const NightTiles({super.key});

  // Inverted luminance with a navy tint: land goes deep blue-black, labels go light.
  static const _night = ColorFilter.matrix([
    -0.2126 * 1.05, -0.7152 * 1.05, -0.0722 * 1.05, 0, 255 * 1.05 + 4, //
    -0.2126 * 1.08, -0.7152 * 1.08, -0.0722 * 1.08, 0, 255 * 1.08 + 8,
    -0.2126 * 1.22, -0.7152 * 1.22, -0.0722 * 1.22, 0, 255 * 1.22 + 16,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final custom = AppConfig.mapTileUrl.isNotEmpty;
    final layer = TileLayer(
      urlTemplate: custom ? AppConfig.mapTileUrl : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'app.trace.mobile',
      tileDisplay: const TileDisplay.fadeIn(),
    );
    if (custom) return layer;
    return ColorFiltered(colorFilter: _night, child: Opacity(opacity: 0.8, child: layer));
  }
}
