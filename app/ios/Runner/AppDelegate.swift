import CryptoKit
import DeviceCheck
import Flutter
import UIKit
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "TraceIntegrity")?.messenger() {
      IntegrityChannel.register(messenger: messenger)
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
