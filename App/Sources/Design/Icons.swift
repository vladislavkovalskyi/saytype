import SwiftUI

/// Line icons from the design mockups, drawn on a 24-point grid.
struct Icon: View {
    enum Name {
        case check, chevronDown, arrowRight, search, plus, copy, xmark, download, returnKey, card, clipboard, trash, grip
    }

    let name: Name
    var size: CGFloat = 18
    var stroke: CGFloat = 1.8

    init(_ name: Name, size: CGFloat = 18, stroke: CGFloat = 1.8) {
        self.name = name
        self.size = size
        self.stroke = stroke
    }

    var body: some View {
        Group {
            if name == .grip {
                GripShape().fill(.foreground)
            } else {
                IconShape(name: name)
                    .stroke(.foreground, style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct IconShape: Shape {
    let name: Icon.Name

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch name {
        case .check:
            p.move(to: pt(5, 12.5)); p.addLine(to: pt(9.2, 16.7)); p.addLine(to: pt(19, 7))
        case .chevronDown:
            p.move(to: pt(7, 10)); p.addLine(to: pt(12, 15)); p.addLine(to: pt(17, 10))
        case .arrowRight:
            p.move(to: pt(5, 12)); p.addLine(to: pt(19, 12))
            p.move(to: pt(13, 6)); p.addLine(to: pt(19, 12)); p.addLine(to: pt(13, 18))
        case .search:
            p.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 13, height: 13))
            p.move(to: pt(16, 16)); p.addLine(to: pt(20, 20))
        case .plus:
            p.move(to: pt(12, 5)); p.addLine(to: pt(12, 19))
            p.move(to: pt(5, 12)); p.addLine(to: pt(19, 12))
        case .copy:
            p.addRoundedRect(in: CGRect(x: 8.5, y: 8.5, width: 11, height: 11), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: pt(15.5, 8.5))
            p.addLine(to: pt(15.5, 6.5))
            p.addArc(tangent1End: pt(15.5, 4.5), tangent2End: pt(13.5, 4.5), radius: 2)
            p.addLine(to: pt(6.5, 4.5))
            p.addArc(tangent1End: pt(4.5, 4.5), tangent2End: pt(4.5, 6.5), radius: 2)
            p.addLine(to: pt(4.5, 13.5))
            p.addArc(tangent1End: pt(4.5, 15.5), tangent2End: pt(6.5, 15.5), radius: 2)
            p.addLine(to: pt(8.5, 15.5))
        case .xmark:
            p.move(to: pt(7, 7)); p.addLine(to: pt(17, 17))
            p.move(to: pt(17, 7)); p.addLine(to: pt(7, 17))
        case .download:
            p.move(to: pt(12, 4)); p.addLine(to: pt(12, 15))
            p.move(to: pt(7.5, 10.5)); p.addLine(to: pt(12, 15)); p.addLine(to: pt(16.5, 10.5))
            p.move(to: pt(5, 19.5)); p.addLine(to: pt(19, 19.5))
        case .returnKey:
            p.move(to: pt(19, 5))
            p.addLine(to: pt(19, 11))
            p.addArc(tangent1End: pt(19, 14), tangent2End: pt(16, 14), radius: 3)
            p.addLine(to: pt(6, 14))
            p.move(to: pt(9.5, 10.5)); p.addLine(to: pt(6, 14)); p.addLine(to: pt(9.5, 17.5))
        case .card:
            p.addRoundedRect(in: CGRect(x: 4, y: 8, width: 16, height: 12), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: pt(7, 5)); p.addLine(to: pt(17, 5))
        case .clipboard:
            p.addRoundedRect(in: CGRect(x: 6, y: 4.5, width: 12, height: 16), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.addRect(CGRect(x: 9.5, y: 4.5, width: 5, height: 2.5))
        case .trash:
            p.move(to: pt(4.5, 7)); p.addLine(to: pt(19.5, 7))
            p.move(to: pt(9.5, 7)); p.addLine(to: pt(9.5, 4.5)); p.addLine(to: pt(14.5, 4.5)); p.addLine(to: pt(14.5, 7))
            p.move(to: pt(6.5, 7)); p.addLine(to: pt(7.5, 19.5)); p.addLine(to: pt(16.5, 19.5)); p.addLine(to: pt(17.5, 7))
        case .grip:
            break
        }
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 24, y: rect.height / 24))
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct GripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let scale = rect.width / 24
        for (x, y) in [(9.0, 6.0), (15, 6), (9, 12), (15, 12), (9, 18), (15, 18)] {
            p.addEllipse(in: CGRect(x: rect.minX + (x - 1.6) * scale, y: rect.minY + (y - 1.6) * scale, width: 3.2 * scale, height: 3.2 * scale))
        }
        return p
    }
}
