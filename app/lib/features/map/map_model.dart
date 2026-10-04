import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_error.dart';
import '../../core/api/geo.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';

class MapModel extends ChangeNotifier {
  MapModel(this.api);

  final TraceApi api;

  List<NearbyDrop> drops = const [];
  bool loading = false;
  ApiError? error;
  String? selectedId;

  LatLng? _lastQuery;
  DateTime? _lastQueryAt;

  NearbyDrop? get selected => selectedId == null ? null : drops.where((d) => d.id == selectedId).firstOrNull;

  /// Refetches when forced, after moving 150 m, or once a minute.
  Future<void> refreshIfNeeded(LatLng here, {bool force = false}) async {
    final moved = _lastQuery == null || metersBetween(_lastQuery!, here) > 150;
    final old = _lastQueryAt == null || DateTime.now().difference(_lastQueryAt!) > const Duration(minutes: 1);
    if (!force && !moved && !old) return;
    if (loading) return;

    _lastQuery = here;
    _lastQueryAt = DateTime.now();
    loading = true;
    notifyListeners();
    try {
      drops = await api.nearby(here.latitude, here.longitude);
      error = null;
      if (selectedId != null && selected == null) selectedId = null;
    } on ApiError catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void select(String? id) {
    if (id == selectedId) return;
    selectedId = id;
    notifyListeners();
  }

  void markUnlocked(String id) {
    drops = [
      for (final d in drops)
        if (d.id == id)
          NearbyDrop(
            id: d.id,
            type: d.type,
            teaser: d.teaser,
            createdAt: d.createdAt,
            center: d.center,
            radius: d.radius,
            mine: d.mine,
            unlocked: true,
            pending: d.pending,
            hasCondition: d.hasCondition,
            capsuleUnlockAt: d.capsuleUnlockAt,
            isRelay: d.isRelay,
          )
        else
          d,
    ];
    notifyListeners();
  }
}
