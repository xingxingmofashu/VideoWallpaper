import Combine

final class SpectrumStore: ObservableObject {
    @Published var bands: [Float] = []
    @Published var visible = false
}
