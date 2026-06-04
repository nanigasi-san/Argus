import AVFoundation
import AudioToolbox
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let alarmPlayer = IOSAlarmPlayer()
  private let vibrationPlayer = IOSVibrationPlayer()
  private var alarmChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "argus/alarm",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleAlarmMethodCall(call, result: result)
    }
    alarmChannel = channel
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    alarmPlayer.stop()
    vibrationPlayer.stop()
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
    case "startVibration":
      vibrationPlayer.start()
      result(nil)
    case "stopVibration":
      vibrationPlayer.stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class IOSAlarmPlayer: NSObject {
  private var player: AVAudioPlayer?
  private var isAlarming = false
  private var lastVolume = 1.0

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func play(volume: Double) throws {
    stop()
    lastVolume = min(max(volume, 0), 1)
    isAlarming = true

    do {
      try startPlayback(volume: lastVolume)
    } catch {
      isAlarming = false
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
      throw error
    }
  }

  func stop() {
    isAlarming = false
    player?.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  private func startPlayback(volume: Double) throws {
    player?.stop()
    player = nil

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

  @objc private func handleAudioSessionInterruption(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else {
      return
    }

    switch type {
    case .began:
      player?.pause()
    case .ended:
      guard isAlarming else {
        return
      }
      let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      guard options.contains(.shouldResume) else {
        return
      }
      do {
        try startPlayback(volume: lastVolume)
      } catch {
        isAlarming = false
        player = nil
        try? AVAudioSession.sharedInstance().setActive(
          false,
          options: .notifyOthersOnDeactivation
        )
      }
    @unknown default:
      return
    }
  }
}

private final class IOSVibrationPlayer {
  private var timer: Timer?

  func start() {
    if timer != nil {
      return
    }

    vibrate()
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.vibrate()
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func vibrate() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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
