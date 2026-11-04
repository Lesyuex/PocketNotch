import SwiftUI

struct ShelfCollapsedView: View {
    let store: ShelfStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tray.full")
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.white)
    }
}
