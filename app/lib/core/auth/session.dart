import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_error.dart';
import '../api/models.dart';
import '../api/trace_api.dart';
import '../config.dart';

enum SessionStage { loading, signedOut, onboarding, ready }

enum OnboardingStep { handle, location, homeZone }

class Session extends ChangeNotifier {
  Session(this.api);

  final TraceApi api;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'trace.token';
  static const _onboardedKey = 'trace.onboarded';

  SessionStage stage = SessionStage.loading;
  OnboardingStep step = OnboardingStep.handle;
  User? user;

  /// Demo mode keeps nothing on the device: its backend lives in memory.
  bool get _persist => !AppConfig.isDemo;

  Future<void> restore() async {
    if (!_persist) {
      if (!AppConfig.demoAutostart) return _go(SessionStage.signedOut);
      final result = await api.signInDemo('demo');
      api.token = result.token;
      user = await api.setHandle('explorer');
      return _go(SessionStage.ready);
    }
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return _go(SessionStage.signedOut);
      api.token = token;
      user = await api.me();
      final onboarded = await _storage.read(key: _onboardedKey) == 'true';
      _route(onboarded: onboarded);
    } on ApiError catch (e) {
      if (e.code == 'unauthorized') await signOut();
      _go(SessionStage.signedOut);
    } catch (_) {
      _go(SessionStage.signedOut);
    }
  }

  Future<void> completeSignIn(AuthResult result) async {
    api.token = result.token;
    user = result.user;
    if (_persist) await _storage.write(key: _tokenKey, value: result.token);
    final onboarded = _persist && await _storage.read(key: _onboardedKey) == 'true';
    _route(onboarded: onboarded);
  }

  Future<void> chooseHandle(String handle) async {
    user = await api.setHandle(handle);
    advance(OnboardingStep.location);
  }

  void advance(OnboardingStep next) {
    step = next;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    if (_persist) await _storage.write(key: _onboardedKey, value: 'true');
    _go(SessionStage.ready);
  }

  Future<void> signOut() async {
    api.token = null;
    user = null;
    if (_persist) await _storage.deleteAll();
    step = OnboardingStep.handle;
    _go(SessionStage.signedOut);
  }

  void _route({required bool onboarded}) {
    if (user?.handle == null) {
      step = OnboardingStep.handle;
      _go(SessionStage.onboarding);
    } else if (!onboarded) {
      step = OnboardingStep.location;
      _go(SessionStage.onboarding);
    } else {
      _go(SessionStage.ready);
    }
  }

  void _go(SessionStage s) {
    stage = s;
    notifyListeners();
  }
}
