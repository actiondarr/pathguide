import ARKit
import AVFoundation
import Flutter
import SceneKit
import UIKit

/// One explicit, local-only measurement session. No image/depth/pose is saved.
final class DepthPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, ARSessionDelegate {
  static weak var active: DepthPlugin?
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let session = ARSession()
  private weak var preview: ARSCNView?
  private var sink: FlutterEventSink?
  private var running = false
  private var generation = 0
  private var lastSent = -Double.infinity
  private var previousPose: simd_float4x4?
  private var token = ""
  private var startedAt = Double.infinity

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "hk.pathguide/depth", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "hk.pathguide/depth/frames", binaryMessenger: messenger)
    super.init()
    Self.active = self
    session.delegate = self
    // All state, view geometry and delegate calls belong to the main queue.
    session.delegateQueue = .main
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    events.setStreamHandler(self)
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIApplication.willResignActiveNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = DepthPlugin(messenger: registrar.messenger())
    registrar.register(DepthPreviewFactory(plugin: plugin), withId: "hk.pathguide/depth/preview")
  }

  func attach(_ view: ARSCNView) {
    preview = view
    view.session = session
    view.scene = SCNScene()
    view.automaticallyUpdatesLighting = false
    view.isAccessibilityElement = false
    view.accessibilityElementsHidden = true
  }

  func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }
  func onCancel(withArguments _: Any?) -> FlutterError? {
    stop()
    sink = nil
    return nil
  }

  @objc private func background() {
    emit("paused")
    stop()
  }

  /// Also called before the other native camera stacks start.
  func stop() {
    if running { emit("paused") }
    generation += 1
    running = false
    previousPose = nil
    session.pause()
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "stop":
      stop()
      result(nil)
    case "start":
      guard let args = call.arguments as? [String: Any], let id = args["session"] as? String,
        !id.isEmpty else {
        result(FlutterError(code: "bad_session", message: "Missing session", details: nil)); return
      }
      stop()
      token = id
      guard ARWorldTrackingConfiguration.isSupported,
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
        result(["status": "unsupported"]); return
      }
      let expected = generation
      func begin(_ granted: Bool) {
        guard expected == self.generation,
          UIApplication.shared.applicationState == .active else {
          result(["status": "paused"]); return
        }
        guard granted else { result(["status": "permission"]); return }
        func run() {
          guard expected == self.generation,
            UIApplication.shared.applicationState == .active else {
            result(["status": "paused"]); return
          }
          let config = ARWorldTrackingConfiguration()
          config.frameSemantics = .sceneDepth
          config.worldAlignment = .gravity
          self.running = true
          self.lastSent = -Double.infinity
          self.startedAt = ProcessInfo.processInfo.systemUptime
          self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
          result(["status": "running"])
        }
        // Await AVCapture shutdown before ARKit takes the rear camera.
        if let vision = VisionPlugin.active { vision.release { _ in run() } }
        else { run() }
      }
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: begin(true)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async { begin(granted) }
        }
      default: begin(false)
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func emit(_ status: String, frame: ARFrame? = nil, patch: DepthPatch? = nil) {
    var value: [String: Any] = ["session": token, "status": status]
    if let frame {
      value["timestamp"] = frame.timestamp
      value["ageMs"] = max(0, (ProcessInfo.processInfo.systemUptime - frame.timestamp) * 1000)
    }
    if let patch {
      value["rangeM"] = patch.range
      value["planeZM"] = patch.z
      value["accepted"] = patch.accepted
      value["total"] = patch.total
      value["spreadM"] = patch.spread
    }
    sink?(value)
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard running, frame.timestamp >= startedAt, frame.timestamp - lastSent >= 0.12 else { return }
    lastSent = frame.timestamp
    guard ProcessInfo.processInfo.systemUptime - frame.timestamp <= 0.35 else {
      previousPose = nil
      emit("stale", frame: frame); return
    }
    guard case .normal = frame.camera.trackingState else {
      previousPose = nil
      emit("tracking", frame: frame); return
    }
    let pose = frame.camera.transform
    let old = previousPose
    previousPose = pose
    guard let old else { emit("moving", frame: frame); return }
    let moved = simd_distance(SIMD3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z),
      SIMD3(old.columns.3.x, old.columns.3.y, old.columns.3.z))
    let rotation = simd_mul(simd_transpose(simd_float3x3(old)), simd_float3x3(pose))
    let cosine = max(-1, min(1, (rotation.columns.0.x + rotation.columns.1.y + rotation.columns.2.z - 1) / 2))
    guard moved <= 0.025, acos(cosine) <= 0.04 else {
      emit("moving", frame: frame); return
    }
    guard let view = preview, view.bounds.width > 0, view.bounds.height > 0,
      let orientation = view.window?.windowScene?.interfaceOrientation,
      let depth = frame.sceneDepth, let confidence = depth.confidenceMap else {
      emit("unavailable", frame: frame); return
    }
    // The same ARFrame supplies view mapping, RGB, intrinsics, depth and pose.
    let inverse = frame.displayTransform(for: orientation, viewportSize: view.bounds.size).inverted()
    let point = CGPoint(x: 0.5, y: 0.5).applying(inverse)
    let buffer = depth.depthMap
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32,
      CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else {
      emit("unavailable", frame: frame); return
    }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    guard CVPixelBufferGetWidth(confidence) == w, CVPixelBufferGetHeight(confidence) == h,
      point.x.isFinite, point.y.isFinite, point.x >= 0, point.x <= 1,
      point.y >= 0, point.y <= 1 else { emit("unavailable", frame: frame); return }
    let x = Int(point.x * CGFloat(w)), y = Int(point.y * CGFloat(h))
    guard x >= 2, y >= 2, x + 2 < w, y + 2 < h else { emit("unavailable", frame: frame); return }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    CVPixelBufferLockBaseAddress(confidence, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
      CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }
    guard let raw = CVPixelBufferGetBaseAddress(buffer),
      let conf = CVPixelBufferGetBaseAddress(confidence) else { emit("unavailable", frame: frame); return }
    let k = frame.camera.intrinsics
    let sx = Double(w) / Double(frame.camera.imageResolution.width)
    let sy = Double(h) / Double(frame.camera.imageResolution.height)
    let fx = Double(k.columns.0.x) * sx, fy = Double(k.columns.1.y) * sy
    let cx = Double(k.columns.2.x) * sx, cy = Double(k.columns.2.y) * sy
    guard fx > 0, fy > 0 else { emit("unavailable", frame: frame); return }
    var pixels: [DepthPixel] = []
    for row in (y - 2)...(y + 2) {
      let depths = raw.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float32.self)
      let confidences = conf.advanced(by: row * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
      for col in (x - 2)...(x + 2) {
        pixels.append(DepthPixel(z: Double(depths[col]), confidence: confidences[col],
          rayX: (Double(col) - cx) / fx, rayY: (Double(row) - cy) / fy))
      }
    }
    guard let patch = DepthSampling.evaluate(pixels) else { emit("unreliable", frame: frame); return }
    emit("sample", frame: frame, patch: patch)
  }

  func sessionWasInterrupted(_ session: ARSession) {
    emit("interrupted")
    stop()
  }
  func session(_ session: ARSession, didFailWithError error: Error) {
    emit("failed")
    stop()
  }
}

private final class DepthPreviewFactory: NSObject, FlutterPlatformViewFactory {
  private let plugin: DepthPlugin
  init(plugin: DepthPlugin) { self.plugin = plugin }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    DepthPreview(frame: frame, plugin: plugin)
  }
}

private final class DepthPreview: NSObject, FlutterPlatformView {
  private let content: ARSCNView
  init(frame: CGRect, plugin: DepthPlugin) {
    content = ARSCNView(frame: frame)
    super.init()
    plugin.attach(content)
  }
  func view() -> UIView { content }
}

private extension simd_float3x3 {
  init(_ m: simd_float4x4) {
    self.init(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
      SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
      SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
  }
}
