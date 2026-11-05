import Flutter
import UIKit

/// iOS bootstrap for the static CPiOS LOK engine.
/// Requires LOK_HOME_IOS populated and podspec -filelist wiring.
public class OfficeViewerEngineLokPlugin: NSObject, FlutterPlugin {
  private var officePtr: Int = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "office_viewer_engine_lok/bootstrap",
      binaryMessenger: registrar.messenger())
    let instance = OfficeViewerEngineLokPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      do {
        let ptr = try Self.bootstrapOffice()
        officePtr = ptr
        result([
          "officePtr": ptr,
          "library": "lok-static",
          "platform": "ios",
        ])
      } catch {
        result(FlutterError(
          code: "init_failed",
          message: error.localizedDescription,
          details: nil))
      }
    case "isReady":
      result(officePtr != 0 && office_viewer_lok_ios_is_ready() != 0)
    case "officePtr":
      result(officePtr)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func bootstrapOffice() throws -> Int {
    // Static LOK uses NSBundle.mainBundle as $APP_DATA_DIR; the host Podfile
    // copies engine files to Runner.app root. Optional env override for CI.
    let resourcePath =
      ProcessInfo.processInfo.environment["LOK_IOS_RESOURCES"]
      ?? Bundle.main.bundlePath
    let services = (resourcePath as NSString)
      .appendingPathComponent("services.rdb")
    let appServices = (Bundle.main.bundlePath as NSString)
      .appendingPathComponent("services.rdb")
    guard FileManager.default.fileExists(atPath: services)
      || FileManager.default.fileExists(atPath: appServices) else {
      throw BridgeError.missingResources
    }
    let profile = try prepareUserProfile()
    let ptr = office_viewer_lok_ios_init(resourcePath, profile)
    if ptr == 0 {
      throw BridgeError.initFailed
    }
    return ptr
  }

  private static func prepareUserProfile() throws -> String {
    let bases = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)
    guard let base = bases.first else {
      throw BridgeError.profileDir
    }
    let dir = base.appendingPathComponent("office_viewer_lok", isDirectory: true)
    try FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  private enum BridgeError: LocalizedError {
    case missingResources
    case initFailed
    case profileDir

    var errorDescription: String? {
      switch self {
      case .missingResources:
        return """
          LOK iOS resources not found (services.rdb at app root). Run \
          tool/install_lok_home_ios.sh, pod install, and rebuild so the \
          Podfile copy phase packs LO data into Runner.app. See \
          example/spike/ios_feasibility.md.
          """
      case .initFailed:
        return "cok_init_2 failed — check device logs for ICU/bootstrap errors"
      case .profileDir:
        return "Could not create Application Support profile directory"
      }
    }
  }
}
