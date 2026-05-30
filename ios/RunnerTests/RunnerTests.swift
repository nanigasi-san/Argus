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

}
