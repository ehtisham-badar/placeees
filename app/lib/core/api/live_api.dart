import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../analytics.dart' show AppEvent;
import '../integrity/integrity_service.dart';
import 'api_error.dart';
import 'conditions.dart';
import 'models.dart';
import 'signature.dart';
import 'social.dart';
import 'venue.dart';
import 'trace_api.dart';

class LiveApi implements TraceApi {
  LiveApi(String baseUrl) : _base = Uri.parse(baseUrl) {
    integrity = IntegrityService(
      challenge: () async => ((await _send('POST', '/v1/attest/challenge')) as Map<String, dynamic>)['challenge'] as String,
      register: (keyId, attestation, challenge) => _send(
        'POST',
        '/v1/attest/register',
        body: {'keyId': keyId, 'attestation': attestation, 'challenge': challenge},
      ),
    );
  }

  final Uri _base;
  final _client = http.Client();
  late final IntegrityService integrity;

  /// A location payload with its integrity fields attached.
  Future<Map<String, dynamic>> _loc(LocationFix fix) async => {...fix.toJson(), ...await integrity.sign(fix)};

  @override
  String? token;

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = _base.replace(path: path, queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['accept'] = 'application/json'
      ..headers.addAll({if (token != null) 'authorization': 'Bearer $token'});
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw const ApiError('network');
    }

    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final code = decoded is Map ? decoded['error'] as String? : null;
      throw ApiError(code ?? 'http_${res.statusCode}', status: res.statusCode);
    }
    return decoded;
  }

  Future<AuthResult> _auth(String path, Map<String, dynamic> body) async {
    final j = await _send('POST', path, body: body) as Map<String, dynamic>;
    return AuthResult(j['token'] as String, User.fromJson(j['user'] as Map<String, dynamic>));
  }

  @override
  Future<AuthResult> signInWithApple(String identityToken) => _auth('/v1/auth/apple', {'identityToken': identityToken});

  @override
  Future<AuthResult> signInWithGoogle(String idToken) => _auth('/v1/auth/google', {'idToken': idToken});

  @override
  Future<AuthResult> signInDemo(String name) => _auth('/v1/auth/dev', {'name': name});

  @override
  Future<User> me() async => User.fromJson(await _send('GET', '/v1/me') as Map<String, dynamic>);

  @override
  Future<User> setHandle(String handle) async =>
      User.fromJson(await _send('PATCH', '/v1/me', body: {'handle': handle}) as Map<String, dynamic>);

  @override
  Future<bool> isHandleAvailable(String handle) async {
    final j = await _send('GET', '/v1/handles/${Uri.encodeComponent(handle)}/available') as Map<String, dynamic>;
    return j['available'] as bool;
  }

  @override
  Future<User> setHomeZone(double lat, double lng) async =>
      User.fromJson(await _send('PUT', '/v1/me/home-zone', body: {'lat': lat, 'lng': lng}) as Map<String, dynamic>);

  @override
  Future<List<NearbyDrop>> nearby(double lat, double lng) async {
    final j = await _send('GET', '/v1/drops/nearby', query: {'lat': '$lat', 'lng': '$lng'}) as Map<String, dynamic>;
    return (j['drops'] as List).map((d) => NearbyDrop.fromJson(d as Map<String, dynamic>)).toList();
  }

  @override
  Future<DropContent> unlock(String dropId, LocationFix fix) async => DropContent.fromJson(
        await _send('POST', '/v1/drops/$dropId/unlock', body: {'location': await _loc(fix)}) as Map<String, dynamic>,
      );

  @override
  Future<DropContent> drop(String dropId) async =>
      DropContent.fromJson(await _send('GET', '/v1/drops/$dropId') as Map<String, dynamic>);

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
  }) async {
    final mediaKey = photoJpeg == null ? null : await _upload(photoJpeg);
    final j = await _send('POST', '/v1/drops', body: {
      'type': type.wire,
      'body': ?(body == null || body.isEmpty ? null : body),
      'mediaKey': ?mediaKey,
      'teaser': ?(teaser == null || teaser.isEmpty ? null : teaser),
      'isAnonymous': isAnonymous,
      'location': await _loc(fix),
      if (conditions.isNotEmpty) ...{
        'conditions': {'all': [for (final c in conditions) c.toJson()]},
        'revealConditions': revealConditions,
      },
      if (unlockAt != null) 'unlockAt': unlockAt.toUtc().toIso8601String(),
      if (recipientHandles.isNotEmpty) 'recipientHandles': recipientHandles,
      'circleId': ?circleId,
      if (isRelay) 'isRelay': true,
      if (angle != null) ...{'captureHeading': angle.heading, 'capturePitch': angle.pitch},
    }) as Map<String, dynamic>;
    return j['id'] as String;
  }

  @override
  Future<NearHint> nearHint(String dropId, LocationFix fix) async => NearHint.fromJson(
        await _send('POST', '/v1/drops/$dropId/near-hint', body: {'location': await _loc(fix)}) as Map<String, dynamic>,
      );

  @override
  Future<Passport> passport() async {
    final j = await _send('GET', '/v1/me/passport') as Map<String, dynamic>;
    List<PassportEntry> list(String key) =>
        (j[key] as List).map((e) => PassportEntry.fromJson(e as Map<String, dynamic>)).toList();
    return Passport(
      unlocked: list('unlocked'),
      created: list('created'),
      stamps: [for (final s in (j['stamps'] as List?) ?? const []) Stamp.fromJson(s as Map<String, dynamic>)],
    );
  }

  @override
  Future<List<Echo>> echoes(String dropId) async {
    final j = await _send('GET', '/v1/drops/$dropId/echoes') as Map<String, dynamic>;
    return [for (final e in j['echoes'] as List) Echo.fromJson(e as Map<String, dynamic>)];
  }

  @override
  Future<Echo> postEcho(String dropId, String body, LocationFix fix) async {
    final j = await _send('POST', '/v1/drops/$dropId/echoes', body: {'body': body, 'location': await _loc(fix)})
        as Map<String, dynamic>;
    return Echo(id: j['id'] as String, body: body, createdAt: DateTime.parse(j['createdAt'] as String), mine: true, pending: true);
  }

  @override
  Future<String> createTrail(String title, List<({String dropId, String? clue})> stops) async {
    final j = await _send('POST', '/v1/trails', body: {
      'title': title,
      'stops': [
        for (final s in stops) {'dropId': s.dropId, if (s.clue != null && s.clue!.isNotEmpty) 'clue': s.clue},
      ],
    }) as Map<String, dynamic>;
    return j['id'] as String;
  }

  @override
  Future<Trail> trail(String trailId) async =>
      Trail.fromJson(await _send('GET', '/v1/trails/$trailId') as Map<String, dynamic>);

  @override
  Future<List<Circle>> circles() async {
    final j = await _send('GET', '/v1/circles') as Map<String, dynamic>;
    return [for (final c in j['circles'] as List) Circle.fromJson(c as Map<String, dynamic>)];
  }

  @override
  Future<Circle> createCircle(String name) async =>
      Circle.fromJson(await _send('POST', '/v1/circles', body: {'name': name}) as Map<String, dynamic>);

  @override
  Future<Circle> joinCircle(String code) async =>
      Circle.fromJson(await _send('POST', '/v1/circles/join', body: {'code': code}) as Map<String, dynamic>);

  @override
  Future<Circle> circle(String circleId) async =>
      Circle.fromJson(await _send('GET', '/v1/circles/$circleId') as Map<String, dynamic>);

  @override
  Future<void> leaveCircle(String circleId) => _send('POST', '/v1/circles/$circleId/leave');

  /// Uploads a JPEG through a pre-signed URL and returns its media key.
  Future<String> _upload(Uint8List jpeg) async {
    final presign = await _send('POST', '/v1/media/presign', body: {'contentType': 'image/jpeg'}) as Map<String, dynamic>;
    final headers = (presign['headers'] as Map).cast<String, String>();
    final upload = await http.put(Uri.parse(presign['url'] as String), headers: headers, body: jpeg);
    if (upload.statusCode >= 300) throw const ApiError('upload_failed');
    return presign['key'] as String;
  }

  @override
  Future<DateTime> pickUpRelay(String dropId, LocationFix fix) async {
    final j = await _send('POST', '/v1/relays/$dropId/pickup', body: {'location': await _loc(fix)}) as Map<String, dynamic>;
    return DateTime.parse(j['deadlineAt'] as String);
  }

  @override
  Future<double> dropRelay(String dropId, LocationFix fix, {String? note}) async {
    final j = await _send('POST', '/v1/relays/$dropId/drop', body: {
      'location': await _loc(fix),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }) as Map<String, dynamic>;
    return (j['distanceM'] as num).toDouble();
  }

  @override
  Future<List<CarriedRelay>> carrying() async {
    final j = await _send('GET', '/v1/relays/carrying') as Map<String, dynamic>;
    return [for (final r in j['relays'] as List) CarriedRelay.fromJson(r as Map<String, dynamic>)];
  }

  @override
  Future<RelayJourney> relayJourney(String dropId) async =>
      RelayJourney.fromJson(await _send('GET', '/v1/relays/$dropId/journey') as Map<String, dynamic>);

  @override
  Future<void> registerDevice(String token, String platform) =>
      _send('POST', '/v1/devices', body: {'token': token, 'platform': platform});

  @override
  Future<void> unregisterDevice(String token) => _send('DELETE', '/v1/devices/${Uri.encodeComponent(token)}');

  @override
  Future<void> track(List<AppEvent> events) async {
    if (token == null || events.isEmpty) return;
    await _send('POST', '/v1/events', body: {
      'events': [
        for (final e in events) {'name': e.name, 'at': e.at.toUtc().toIso8601String(), 'props': ?e.props},
      ],
    });
  }

  @override
  Future<Venue> venue(String code) async =>
      Venue.fromJson(await _send('GET', '/v1/venues/${Uri.encodeComponent(code)}') as Map<String, dynamic>);

  @override
  Future<List<NowPhoto>> nowPhotos(String dropId) async {
    final j = await _send('GET', '/v1/drops/$dropId/now-photos') as Map<String, dynamic>;
    return [for (final p in j['photos'] as List) NowPhoto.fromJson(p as Map<String, dynamic>)];
  }

  @override
  Future<NowPhoto> postNowPhoto(String dropId, Uint8List jpeg, LocationFix fix, {double? heading, double? pitch}) async {
    final key = await _upload(jpeg);
    final j = await _send('POST', '/v1/drops/$dropId/now-photos', body: {
      'mediaKey': key,
      'location': await _loc(fix),
      'heading': ?heading,
      'pitch': ?pitch,
    }) as Map<String, dynamic>;
    return NowPhoto(id: j['id'] as String, bytes: jpeg, createdAt: DateTime.parse(j['createdAt'] as String), mine: true, pending: true);
  }

  @override
  Future<void> reportDrop(String dropId, {String? reason}) =>
      _send('POST', '/v1/reports', body: {'targetType': 'drop', 'targetId': dropId, 'reason': ?reason});

  @override
  Future<void> blockAuthor(String dropId) => _send('POST', '/v1/drops/$dropId/block-author');
}
