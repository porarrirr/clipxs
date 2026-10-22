import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var showLaunchAtLoginError = false
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section(String(localized: "settings_section_hotkey")) {
                LabeledContent(String(localized: "settings_hotkey_label")) {
                    HotkeyRecorderView()
                }
            }

            Section(String(localized: "settings_section_general")) {
                Stepper(value: $settings.maxEntries, in: SettingsAccess.maxEntriesRange, step: 10) {
                    LabeledContent(
                        String(localized: "settings_max_entries_label"),
                        value: "\(settings.maxEntries)"
                    )
                }
                Picker(String(localized: "settings_retention_label"), selection: $settings.retentionSeconds) {
                    ForEach(RetentionPeriod.allCases) { period in
                        Text(String(localized: String.LocalizationValue(period.titleKey)))
                            .tag(period.rawValue)
                    }
                }
                Toggle(String(localized: "settings_ocr_label"), isOn: $settings.ocrEnabled)
                Toggle(String(localized: "menu_launch_at_login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        guard newValue != LaunchAtLoginManager.isEnabled else { return }
                        if !LaunchAtLoginManager.setEnabled(newValue) {
                            launchAtLogin = LaunchAtLoginManager.isEnabled
                            showLaunchAtLoginError = true
                        }
                    }
            }

            Section(String(localized: "settings_section_excluded_apps")) {
                BundleIdListEditor(
                    descriptionKey: "settings_excluded_apps_description",
                    emptyKey: "settings_excluded_apps_empty",
                    bundleIds: $settings.excludedBundleIds
                )
            }

            Section(String(localized: "settings_section_plain_paste")) {
                BundleIdListEditor(
                    descriptionKey: "settings_plain_paste_description",
                    emptyKey: "settings_plain_paste_empty",
                    bundleIds: $settings.plainPasteBundleIds
                )
            }

            Section(String(localized: "settings_section_data")) {
                Button(String(localized: "menu_clear_history"), role: .destructive) {
                    showClearConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert(String(localized: "launch_at_login_failed_title"), isPresented: $showLaunchAtLoginError) {
            Button(String(localized: "open_login_items_settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "launch_at_login_failed_message"))
        }
        .alert(String(localized: "settings_clear_confirm_title"), isPresented: $showClearConfirmation) {
            Button(String(localized: "menu_clear_history"), role: .destructive) {
                ClipboardStore.shared.clearAll()
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings_clear_confirm_message"))
        }
        .onAppear {
            LaunchAtLoginManager.syncWithSystem()
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }
}
