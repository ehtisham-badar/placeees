import CryptoKit
import DeviceCheck
import Flutter
import UIKit
import UserNotifications
import native_geofence

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Geofence events can wake the app in the background; give that engine the plugins too.
    NativeGeofencePlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "TraceIntegrity")?.messenger() {
      IntegrityChannel.register(messenger: messenger)
    }
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "TracePush")?.messenger() {
      PushChannel.shared.attach(messenger: messenger)
    }
  }

  // MARK: - Remote notifications (APNs)

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Handled here rather than forwarded: Firebase isn't configured on iOS.
    PushChannel.shared.deliver("onToken", deviceToken.map { String(format: "%02x", $0) }.joined())
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    PushChannel.shared.deliver("onError", error.localizedDescription)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show pushes as banners even while Trace is open; local notifications keep their plugin's handling.
    if notification.request.trigger is UNPushNotificationTrigger {
      completionHandler([.banner, .list, .sound])
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let request = response.notification.request
    if request.trigger is UNPushNotificationTrigger {
      let info = request.content.userInfo
      PushChannel.shared.deliver("onTap", ["dropId": info["dropId"] as? String ?? "", "kind": info["kind"] as? String ?? ""])
      completionHandler()
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }
}

/// APNs device tokens and notification taps for Dart. Buffers events that arrive before Dart listens
/// (e.g. the tap that launched the app).
final class PushChannel {
  static let shared = PushChannel()
  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pending: [(String, Any)] = []

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.trace/push", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        result(nil)
      case "ready":
        // Dart is listening: hand over anything that arrived early.
        self?.dartReady = true
        let early = self?.pending ?? []
        self?.pending.removeAll()
        for (method, args) in early { channel.invokeMethod(method, arguments: args) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func deliver(_ method: String, _ args: Any) {
    DispatchQueue.main.async {
      if self.dartReady, let channel = self.channel {
        channel.invokeMethod(method, arguments: args)
      } else {
        self.pending.append((method, args))
      }
    }
  }
}

/// App Attest for location payloads (spec F-17). The server verifies attestations and assertions.
enum IntegrityChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.trace/integrity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let service = DCAppAttestService.shared
      let args = call.arguments as? [String: Any] ?? [:]
      let reply: (Any?, Error?) -> Void = { value, error in
        DispatchQueue.main.async {
          if let error {
            result(FlutterError(code: "attest_error", message: error.localizedDescription, details: nil))
          } else {
            result(value)
          }
        }
      }

      switch call.method {
      case "isSupported":
        result(service.isSupported)
      case "generateKey":
        service.generateKey { keyId, error in reply(keyId, error) }
      case "attestKey":
        // The server hashes the same challenge string to build clientDataHash.
        guard let keyId = args["keyId"] as? String, let challenge = args["challenge"] as? String else {
          return result(FlutterError(code: "bad_args", message: nil, details: nil))
        }
        let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
        service.attestKey(keyId, clientDataHash: hash) { attestation, error in
          reply(attestation?.base64EncodedString(), error)
        }
      case "generateAssertion":
        guard let keyId = args["keyId"] as? String, let clientData = args["clientData"] as? String else {
          return result(FlutterError(code: "bad_args", message: nil, details: nil))
        }
        let hash = Data(SHA256.hash(data: Data(clientData.utf8)))
        service.generateAssertion(keyId, clientDataHash: hash) { assertion, error in
          reply(assertion?.base64EncodedString(), error)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
