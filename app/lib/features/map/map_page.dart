import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/auth/session.dart';
import '../../core/config.dart';
import '../../core/api/signature.dart';
import '../../core/analytics.dart';
import '../../core/events.dart';
import '../../core/alerts/nearby_alerts.dart';
import '../../core/widgets/home_summary.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/pulse_rings.dart';
import '../compass/compass_page.dart';
import '../create/composer_page.dart';
import '../passport/passport_page.dart';
import '../relays/carrying_page.dart';
import '../venues/scanner_page.dart';
import '../unlock/drop_detail_page.dart';
import '../unlock/unlock_page.dart';
import 'drop_card.dart';
import 'drop_marker.dart';
import 'map_model.dart';
import 'night_tiles.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final alerts = context.read<NearbyAlerts>();
        return MapModel(context.read<TraceApi>())
          ..onLoaded = (drops, here) {
            updateHomeWidget(drops, here);
            alerts.sync(drops, here);
          };
      },
      child: const _MapView(),
    );
  }
}

class _MapView extends StatefulWidget {
  const _MapView();

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  final _map = MapController();
  late final LocationService _location = context.read<LocationService>();
  late final DataEvents _events = context.read<DataEvents>();
  bool _mapReady = false;
  bool _centeredOnce = false;
  List<CarriedRelay> _carrying = const [];

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocation);
    _events.addListener(_onDataChanged);
    _location.start();
    _loadCarrying();
    // The map is the app's home: a session starts here.
    context.read<Analytics>()
      ..track('app_open')
      ..track('map_view');
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLocation());
  }

  @override
  void dispose() {
    _location.removeListener(_onLocation);
    _events.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _refresh();
    _loadCarrying();
  }

  Future<void> _loadCarrying() async {
    final list = await context.read<TraceApi>().carrying().catchError((_) => <CarriedRelay>[]);
    if (mounted) setState(() => _carrying = list);
  }

  Future<void> _openCarrying() async {
    final dropped = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CarryingPage()));
    if (dropped == true) _onDataChanged();
  }

  void _onLocation() {
    final fix = _location.fix;
    if (fix == null || !mounted) return;
    if (_mapReady && !_centeredOnce) {
      _centeredOnce = true;
      _map.move(fix.point, 16.2);
    }
    context.read<MapModel>().refreshIfNeeded(fix.point);
  }

  void _recenter() {
    final fix = _location.fix;
    if (fix != null) _map.move(fix.point, 16.2);
  }

  Future<void> _refresh() async {
    final fix = await _location.freshFix();
    if (fix != null && mounted) await context.read<MapModel>().refreshIfNeeded(fix.point, force: true);
  }

  void _select(NearbyDrop d) {
    context.read<MapModel>().select(d.id);
    // Nudge the camera so the circle sits above the card.
    final cam = _map.camera;
    _map.move(LatLng(d.center.latitude - 0.0012 * (16.2 / cam.zoom), d.center.longitude), cam.zoom);
  }

  void _unlock(NearbyDrop d) {
    final model = context.read<MapModel>();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: Motion.slow,
        reverseTransitionDuration: Motion.medium,
        pageBuilder: (_, _, _) => UnlockPage(drop: d, onUnlocked: model.markUnlocked),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _find(NearbyDrop d) {
    final model = context.read<MapModel>();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CompassPage(drop: d, onUnlocked: model.markUnlocked)),
    );
  }

  Future<void> _open(NearbyDrop d) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DropDetailPage.load(dropId: d.id)),
    );
    if (changed == true) _refresh();
  }

  Future<void> _compose() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ComposerPage()),
    );
    if (created == true) _refresh();
  }

  void _passport() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PassportPage()));
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<MapModel>();
    final fix = context.watch<LocationService>().fix;
    final selected = model.selected;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: fix?.point ?? const LatLng(31.5925, 74.3095),
              initialZoom: fix == null ? 12 : 16.2,
              minZoom: 12,
              maxZoom: 19,
              backgroundColor: TraceColors.ink,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                _mapReady = true;
                _onLocation();
              },
              onTap: (_, _) => model.select(null),
            ),
            children: [
              const NightTiles(),
              CircleLayer(
                circles: [
                  for (final d in model.drops)
                    CircleMarker(
                      point: d.center,
                      radius: d.radius,
                      useRadiusInMeter: true,
                      color: dropColor(d).withValues(alpha: d.id == model.selectedId ? 0.2 : 0.09),
                      borderColor: dropColor(d).withValues(alpha: d.id == model.selectedId ? 0.7 : 0.3),
                      borderStrokeWidth: 1.2,
                    ),
                  if (fix != null && fix.accuracy > 15)
                    CircleMarker(
                      point: fix.point,
                      radius: fix.accuracy,
                      useRadiusInMeter: true,
                      color: TraceColors.text.withValues(alpha: 0.05),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (fix != null) Marker(point: fix.point, width: 70, height: 70, child: const UserDot()),
                  for (final d in model.drops)
                    Marker(
                      point: d.center,
                      width: 96,
                      height: 96,
                      child: Center(
                        child: Pressable(
                          onTap: () => _select(d),
                          scale: 0.9,
                          child: DropMarker(drop: d, selected: d.id == model.selectedId),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Fade the map into the UI at the top and bottom.
          const IgnorePointer(child: _EdgeFade()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Column(
                children: [
                  const SizedBox(height: Space.sm),
                  _TopBar(onPassport: _passport, onRefresh: _refresh),
                  if (_carrying.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Pressable(onTap: _openCarrying, child: _CarryingPill(relays: _carrying)),
                    ),
                  ],
                  const Spacer(),
                  if (fix == null) const _LocatingHint(),
                  AnimatedSwitcher(
                    duration: Motion.medium,
                    switchInCurve: Motion.curve,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: selected != null
                        ? DropCard(
                            key: ValueKey(selected.id),
                            drop: selected,
                            onClose: () => model.select(null),
                            onUnlock: () => _unlock(selected),
                            onOpen: () => _open(selected),
                            onFind: () => _find(selected),
                          )
                        : _Dock(
                            key: const ValueKey('dock'),
                            onRecenter: _recenter,
                            onCompose: _compose,
                            onPassport: _passport,
                            empty: !model.loading && model.drops.isEmpty && fix != null,
                          ),
                  ),
                  SizedBox(height: bottomInset > 0 ? 0 : Space.md),
                ],
              ),
            ),
          ),
          Positioned(
            left: Space.md + 4,
            bottom: bottomInset + (selected == null ? 108 : 8),
            child: IgnorePointer(
              child: Text(AppConfig.mapTileUrl.isEmpty ? '© OpenStreetMap contributors' : '© OpenStreetMap', style: TextStyle(fontSize: 9, color: TraceColors.textFaint)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarryingPill extends StatelessWidget {
  const _CarryingPill({required this.relays});

  final List<CarriedRelay> relays;

  @override
  Widget build(BuildContext context) {
    final soonest = relays.map((r) => r.deadlineAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final days = soonest.difference(DateTime.now()).inDays;
    return Glass(
      radius: 100,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.back_hand_rounded, size: 15, color: TraceColors.sun),
          const SizedBox(width: 8),
          Text(
            'Carrying ${relays.length} ${relays.length == 1 ? 'relay' : 'relays'} · ${days < 1 ? 'due today' : '$days d left'}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 18, color: TraceColors.textMuted),
        ],
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [TraceColors.ink.withValues(alpha: 0.85), TraceColors.ink.withValues(alpha: 0)],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [TraceColors.ink.withValues(alpha: 0.9), TraceColors.ink.withValues(alpha: 0)],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onPassport, required this.onRefresh});

  final VoidCallback onPassport;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<MapModel>();
    final fix = context.watch<LocationService>().fix;
    final handle = context.watch<Session>().user?.handle ?? '?';
    final locked = model.drops.where((d) => !d.canOpenAnywhere).length;

    final (gpsColor, gpsLabel) = switch (fix?.accuracy) {
      null => (TraceColors.textFaint, 'No GPS'),
      < 20 => (TraceColors.mint, 'GPS strong'),
      < 65 => (TraceColors.amber, 'GPS ok'),
      _ => (TraceColors.rose, 'GPS weak'),
    };

    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: onRefresh,
            child: Glass(
              radius: 100,
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 12),
              child: Row(
                children: [
                  const EmberDot(size: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Motion.fast,
                      child: Text(
                        key: ValueKey('$locked-${model.loading}'),
                        model.loading && model.drops.isEmpty
                            ? 'Looking around…'
                            : locked == 0
                                ? 'Nothing nearby yet'
                                : '$locked ${locked == 1 ? 'drop' : 'drops'} nearby',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Icon(Icons.gps_fixed_rounded, size: 13, color: gpsColor),
                  const SizedBox(width: 4),
                  Text(gpsLabel, style: TextStyle(fontSize: 11, color: gpsColor, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        OrbButton(
          icon: Icons.qr_code_scanner_rounded,
          tooltip: 'Scan a code',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScannerPage())),
        ),
        const SizedBox(width: Space.sm),
        Pressable(
          onTap: onPassport,
          scale: 0.9,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: TraceColors.emberGradient),
            alignment: Alignment.center,
            child: Text(
              handle.characters.first.toUpperCase(),
              style: const TextStyle(color: TraceColors.ink, fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({super.key, required this.onRecenter, required this.onCompose, required this.onPassport, required this.empty});

  final VoidCallback onRecenter;
  final VoidCallback onCompose;
  final VoidCallback onPassport;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (empty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm + 4),
            child: Glass(
              radius: Radii.md,
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 12),
              child: Text(
                'Nothing here yet. Be the first to leave something.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TraceColors.text),
              ),
            ),
          ),
        Glass(
          radius: 100,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              OrbButton(icon: Icons.my_location_rounded, onTap: onRecenter, tooltip: 'Recenter'),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Pressable(
                  onTap: onCompose,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: TraceColors.emberGradient,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [BoxShadow(color: TraceColors.ember.withValues(alpha: 0.4), blurRadius: 20)],
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_location_alt_rounded, color: TraceColors.ink, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Leave a drop here',
                          style: TextStyle(color: TraceColors.ink, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              OrbButton(icon: Icons.auto_stories_rounded, onTap: onPassport, tooltip: 'Passport'),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocatingHint extends StatelessWidget {
  const _LocatingHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: Space.sm + 4),
      child: Glass(
        radius: 100,
        padding: EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: TraceColors.sun)),
            SizedBox(width: 10),
            Text('Finding you…', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
