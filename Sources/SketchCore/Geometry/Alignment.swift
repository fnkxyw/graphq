import CoreGraphics
import Foundation

public enum AlignMode: String, CaseIterable, Sendable {
    case left, centerX, right, top, centerY, bottom
}

public enum DistributeAxis: String, CaseIterable, Sendable {
    case horizontal, vertical
}

/// Alignment math on boxes; callers map the returned offsets back to elements/groups.
public enum Alignment {
    /// Offsets that align every box to the selection bounds.
    public static func align(_ boxes: [CGRect], _ mode: AlignMode) -> [CGPoint] {
        let all = boxes.reduce(CGRect.null) { $0.union($1) }
        guard !all.isNull else { return boxes.map { _ in .zero } }
        return boxes.map { b in
            switch mode {
            case .left: CGPoint(x: all.minX - b.minX, y: 0)
            case .centerX: CGPoint(x: all.midX - b.midX, y: 0)
            case .right: CGPoint(x: all.maxX - b.maxX, y: 0)
            case .top: CGPoint(x: 0, y: all.minY - b.minY)
            case .centerY: CGPoint(x: 0, y: all.midY - b.midY)
            case .bottom: CGPoint(x: 0, y: all.maxY - b.maxY)
            }
        }
    }

    /// Offsets that make gaps between consecutive boxes equal, keeping the outermost boxes in place.
    public static func distribute(_ boxes: [CGRect], _ axis: DistributeAxis) -> [CGPoint] {
        var offsets = boxes.map { _ in CGPoint.zero }
        guard boxes.count > 2 else { return offsets }
        let horizontal = axis == .horizontal
        let order = boxes.indices.sorted {
            horizontal ? boxes[$0].midX < boxes[$1].midX : boxes[$0].midY < boxes[$1].midY
        }
        let first = boxes[order.first!], last = boxes[order.last!]
        let span = horizontal ? last.maxX - first.minX : last.maxY - first.minY
        let sizes = order.reduce(CGFloat(0)) { $0 + (horizontal ? boxes[$1].width : boxes[$1].height) }
        let gap = (span - sizes) / CGFloat(boxes.count - 1)
        var cursor = horizontal ? first.minX : first.minY
        for i in order {
            let b = boxes[i]
            if horizontal {
                offsets[i] = CGPoint(x: cursor - b.minX, y: 0)
                cursor += b.width + gap
            } else {
                offsets[i] = CGPoint(x: 0, y: cursor - b.minY)
                cursor += b.height + gap
            }
        }
        return offsets
    }
}
