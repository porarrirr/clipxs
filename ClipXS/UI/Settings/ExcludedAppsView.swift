import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Editable bundle-ID list shared by the excluded-apps and plain-paste-apps
/// settings sections.
struct BundleIdListEditor: View {
    let descriptionKey: String
    let emptyKey: String
    @Binding var bundleIds: [String]

    @State private var selection: String?
    @State private var manualBundleId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: String.LocalizationValue(descriptionKey)))
                .font(.caption)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(bundleIds, id: \.self) { bundleId in
                    BundleIdRow(bundleId: bundleId)
                        .tag(bundleId)
                }
            }
            .frame(minHeight: 110, maxHeight: 150)
            .overlay {
                if bundleIds.isEmpty {
                    Text(String(localized: String.LocalizationValue(emptyKey)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    addFromOpenPanel()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    removeSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)

                Spacer()

                TextField(String(localized: "settings_excluded_apps_bundle_id_placeholder"), text: $manualBundleId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(addManualBundleId)
                Button(String(localized: "settings_excluded_apps_add"), action: addManualBundleId)
                    .disabled(manualBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleId = Bundle(url: url)?.bundleIdentifier else { continue }
            append(bundleId)
        }
    }

    private func addManualBundleId() {
        let trimmed = manualBundleId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        append(trimmed)
        manualBundleId = ""
    }

    private func append(_ bundleId: String) {
        guard !bundleIds.contains(bundleId) else { return }
        bundleIds.append(bundleId)
    }

    private func removeSelected() {
        guard let selection else { return }
        bundleIds.removeAll { $0 == selection }
        self.selection = nil
    }
}

private struct BundleIdRow: View {
    let bundleId: String

    var body: some View {
        HStack(spacing: 8) {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(appName ?? bundleId)
                Text(bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
                Text(bundleId)
            }
        }
    }

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    private var appName: String? {
        guard let appURL else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
    }
}
