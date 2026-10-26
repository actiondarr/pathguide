import Flutter
@testable import Runner
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testNavigationPluginAcceptsFlutterDelegateCalls() {
    let plugin: FlutterPlugin = NavigationPlugin(messenger: NavigationTestMessenger())
    // Flutter's registrar dispatches this Objective-C selector, rather than a
    // Swift-only helper. A missing implementation aborts the app on first use.
    guard plugin.responds(to: NSSelectorFromString("handleMethodCall:result:")) else {
      XCTFail("NavigationPlugin must implement FlutterPlugin's method-call selector")
      return
    }
    for method in ["cancelRoute", "cancelSearch"] {
      var replied = false
      plugin.handle?(FlutterMethodCall(methodName: method, arguments: nil), result: { value in
        replied = true
        XCTAssertNil(value)
      })
      XCTAssertTrue(replied, "\(method) must reply through FlutterPlugin dispatch")
    }
    var failure: FlutterError?
    plugin.handle?(FlutterMethodCall(methodName: "searchPlaces", arguments: ["query": ""]), result: { value in
      failure = value as? FlutterError
    })
    XCTAssertEqual(failure?.code, "invalid_argument")
  }

  func testPlanarModelReceivesSeparateRGBChannels() throws {
    let layout = try IOSModelInputLayout(shape: [1, 3, 2, 2])
    XCTAssertEqual(layout.side, 2)
    XCTAssertEqual(try layout.packRGB([1,2,3,4,5,6,7,8,9,10,11,12]),
                   [1,4,7,10,2,5,8,11,3,6,9,12])
    let legacy = try IOSModelInputLayout(shape: [1, 2, 2, 3])
    XCTAssertEqual(try legacy.packRGB([1,2,3,4,5,6,7,8,9,10,11,12]),
                   [1,2,3,4,5,6,7,8,9,10,11,12])
    XCTAssertThrowsError(try IOSModelInputLayout(shape: [1, 3, 640, 320]))
    XCTAssertThrowsError(try layout.packRGB([1,2,3]))
  }

  func testPortraitRotationMapping() {
    let size = IOSFramePreprocessor.rotatedSize(width: 1280, height: 720, degrees: 90)
    XCTAssertEqual(size.0, 720)
    XCTAssertEqual(size.1, 1280)
    let topLeft = IOSFramePreprocessor.sourcePoint(
      uprightX: 0, uprightY: 0, rawWidth: 1280, rawHeight: 720, degrees: 90)
    XCTAssertEqual(topLeft.0, 0)
    XCTAssertEqual(topLeft.1, 719)
  }

  func testDecoderMapsClassAndSuppressesOverlap() {
    // channels-first [cx, cy, width, height, score], one anchor and one class.
    let values: [Float32] = [0.5, 0.5, 0.2, 0.4, 0.9]
    let decoded = IOSYoloDecoder.decode(
      values: values,
      anchors: 1,
      classes: 1,
      transposed: false,
      threshold: 0.3,
      inputSize: 416,
      sourceWidth: 416,
      sourceHeight: 416,
      scaledWidth: 416,
      scaledHeight: 416,
      padX: 0,
      padY: 0,
      classIds: [7]
    )
    XCTAssertEqual(decoded.detections.count, 1)
    XCTAssertEqual(decoded.detections.first?.id, 7)
    XCTAssertEqual(decoded.detections.first?.score ?? 0, 0.9, accuracy: 0.0001)
    let doubled = decoded.detections + decoded.detections
    XCTAssertEqual(
      IOSYoloDecoder.nonMaximumSuppression(doubled, iouThreshold: 0.45, maximum: 100).count,
      1
    )
  }

  func testBundledModelShape() throws {
    let modelURL = Bundle.main.bundleURL
      .appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/models/detector.tflite")
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path), "Flutter model asset missing")
    let interpreter = try TFLiteModelRunner(modelPath: modelURL.path, threadCount: 4)
    XCTAssertEqual(interpreter.inputShape, [1, 3, 640, 640])
    XCTAssertEqual(interpreter.outputShape, [1, 13, 8400])
    let output = try interpreter.invoke(input: [Float32](repeating: 114.0 / 255.0, count: 640 * 640 * 3))
    XCTAssertEqual(output.count, 13 * 8400)
    XCTAssertTrue(output.allSatisfy { $0.isFinite })
    XCTAssertTrue(output.dropFirst(4 * 8400).allSatisfy { $0 >= 0 && $0 <= 1 })
  }

}

private final class NavigationTestMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection { 1 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
