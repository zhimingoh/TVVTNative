import Foundation
import ServiceManagement

final class LoginItemController: ObservableObject {
    @Published private(set) var status = "正在检查登录启动…"
    @Published private(set) var enabled = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
        if !defaults.bool(forKey: "loginRegistrationAttempted") {
            defaults.set(true, forKey: "loginRegistrationAttempted")
            register()
        }
    }
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: enabled = true; status = "登录时自动启动已启用"
        case .requiresApproval: enabled = false; status = "登录启动等待系统批准"
        case .notRegistered: enabled = false; status = "登录启动未启用"
        case .notFound: enabled = false; status = "登录项找不到应用，请从固定位置运行"
        @unknown default: enabled = false; status = "登录启动状态未知"
        }
    }
    func register() {
        do { try SMAppService.mainApp.register(); refresh() }
        catch { refresh(); status = "登录启动注册失败：\(error.localizedDescription)" }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
