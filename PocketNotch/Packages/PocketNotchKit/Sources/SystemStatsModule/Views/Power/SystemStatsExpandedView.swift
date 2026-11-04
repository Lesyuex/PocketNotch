import SwiftUI
import PocketNotchShared

struct SystemStatsExpandedView: View {
    let viewModel: SystemStatsViewModel

    var body: some View {
        if let battery = viewModel.battery {
            Label(String(format: L10n.tr("system.batteryLevel"), battery.percentage), systemImage: battery.isCharging ? "bolt.fill" : "battery.50percent")
        } else {
            Label("system.noBuiltInBattery", systemImage: "battery.0percent")
        }
    }
}
