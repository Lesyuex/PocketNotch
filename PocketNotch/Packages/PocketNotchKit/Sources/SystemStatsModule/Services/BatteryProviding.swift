@MainActor
protocol BatteryProviding: AnyObject {
    func currentSnapshot() -> BatterySnapshot?
    func startObserving(_ handler: @escaping () -> Void)
    func stopObserving()
}
