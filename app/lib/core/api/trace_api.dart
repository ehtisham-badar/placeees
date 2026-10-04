import 'dart:typed_data';

import 'conditions.dart';
import 'models.dart';

/// Everything the app needs from the backend. Implemented by [LiveApi] and [DemoApi].
abstract class TraceApi {
  set token(String? value);

  Future<AuthResult> signInWithApple(String identityToken);
  Future<AuthResult> signInWithGoogle(String idToken);
  Future<AuthResult> signInDemo(String name);

  Future<User> me();
  Future<User> setHandle(String handle);
  Future<bool> isHandleAvailable(String handle);
  Future<User> setHomeZone(double lat, double lng);

  Future<List<NearbyDrop>> nearby(double lat, double lng);
  Future<DropContent> unlock(String dropId, LocationFix fix);
  Future<DropContent> drop(String dropId);

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
  });

  /// The true point of a drop once you're within 100 m of it (compass, F-07).
  Future<NearHint> nearHint(String dropId, LocationFix fix);

  Future<Passport> passport();

  Future<void> reportDrop(String dropId, {String? reason});
  Future<void> blockAuthor(String dropId);
}
