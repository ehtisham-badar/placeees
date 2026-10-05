import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart' show LatLng;

import '../analytics.dart' show AppEvent;
import 'api_error.dart';
import 'conditions.dart';
import 'geo.dart';
import 'models.dart';
import 'signature.dart';
import 'social.dart';
import 'venue.dart';
import 'sun.dart';
import 'trace_api.dart';

/// An in-memory backend that seeds hand-written drops around wherever you are.
/// Applies the same unlock rules as the server so the whole loop can be felt without one.
class DemoApi implements TraceApi {
  @override
  String? token;

  User _user = const User(id: 'demo-user', handle: null, hasHomeZone: false);
  final _drops = <String, _DemoDrop>{};
  final _unlockedAt = <String, DateTime>{};
  final _trails = <String, _DemoTrail>{};
  final _completedAt = <String, DateTime>{};
  final _circles = <String, _DemoCircle>{};
  final _echoes = <String, List<Echo>>{};
  final _carrying = <String, ({DateTime pickedAt, DateTime deadline, LatLng pickup})>{};
  final _carriedBefore = <String>{};
  final _hops = <String, List<_DemoHop>>{};
  final _nowPhotos = <String, List<NowPhoto>>{};
  final _rng = math.Random();
  int _seq = 0;

  Future<void> _latency([int ms = 350]) => Future.delayed(Duration(milliseconds: ms + _rng.nextInt(200)));

  @override
  Future<AuthResult> signInWithApple(String identityToken) => signInDemo('apple');

  @override
  Future<AuthResult> signInWithGoogle(String idToken) => signInDemo('google');

  @override
  Future<AuthResult> signInDemo(String name) async {
    await _latency(600);
    return AuthResult('demo-token', _user);
  }

  @override
  Future<User> me() async => _user;

  @override
  Future<bool> isHandleAvailable(String handle) async {
    await _latency(150);
    return RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(handle) && !const {'trace', 'admin', 'ali', 'sara'}.contains(handle);
  }

  @override
  Future<User> setHandle(String handle) async {
    await _latency();
    if (!await isHandleAvailable(handle)) throw const ApiError('handle_taken');
    return _user = User(id: _user.id, handle: handle, hasHomeZone: _user.hasHomeZone);
  }

  @override
  Future<User> setHomeZone(double lat, double lng) async {
    await _latency();
    return _user = User(id: _user.id, handle: _user.handle, hasHomeZone: true);
  }

  @override
  Future<User> clearHomeZone() async {
    await _latency();
    return _user = User(id: _user.id, handle: _user.handle, hasHomeZone: false);
  }

  @override
  Future<List<NearbyDrop>> nearby(double lat, double lng) async {
    if (_drops.isEmpty) _seed(LatLng(lat, lng));
    await _latency(250);
    final here = LatLng(lat, lng);
    return [
      for (final d in _drops.values)
        if (metersBetween(here, d.point) < 2000 && (!d.pending || d.mine) && _visible(d) && _trailOrderOk(d))
          d.toNearby(
            _unlockedAt.containsKey(d.id),
            trail: _trailRef(d, content: false),
            circle: _circleRef(d),
            relayHops: _hops[d.id]?.length ?? 0,
          ),
    ];
  }

  bool _visible(_DemoDrop d) =>
      !_carrying.containsKey(d.id) && (d.mine || d.circleId == null || (_circles[d.circleId]?.joined ?? false));

  (_DemoTrail, int)? _trailOf(String dropId) {
    for (final t in _trails.values) {
      final i = t.dropIds.indexOf(dropId);
      if (i >= 0) return (t, i);
    }
    return null;
  }

  /// Same rule as the API: later stops stay hidden until the previous one is unlocked.
  bool _trailOrderOk(_DemoDrop d) {
    final found = _trailOf(d.id);
    if (found == null || d.mine) return true;
    final (t, i) = found;
    return i == 0 || _unlockedAt.containsKey(t.dropIds[i - 1]);
  }

  TrailRef? _trailRef(_DemoDrop d, {required bool content}) {
    final found = _trailOf(d.id);
    if (found == null) return null;
    final (t, i) = found;
    final reachedNext = content && (d.mine || _unlockedAt.containsKey(d.id));
    return TrailRef(
      id: t.id,
      title: t.title,
      seq: i + 1,
      total: t.dropIds.length,
      nextClue: reachedNext && i + 1 < t.clues.length ? t.clues[i + 1] : null,
      completedAt: _completedAt[t.id],
    );
  }

  CircleRef? _circleRef(_DemoDrop d) {
    final c = d.circleId == null ? null : _circles[d.circleId];
    return c == null ? null : CircleRef(id: c.id, name: c.name);
  }

