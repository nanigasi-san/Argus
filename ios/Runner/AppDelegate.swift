import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let alarmPlayer = IOSAlarmPlayer()
  private var alarmChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    UNUserNotificationCenter.current().delegate = self

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "argus/alarm",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleAlarmMethodCall(call, result: result)
      }
      alarmChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    alarmPlayer.stop()
    super.applicationWillTerminate(application)
  }

  private func handleAlarmMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "play":
      let arguments = call.arguments as? [String: Any]
      let volume = (arguments?["volume"] as? NSNumber)?.doubleValue ?? 1.0
      do {
        try alarmPlayer.play(volume: volume)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "alarm_play_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    case "stop":
      alarmPlayer.stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class IOSAlarmPlayer {
  private var player: AVAudioPlayer?

  func play(volume: Double) throws {
    stop()

    guard let soundURL = Bundle.main.url(forResource: "alarm", withExtension: "caf") else {
      throw IOSAlarmError.missingSoundResource
    }

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)

    let player = try AVAudioPlayer(contentsOf: soundURL)
    player.numberOfLoops = -1
    player.volume = Float(min(max(volume, 0), 1))
    player.prepareToPlay()
    guard player.play() else {
      throw IOSAlarmError.playbackFailed
    }
    self.player = player
  }

  func stop() {
    player?.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }
}

private enum IOSAlarmError: LocalizedError {
  case missingSoundResource
  case playbackFailed

  var errorDescription: String? {
    switch self {
    case .missingSoundResource:
      return "alarm.caf is missing from the iOS app bundle."
    case .playbackFailed:
      return "iOS could not start alarm playback."
    }
  }
}
