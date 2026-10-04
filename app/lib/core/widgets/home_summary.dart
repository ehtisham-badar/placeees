import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../api/geo.dart';
import '../api/models.dart';
import '../format.dart';

/// Shared container for the iOS widget extension (see ios/TraceWidget/README.md).
const widgetAppGroup = 'group.app.trace.mobile';
const widgetRadiusM = 500.0;

typedef WidgetSummary = ({int count, String? teaser, String? distance});

/// "3 drops within 500 m", plus the nearest one's hint (spec F-15).
@visibleForTesting
WidgetSummary widgetSummary(List<NearbyDrop> drops, LatLng here) {
  double edge(NearbyDrop d) => (metersBetween(here, d.center) - d.radius).clamp(0, double.infinity).toDouble();
  final near = drops.where((d) => !d.canOpenAnywhere && !d.pending && edge(d) <= widgetRadiusM).toList()
    ..sort((a, b) => edge(a).compareTo(edge(b)));
  if (near.isEmpty) return (count: 0, teaser: null, distance: null);
  final first = near.first;
  return (count: near.length, teaser: first.teaser, distance: edge(first) == 0 ? 'right here' : distanceLabel(edge(first)));
}

bool _groupSet = false;

/// Pushes the latest summary to the home-screen widget. Never throws.
Future<void> updateHomeWidget(List<NearbyDrop> drops, LatLng here) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  try {
    if (Platform.isIOS && !_groupSet) {
      await HomeWidget.setAppGroupId(widgetAppGroup);
      _groupSet = true;
    }
    final s = widgetSummary(drops, here);
    await HomeWidget.saveWidgetData<int>('nearby_count', s.count);
    await HomeWidget.saveWidgetData<String>('nearest_teaser', s.teaser ?? '');
    await HomeWidget.saveWidgetData<String>('nearest_distance', s.distance ?? '');
    await HomeWidget.saveWidgetData<int>('updated_at', DateTime.now().millisecondsSinceEpoch);
    await HomeWidget.updateWidget(androidName: 'TraceWidgetProvider', iOSName: 'TraceWidget');
  } catch (_) {
    // No widget placed, or the iOS extension isn't installed yet.
  }
}