  DropContent _content(_DemoDrop d) => d.toContent(
        _unlockedAt[d.id],
        trail: _trailRef(d, content: true),
        circle: _circleRef(d),
        relay: d.isRelay
            ? RelayInfo(
                hops: _hops[d.id]?.length ?? 0,
                carrying: _carrying.containsKey(d.id),
                carryDeadline: _carrying[d.id]?.deadline,
                canPickUp: !d.mine &&
                    !_carriedBefore.contains(d.id) &&
                    !_carrying.containsKey(d.id) &&
                    _unlockedAt.containsKey(d.id),
              )
            : null,
      );

  @override
  Future<DropContent> unlock(String dropId, LocationFix fix) async {
    await _latency(700);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (fix.accuracy > 80) throw const ApiError('low_accuracy');
    if (metersBetween(fix.point, d.point) > unlockRadius(fix.accuracy)) throw const ApiError('too_far');
    if (!_visible(d)) throw const ApiError('not_found');
    if (!_trailOrderOk(d)) throw const ApiError('trail_order');
    if (d.capsuleUnlockAt != null && DateTime.now().isBefore(d.capsuleUnlockAt!)) {
      throw const ApiError('capsule_locked');
    }
    if (!_conditionsMet(d, DateTime.now())) throw const ApiError('condition_locked');
    if (!_unlockedAt.containsKey(d.id)) {
      _unlockedAt[d.id] = DateTime.now();
      d.unlockCount++;
    }
    final trail = _trailOf(d.id)?.$1;
    if (trail != null && trail.dropIds.every(_unlockedAt.containsKey)) _completedAt.putIfAbsent(trail.id, DateTime.now);
    return _content(d);
  }

