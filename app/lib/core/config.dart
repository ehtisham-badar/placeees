/// Build-time configuration.
///
/// Run against a real backend with:
///   flutter run --dart-define=TRACE_API_URL=http://localhost:3000
/// Without it the app runs in demo mode with simulated drops around you.
class AppConfig {
  static const apiUrl = String.fromEnvironment('TRACE_API_URL');
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// A dark-styled raster tile URL (e.g. MapTiler or Stadia with your key) for production.
  /// When unset, standard OpenStreetMap tiles are darkened on the device (fine for development;
  /// OSM's tile policy does not allow heavy production use).
  static const mapTileUrl = String.fromEnvironment('MAP_TILE_URL');

  /// Dev only: in demo mode, skip sign-in and onboarding and open straight on the map.
  static const demoAutostart = bool.fromEnvironment('DEMO_AUTOSTART');

  /// Google Cloud project number for Play Integrity (Android). Unset = no integrity tokens.
  static const playCloudProjectNumber = String.fromEnvironment('PLAY_CLOUD_PROJECT_NUMBER');

  /// Firebase (Android push only). iOS push goes straight to APNs and needs none of this.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAndroidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty && firebaseAndroidAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;

  /// Local testing against a dev API: shows a name-only sign-in (the API needs ALLOW_DEV_LOGIN).
  static const devLogin = bool.fromEnvironment('DEV_LOGIN');

  /// Sent with dev sign-in when the API requires DEV_LOGIN_CODE (a dev login on a public server).
  static const devLoginCode = String.fromEnvironment('DEV_LOGIN_CODE');

  static bool get isDemo => apiUrl.isEmpty;
}
