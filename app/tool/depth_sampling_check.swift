import Foundation

@main struct CheckDepthSampling {
  static func main() {
    var checks = 0
    func check(_ ok: Bool, _ name: String) {
      precondition(ok, name)
      checks += 1
    }
    func pixel(_ z: Double, _ c: UInt8 = 2, _ x: Double = 0) -> DepthPixel {
      DepthPixel(z: z, confidence: c, rayX: x, rayY: 0)
    }
    let wall = Array(repeating: pixel(2), count: 25)
    let result = DepthSampling.evaluate(wall)!
    check(result.z == 2 && result.range == 2 && result.accepted == 25, "uniform central wall")
    let oblique = DepthSampling.evaluate(Array(repeating: pixel(2, 2, 0.75), count: 25))!
    check(abs(oblique.range - 2.5) < 1e-9 && oblique.z == 2, "unprojection separates radial range and Z")
    check(DepthSampling.evaluate(Array(repeating: pixel(2, 1), count: 25)) == nil, "low confidence rejected")
    check(DepthSampling.evaluate(Array(wall.prefix(17)) + Array(repeating: pixel(.nan), count: 8)) == nil, "coverage below70%")
    check(DepthSampling.evaluate(Array(wall.prefix(18)) + Array(repeating: pixel(.nan), count: 7)) != nil, "coverage above70%")
    check(DepthSampling.evaluate(Array(wall.prefix(20)) + Array(repeating: pixel(3), count: 5))?.range == 2, "minority background rejected")
    check(DepthSampling.evaluate(Array(wall.prefix(19)) + Array(repeating: pixel(3), count: 6)) == nil, "mixed surface rejected")
    check(DepthSampling.evaluate(Array(repeating: pixel(0.1), count: 25)) == nil, "near range gate")
    check(DepthSampling.evaluate(Array(repeating: pixel(4.1), count: 25)) == nil, "far range gate")
    check(DepthSampling.evaluate(Array(repeating: pixel(4, 2, 0.5), count: 25)) == nil, "radial exceeds supported range")
    check(DepthSampling.evaluate(Array(wall.prefix(24))) == nil, "patch too small")
    check(DepthSampling.evaluate(Array(repeating: pixel(.infinity), count: 25)) == nil, "infinite depth rejected")
    print("DepthSampling: \(checks) deterministic checks passed; no device accuracy claim")
  }
}