  @override
  Future<DropContent> drop(String dropId) async {
    await _latency(200);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.mine && !_unlockedAt.containsKey(d.id)) throw const ApiError('locked');
    return _content(d);
  }

  @override
  Future<String> createDrop({
    required DropType type,
    required LocationFix fix,
    String? body,
    Uint8List? photoJpeg,
    String? teaser,
    bool isAnonymous = false,
    List<DropCondition> conditions = const [],
    bool revealConditions = false,
    DateTime? unlockAt,
    List<String> recipientHandles = const [],
    String? circleId,
    bool isRelay = false,
    CaptureAngle? angle,
    Uint8List? voiceAac,
    List<double>? waveform,
  }) async {
    await _latency(900);
    if (type == DropType.voice && voiceAac == null) throw const ApiError('media_required');
    if (type == DropType.thenNow && angle == null) throw const ApiError('angle_required');
    if (isRelay && (unlockAt != null || circleId != null || recipientHandles.isNotEmpty)) {
      throw const ApiError('relay_must_be_public');
    }
    if (circleId != null && recipientHandles.isNotEmpty) throw const ApiError('visibility_conflict');
    if (circleId != null && !(_circles[circleId]?.joined ?? false)) throw const ApiError('not_a_member');
    if (fix.accuracy > 65) throw const ApiError('low_accuracy');
    if (unlockAt != null) {
      final ahead = unlockAt.difference(DateTime.now());
      if (ahead < const Duration(hours: 24)) throw const ApiError('capsule_too_soon');
      if (ahead > const Duration(days: 25 * 365)) throw const ApiError('capsule_too_far');
    }
    if (recipientHandles.length > 20) throw const ApiError('too_many_recipients');
    final mineToday = _drops.values.where((d) => d.mine).length;
    if (mineToday >= 10) throw const ApiError('daily_limit');

    final d = _DemoDrop(
      id: 'mine-${_seq++}',
      type: type,
      point: fix.point,
      teaser: teaser,
      body: body,
      localImage: photoJpeg,
      author: isAnonymous ? null : _user.handle,
      createdAt: DateTime.now(),
      mine: true,
      pending: true,
      conditions: conditions.isEmpty ? null : conditions,
      revealed: revealConditions,
      capsuleUnlockAt: unlockAt,
      circleId: circleId,
      isRelay: isRelay,
      angle: angle,
      localAudio: voiceAac,
      waveform: waveform,
    );
    _drops[d.id] = d;
    // Simulated moderation pass.
    Timer(const Duration(seconds: 4), () => d.pending = false);
    return d.id;
  }

  @override
  Future<NearHint> nearHint(String dropId, LocationFix fix) async {
    await _latency(200);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (metersBetween(fix.point, d.point) > 100) throw const ApiError('too_far');
    return NearHint(point: d.point, expiresAt: DateTime.now().add(const Duration(minutes: 5)));
  }

  /// Same rules as the API. Demo weather is always clear; times use the device clock.
  bool _conditionsMet(_DemoDrop d, DateTime now) {
    for (final c in d.conditions ?? const <DropCondition>[]) {
      final ok = switch (c) {
        SunCondition(:final phase, :final windowMinutes) => _inSunPhase(phase, now, d.point, windowMinutes),
        WeatherCondition(:final kind) => kind == WeatherKind.clear,
        TimeRangeCondition(:final from, :final to) => _inTimeRange(_hhmm(now), from, to),
        DateRangeCondition(:final from, :final to) =>
          !DateTime(now.year, now.month, now.day).isBefore(from) && !DateTime(now.year, now.month, now.day).isAfter(to),
      };
      if (!ok) return false;
    }
    return true;
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static bool _inTimeRange(String t, String from, String to) =>
      from.compareTo(to) <= 0 ? t.compareTo(from) >= 0 && t.compareTo(to) < 0 : t.compareTo(from) >= 0 || t.compareTo(to) < 0;

  static bool _inSunPhase(SunPhase phase, DateTime now, LatLng p, int windowMinutes) {
    final days = [-1, 0, 1].map((o) => SunTimes.of(now.add(Duration(days: o)), p.latitude, p.longitude)).toList();
    final w = Duration(minutes: windowMinutes);
    bool near(DateTime? at) => at != null && now.difference(at).abs() <= w;
    bool between(DateTime? a, DateTime? b) => a != null && b != null && !now.isBefore(a) && !now.isAfter(b);
    return switch (phase) {
      SunPhase.sunrise => days.any((s) => near(s.sunrise)),
      SunPhase.sunset => days.any((s) => near(s.sunset)),
      SunPhase.goldenHour => days.any((s) => between(s.sunrise, s.goldenHourEnd) || between(s.goldenHour, s.sunset)),
      SunPhase.night => [0, 1].any((i) => between(days[i].dusk, days[i + 1].dawn)),
    };
  }

  @override
  Future<Passport> passport() async {
    await _latency(300);
    final unlocked = _unlockedAt.entries.map((e) => _drops[e.key]!.toPassport(unlockedAt: e.value)).toList()
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    final created = _drops.values.where((d) => d.mine).map((d) => d.toPassport()).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final stamps = [
      for (final e in _completedAt.entries)
        Stamp(trailId: e.key, title: _trails[e.key]!.title, completedAt: e.value, stops: _trails[e.key]!.dropIds.length),
    ];
    return Passport(unlocked: unlocked, created: created, stamps: stamps);
  }

  @override
  Future<List<Echo>> echoes(String dropId) async {
    await _latency(250);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.mine && !_unlockedAt.containsKey(dropId)) throw const ApiError('locked');
    return List.of(_echoes[dropId] ?? const []);
  }

  @override
  Future<Echo> postEcho(String dropId, String body, LocationFix fix) async {
    await _latency(500);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.mine && !_unlockedAt.containsKey(dropId)) throw const ApiError('locked');
    if (fix.accuracy > 80) throw const ApiError('low_accuracy');
    if (metersBetween(fix.point, d.point) > unlockRadius(fix.accuracy)) throw const ApiError('too_far');
    final echo = Echo(
      id: 'echo-${_seq++}',
      body: body.trim(),
      createdAt: DateTime.now(),
      authorHandle: _user.handle,
      mine: true,
      pending: true,
    );
    final list = _echoes.putIfAbsent(dropId, () => []);
    list.add(echo);
    // Simulated moderation pass.
    Timer(const Duration(seconds: 3), () {
      final i = list.indexOf(echo);
      if (i >= 0) {
        list[i] = Echo(id: echo.id, body: echo.body, createdAt: echo.createdAt, authorHandle: echo.authorHandle, mine: true);
      }
    });
    return echo;
  }

  @override
  Future<String> createTrail(String title, List<({String dropId, String? clue})> stops) async {
    await _latency(600);
    final ids = [for (final s in stops) s.dropId];
    if (ids.length < 3 || ids.length > 15) throw const ApiError('invalid_stops');
    if (ids.toSet().length != ids.length) throw const ApiError('duplicate_stop');
    for (final id in ids) {
      final d = _drops[id];
      if (d == null || !d.mine || d.circleId != null || _trailOf(id) != null) throw const ApiError('invalid_stops');
    }
    final t = _DemoTrail(id: 'trail-${_seq++}', title: title.trim(), author: _user.handle, dropIds: ids, clues: [
      for (final s in stops) (s.clue?.trim().isEmpty ?? true) ? null : s.clue!.trim(),
    ]);
    _trails[t.id] = t;
    return t.id;
  }

  @override
  Future<Trail> trail(String trailId) async {
    await _latency(300);
    final t = _trails[trailId] ?? (throw const ApiError('not_found'));
    final mine = t.author == _user.handle;
    return Trail(
      id: t.id,
      title: t.title,
      creatorHandle: t.author,
      mine: mine,
      completedAt: _completedAt[t.id],
      stops: [
        for (final (i, id) in t.dropIds.indexed)
          () {
            final d = _drops[id]!;
            final unlocked = _unlockedAt.containsKey(id);
            final reached = mine || i == 0 || _unlockedAt.containsKey(t.dropIds[i - 1]);
            return TrailStop(
              seq: i + 1,
              unlocked: unlocked,
              reached: reached,
              clue: reached ? t.clues[i] : null,
              dropId: reached ? id : null,
              type: mine || unlocked ? d.type : null,
              teaser: mine || unlocked ? d.teaser : null,
              areaCenter: reached && !unlocked ? fuzzyCircle(id, d.point).center : null,
            );
          }(),
      ],
    );
  }

  @override
  Future<List<Circle>> circles() async {
    await _latency(250);
    return [for (final c in _circles.values) if (c.joined) c.toCircle(_user.handle)];
  }

  @override
  Future<Circle> createCircle(String name) async {
    await _latency(500);
    if (_circles.values.where((c) => c.owner == _user.handle).length >= 10) throw const ApiError('circle_limit');
    const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
    final code = String.fromCharCodes([for (var i = 0; i < 8; i++) alphabet.codeUnitAt(_rng.nextInt(alphabet.length))]);
    final c = _DemoCircle(id: 'circle-${_seq++}', name: name.trim(), code: code, owner: _user.handle ?? 'you', members: [
      _user.handle ?? 'you',
    ])..joined = true;
    _circles[c.id] = c;
    return c.toCircle(_user.handle);
  }

  @override
  Future<Circle> joinCircle(String code) async {
    await _latency(500);
    final normalized = code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final c = _circles.values.where((c) => c.code == normalized).firstOrNull ?? (throw const ApiError('invalid_code'));
    if (!c.joined) {
      if (c.members.length >= 50) throw const ApiError('circle_full');
      c.joined = true;
      c.members.add(_user.handle ?? 'you');
    }
    return c.toCircle(_user.handle);
  }

  @override
  Future<Circle> circle(String circleId) async {
    await _latency(250);
    final c = _circles[circleId];
    if (c == null || !c.joined) throw const ApiError('not_found');
    return c.toCircle(_user.handle);
  }

  @override
  Future<DateTime> pickUpRelay(String dropId, LocationFix fix) async {
    await _latency(600);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.isRelay) throw const ApiError('not_a_relay');
    if (d.mine) throw const ApiError('own_relay');
    if (_carrying.containsKey(dropId)) throw const ApiError('already_carried');
    if (_carriedBefore.contains(dropId)) throw const ApiError('carried_before');
    if (!_unlockedAt.containsKey(dropId)) throw const ApiError('locked');
    if (_carrying.length >= 3) throw const ApiError('carrying_limit');
    if (metersBetween(fix.point, d.point) > unlockRadius(fix.accuracy)) throw const ApiError('too_far');
    final now = DateTime.now();
    final deadline = now.add(const Duration(days: 7));
    _carrying[dropId] = (pickedAt: now, deadline: deadline, pickup: d.point);
    _carriedBefore.add(dropId);
    return deadline;
  }

  @override
  Future<double> dropRelay(String dropId, LocationFix fix, {String? note}) async {
    await _latency(700);
    final carry = _carrying[dropId] ?? (throw const ApiError('not_carrying'));
    if (fix.accuracy > 65) throw const ApiError('low_accuracy');
    final distance = metersBetween(carry.pickup, fix.point);
    if (distance < 1000) throw const ApiError('too_close');
    final d = _drops[dropId]!;
    d.point = fix.point;
    _carrying.remove(dropId);
    _hops.putIfAbsent(dropId, () => []).add(_DemoHop(
          handle: _user.handle,
          pickedAt: carry.pickedAt,
          droppedAt: DateTime.now(),
          from: carry.pickup,
          to: fix.point,
          note: note?.trim().isEmpty ?? true ? null : note!.trim(),
        ));
    return distance;
  }

  @override
  Future<List<CarriedRelay>> carrying() async {
    await _latency(200);
    return [
      for (final e in _carrying.entries)
        CarriedRelay(
          id: e.key,
          teaser: _drops[e.key]?.teaser,
          pickedAt: e.value.pickedAt,
          deadlineAt: e.value.deadline,
          pickup: e.value.pickup,
        ),
    ];
  }

  @override
  Future<RelayJourney> relayJourney(String dropId) async {
    await _latency(300);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.isRelay) throw const ApiError('not_found');
    final hops = _hops[dropId] ?? const <_DemoHop>[];
    final origin = hops.isEmpty ? d.point : hops.first.from;
    return RelayJourney(
      origin: fuzzyCircle('$dropId:origin', origin).center,
      originAt: d.createdAt,
      originHandle: d.author,
      totalDistanceM: hops.fold(0, (sum, h) => sum + metersBetween(h.from, h.to)),
      carriedBy: _carrying.containsKey(dropId) ? _user.handle : null,
      hops: [
        for (final (i, h) in hops.indexed)
          RelayHop(
            handle: h.handle,
            pickedAt: h.pickedAt,
            droppedAt: h.droppedAt,
            distanceM: metersBetween(h.from, h.to),
            note: h.note,
            // The resting point matches the map circle; earlier ones are fuzzed per hop.
            to: i == hops.length - 1 && !_carrying.containsKey(dropId)
                ? fuzzyCircle(dropId, h.to).center
                : fuzzyCircle('$dropId:$i', h.to).center,
          ),
      ],
    );
  }

  @override
  Future<void> track(List<AppEvent> events) async {} // demo mode records nothing

  @override
  Future<void> registerDevice(String token, String platform) async {}

  @override
  Future<void> unregisterDevice(String token) async {}

  /// Demo venue: the chai stall drop, as if a QR poster hung there.
  static const demoVenueCode = 'CHA23456';

  @override
  Future<Venue> venue(String code) async {
    await _latency(300);
    final d = _drops['seed-2'];
    if (code != demoVenueCode || d == null) throw const ApiError('not_found');
    return Venue(code: code, name: 'Bilal’s chai stall', drop: d.toNearby(_unlockedAt.containsKey(d.id)));
  }

  @override
  Future<List<NowPhoto>> nowPhotos(String dropId) async {
    await _latency(250);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (d.type != DropType.thenNow) throw const ApiError('not_found');
    if (!d.mine && !_unlockedAt.containsKey(dropId)) throw const ApiError('locked');
    return List.of(_nowPhotos[dropId] ?? const []);
  }

  @override
  Future<NowPhoto> postNowPhoto(String dropId, Uint8List jpeg, LocationFix fix, {double? heading, double? pitch}) async {
    await _latency(800);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.mine && !_unlockedAt.containsKey(dropId)) throw const ApiError('locked');
    if (metersBetween(fix.point, d.point) > unlockRadius(fix.accuracy)) throw const ApiError('too_far');
    final photo = NowPhoto(
      id: 'now-${_seq++}',
      bytes: jpeg,
      createdAt: DateTime.now(),
      authorHandle: _user.handle,
      mine: true,
    );
    _nowPhotos.putIfAbsent(dropId, () => []).insert(0, photo);
    return photo;
  }

  @override
  Future<void> leaveCircle(String circleId) async {
    await _latency(300);
    final c = _circles[circleId] ?? (throw const ApiError('not_found'));
    if (c.owner == _user.handle) throw const ApiError('owner_cannot_leave');
    c.joined = false;
    c.members.remove(_user.handle);
  }

  @override
  Future<void> reportDrop(String dropId, {String? reason}) => _latency();

  @override
  Future<void> blockAuthor(String dropId) async {
    await _latency();
    final author = _drops[dropId]?.author;
    _drops.removeWhere((_, d) => !d.mine && d.author == author);
  }

  void _seed(LatLng here) {
    final now = DateTime.now();
    _seedSocial(here, now);
    for (final (i, s) in _seeds.indexed) {
      final d = _DemoDrop(
        id: 'seed-$i',
        type: s.type,
        point: offsetBy(here, s.bearing, s.meters),
        teaser: s.teaser,
        body: s.body,
        mediaUrl: s.photoSeed == null ? null : 'https://picsum.photos/seed/${s.photoSeed}/900/1200',
        author: s.author,
        createdAt: now.subtract(s.age),
        unlockCount: s.unlocks,
        conditions: s.conditions,
        revealed: s.revealed,
        forYou: s.forYou,
        capsuleUnlockAt: s.capsuleIn == null ? null : now.add(s.capsuleIn!),
      );
      _drops[d.id] = d;
    }
  }
}

