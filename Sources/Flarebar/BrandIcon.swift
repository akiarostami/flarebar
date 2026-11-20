import AppKit
import SwiftUI

/// Flarebar's mark: a cloud with a flare streaking across it, drawn in code so it stays
/// sharp at any size and can be tinted.
enum BrandIcon {
    /// The mark is designed in a box of this shape, y up.
    static let aspect: CGFloat = 46.0 / 100.0

    static let orange = Color(red: 0.953, green: 0.502, blue: 0.125)
    static let lightOrange = Color(red: 0.984, green: 0.678, blue: 0.255)

    static var gradient: LinearGradient {
        LinearGradient(colors: [lightOrange, orange], startPoint: .top, endPoint: .bottom)
    }

    /// The mark in one colour, `pointSize` wide.
    static func image(pointSize: CGFloat, colour: NSColor) -> NSImage {
        let size = NSSize(width: pointSize, height: (pointSize * aspect).rounded(.up))
        return NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, colour: colour, context: context)
            return true
        }
    }

    /// The mark for the menu bar: a template image, so macOS colours it, with `drop` points
    /// of empty space above the mark to lower it in the bar.
    static func menuBarImage(width: CGFloat, drop: CGFloat) -> NSImage {
        let markHeight = (width * aspect).rounded(.up)
        let image = NSImage(size: NSSize(width: width, height: markHeight + drop * 2), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: CGRect(x: 0, y: 0, width: width, height: markHeight), colour: .black, context: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Flarebar"
        return image
    }

    /// Draws the mark scaled to fit `rect`, centred.
    static func draw(in rect: CGRect, colour: NSColor, context: CGContext) {
        let scale = min(rect.width / 100, rect.height / 46)
        context.saveGState()
        context.translateBy(x: rect.midX - 50 * scale, y: rect.midY - 23 * scale)
        context.scaleBy(x: scale, y: scale)
        // A layer of its own, so the cut-outs below remove only the mark.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(colour.cgColor)

        // The main cloud: a flat base, a small bump on the left and a large one in the middle.
        let main = CGMutablePath()
        main.addRoundedRect(in: CGRect(x: 3, y: 3, width: 70, height: 17), cornerWidth: 8.5, cornerHeight: 8.5)
        main.addEllipse(in: CGRect(x: 10, y: 9, width: 25, height: 25))
        main.addEllipse(in: CGRect(x: 26, y: 7, width: 38, height: 38))
        context.addPath(main)
        context.fillPath()

        // The smaller lobe on the right.
        let lobe = CGMutablePath()
        lobe.addEllipse(in: CGRect(x: 66, y: 5, width: 24, height: 24))
        lobe.addRoundedRect(in: CGRect(x: 66, y: 3, width: 31, height: 13), cornerWidth: 6.5, cornerHeight: 6.5)
        context.addPath(lobe)
        context.fillPath()

        // Cut-outs: the slanted gap between the two parts, and the flare streaks running left from it.
        context.setBlendMode(.destinationOut)
        context.setFillColor(NSColor.black.cgColor)
        let gap = CGMutablePath()
        gap.move(to: CGPoint(x: 67, y: 1))
        gap.addLine(to: CGPoint(x: 71.5, y: 1))
        gap.addQuadCurve(to: CGPoint(x: 76, y: 34), control: CGPoint(x: 76, y: 16))
        gap.addLine(to: CGPoint(x: 71.5, y: 34))
        gap.addQuadCurve(to: CGPoint(x: 67, y: 1), control: CGPoint(x: 71.5, y: 16))
        context.addPath(gap)
        context.fillPath()
        streak(from: CGPoint(x: 73, y: 19.5), to: CGPoint(x: 30, y: 16), bend: 3, width: 3.6, context: context)
        streak(from: CGPoint(x: 71.5, y: 11), to: CGPoint(x: 42, y: 9), bend: 1.5, width: 3.2, context: context)

        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// A streak that is `width` thick at `start` and tapers to a point at `end`.
    private static func streak(from start: CGPoint, to end: CGPoint, bend: CGFloat, width: CGFloat, context: CGContext) {
        let path = CGMutablePath()
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + bend)
        path.move(to: CGPoint(x: start.x, y: start.y + width / 2))
        path.addQuadCurve(to: end, control: CGPoint(x: mid.x, y: mid.y + width / 2))
        path.addQuadCurve(to: CGPoint(x: start.x, y: start.y - width / 2), control: CGPoint(x: mid.x, y: mid.y - width / 2))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }
}
