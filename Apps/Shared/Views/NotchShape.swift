import SwiftUI

/// The outline of a notch that has grown: a body hanging from the top edge,
/// with concave "ears" where it meets that edge and rounded bottom corners.
///
/// The top edge runs the full width of the rect. Each ear curves from the top
/// edge in to the body's side, so the body is `topCornerRadius` narrower than
/// the rect on each side. Filled black, it reads as part of the hardware
/// notch.
struct NotchShape: Shape {

    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(max(0, topCornerRadius), rect.width / 4, rect.height / 2)
        let corner = min(max(0, bottomCornerRadius), (rect.width - 2 * ear) / 2, rect.height - ear)
        let left = rect.minX + ear
        let right = rect.maxX - ear

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: from the top edge, curving down into the body's left side.
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: left + corner, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - corner), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        // Right ear: back up and out to the top edge.
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
