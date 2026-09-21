import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    @State private var hotkeyProblem: String?

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Take a screenshot") {
                    HotkeyRecorder(combo: $settings.hotkey)
                }
                if let hotkeyProblem {
                    Text(hotkeyProblem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Works in any app. Avoid ⇧⌘3, ⇧⌘4 and ⇧⌘5 — macOS already uses those for its own screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dock icon") {
                Picker("Clicking the Dock icon", selection: $settings.dockClickMode) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.menuTitle).tag(mode)
                    }
                }
            }

            Section("Appearance") {
                Picker("Background", selection: $settings.defaultBackground) {
                    Text("Neutral").tag(BackgroundStyle.neutral)
                    ForEach(BackgroundStyle.Gradient.allCases, id: \.self) { gradient in
                        Text(gradient.rawValue.capitalized).tag(BackgroundStyle.gradient(gradient))
                    }
                    ForEach(BackgroundStyle.Tone.allCases, id: \.self) { tone in
                        Text("\(tone.rawValue.capitalized) (flat)").tag(BackgroundStyle.solid(tone))
                    }
                    Text("None").tag(BackgroundStyle.bare)
                }
                Picker("Light or dark", selection: $settings.appearanceMode) {
                    ForEach(Settings.AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("New captures start this way. You can still change either one per screenshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Export") {
                Picker("Image size", selection: $settings.exportScale) {
                    ForEach(Settings.ExportScale.allCases, id: \.self) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                Toggle("Also save a PNG", isOn: $settings.savesToDisk)
                if settings.savesToDisk {
                    LabeledContent("Save to") {
                        HStack(spacing: 8) {
                            Text(settings.saveFolderDisplayName)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseFolder)
                        }
                    }
                }
                Text("The image always goes on the clipboard, with the legend as text beside it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings.onHotkeyError = { error in
                hotkeyProblem = error.localizedDescription
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Where should Shot and Tell save screenshots?"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setSaveFolder(url)
    }
}
