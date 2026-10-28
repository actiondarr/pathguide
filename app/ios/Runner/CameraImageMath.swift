import Foundation
import CoreGraphics

/// Normalized, top-left origin coordinates. Detection boxes are upright;
/// ARKit depth and intrinsics use the unrotated captured image coordinates.
enum CameraImageMath {
  static func rawPoint(x: Double, y: Double, rotation: Int) -> (Double, Double) {
    switch rotation {
    case 90: return (y, 1 - x)
    case 180: return (1 - x, 1 - y)
    case 270: return (1 - y, x)
    default: return (x, y)
    }
  }

  static func rgb(y: Double, cb: Double, cr: Double, fullRange: Bool, bt709: Bool) -> (Float32, Float32, Float32) {
    let luma = fullRange ? y : (y - 16) * 255 / 219
    let u = (cb - 128) * (fullRange ? 1 : 255 / 224)
    let v = (cr - 128) * (fullRange ? 1 : 255 / 224)
    let r = luma + (bt709 ? 1.5748 : 1.402) * v
    let g = luma - (bt709 ? 0.187324 : 0.344136) * u - (bt709 ? 0.468124 : 0.714136) * v
    let b = luma + (bt709 ? 1.8556 : 1.772) * u
    func clamp(_ value: Double) -> Float32 { Float32(min(1, max(0, value / 255))) }
    return (clamp(r), clamp(g), clamp(b))
  }

  /// Five distinct pixels along each axis inside the central half of a box.
  /// Thin/small boxes cannot borrow repeated pixels to inflate confidence.
  static func grid(box: CGRect, width: Int, height: Int) -> [(Int, Int)]? {
    guard width > 0, height > 0, box.origin.x.isFinite, box.origin.y.isFinite,
      box.size.width.isFinite, box.size.height.isFinite,
      box.minX >= 0, box.minY >= 0, box.maxX <= 1, box.maxY <= 1,
      box.size.width > 0, box.size.height > 0 else { return nil }
    let inner = box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
    let left = Int(ceil(inner.minX * Double(width)))
    let right = Int(floor(inner.maxX * Double(width)))
    let top = Int(ceil(inner.minY * Double(height)))
    let bottom = Int(floor(inner.maxY * Double(height)))
    guard left >= 0, top >= 0, right < width, bottom < height,
      right - left >= 4, bottom - top >= 4 else { return nil }
    return (0..<5).flatMap { row in
      (0..<5).map { col in (left + (right - left) * col / 4, top + (bottom - top) * row / 4) }
    }
  }
}
