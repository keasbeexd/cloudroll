import SwiftUI

/// Cloudroll's own settings; Memories' settings stay in Memories.
struct SettingsView: View {
    let source: MemoriesSource?

    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var icon = AppIcon.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { lock.isEnabled }, set: { enabled in
                        Task { await lock.setEnabled(enabled) }
                    })) {
                        Label("Require \(AppLock.methodName)", systemImage: AppLock.methodSymbol)
                    }
                    .disabled(!AppLock.isAvailable)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(AppLock.isAvailable
                        ? "Cloudroll locks whenever you leave it. Your passcode works too."
                        : "Set a passcode in the Settings app to lock Cloudroll.")
                }

                Section {
                    NavigationLink {
                        AppIconPicker(selected: $icon)
                    } label: {
                        HStack(spacing: 12) {
                            AppIconImage(icon: icon, size: 29)
                            Text("App Icon")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        DiagnosticsView(source: source)
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    LabeledContent("Version", value: DiagnosticsView.appVersion)
                }
            }
            .navigationTitle("Cloudroll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
