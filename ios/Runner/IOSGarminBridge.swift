import ConnectIQ
import Flutter
import Foundation

/// The iOS SDK talks to the watch over BLE. Garmin Connect is used to authorize devices.
final class IOSGarminBridge: NSObject, IQDeviceEventDelegate, IQAppMessageDelegate {
  private static let channelName = "argus/garmin"
  private static let callbackScheme = "argus-ciq-a86f7de8"
  private static let appID = "a86f7de8-169f-4a3e-8c38-763cdd2e4d55"
  private static let cachedDevicesKey = "argus.garmin.authorizedDevices.v1"

  private let sdk = ConnectIQ.sharedInstance()
  private var initialized = false
  private var channel: FlutterMethodChannel?
  private var devices: [String: IQDevice] = [:]
  private var readyDevices = Set<String>()
  private var pendingResult: FlutterResult?
  private var pendingRequest: [String: Any]?
  private var pendingDevice: IQDevice?
  private var pendingApp: IQApp?
  private var timeout: DispatchWorkItem?
  private var sentAt: TimeInterval = 0

  func initialize() {
    if initialized { return }
    initialized = true
    sdk.initialize(withUrlScheme: Self.callbackScheme, uiOverrideDelegate: nil)
    restoreDevices()
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  @discardableResult
  func handleDeviceSelection(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == Self.callbackScheme else { return false }
    initialize()
    // The SDK's selector is stable across its ObjC releases; use it here because
    // the Swift importer has changed the URL argument label between releases.
    guard let response = sdk.perform(
      NSSelectorFromString("parseDeviceSelectionResponseFromURL:"), with: url
    )?.takeUnretainedValue() as? [IQDevice] else { return false }
    replaceDevices(response)
    channel?.invokeMethod("devicesChanged", arguments: nil)
    return true
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    initialize()
    switch call.method {
    case "getDevices":
      result(devices.values.sorted { $0.friendlyName < $1.friendlyName }.map { device in
        [
          "id": device.uuid.uuidString,
          "name": device.friendlyName,
          "connected": isReady(device),
        ] as [String: Any]
      })
    case "selectDevices":
      sdk.showConnectIQDeviceSelection()
      result(nil)
    case "sendCourse":
      sendCourse(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func replaceDevices(_ selected: [IQDevice]) {
    if pendingResult != nil {
      fail("device_selection_changed", "GARMINの共有設定が変わりました。再送してください。")
    }
    sdk.unregisterForAllDeviceEvents(self)
    readyDevices.removeAll()
    devices.removeAll()
    // A new selection revokes every device that was authorized previously.
    for device in selected {
      devices[device.uuid.uuidString] = device
      sdk.registerForDeviceEvents(device, delegate: self)
    }
    let values: [[String: String]] = selected.map { device in
      [
        "id": device.uuid.uuidString,
        "model": device.modelName,
        "name": device.friendlyName,
        "partNumber": device.partNumber ?? "",
      ]
    }
    UserDefaults.standard.set(values, forKey: Self.cachedDevicesKey)
  }

  private func restoreDevices() {
    let values = UserDefaults.standard.array(forKey: Self.cachedDevicesKey) as? [[String: String]] ?? []
    let restored: [IQDevice] = values.compactMap { value in
      guard let id = value["id"], let uuid = NSUUID(uuidString: id),
            let model = value["model"], let name = value["name"] else { return nil }
      return IQDevice.device(
        withId: uuid, modelName: model, friendlyName: name,
        partNumber: value["partNumber"] ?? ""
      )
    }
    replaceDevices(restored)
  }

  private func isReady(_ device: IQDevice) -> Bool {
    readyDevices.contains(device.uuid.uuidString)
      && sdk.getDeviceStatus(device).rawValue == 4 // IQDeviceStatus_Connected
  }

  func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
    DispatchQueue.main.async {
      if status.rawValue != 4 { self.readyDevices.remove(device.uuid.uuidString) }
      self.channel?.invokeMethod("devicesChanged", arguments: nil)
    }
  }

  func deviceCharacteristicsDiscovered(_ device: IQDevice) {
    DispatchQueue.main.async {
      self.readyDevices.insert(device.uuid.uuidString)
      self.channel?.invokeMethod("devicesChanged", arguments: nil)
    }
  }

  private func sendCourse(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "transfer_busy", message: "別の転送を実行中です。", details: nil))
      return
    }
    guard var request = call.arguments as? [String: Any],
          let id = request.removeValue(forKey: "deviceId") as? String,
          let device = devices[id] else {
      result(FlutterError(code: "device_unknown", message: "送信先GARMINを選び直してください。", details: nil))
      return
    }
    guard isReady(device) else {
      result(FlutterError(code: "device_disconnected", message: "選択したGARMINが接続されていません。", details: nil))
      return
    }
    guard let uuid = NSUUID(uuidString: Self.appID) else {
      result(FlutterError(code: "app_id", message: "Data Field IDが不正です。", details: nil))
      return
    }
    request["requestId"] = UUID().uuidString
    let app = IQApp.app(withUUID: uuid, storeUuid: uuid, device: device)
    pendingResult = result
    pendingRequest = request
    pendingDevice = device
    pendingApp = app
    sentAt = ProcessInfo.processInfo.systemUptime
    scheduleTimeout(seconds: 15, code: "app_query_timeout", message: "GARMINのData Field確認が15秒以内に終わりませんでした。")
    sdk.getAppStatus(app) { [weak self] status in
      DispatchQueue.main.async {
        guard let self = self, self.pendingResult != nil,
              self.pendingRequest?["requestId"] as? String == request["requestId"] as? String else { return }
        guard let status = status else {
          self.fail("app_query_timeout", "GARMINのData Field状態を取得できませんでした。再検索してください。")
          return
        }
        guard status.isInstalled else {
          self.fail("app_not_installed", "ARGUS Data FieldがGARMINにインストールされていません。")
          return
        }
        self.sdk.registerForAppMessages(app, delegate: self)
        self.scheduleTimeout(seconds: 30, code: "ack_timeout", message: "保存・照合ACKが30秒以内に届きませんでした。再送してください。")
        self.sdk.sendMessage(request, toApp: app, progress: { _, _ in }, completion: { [weak self] sendResult in
          DispatchQueue.main.async {
            guard let self = self, self.pendingResult != nil else { return }
            // Delivery alone is not success. Only a matching storage ACK completes a transfer.
            if sendResult.rawValue != 0 {
              self.fail("send_failed", "GARMINへの送信に失敗しました: \(NSStringFromSendMessageResult(sendResult))")
            }
          }
        })
      }
    }
  }