extension on DemoApi {
  void _seedSocial(LatLng here, DateTime now) {
    _DemoDrop add(String id, double bearing, double meters, String teaser, String body,
            {String? author, String? circleId, int unlocks = 0, Duration age = const Duration(days: 5)}) =>
        _drops[id] = _DemoDrop(
          id: id,
          type: DropType.text,
          point: offsetBy(here, bearing, meters),
          teaser: teaser,
          body: body,
          author: author,
          createdAt: now.subtract(age),
          unlockCount: unlocks,
          circleId: circleId,
        );

    // A three-stop trail starting right next to you.
    add('trail-a', 60, 22, 'The hunt starts here.',
        'Welcome to the Old City Hunt. Three stops, one story. Read the clue below, then follow it.',
        author: 'noor', unlocks: 31);
    add('trail-b', 150, 190, 'Stop two.',
        'The gate has stood here for four hundred years. Touch the wood. Somebody’s great-great-grandfather did too.',
        author: 'noor', unlocks: 18);
    add('trail-c', 230, 340, 'The last stop.',
        'You made it. The best view in the old city is right behind you. Turn around.',
        author: 'noor', unlocks: 11);
    _trails['trail-old-city'] = _DemoTrail(
      id: 'trail-old-city',
      title: 'Old City Hunt',
      author: 'noor',
      dropIds: const ['trail-a', 'trail-b', 'trail-c'],
      clues: const [
        'Begin where the fountain used to be.',
        'Walk toward the oldest door you can find. It’s green and it creaks.',
        'Climb until you can see the minaret over the rooftops.',
      ],
    );

    // A circle you belong to, with a drop only its members can see.
    _circles['circle-hostel'] = _DemoCircle(
      id: 'circle-hostel',
      name: 'Hostel 4 crew',
      code: 'H7K2M9QX',
      owner: 'bilal',
      members: ['bilal', 'noor', 'zara', _user.handle ?? 'you'],
    )..joined = true;
    add('circle-a', 330, 120, 'Movie night spot. Members only.',
        'Friday, 9pm, bring a blanket. The projector lives in Bilal’s room.',
        author: 'bilal', circleId: 'circle-hostel', unlocks: 3, age: const Duration(days: 2));

    // A circle you can join with a code.
    _circles['circle-walkers'] = _DemoCircle(
      id: 'circle-walkers',
      name: 'Saturday walkers',
      code: 'WANDER29',
      owner: 'zara',
      members: ['zara', 'umar_and_aiza', 'hamza.shoots'],
    );

    // A relay that has already travelled across the city.
    final relay = add('relay-a', 250, 28, 'Pass it on: the travelling notebook.',
        'Write a line in your head, carry this a kilometre, and leave it somewhere you love. '
        'So far it has seen a book market, a bus stop and a rooftop.',
        author: 'zara', unlocks: 9, age: const Duration(days: 20))
      ..isRelay = true;
    final legs = [
      (offsetBy(here, 20, 9000), offsetBy(here, 60, 6000), 'noor', 'Left it at the book market.'),
      (offsetBy(here, 60, 6000), offsetBy(here, 110, 3500), 'bilal', 'Rode the bus with it. Felt important.'),
      (offsetBy(here, 110, 3500), offsetBy(here, 200, 1800), 'mehak', null),
      (offsetBy(here, 200, 1800), relay.point, 'faris', 'Your turn.'),
    ];
    _hops['relay-a'] = [
      for (final (i, (from, to, handle, note)) in legs.indexed)
        _DemoHop(
          handle: handle,
          pickedAt: now.subtract(Duration(days: 16 - i * 4)),
          droppedAt: now.subtract(Duration(days: 15 - i * 4)),
          from: from,
          to: to,
          note: note,
        ),
    ];

    // A Then/Now spot with a photo from 1965.
    add('thennow-a', 170, 30, 'Mall Road, 1965.',
        'My grandfather took this from exactly here. Same arches, fewer cars. Line it up and add yours.',
        author: 'umar_and_aiza', unlocks: 14, age: const Duration(days: 40))
      ..type = DropType.thenNow
      ..mediaUrl = 'https://picsum.photos/seed/trace-1965/900/1200?grayscale'
      ..angle = const CaptureAngle(heading: 135, pitch: 4);
    _nowPhotos['thennow-a'] = [
      NowPhoto(id: 'n1', url: 'https://picsum.photos/seed/trace-now-1/900/1200', createdAt: now.subtract(const Duration(days: 3)), authorHandle: 'hamza.shoots'),
      NowPhoto(id: 'n2', url: 'https://picsum.photos/seed/trace-now-2/900/1200', createdAt: now.subtract(const Duration(days: 12)), authorHandle: 'mehak'),
    ];

    _echoes['seed-0'] = [
      Echo(id: 'e1', body: 'Needed this today. Thank you, stranger.', createdAt: now.subtract(const Duration(days: 2)), authorHandle: 'faris'),
      Echo(id: 'e2', body: 'Sat here for ten minutes. The pigeons are indeed friendly.', createdAt: now.subtract(const Duration(hours: 30)), authorHandle: 'mehak'),
      Echo(id: 'e3', body: 'Came back a week later to read it again.', createdAt: now.subtract(const Duration(hours: 4)), authorHandle: 'faris'),
    ];
    _echoes['trail-a'] = [
      Echo(id: 'e4', body: 'Did the whole hunt with my little brother. He found stop two first.', createdAt: now.subtract(const Duration(days: 1)), authorHandle: 'ayesha'),
    ];
  }
}

