import AppKit
import ApplicationServices
import Combine
import CoreBluetooth
import CoreGraphics
import CoreLocation
import Foundation
import MediaModule
import SwiftUI

enum AudioCaptureAuthorizationStatus: Equatable {
    case granted
    case notDetermined
    case denied
}

private enum SettingsPermissionRequest: Hashable {
    case accessibility
    case audioCapture
    case location
    case bluetooth
    case dataAccess
    case musicControl(String)
}

@MainActor
private final class SettingsPermissionModel: NSObject, ObservableObject {
    @Published private(set) var isAccessibilityAuthorized = false
    @Published private(set) var audioCaptureStatus: AudioCaptureAuthorizationStatus?
    @Published private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var bluetoothAuthorization: CBManagerAuthorization = .notDetermined
    @Published private(set) var isDataAccessEnabled = true
    @Published private(set) var requestingPermissions: Set<SettingsPermissionRequest> = []
    @Published var guidance: String?
    @Published private(set) var authorizedMusicApps: Set<String> = []
    @Published private(set) var deniedMusicApps: Set<String> = []
    @Published private(set) var runningMusicApps: Set<String> = MusicControlAuthorization.runningMusicApps()

    private let monitoringSettings: MediaMonitoringSettings
    private let locationManager = CLLocationManager()
    private var bluetoothManager: CBCentralManager?
    private var accessibilityPollingTask: Task<Void, Never>?
    private var requestTimeoutTasks: [SettingsPermissionRequest: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(monitoringSettings: MediaMonitoringSettings) {
        self.monitoringSettings = monitoringSettings
        super.init()
        locationManager.delegate = self
        authorizedMusicApps = Set(monitoringSettings.musicControlAuthorizedApps)
        deniedMusicApps = Set(monitoringSettings.musicControlDeniedApps)
        monitoringSettings.$musicControlAuthorizedApps
            .sink { [weak self] apps in
                self?.authorizedMusicApps = Set(apps)
            }
            .store(in: &cancellables)
        monitoringSettings.$musicControlDeniedApps
            .sink { [weak self] apps in
                self?.deniedMusicApps = Set(apps)
            }
            .store(in: &cancellables)
        refresh()
        startMusicAppPolling()
    }

    deinit {
        accessibilityPollingTask?.cancel()
        requestTimeoutTasks.values.forEach { $0.cancel() }
    }

    private func startMusicAppPolling() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
            await MainActor.run {
                self.runningMusicApps = MusicControlAuthorization.runningMusicApps()
            }
            }
        }
    }

    func refresh() {
        let accessibilityAuthorized = AXIsProcessTrusted()
        let currentLocationAuthorization = locationManager.authorizationStatus
        let currentBluetoothAuthorization = CBManager.authorization

        if isAccessibilityAuthorized != accessibilityAuthorized {
            isAccessibilityAuthorized = accessibilityAuthorized
        }
        if #available(macOS 14.4, *) {
            let currentAudioAuth: AudioCaptureAuthorizationStatus = switch systemAudioRecordingAuthorization() {
            case .granted: .granted
            case .notDetermined: .notDetermined
            case .denied: .denied
            }
            if audioCaptureStatus != currentAudioAuth {
                audioCaptureStatus = currentAudioAuth
            }
        }
        if locationAuthorization != currentLocationAuthorization {
            locationAuthorization = currentLocationAuthorization
        }
        if bluetoothAuthorization != currentBluetoothAuthorization {
            bluetoothAuthorization = currentBluetoothAuthorization
        }

        if isAccessibilityAuthorized {
            finishRequest(.accessibility)
        }
        if let audioAuth = audioCaptureStatus {
            if audioAuth == .granted { finishRequest(.audioCapture) }
        }
        if locationAuthorization != .notDetermined {
            finishRequest(.location)
        }
        if bluetoothAuthorization != .notDetermined {
            finishRequest(.bluetooth)
        }
        if isDataAccessEnabled {
            finishRequest(.dataAccess)
        }
    }

    func isRequesting(_ request: SettingsPermissionRequest) -> Bool {
        requestingPermissions.contains(request)
    }

    func requestAccessibilityAuthorization() {
        guard beginRequest(.accessibility) else { return }
        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            beginAccessibilityPolling()
        }
    }

    func requestLocationAuthorization() {
        guidance = nil
        guard CLLocationManager.locationServicesEnabled() else {
            guidance = NSLocalizedString("settings.permissions.locationServiceOff", comment: "")
            openSystemSettings(.location)
            return
        }

        if locationAuthorization == .notDetermined {
            guard beginRequest(.location) else { return }
            Task { [weak self] in
                await Task.yield()
                self?.locationManager.requestWhenInUseAuthorization()
            }
        } else {
            openSystemSettings(.location)
        }
    }

    func requestBluetoothAuthorization() {
        guidance = nil
        if bluetoothAuthorization == .notDetermined {
            guard beginRequest(.bluetooth) else { return }
            Task { [weak self] in
                await Task.yield()
                guard let self else { return }
                bluetoothManager = CBCentralManager(delegate: self, queue: nil)
            }
        } else {
            openSystemSettings(.bluetooth)
        }
    }

    func toggleDataAccess() {
        isDataAccessEnabled.toggle()
        if isDataAccessEnabled {
            finishRequest(.dataAccess)
        }
    }

    func requestAudioCaptureAuthorization() {
        guidance = nil
        guard let auth = audioCaptureStatus else {
            guidance = NSLocalizedString("settings.permissions.audioUnknown", comment: "")
            return
        }
        if auth == .granted {
            openSystemSettings(.screenCapture)
            return
        }
        guard beginRequest(.audioCapture) else { return }
        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            if #available(macOS 14.4, *) {
                let granted = await requestSystemAudioRecordingAccess()
                finishRequest(.audioCapture)
                refresh()
                if !granted {
                    guidance = NSLocalizedString("settings.permissions.audioNotEnabled", comment: "")
                }
            } else {
                finishRequest(.audioCapture)
            }
        }
    }

    func requestMusicControlAuthorization(for appName: String) {
        guidance = nil
        guard runningMusicApps.contains(appName) else {
            guidance = String(format: NSLocalizedString("settings.permissions.openAppFirstFormat", comment: ""), MusicControlAuthorization.displayName(for: appName))
            return
        }
        guard beginRequest(.musicControl(appName)) else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await MusicControlAuthorization.requestAuthorization(for: self.monitoringSettings)
            self.finishRequest(.musicControl(appName))
            self.refresh()
        }
    }

    func openMusicAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func openSystemSettings(_ destination: SystemSettingsDestination) {
        guidance = nil
        guard let url = URL(string: destination.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func beginRequest(_ request: SettingsPermissionRequest) -> Bool {
        guidance = nil
        guard !requestingPermissions.contains(request) else { return false }
        requestingPermissions.insert(request)

        requestTimeoutTasks[request]?.cancel()
        requestTimeoutTasks[request] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            self?.finishRequest(request)
        }
        return true
    }

    private func finishRequest(_ request: SettingsPermissionRequest) {
        guard requestingPermissions.contains(request) else { return }
        requestingPermissions.remove(request)
        requestTimeoutTasks.removeValue(forKey: request)?.cancel()
    }

    private func beginAccessibilityPolling() {
        accessibilityPollingTask?.cancel()
        accessibilityPollingTask = Task { [weak self] in
            for _ in 0..<40 {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                guard let self else { return }
                // 只查询辅助功能本身，不跑整轮 refresh，避免高频完整探测卡主线程。
                if AXIsProcessTrusted() {
                    self.isAccessibilityAuthorized = true
                    self.finishRequest(.accessibility)
                    return
                }
            }
            self?.finishRequest(.accessibility)
        }
    }
}

