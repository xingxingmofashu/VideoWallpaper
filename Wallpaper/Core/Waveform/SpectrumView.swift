import SwiftUI

struct SpectrumView: View {
    static let verticalPosition: CGFloat = 0.68
    static let widthRatio: CGFloat = 0.48
    static let heightRatio: CGFloat = 0.14
    static let minimumWidth: CGFloat = 720
    static let maximumWidth: CGFloat = 1200
    static let minimumHeight: CGFloat = 160
    static let maximumHeight: CGFloat = 260
    static let barWidthRatio: CGFloat = 0.42
    static let horizontalInset: CGFloat = 44
    static let minimumBarHeight: CGFloat = 2
    static let shadowOpacity: Double = 0.45
    static let shadowRadius: CGFloat = 10
    static let edgeOpacity: Double = 0.45
    static let centreOpacity: Double = 0.95
    static let fadeDuration: Double = 0.35

    static func panelSize(in bounds: CGSize) -> CGSize {
        let width = min(max(bounds.width * widthRatio, minimumWidth), maximumWidth)
        let height = min(max(bounds.height * heightRatio, minimumHeight), maximumHeight)
        return CGSize(width: width, height: height)
    }

    @ObservedObject var store: SpectrumStore
    let panelSize: CGSize

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .shadow(color: Color.black.opacity(Self.shadowOpacity), radius: Self.shadowRadius, y: 1)
        .opacity(store.visible ? 1 : 0)
        .animation(.easeInOut(duration: Self.fadeDuration), value: store.visible)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let count = store.bands.count
        guard count > 0 else { return }

        let inset = Self.horizontalInset
        let innerWidth = max(size.width - inset * 2, 1)
        let slot = innerWidth / CGFloat(count)
        let barWidth = max(2, slot * Self.barWidthRatio)
        let baseline = size.height

        var bars = Path()
        for index in 0..<count {
            let x = inset + slot * CGFloat(index) + (slot - barWidth) / 2
            let height = max(Self.minimumBarHeight, size.height * CGFloat(min(store.bands[index], 1)))
            bars.addRect(CGRect(x: x, y: baseline - height, width: barWidth, height: height))
        }

        context.fill(bars, with: .linearGradient(
            Gradient(colors: [
                Color.white.opacity(Self.edgeOpacity),
                Color.white.opacity(Self.centreOpacity),
                Color.white.opacity(Self.edgeOpacity),
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: 0)))
    }
}