class _DemoHop {
  _DemoHop({required this.handle, required this.pickedAt, required this.droppedAt, required this.from, required this.to, this.note});

  final String? handle;
  final DateTime pickedAt;
  final DateTime droppedAt;
  final LatLng from;
  final LatLng to;
  final String? note;
}

class _DemoTrail {
  _DemoTrail({required this.id, required this.title, required this.author, required this.dropIds, required this.clues});

  final String id;
  final String title;
  final String? author;
  final List<String> dropIds;

  /// clues[i] leads to stop i; revealed once stop i-1 is unlocked.
  final List<String?> clues;
}

class _DemoCircle {
  _DemoCircle({required this.id, required this.name, required this.code, required this.owner, required this.members});

  final String id;
  final String name;
  final String code;
  final String owner;
  final List<String> members;
  bool joined = false;

  Circle toCircle(String? me) => Circle(
        id: id,
        name: name,
        inviteCode: code,
        memberCount: members.length,
        isOwner: owner == me,
        members: [for (final m in members) CircleMember(handle: m, isOwner: m == owner)],
      );
}

class _DemoDrop {
  _DemoDrop({
    required this.id,
    required this.type,
    required this.point,
    required this.createdAt,
    this.teaser,
    this.body,
    this.mediaUrl,
    this.localImage,
    this.author,
    this.unlockCount = 0,
    this.mine = false,
    this.pending = false,
    this.conditions,
    this.revealed = false,
    this.forYou = false,
    this.capsuleUnlockAt,
    this.circleId,
    this.isRelay = false,
    this.angle,
    this.localAudio,
    this.waveform,
  });