extension SettingsPermissionModel: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorization = manager.authorizationStatus
        guard manager.authorizationStatus != .notDetermined else { return }
        finishRequest(.location)
        if manager.authorizationStatus == .denied {
            guidance = NSLocalizedString("settings.permissions.locationNotEnabled", comment: "")
        }
    }
}

extension SettingsPermissionModel: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothAuthorization = CBManager.authorization
        if bluetoothAuthorization == .allowedAlways {
            monitoringSettings.isBluetoothDeviceMonitoringEnabled = true
        }
        guard bluetoothAuthorization != .notDetermined else { return }
        finishRequest(.bluetooth)
        if bluetoothAuthorization == .denied {
            guidance = NSLocalizedString("settings.permissions.bluetoothNotEnabled", comment: "")
        }
    }
}

private enum SystemSettingsDestination {
    case accessibility
    case screenCapture
    case location
    case bluetooth

    var urlString: String {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenCapture: "Privacy_ScreenCapture"
        case .location: "Privacy_LocationServices"
        case .bluetooth: "Privacy_Bluetooth"
        }
        return "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    }
}
private enum PermissionDisplayState: Equatable {
    case authorized
    case notAuthorized
    case denied
    case unavailable

    var title: String {
        switch self {
        case .authorized: NSLocalizedString("settings.permissions.stateAuthorized", comment: "")
        case .notAuthorized: NSLocalizedString("settings.permissions.stateNotAuthorized", comment: "")
        case .denied: NSLocalizedString("settings.permissions.stateDenied", comment: "")
        case .unavailable: NSLocalizedString("settings.permissions.stateUnavailable", comment: "")
        }
    }