  func receivedMessage(_ message: Any, fromApp app: IQApp) {
    DispatchQueue.main.async { self.receive(message, from: app) }
  }

  private func receive(_ message: Any, from app: IQApp) {
    guard let pendingApp = pendingApp,
          app.uuid == pendingApp.uuid,
          app.device.uuid == pendingApp.device.uuid,
          let request = pendingRequest else { return }
    if let parts = message as? [Any] {
      for part in parts { receive(part, from: app) }
      return
    }
    guard let ack = message as? [String: Any],
          let requestId = ack["requestId"] as? String,
          requestId == request["requestId"] as? String else { return }
    let matches = (ack["type"] as? String) == "ack"
      && (ack["receiver"] as? String) == "background"
      && (ack["saved"] as? Bool) == true
      && number(ack["v"]) == 1
      && (ack["courseId"] as? String) == request["courseId"] as? String
      && (ack["displayName"] as? String) == request["displayName"] as? String
      && (ack["checksum"] as? String) == request["checksum"] as? String
      && number(ack["bytes"]) == number(request["bytes"])
      && number(ack["vertexCount"]) == number(request["vertexCount"])
      && number(ack["armedUntil"]) == number(request["armedUntil"])
    guard matches else {
      fail("ack_mismatch", "GARMINの保存・照合結果が一致しません: \(ack["error"] ?? "unknown")")
      return
    }
    let reply = pendingResult
    let name = pendingDevice?.friendlyName ?? "GARMIN"
    let elapsed = Int((ProcessInfo.processInfo.systemUptime - sentAt) * 1000)
    clearTransfer()
    reply?(["deviceName": name, "elapsedMs": elapsed])
  }

  private func number(_ value: Any?) -> Int64? {
    (value as? NSNumber)?.int64Value
  }

  private func scheduleTimeout(seconds: TimeInterval, code: String, message: String) {
    timeout?.cancel()
    let task = DispatchWorkItem { [weak self] in self?.fail(code, message) }
    timeout = task
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
  }

  private func fail(_ code: String, _ message: String) {
    guard let reply = pendingResult else { return }
    clearTransfer()
    reply(FlutterError(code: code, message: message, details: nil))
  }

  private func clearTransfer() {
    timeout?.cancel()
    timeout = nil
    if let app = pendingApp { sdk.unregisterForAppMessages(app, delegate: self) }
    pendingResult = nil
    pendingRequest = nil
    pendingDevice = nil
    pendingApp = nil
  }
}
