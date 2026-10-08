import Combine

final class SpectrumStore: ObservableObject {
    @Published var bands: [Float] = []
    @Published var color: SpectrumColor = .white
    @Published var visible = false
}
