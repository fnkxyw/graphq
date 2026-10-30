import CoreGraphics
import Foundation

/// Port of perfect-freehand (https://github.com/steveruizok/perfect-freehand, MIT):
/// turns input points (+ optional pressure) into a closed outline polygon with
/// variable width, smoothing and round caps.
public enum Freehand {
    public struct Options: Sendable {
        public var size: Double = 8
        public var thinning: Double = 0.6
        public var smoothing: Double = 0.5
        public var streamline: Double = 0.5
        public var simulatePressure: Bool = true
        public var last: Bool = true
        /// Excalidraw uses an ease-out sine for a more ink-like width curve.
        public var easing: @Sendable (Double) -> Double = { sin($0 * .pi / 2) }

        public init(size: Double = 8, simulatePressure: Bool = true, last: Bool = true) {
            self.size = size
            self.simulatePressure = simulatePressure
            self.last = last
        }
    }

    struct StrokePoint {
        var point: CGPoint
        var pressure: Double
        var vector: CGPoint
        var distance: Double
        var runningLength: Double
    }

    private static let rateOfPressureChange = 0.275
    private static let fixedPI = Double.pi + 0.0001

    /// Outline polygon for the stroke.
    public static func outline(points: [CGPoint], pressures: [Double], options: Options) -> [CGPoint] {
        let strokePoints = strokePoints(points: points, pressures: pressures, options: options)
        return outlinePoints(strokePoints, options: options)
    }

    static func strokePoints(points input: [CGPoint], pressures: [Double], options: Options) -> [StrokePoint] {
        let t = 0.15 + (1 - options.streamline) * 0.85
        guard !input.isEmpty else { return [] }
        var pts: [(CGPoint, Double)] = input.enumerated().map { i, p in
            (p, i < pressures.count ? pressures[i] : 0.5)
        }
        if pts.count == 2 {
            let lastP = pts[1]
            pts = [pts[0]]
            for i in 1..<5 {
                pts.append((pts[0].0.lerp(to: lastP.0, CGFloat(i) / 4), lastP.1))
            }
        }
        if pts.count == 1 {
            pts.append((pts[0].0 + CGPoint(x: 1, y: 1), pts[0].1))
        }

        var result: [StrokePoint] = [
            StrokePoint(point: pts[0].0, pressure: pts[0].1 >= 0 ? pts[0].1 : 0.25,
                        vector: CGPoint(x: 1, y: 1), distance: 0, runningLength: 0)
        ]
        var reachedMinimum = false
        var runningLength = 0.0
        var prev = result[0]
        let maxIndex = pts.count - 1
        for i in 1..<pts.count {
            let point = options.last && i == maxIndex ? pts[i].0 : prev.point.lerp(to: pts[i].0, t)
            if prev.point.isClose(to: point) { continue }
            let distance = point.distance(to: prev.point)
            runningLength += distance
            if i < maxIndex && !reachedMinimum {
                if runningLength < options.size { continue }
                reachedMinimum = true
            }
            prev = StrokePoint(point: point, pressure: pts[i].1,
                               vector: (prev.point - point).normalized,
                               distance: distance, runningLength: runningLength)
            result.append(prev)
        }
        result[0].vector = result.count > 1 ? result[1].vector : .zero
        return result
    }

    private static func radius(size: Double, thinning: Double, pressure: Double, easing: (Double) -> Double) -> Double {
        size * easing(0.5 - thinning * (0.5 - pressure))
    }

