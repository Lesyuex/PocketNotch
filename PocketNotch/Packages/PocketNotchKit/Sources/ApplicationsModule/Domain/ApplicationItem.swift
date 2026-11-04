import Foundation

struct ApplicationItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String

    var id: URL { url }
}
