import SwiftUI

struct ScreenshotsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// Read per render: Save to can change in ⇧⌘5 while this pane is open.
    private var folder: URL {
        ScreenshotScanner.folder(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureCommandsSection(owner: .screenshots, anchor: .screenshotsCommands)

            Section {
                Picker(selection: $settings.screenshotAfterUse) {
                    ForEach(ScreenshotAfterUse.allCases) { afterUse in
                        Text(afterUse.title).tag(afterUse)
                    }
                } label: {
                    SettingsRowTitle(.screenshotsCleanUp, "After pasting or copying")
                    Text("⌃⌘↵ always does the other.")
                }
                Picker(selection: $settings.screenshotAutoDelete) {
                    ForEach(ScreenshotAutoDelete.allCases) { autoDelete in
                        Text(autoDelete.title).tag(autoDelete)
                    }
                } label: {
                    SettingsRowTitle(.screenshotsCleanUp, "Move old captures to the Trash")
                    Text("Checked every hour. Kept captures always stay.")
                }
            } header: {
                SettingsSectionHeader(.screenshotsCleanUp)
            }

            Section {
                Toggle(isOn: $settings.screenshotTextSearchEnabled) {
                    SettingsRowTitle(.screenshotsSearch, "Search text in screenshots")
                    Text("Recognized on this Mac while Screenshots is open.")
                }
            } header: {
                SettingsSectionHeader(.screenshotsSearch)
            }

            Section {
                LabeledContent {
                    Button("Show in Finder") { NSWorkspace.shared.open(folder) }
                } label: {
                    SettingsRowTitle(.screenshotsFolder, "Screenshot folder")
                    Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)
                }
            } header: {
                SettingsSectionHeader(.screenshotsFolder)
            } footer: {
                Text("macOS decides where captures go. Press ⇧⌘5 and choose Options to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.screenshots)
    }
}