    static func outlinePoints(_ points: [StrokePoint], options: Options) -> [CGPoint] {
        let size = options.size, thinning = options.thinning, smoothing = options.smoothing
        guard !points.isEmpty, size > 0 else { return [] }
        let totalLength = points[points.count - 1].runningLength
        let minDistance = pow(size * smoothing, 2)

        var left: [CGPoint] = []
        var right: [CGPoint] = []

        // Seed the simulated pressure from the first few points.
        var prevPressure = points.prefix(10).reduce(points[0].pressure) { acc, curr in
            var pressure = curr.pressure
            if options.simulatePressure {
                let sp = min(1, curr.distance / size)
                let rp = min(1, 1 - sp)
                pressure = min(1, acc + (rp - acc) * (sp * rateOfPressureChange))
            }
            return (acc + pressure) / 2
        }

        var r = radius(size: size, thinning: thinning, pressure: points[points.count - 1].pressure, easing: options.easing)
        var firstRadius: Double?
        var prevVector = points[0].vector
        var pl = points[0].point, pr = pl
        var tl = pl, tr = pr
        var isPrevPointSharpCorner = false

        for i in 0..<points.count {
            var pressure = points[i].pressure
            let point = points[i].point, vector = points[i].vector
            let distance = points[i].distance, runningLength = points[i].runningLength

            if i < points.count - 1 && totalLength - runningLength < 3 { continue }

            if thinning != 0 {
                if options.simulatePressure {
                    let sp = min(1, distance / size)
                    let rp = min(1, 1 - sp)
                    pressure = min(1, prevPressure + (rp - prevPressure) * (sp * rateOfPressureChange))
                }
                r = radius(size: size, thinning: thinning, pressure: pressure, easing: options.easing)
            } else {
                r = size / 2
            }
            if firstRadius == nil { firstRadius = r }

            let nextVector = (i < points.count - 1 ? points[i + 1] : points[i]).vector
            let nextDpr = i < points.count - 1 ? vector.dot(nextVector) : 1.0
            let prevDpr = vector.dot(prevVector)
            let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
            let isNextPointSharpCorner = nextDpr < 0

            if isPointSharpCorner || isNextPointSharpCorner {
                // Draw a round cap around sharp turns.
                let off = prevVector.perpendicular * r
                var t = 0.0
                let step = 1.0 / 13
                while t <= 1 {
                    tl = (point - off).rotated(around: point, by: fixedPI * t)
                    left.append(tl)
                    tr = (point + off).rotated(around: point, by: fixedPI * -t)
                    right.append(tr)
                    t += step
                }
                pl = tl
                pr = tr
                if isNextPointSharpCorner { isPrevPointSharpCorner = true }
                continue
            }
            isPrevPointSharpCorner = false

            if i == points.count - 1 {
                let off = vector.perpendicular * r
                left.append(point - off)
                right.append(point + off)
                continue
            }

            let off = nextVector.lerp(to: vector, nextDpr).perpendicular * r
            tl = point - off
            if i <= 1 || pl.distanceSquared(to: tl) > minDistance {
                left.append(tl)
                pl = tl
            }
            tr = point + off
            if i <= 1 || pr.distanceSquared(to: tr) > minDistance {
                right.append(tr)
                pr = tr
            }
            prevPressure = pressure
            prevVector = vector
        }

        let firstPoint = points[0].point
        let lastPoint = points.count > 1 ? points[points.count - 1].point : points[0].point + CGPoint(x: 1, y: 1)

        if points.count == 1 {
            // A dot.
            let start = firstPoint + (firstPoint - lastPoint).perpendicular.normalized * -(firstRadius ?? r)
            var dot: [CGPoint] = []
            var t = 1.0 / 13
            while t <= 1 {
                dot.append(start.rotated(around: firstPoint, by: fixedPI * 2 * t))
                t += 1.0 / 13
            }
            return dot
        }

        var startCap: [CGPoint] = []
        if let firstRight = right.first {
            var t = 0.0
            while t <= 1 {
                startCap.append(firstRight.rotated(around: firstPoint, by: fixedPI * t))
                t += 1.0 / 13
            }
        }

        var endCap: [CGPoint] = []
        let direction = (-points[points.count - 1].vector).perpendicular
        let start = lastPoint + direction * r
        var t = 1.0 / 29
        while t < 1 {
            endCap.append(start.rotated(around: lastPoint, by: fixedPI * 3 * t))
            t += 1.0 / 29
        }

        return left + endCap + right.reversed() + startCap
    }

    /// Smooth closed path through outline points using quadratic midpoints (like `getSvgPathFromStroke`).
    public static func pathOps(outline: [CGPoint]) -> [PathOp] {
        guard outline.count > 2 else { return [] }
        var ops: [PathOp] = [.move(outline[0])]
        for i in 0..<outline.count {
            let p0 = outline[i]
            let p1 = outline[(i + 1) % outline.count]
            let mid = p0.lerp(to: p1, 0.5)
            // Quadratic p_prevMid -> p0 -> mid approximated as cubic from the current point.
            let prevMid = i == 0 ? outline[0] : outline[i - 1].lerp(to: p0, 0.5)
            let c1 = prevMid + (p0 - prevMid) * (2.0 / 3.0)
            let c2 = mid + (p0 - mid) * (2.0 / 3.0)
            if i == 0 {
                ops.append(.line(mid))
            } else {
                ops.append(.curve(c1, c2, mid))
            }
        }
        return ops
    }
}
