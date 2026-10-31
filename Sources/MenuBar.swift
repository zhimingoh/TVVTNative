import SwiftUI
import AppKit
import Combine

struct CoolerMenu: View {
    @ObservedObject var ble: BluetoothController
    @ObservedObject var temperature: TemperatureMonitor
    @ObservedObject var login: LoginItemController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "fanblades.fill").foregroundStyle(.cyan)
                Text("TVVT 散热器").font(.headline)
                Spacer()
                Circle().fill(ble.connected ? .green : .orange).frame(width: 8, height: 8)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(ble.temperatureText).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("本机芯片温度").foregroundStyle(.secondary)
            }
            Text(temperature.source).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                modeButton(.fullSpeed, symbol: "bolt.fill")
                modeButton(.automatic, symbol: "thermometer.medium")
            }
            Text(ble.controlStatus).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let demand = ble.demand, ble.coolingMode != .manual {
                Text("请求 \(demand.watts)W · 风扇 \(demand.fan)/10").font(.caption).foregroundStyle(.secondary)
            }
            if let state = ble.telemetry {
                Divider()
                HStack {
                    reading("冷面", value: String(format: "%.1f℃", state.cold))
                    Spacer()
                    reading("热面", value: String(format: "%.1f℃", state.hot))
                    Spacer()
                    reading("转速", value: "\(state.rpm) RPM")
                }
                Text("设备报告：\([1:10, 2:18, 3:36][state.power].map { "\($0)W 档" } ?? "未知功率档") · 风扇 \(state.fan)/10")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text(ble.message).font(.caption).fixedSize(horizontal: false, vertical: true)
            if ble.needsBluetoothAuthorization {
                Button("蓝牙授权设置", action: ble.openBluetoothAuthorization)
            }
            HStack {
                if ble.connected || ble.isConnecting { Button("断开", action: ble.disconnect) }
                else { Button(ble.autoPaused ? "恢复自动连接" : "连接散热器", action: ble.reconnect) }
                Spacer()
                Button("控制面板") { AppDelegate.current?.showControlPanel() }
            }
            Divider()
            Text(login.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                if !login.enabled { Button("启用登录启动", action: login.register) }
                Button("登录项设置", action: login.openSettings)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }.font(.caption)
        }
        .padding(18).frame(width: 350)
        .onAppear { login.refresh() }
    }
    private func modeButton(_ mode: CoolingMode, symbol: String) -> some View {
        Button { ble.selectMode(mode) } label: {
            HStack(spacing: 5) {
                Image(systemName: ble.coolingMode == mode ? "checkmark.circle.fill" : symbol)
                Text(mode.title)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(ble.coolingMode == mode ? .accentColor : .gray)
        .accessibilityLabel(mode.title)
        .accessibilityValue(ble.coolingMode == mode ? "已选中" : "未选中")
    }
    private func reading(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).monospacedDigit()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    private var panel: NSWindow?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        let ble = BluetoothController.shared
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "TVVT 散热器")
        statusItem?.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem?.button?.imagePosition = .imageLeading
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(toggleMenu)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CoolerMenu(ble: ble, temperature: ble.temperature, login: ble.login))
        subscription = ble.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.statusItem?.button?.title = ble.menuTitle }
        }
        statusItem?.button?.title = ble.menuTitle
        ble.startBluetooth()
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstLaunch { showControlPanel() }
    }
    @objc func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func showControlPanel() {
        popover.performClose(nil)
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "TVVT 散热器"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView(ble: .shared))
            window.center(); panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlPanel(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct TVVTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
