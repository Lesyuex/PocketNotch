import AppKit
import Foundation

@MainActor
final class ShelfClipboardService {
    func readFileURLs() -> [URL] {
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL]
        return objects?.compactMap { $0 as URL } ?? []
    }

    @discardableResult
    func writeFileURLs(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls.map { $0 as NSURL })
    }
}

@MainActor
final class ShelfAirDropService {
    func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            return false
        }
        service.perform(withItems: urls)
        return true
    }
}
