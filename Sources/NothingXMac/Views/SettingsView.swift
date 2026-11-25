// Settings page: the app preferences that used to live only in the right-click
// menu (menu bar battery, low battery alerts, accent, Open at Login), plus
// keyboard shortcuts, version and Quit. Reachable with the gear or ⌘,.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var loginEnabled = Local(LoginItem.isEnabled)

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        guard let short else { return "Development build" }
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "Settings", back: .main)

            PageStack {
                PanelCard(spacing: 10) {
                    SectionCaption("Menu Bar", symbol: "menubar.rectangle")
                    HStack(spacing: 10) {
                        RowIcon(symbol: "battery.75percent", color: Theme.label)
                        Text("Battery").font(.body13)
                        Spacer(minLength: 4)
                        Picker("Battery in Menu Bar", selection: $settings.menuBarBattery) {
                            ForEach(MenuBarBattery.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                    PanelSeparator()
                    toggleRow(Earbud.Part.chargingCase.symbol, "Show Case Battery", detail: "When the case reports its level",
                              isOn: $settings.menuBarCase)
                        .disabled(settings.menuBarBattery == .off)
                }

                PanelCard(spacing: 10) {
                    SectionCaption("General", symbol: "gearshape")
                    toggleRow("bell.badge.fill", "Low Battery Alerts", detail: "Notify at 20% and 10%",
                              isOn: $settings.lowBatteryAlerts)
                    PanelSeparator()
                    toggleRow("paintpalette.fill", "Use System Accent Color", detail: "Instead of Nothing red",
                              isOn: $settings.useSystemAccent)
                    PanelSeparator()
                    toggleRow("power", "Open at Login",
                              detail: LoginItem.isSupported ? "Start with your Mac" : "Install in Applications to enable",
                              isOn: Binding(get: { loginEnabled.value }, set: { on in
                                  LoginItem.setEnabled(on)
                                  loginEnabled.value = LoginItem.isEnabled
                              }))
                        .disabled(!LoginItem.isSupported)
                }

                PanelCard(spacing: 6) {
                    SectionCaption("Keyboard", symbol: "keyboard")
                    shortcut("Noise Cancel · Transparency · Off", "⌘1–3")
                    shortcut("Equalizer", "⌘E")
                    shortcut("Quick Settings", "⌘K")
                    shortcut("Back", "esc")
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppDelegate.appName).font(.caption11Medium)
                        Text(Self.version).font(.caption11).foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                    Button { NSApp.terminate(nil) } label: {
                        Label("Quit", systemImage: "power")
                    }
                    .buttonStyle(PanelButtonStyle())
                    .help("Quit \(AppDelegate.appName) (⌘Q)")
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .onAppear { loginEnabled.value = LoginItem.isEnabled }
    }

    private func toggleRow(_ symbol: String, _ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            RowIcon(symbol: symbol, color: Theme.label)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body13)
                Text(detail).font(.caption11).foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.caption11).foregroundStyle(Theme.secondaryLabel).lineLimit(1)
            Spacer(minLength: 6)
            Text(keys).font(.caption11Medium.monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.controlFill))
        }
    }
}