  final String id;
  DropType type;

  /// Mutable: relays move when they're dropped somewhere new.
  LatLng point;
  final DateTime createdAt;
  final String? teaser;
  final String? body;
  String? mediaUrl;
  final Uint8List? localImage;
  final String? author;
  final bool mine;
  final List<DropCondition>? conditions;
  final bool revealed;
  final bool forYou;
  final DateTime? capsuleUnlockAt;
  final String? circleId;
  bool isRelay;
  CaptureAngle? angle;
  final Uint8List? localAudio;
  final List<double>? waveform;
  int unlockCount;
  bool pending;

  NearbyDrop toNearby(bool unlocked, {TrailRef? trail, CircleRef? circle, int relayHops = 0}) {
    final fuzz = fuzzyCircle(id, point);
    return NearbyDrop(
      id: id,
      type: type,
      teaser: teaser,
      createdAt: createdAt,
      center: fuzz.center,
      radius: fuzz.radius,
      mine: mine,
      unlocked: unlocked,
      pending: pending,
      hasCondition: conditions != null,
      conditionKinds: [
        for (final c in conditions ?? const <DropCondition>[])
          switch (c) {
            SunCondition(phase: SunPhase.night) => 'night',
            SunCondition() => 'sun',
            WeatherCondition() => 'weather',
            TimeRangeCondition() => 'timeRange',
            DateRangeCondition() => 'dateRange',
          },
      ],
      conditions: revealed || mine ? conditions : null,
      capsuleUnlockAt: capsuleUnlockAt,
      forYou: forYou,
      trail: trail,
      circle: circle,
      isRelay: isRelay,
      relayHops: relayHops,
    );
  }

