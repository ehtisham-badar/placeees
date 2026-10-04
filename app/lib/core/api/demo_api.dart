import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'api_error.dart';
import 'conditions.dart';
import 'geo.dart';
import 'models.dart';
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
  Future<List<NearbyDrop>> nearby(double lat, double lng) async {
    if (_drops.isEmpty) _seed(LatLng(lat, lng));
    await _latency(250);
    final here = LatLng(lat, lng);
    return [
      for (final d in _drops.values)
        if (metersBetween(here, d.point) < 2000 && (!d.pending || d.mine)) d.toNearby(_unlockedAt.containsKey(d.id)),
    ];
  }

  @override
  Future<DropContent> unlock(String dropId, LocationFix fix) async {
    await _latency(700);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (fix.accuracy > 80) throw const ApiError('low_accuracy');
    if (metersBetween(fix.point, d.point) > unlockRadius(fix.accuracy)) throw const ApiError('too_far');
    if (d.capsuleUnlockAt != null && DateTime.now().isBefore(d.capsuleUnlockAt!)) {
      throw const ApiError('capsule_locked');
    }
    if (!_conditionsMet(d, DateTime.now())) throw const ApiError('condition_locked');
    if (!_unlockedAt.containsKey(d.id)) {
      _unlockedAt[d.id] = DateTime.now();
      d.unlockCount++;
    }
    return d.toContent(_unlockedAt[d.id]);
  }

  @override
  Future<DropContent> drop(String dropId) async {
    await _latency(200);
    final d = _drops[dropId] ?? (throw const ApiError('not_found'));
    if (!d.mine && !_unlockedAt.containsKey(d.id)) throw const ApiError('locked');
    return d.toContent(_unlockedAt[d.id]);
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
  }) async {
    await _latency(900);
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
    return Passport(unlocked: unlocked, created: created);
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
  });

  final String id;
  final DropType type;
  final LatLng point;
  final DateTime createdAt;
  final String? teaser;
  final String? body;
  final String? mediaUrl;
  final Uint8List? localImage;
  final String? author;
  final bool mine;
  final List<DropCondition>? conditions;
  final bool revealed;
  final bool forYou;
  final DateTime? capsuleUnlockAt;
  int unlockCount;
  bool pending;

  NearbyDrop toNearby(bool unlocked) {
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
    );
  }

  DropContent toContent(DateTime? unlockedAt) => DropContent(
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
