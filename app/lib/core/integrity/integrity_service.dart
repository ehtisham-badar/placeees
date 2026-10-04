import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/models.dart';
import '../config.dart';

/// Signs location payloads so the server can tell a real app on a real device from a script (spec F-17).
/// iOS: App Attest assertion. Android: Play Integrity standard token. Failures never block a request;
/// the server decides what to do based on its INTEGRITY_MODE.
class IntegrityService {
  IntegrityService({required this.challenge, required this.register});

  /// Fetches a one-time attestation challenge from the server.
  final Future<String> Function() challenge;

  /// Sends a new key's attestation to the server.
  final Future<void> Function(String keyId, String attestation, String challenge) register;

  static const _channel = MethodChannel('app.trace/integrity');
  static const _storage = FlutterSecureStorage();
  static const _keyIdKey = 'trace.attestKeyId';

  String? _keyId;
  Future<String?>? _keySetup;
  Future<bool>? _androidSetup;

  /// The exact bytes both sides hash. Must match `locationClientData` on the server.
  static String clientData(LocationFix f) =>
      'trace-loc-v1|${f.lat.toStringAsFixed(6)}|${f.lng.toStringAsFixed(6)}|${f.accuracy.toStringAsFixed(1)}|${f.timestampWire}';

  /// Extra payload fields for this fix: platform plus assertion/keyId when available.
  Future<Map<String, Object>> sign(LocationFix fix) async {
    try {
      if (Platform.isIOS) return await _signIos(fix);
      if (Platform.isAndroid) return await _signAndroid(fix);
    } catch (_) {
      // Unsupported device, simulator, or the attestation service is down.
    }
    return {if (Platform.isIOS) 'platform': 'ios', if (Platform.isAndroid) 'platform': 'android'};
  }

  Future<Map<String, Object>> _signIos(LocationFix fix) async {
    final keyId = await (_keySetup ??= _ensureKey());
    if (keyId == null) return {'platform': 'ios'};
    final assertion = await _channel.invokeMethod<String>('generateAssertion', {'keyId': keyId, 'clientData': clientData(fix)});
    return {'platform': 'ios', 'keyId': keyId, 'assertion': ?assertion};
  }

  /// One App Attest key per install: generated, attested by Apple, registered with our server.
  Future<String?> _ensureKey() async {
    _keyId ??= await _storage.read(key: _keyIdKey);
    if (_keyId != null) return _keyId;
    if (await _channel.invokeMethod<bool>('isSupported') != true) return null;
    final keyId = await _channel.invokeMethod<String>('generateKey');
    if (keyId == null) return null;
    final c = await challenge();
    final attestation = await _channel.invokeMethod<String>('attestKey', {'keyId': keyId, 'challenge': c});
    if (attestation == null) return null;
    await register(keyId, attestation, c);
    await _storage.write(key: _keyIdKey, value: keyId);
    return _keyId = keyId;
  }

  Future<Map<String, Object>> _signAndroid(LocationFix fix) async {
    final project = int.tryParse(AppConfig.playCloudProjectNumber);
    if (project == null) return {'platform': 'android'};
    final ready = await (_androidSetup ??= _channel
        .invokeMethod<bool>('prepare', {'cloudProjectNumber': project})
        .then((v) => v == true)
        .catchError((_) => false));
    if (!ready) {
      _androidSetup = null; // try again next time
      return {'platform': 'android'};
    }
    final hash = sha256.convert(utf8.encode(clientData(fix))).toString();
    final token = await _channel.invokeMethod<String>('request', {'requestHash': hash});
    return {'platform': 'android', 'assertion': ?token};
  }
}
