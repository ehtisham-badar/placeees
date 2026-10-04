import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'models.dart';
import 'trace_api.dart';

class LiveApi implements TraceApi {
  LiveApi(String baseUrl) : _base = Uri.parse(baseUrl);

  final Uri _base;
  final _client = http.Client();

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
        await _send('POST', '/v1/drops/$dropId/unlock', body: {'location': fix.toJson()}) as Map<String, dynamic>,
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
  }) async {
    String? mediaKey;
    if (photoJpeg != null) {
      final presign = await _send('POST', '/v1/media/presign', body: {'contentType': 'image/jpeg'}) as Map<String, dynamic>;
      final headers = (presign['headers'] as Map).cast<String, String>();
      final upload = await http.put(Uri.parse(presign['url'] as String), headers: headers, body: photoJpeg);
      if (upload.statusCode >= 300) throw const ApiError('upload_failed');
      mediaKey = presign['key'] as String;
    }
    final j = await _send('POST', '/v1/drops', body: {
      'type': type.name,
      'body': ?(body == null || body.isEmpty ? null : body),
      'mediaKey': ?mediaKey,
      'teaser': ?(teaser == null || teaser.isEmpty ? null : teaser),
      'isAnonymous': isAnonymous,
      'location': fix.toJson(),
    }) as Map<String, dynamic>;
    return j['id'] as String;
  }

  @override
  Future<Passport> passport() async {
    final j = await _send('GET', '/v1/me/passport') as Map<String, dynamic>;
    List<PassportEntry> list(String key) =>
        (j[key] as List).map((e) => PassportEntry.fromJson(e as Map<String, dynamic>)).toList();
    return Passport(unlocked: list('unlocked'), created: list('created'));
  }

  @override
  Future<void> reportDrop(String dropId, {String? reason}) =>
      _send('POST', '/v1/reports', body: {'targetType': 'drop', 'targetId': dropId, 'reason': ?reason});

  @override
  Future<void> blockAuthor(String dropId) => _send('POST', '/v1/drops/$dropId/block-author');
}
