import 'dart:typed_data';

import 'conditions.dart';
import '../analytics.dart' show AppEvent;
import 'models.dart';
import 'signature.dart';
import 'social.dart';
import 'venue.dart';

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
  Future<User> clearHomeZone();

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
    String? circleId,
    bool isRelay = false,
    CaptureAngle? angle,
    Uint8List? voiceAac,
    List<double>? waveform,
  });

  /// The true point of a drop once you're within 100 m of it (compass, F-07).
  Future<NearHint> nearHint(String dropId, LocationFix fix);

  Future<Passport> passport();

  // Echoes (F-11)
  Future<List<Echo>> echoes(String dropId);
  Future<Echo> postEcho(String dropId, String body, LocationFix fix);

  // Trails (F-10)
  Future<String> createTrail(String title, List<({String dropId, String? clue})> stops);
  Future<Trail> trail(String trailId);

  // Circles (F-12)
  Future<List<Circle>> circles();
  Future<Circle> createCircle(String name);
  Future<Circle> joinCircle(String code);
  Future<Circle> circle(String circleId);
  Future<void> leaveCircle(String circleId);

  // Relays (F-13)
  Future<DateTime> pickUpRelay(String dropId, LocationFix fix);
  Future<double> dropRelay(String dropId, LocationFix fix, {String? note});
  Future<List<CarriedRelay>> carrying();
  Future<RelayJourney> relayJourney(String dropId);

  // Push (device tokens)
  Future<void> registerDevice(String token, String platform);
  Future<void> unregisterDevice(String token);

  // Metrics (§11)
  Future<void> track(List<AppEvent> events);

  // Venues (F-16)
  Future<Venue> venue(String code);

  // Then/Now (F-14)
  Future<List<NowPhoto>> nowPhotos(String dropId);
  Future<NowPhoto> postNowPhoto(String dropId, Uint8List jpeg, LocationFix fix, {double? heading, double? pitch});

  Future<void> reportDrop(String dropId, {String? reason});
  Future<void> blockAuthor(String dropId);
}
