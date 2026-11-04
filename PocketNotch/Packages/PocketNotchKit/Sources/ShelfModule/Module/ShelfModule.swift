import SwiftUI
import PocketNotchCore

public struct ShelfModule: PocketNotchModule {
    public let id = "shelf"
    public let title: LocalizedStringKey = "module.shelf.title"
    public let priority = 20

    @MainActor private let store = ShelfStore()
    @MainActor private let airDropService = ShelfAirDropService()

    public init() {}

    public func collapsedView() -> AnyView {
        AnyView(ShelfCollapsedView(store: store))
    }

    public var showsInExpandedPage: Bool { true }

    public var expandedIslandTab: ExpandedIslandTab { .transfer }

    public func expandedView() -> AnyView {
        AnyView(ShelfExpandedView(store: store))
    }

    public func handleFileDrop(_ urls: [URL], at location: CGPoint) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        if location.x <= ShelfDropLayout.airDropNormalizedBoundary {
            return airDropService.send(fileURLs)
        }
        store.add(contentsOf: fileURLs)
        return true
    }

    public func activate() {}
    public func deactivate() {}
}
