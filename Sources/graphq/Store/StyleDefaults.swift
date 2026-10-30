import Foundation
import SketchCore

/// Style applied to newly created elements. Updated whenever the user changes a
/// property in the panel, so the next shape "remembers" the last used style.
struct StyleDefaults: Equatable {
    var strokeColor: RGBAColor = .ink
    var fillColor: RGBAColor = .transparent
    var fillStyle: FillStyle = .hachure
    var strokeWidth: Double = 2
    var strokeStyle: StrokeStyle = .solid
    var roughness: Double = 1
    var opacity: Double = 1
    var roundness: Double = 0
    var fontFamily: FontFamily = .hand
    var fontSize: Double = 20
    var textAlign: TextAlign = .left
    var startArrowhead: Arrowhead = .none
    var endArrowhead: Arrowhead = .arrow
    var curvedArrows: Bool = false

    func makeElement(_ type: ElementType) -> Element {
        var e = Element(type: type)
        e.strokeColor = strokeColor
        e.fillColor = type.supportsFill ? fillColor : .transparent
        e.fillStyle = fillStyle
        e.strokeWidth = strokeWidth
        e.strokeStyle = type == .freedraw ? .solid : strokeStyle
        e.roughness = roughness
        e.opacity = opacity
        e.roundness = (type == .rectangle || type == .diamond) ? roundness : 0
        e.fontFamily = fontFamily
        e.fontSize = fontSize
        e.textAlign = type == .text ? textAlign : .center
        if type == .arrow {
            e.startArrowhead = startArrowhead
            e.endArrowhead = endArrowhead
        }
        e.curved = type.isLinear && curvedArrows
        return e
    }
}
