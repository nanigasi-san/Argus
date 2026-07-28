import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testAlarmSoundIsBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "alarm", withExtension: "caf"))
  }

  func testRequiredBackgroundModesAreEnabled() {
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    XCTAssertEqual(Set(modes ?? []), Set(["audio", "location"]))
  }

  func testLocationPurposeStringsExplainBackgroundMonitoring() {
    let whenInUse = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
    let always = Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") as? String

    XCTAssertTrue(whenInUse?.contains("競技エリア") == true)
    XCTAssertTrue(always?.contains("画面ロック中") == true)
    XCTAssertTrue(always?.contains("離脱を検知") == true)
  }

  func testSceneLifecycleIsConfigured() {
    let manifest = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
    XCTAssertEqual(manifest?["UIApplicationSupportsMultipleScenes"] as? Bool, false)

    let configurations = manifest?["UISceneConfigurations"] as? [String: Any]
    let appScenes = configurations?["UIWindowSceneSessionRoleApplication"] as? [[String: Any]]
    let scene = appScenes?.first

    XCTAssertEqual(scene?["UISceneClassName"] as? String, "UIWindowScene")
    XCTAssertEqual(scene?["UISceneDelegateClassName"] as? String, "FlutterSceneDelegate")
    XCTAssertEqual(scene?["UISceneStoryboardFile"] as? String, "Main")
  }

}
