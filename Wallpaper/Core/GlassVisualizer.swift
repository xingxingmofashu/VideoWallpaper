import SwiftUI
import Combine

final class SpectrumStore: ObservableObject {
    @Published var bands: [Float] = []
    @Published var peaks: [Float] = []
    @Published var visible = false
}

struct GlassSpectrumView: View {
    static let verticalPosition: CGFloat = 0.68
    static let cornerRadius: CGFloat = 40
    static let widthRatio: CGFloat = 0.48
    static let heightRatio: CGFloat = 0.14
    static let minimumWidth: CGFloat = 720
    static let maximumWidth: CGFloat = 1200
    static let minimumHeight: CGFloat = 160
    static let maximumHeight: CGFloat = 260
    static let barWidthRatio: CGFloat = 0.42
    static let innerInset: CGFloat = 44

    static func panelSize(in bounds: CGSize) -> CGSize {
        let width = min(max(bounds.width * widthRatio, minimumWidth), maximumWidth)
        let height = min(max(bounds.height * heightRatio, minimumHeight), maximumHeight)
        return CGSize(width: width, height: height)
    }

    @ObservedObject var store: SpectrumStore
    let panelSize: CGSize

    var body: some View {
        GlassEffectContainer {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .glassEffect(.clear, in: .rect(cornerRadius: Self.cornerRadius))
        }
        .opacity(store.visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: store.visible)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let count = min(store.bands.count, store.peaks.count)
        guard count > 0 else { return }

        let inset = Self.innerInset
        let innerWidth = max(size.width - inset * 2, 1)
        let innerHeight = max(size.height - inset * 2, 1)
        let slot = innerWidth / CGFloat(count)
        let barWidth = max(2, slot * Self.barWidthRatio)
        let radius = barWidth / 2
        let centreY = size.height / 2
        let maxHalf = innerHeight / 2

        var bars = Path()
        var caps = Path()
        for index in 0..<count {
            let x = inset + slot * CGFloat(index) + (slot - barWidth) / 2
            let half = max(radius, maxHalf * CGFloat(min(store.bands[index], 1)))
            bars.addPath(Path(
                roundedRect: CGRect(x: x, y: centreY - half, width: barWidth, height: half * 2),
                cornerRadius: radius))

            let peakHalf = max(half, maxHalf * CGFloat(min(store.peaks[index], 1)))
            caps.addPath(Path(
                roundedRect: CGRect(x: x, y: centreY - peakHalf - 2, width: barWidth, height: 2.5),
                cornerRadius: 1.25))
        }

        context.fill(bars, with: .linearGradient(
            Gradient(colors: [
                Color.white.opacity(0.45),
                Color.white.opacity(0.95),
                Color.white.opacity(0.45),
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: 0)))
        context.fill(caps, with: .color(Color.white.opacity(0.6)))
    }
}
