import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api/trace_api.dart';

typedef AppEvent = ({String name, DateTime at, Map<String, Object>? props});

/// Product events for the pilot dashboard (spec §11). Batched, best-effort, never blocks the UI.
/// Props stay small and non-identifying: reasons, types, ids of content (never locations).
class Analytics with WidgetsBindingObserver {
  Analytics(this._api) {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => flush());
  }

  final TraceApi _api;
  final _queue = <AppEvent>[];
  late final Timer _timer;
  bool _flushing = false;

  void track(String name, [Map<String, Object>? props]) {
    _queue.add((name: name, at: DateTime.now(), props: props));
    if (_queue.length >= 20) flush();
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    final batch = List.of(_queue.take(50));
    try {
      await _api.track(batch);
      _queue.removeRange(0, batch.length);
    } catch (_) {
      // Offline: keep them for the next try, but never grow without bound.
      if (_queue.length > 500) _queue.removeRange(0, _queue.length - 500);
    } finally {
      _flushing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) flush();
    if (state == AppLifecycleState.resumed) track('app_open');
  }

  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