    var color: Color {
        switch self {
        case .authorized: .green
        case .notAuthorized: .secondary
        case .denied: .orange
        case .unavailable: .red
        }
    }

    var symbol: String {
        switch self {
        case .authorized: "checkmark.circle.fill"
        case .notAuthorized: "circle.dashed"
        case .denied: "exclamationmark.circle.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }
}

struct PermissionSettingsView: View {
    @StateObject private var model: SettingsPermissionModel

    init(monitoringSettings: MediaMonitoringSettings) {
        _model = StateObject(
            wrappedValue: SettingsPermissionModel(monitoringSettings: monitoringSettings)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                permissionCard
                guidanceArea
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: authorizedPermissionCount == permissionCount
                ? "checkmark.shield.fill"
                : "checkmark.shield")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(authorizedPermissionCount == permissionCount ? Color.green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("settings.permissions.systemPermissions")
                    .font(.system(size: 12, weight: .semibold))
                Text(String(format: NSLocalizedString("settings.permissions.authorizedCountFormat", comment: ""), authorizedPermissionCount, permissionCount))
                    .settingsNoteStyle()
            }

            Spacer(minLength: 12)

            Button {
                model.refresh()
            } label: {
                Label("settings.common.refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var permissionCard: some View {
        SettingsCard {
            permissionRow(
                title: NSLocalizedString("settings.permissions.accessibility", comment: ""),
                description: NSLocalizedString("settings.permissions.accessibility.description", comment: ""),
                symbol: "accessibility",
                state: model.isAccessibilityAuthorized ? .authorized : .notAuthorized,
                actionTitle: model.isAccessibilityAuthorized ? NSLocalizedString("settings.permissions.manage", comment: "") : NSLocalizedString("settings.permissions.authorize", comment: ""),
                actionSymbol: model.isAccessibilityAuthorized ? "gear" : "hand.raised",
                isWorking: model.isRequesting(.accessibility)
            ) {
                if model.isAccessibilityAuthorized {
                    model.openSystemSettings(.accessibility)
                } else {
                    model.requestAccessibilityAuthorization()
                }
            }

            AppearanceRowDivider()

            permissionRow(
                title: NSLocalizedString("settings.permissions.audio", comment: ""),
                description: NSLocalizedString("settings.permissions.audio.description", comment: ""),
                symbol: "waveform",
                state: audioCaptureDisplayState,
                actionTitle: actionTitle(for: audioCaptureDisplayState),
                actionSymbol: actionSymbol(for: audioCaptureDisplayState, requestingSymbol: "waveform"),
                isWorking: model.isRequesting(.audioCapture)
            ) {
                if audioCaptureDisplayState == .notAuthorized {
                    model.requestAudioCaptureAuthorization()
                } else {
                    model.openSystemSettings(.screenCapture)
                }
            }

            AppearanceRowDivider()

            permissionRow(
                title: NSLocalizedString("settings.permissions.location", comment: ""),
                description: NSLocalizedString("settings.permissions.location.description", comment: ""),
                symbol: "location.fill",
                state: locationDisplayState,
                actionTitle: actionTitle(for: locationDisplayState),
                actionSymbol: actionSymbol(for: locationDisplayState, requestingSymbol: "location"),
                isWorking: model.isRequesting(.location)
            ) {
                model.requestLocationAuthorization()
            }

            AppearanceRowDivider()

            permissionRow(
                title: NSLocalizedString("settings.permissions.bluetooth", comment: ""),
                description: NSLocalizedString("settings.permissions.bluetooth.description", comment: ""),
                symbol: "dot.radiowaves.left.and.right",
                state: bluetoothDisplayState,
                actionTitle: actionTitle(for: bluetoothDisplayState),
                actionSymbol: actionSymbol(for: bluetoothDisplayState, requestingSymbol: "antenna.radiowaves.left.and.right"),
                isWorking: model.isRequesting(.bluetooth)
            ) {
                model.requestBluetoothAuthorization()
            }

            AppearanceRowDivider()

            musicAutomationRow(for: "Music")

            AppearanceRowDivider()

            musicAutomationRow(for: "Spotify")

            AppearanceRowDivider()

            permissionRow(
                title: NSLocalizedString("settings.permissions.dataAccess", comment: ""),
                description: NSLocalizedString("settings.permissions.dataAccess.description", comment: ""),
                symbol: "lock.shield",
                state: dataAccessDisplayState,
                actionTitle: dataAccessActionTitle,
                actionSymbol: "gearshape",
                isWorking: model.isRequesting(.dataAccess)
            ) {
                model.toggleDataAccess()
            }
        }
    }

    private func musicAutomationRow(for appName: String) -> some View {
        let displayName = MusicControlAuthorization.displayName(for: appName)
        let isRunning = model.runningMusicApps.contains(appName)
        let isAuthorized = model.authorizedMusicApps.contains(appName)
        let isDenied = model.deniedMusicApps.contains(appName)
        let state: PermissionDisplayState = isAuthorized ? .authorized : (isDenied ? .denied : (isRunning ? .notAuthorized : .unavailable))
        let actionTitle: String = isAuthorized ? NSLocalizedString("settings.permissions.manage", comment: "") : (isRunning ? NSLocalizedString("settings.permissions.authorize", comment: "") : NSLocalizedString("settings.permissions.goEnable", comment: ""))
        let actionSymbol: String = isAuthorized ? "gear" : (isRunning ? "hand.raised" : "arrow.right.circle")
        return permissionRow(
            title: String(format: NSLocalizedString("settings.permissions.automationFormat", comment: ""), displayName),
            description: String(format: NSLocalizedString("settings.permissions.automationDescriptionFormat", comment: ""), displayName),
            symbol: "music.note",
            state: state,
            actionTitle: actionTitle,
            actionSymbol: actionSymbol,
            isWorking: model.isRequesting(.musicControl(appName))
        ) {
            if isAuthorized {
                model.openMusicAutomationSettings()
            } else if isRunning {
                model.requestMusicControlAuthorization(for: appName)
            } else {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName == "Music" ? "com.apple.Music" : "com.spotify.client") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        symbol: String,
        state: PermissionDisplayState,
        actionTitle: String,
        actionSymbol: String,
        isWorking: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: AppearanceRowLayout.titleDescriptionSpacing) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    permissionBadge(state)
                }

                Text(description)
                    .settingsNoteStyle()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if state == .notAuthorized {
                    Button(action: action) {
                        permissionButtonLabel(
                            title: actionTitle,
                            symbol: actionSymbol,
                            isWorking: isWorking
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else if state == .denied {
                    Button(action: action) {
                        permissionButtonLabel(
                            title: actionTitle,
                            symbol: actionSymbol,
                            isWorking: isWorking
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Button(action: action) {
                        permissionButtonLabel(
                            title: actionTitle,
                            symbol: actionSymbol,
                            isWorking: isWorking
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
            .disabled(isWorking)
        }
        .frame(height: 72)
        .accessibilityElement(children: .contain)
        .animation(.easeOut(duration: 0.16), value: state)
    }

    private func permissionBadge(_ state: PermissionDisplayState) -> some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(state.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(state.color.opacity(0.12))
            }
    }

    @ViewBuilder
    private func permissionButtonLabel(
        title: String,
        symbol: String,
        isWorking: Bool
    ) -> some View {
        if isWorking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 58)
        } else {
            Label(title, systemImage: symbol)
                .frame(minWidth: 58)
        }
    }

    private var guidanceArea: some View {
        ZStack(alignment: .topLeading) {
            if let guidance = model.guidance {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    Text(guidance)
                        .settingsNoteStyle()
                        .lineLimit(2)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        .padding(.horizontal, 2)
        .animation(.easeOut(duration: 0.16), value: model.guidance)
    }

    private var audioCaptureDisplayState: PermissionDisplayState {
        switch model.audioCaptureStatus {
        case .granted: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notAuthorized
        case nil: return .unavailable
        }
    }

    private func actionTitle(for state: PermissionDisplayState) -> String {
        switch state {
        case .authorized: NSLocalizedString("settings.permissions.manage", comment: "")
        case .notAuthorized: NSLocalizedString("settings.permissions.authorize", comment: "")
        case .denied: NSLocalizedString("settings.permissions.goEnable", comment: "")
        case .unavailable: NSLocalizedString("settings.permissions.manage", comment: "")
        }
    }

    private func actionSymbol(for state: PermissionDisplayState, requestingSymbol: String) -> String {
        switch state {
        case .authorized: "gear"
        case .notAuthorized: requestingSymbol
        case .denied: "arrow.right.circle"
        case .unavailable: "gear"
        }
    }

    private var locationDisplayState: PermissionDisplayState {
        guard CLLocationManager.locationServicesEnabled() else { return .unavailable }
        switch model.locationAuthorization {
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied: return .denied
        case .restricted: return .unavailable
        case .notDetermined: return .notAuthorized
        @unknown default: return .unavailable
        }
    }

    private var bluetoothDisplayState: PermissionDisplayState {
        switch model.bluetoothAuthorization {
        case .allowedAlways: return .authorized
        case .denied: return .denied
        case .restricted: return .unavailable
        case .notDetermined: return .notAuthorized
        @unknown default: return .unavailable
        }
    }

    private var dataAccessDisplayState: PermissionDisplayState {
        model.isDataAccessEnabled ? .authorized : .denied
    }

    private var dataAccessActionTitle: String {
        model.isDataAccessEnabled ? NSLocalizedString("settings.common.turnOff", comment: "") : NSLocalizedString("settings.common.turnOn", comment: "")
    }

    private var authorizedPermissionCount: Int {
        [
            model.isAccessibilityAuthorized,
            audioCaptureDisplayState == .authorized,
            locationDisplayState == .authorized,
            bluetoothDisplayState == .authorized,
            model.isDataAccessEnabled,
        ].filter { $0 }.count
    }

    private var permissionCount: Int { 5 }
}
