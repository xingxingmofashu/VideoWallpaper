import Foundation

final class Playlist {
    private let urls: [URL]
    private let randomizes: Bool
    private var order: [Int]
    private var position = 0
    private var lastPlayedIndex: Int?

    init(urls: [URL], shuffle: Bool) {
        self.urls = urls
        self.randomizes = shuffle
        order = Array(urls.indices)
        if shuffle {
            order.shuffle()
        }
    }

    var count: Int { urls.count }

    func next() -> URL {
        if position >= order.count {
            position = 0
            if randomizes {
                reshuffle()
            }
        }
        let index = order[position]
        position += 1
        lastPlayedIndex = index
        return urls[index]
    }

    private func reshuffle() {
        order.shuffle()
        guard let last = lastPlayedIndex, order.count > 1, order.first == last else { return }
        order.swapAt(0, order.count - 1)
    }
}
