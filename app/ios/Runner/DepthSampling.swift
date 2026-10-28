import Foundation

/// Camera-plane Z and camera-to-surface range are deliberately separate.
/// This is a small surface patch, not an object extent or free-space estimate.
struct DepthPixel {
  let z: Double
  let confidence: UInt8
  let rayX: Double
  let rayY: Double
}

struct DepthPatch {
  let z: Double
  let range: Double
  let accepted: Int
  let total: Int
  let spread: Double
}

enum DepthSampling {
  static func median(_ values: [Double]) -> Double {
    let a = values.sorted()
    let n = a.count
    return n % 2 == 0 ? (a[n / 2 - 1] + a[n / 2]) / 2 : a[n / 2]
  }

  static func evaluate(_ pixels: [DepthPixel]) -> DepthPatch? {
    guard pixels.count >= 25 else { return nil }
    let valid = pixels.filter {
      $0.confidence == 2 && $0.z.isFinite && $0.z >= 0.2 && $0.z <= 4 &&
        $0.rayX.isFinite && $0.rayY.isFinite
    }
    guard Double(valid.count) / Double(pixels.count) >= 0.7 else { return nil }
    let z = median(valid.map(\.z))
    let tolerance = max(0.06, z * 0.04)
    let inliers = valid.filter { abs($0.z - z) <= tolerance }
    guard Double(inliers.count) / Double(valid.count) >= 0.8 else { return nil }
    let values = inliers.map(\.z).sorted()
    let spread = values.last! - values.first!
    guard spread <= max(0.1, z * 0.08) else { return nil }
    let ranges = inliers.map { $0.z * sqrt(1 + $0.rayX * $0.rayX + $0.rayY * $0.rayY) }
    let range = median(ranges)
    guard range.isFinite, range <= 4 else { return nil }
    return DepthPatch(z: median(values), range: range, accepted: inliers.count,
      total: pixels.count, spread: spread)
  }
}