  DropContent toContent(DateTime? unlockedAt, {TrailRef? trail, CircleRef? circle, RelayInfo? relay}) => DropContent(
        id: id,
        type: type,
        body: body,
        teaser: teaser,
        mediaUrl: mediaUrl,
        localImage: localImage,
        authorHandle: author,
        createdAt: createdAt,
        unlockedAt: unlockedAt,
        unlockCount: unlockCount,
        mine: mine,
        pending: pending,
        trail: trail,
        circle: circle,
        relay: relay,
        angle: angle,
        localAudio: localAudio,
        waveform: waveform,
      );

  PassportEntry toPassport({DateTime? unlockedAt}) => PassportEntry(
        id: id,
        type: type,
        teaser: teaser,
        body: body,
        createdAt: createdAt,
        unlockedAt: unlockedAt,
        authorHandle: author,
        unlockCount: unlockCount,
        status: pending ? 'pending_moderation' : 'approved',
      );
}

typedef _Seed = ({
  DropType type,
  double bearing,
  double meters,
  String? teaser,
  String? body,
  String? photoSeed,
  String? author,
  Duration age,
  int unlocks,
  List<DropCondition>? conditions,
  bool revealed,
  bool forYou,
  Duration? capsuleIn,
});

_Seed _s({
  required DropType type,
  required double bearing,
  required double meters,
  String? teaser,
  String? body,
  String? photo,
  String? author,
  Duration age = const Duration(days: 2),
  int unlocks = 0,
  List<DropCondition>? conditions,
  bool revealed = false,
  bool forYou = false,
  Duration? capsuleIn,
}) =>
    (
      type: type,
      bearing: bearing,
      meters: meters,
      teaser: teaser,
      body: body,
      photoSeed: photo,
      author: author,
      age: age,
      unlocks: unlocks,
      conditions: conditions,
      revealed: revealed,
      forYou: forYou,
      capsuleIn: capsuleIn,
    );

final _seeds = <_Seed>[
  _s(
    type: DropType.text,
    bearing: 40,
    meters: 18,
    teaser: 'Read this if today was heavy.',
    body: "Whoever you are, you made it here. Sit for a minute. The bench is warmer than it looks, "
        "and the pigeons are friendlier than they act.\n\nYou're doing better than you think.",
    author: 'noor',
    age: const Duration(days: 3),
    unlocks: 41,
  ),
  _s(
    type: DropType.photo,
    bearing: 200,
    meters: 26,
    teaser: 'Best seat for the 6pm light.',
    body: 'Third step from the top. Thank me later.',
    photo: 'trace-golden',
    author: 'hamza.shoots',
    age: const Duration(hours: 20),
    unlocks: 12,
  ),
  _s(
    type: DropType.text,
    bearing: 120,
    meters: 260,
    teaser: 'The chai guy knows my order. Try mine.',
    body: "Doodh patti, less sugar, extra elaichi. Tell him Bilal sent you. He'll pretend not to remember.",
    author: 'bilal',
    age: const Duration(days: 9),
    unlocks: 88,
  ),
  _s(
    type: DropType.photo,
    bearing: 310,
    meters: 420,
    teaser: 'Look up.',
    photo: 'trace-lookup',
    age: const Duration(days: 1),
    unlocks: 5,
  ),
  _s(
    type: DropType.text,
    bearing: 15,
    meters: 640,
    teaser: 'I proposed right here.',
    body: 'Nervous, sweaty, ring in the wrong pocket. She said yes before I finished the sentence. '
        'If you are standing here with someone, tell them.',
    author: 'umar_and_aiza',
    age: const Duration(days: 140),
    unlocks: 213,
  ),
  _s(
    type: DropType.text,
    bearing: 250,
    meters: 880,
    teaser: 'Exam week survival kit.',
    body: '1. The corner table by the window has a plug that actually works.\n'
        '2. The vending machine gives two if you press B4 twice.\n'
        '3. Sleep. Seriously.',
    author: 'zara',
    age: const Duration(days: 30),
    unlocks: 64,
  ),
  _s(
    type: DropType.photo,
    bearing: 80,
    meters: 1100,
    teaser: 'Night sky from up here.',
    photo: 'trace-stars',
    body: 'Lie on the grass. Give your eyes two minutes. Then count.',
    conditions: const [SunCondition(SunPhase.night)],
    revealed: true,
    age: const Duration(days: 4),
    unlocks: 19,
  ),
  _s(
    type: DropType.text,
    bearing: 300,
    meters: 34,
    teaser: 'Only makes sense in the right light.',
    body: 'See how the whole wall turns copper? That’s why I come back every evening.',
    conditions: const [SunCondition(SunPhase.goldenHour)],
    revealed: true,
    author: 'mahnoor',
    age: const Duration(days: 6),
    unlocks: 7,
  ),
  _s(
    type: DropType.text,
    bearing: 95,
    meters: 230,
    teaser: 'Something only rain can open.',
    body: 'Petrichor. That’s the word for this smell. Now you know.',
    conditions: const [WeatherCondition(WeatherKind.rain)],
    age: const Duration(days: 15),
    unlocks: 3,
  ),
  _s(
    type: DropType.text,
    bearing: 140,
    meters: 70,
    teaser: 'For you, when it’s time.',
    body: 'Told you I’d remember.',
    author: 'sara',
    forYou: true,
    capsuleIn: const Duration(days: 3, hours: 4),
    age: const Duration(days: 1),
  ),
  _s(
    type: DropType.text,
    bearing: 165,
    meters: 1400,
    teaser: 'For whoever finds this on New Year’s.',
    body: 'Happy new year, stranger.',
    capsuleIn: const Duration(days: 88),
    age: const Duration(days: 12),
  ),
];

extension DemoApiWalk on DemoApi {
  /// Demo only: where a drop really is, so "walk there" can place you inside its unlock radius.
  LatLng? truePointOf(String dropId) => _drops[dropId]?.point;
}
