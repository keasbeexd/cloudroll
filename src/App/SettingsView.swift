import SwiftUI

/// Cloudroll's own settings; Memories' settings stay in Memories.
struct SettingsView: View {
    let source: MemoriesSource?

    @Environment(AppLock.self) private var lock
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var icon = AppIcon.current
    @State private var showsAddAccount = false
    @State private var signingOut: Account?

    var body: some View {
        NavigationStack {
            List {
                accountsSection

                Section {
                    NavigationLink {
                        TipJarView()
                    } label: {
                        Label("Support Cloudroll", systemImage: "heart")
                    }
                }

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
            .sheet(isPresented: $showsAddAccount) {
                ServerSetupView(
                    title: "Add Account",
                    isBusy: model.isSigningIn,
                    onCancel: { showsAddAccount = false }
                ) { input in
                    Task {
                        // Success opens the new account, which replaces this whole screen.
                        if await model.signIn(serverInput: input) { showsAddAccount = false }
                    }
                }
                .interactiveDismissDisabled(model.isSigningIn)
            }
            .confirmationDialog(
                "Sign out of \(signingOut?.address ?? "")?",
                isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                titleVisibility: .visible,
                presenting: signingOut
            ) { account in
                Button("Sign Out", role: .destructive) {
                    Task { await model.signOut(account.id) }
                }
            } message: { _ in
                Text("Photos on this iPhone aren't touched. Cloudroll forgets this account and revokes its app password.")
            }
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(model.accounts) { account in
                Button {
                    guard account.id != model.currentID else { return }
                    Task { await model.open(account.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.title).foregroundStyle(.primary)
                            Text(account.address).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.id == model.currentID {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Current account")
                        }
                    }
                }
                // No destructive role: SwiftUI would animate the row away before the confirmation.
                .swipeActions {
                    Button("Sign Out") { signingOut = account }
                        .tint(.red)
                }
                .contextMenu {
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        signingOut = account
                    }
                }
            }
            Button {
                showsAddAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        } header: {
            Text("Accounts")
        } footer: {
            if model.accounts.count > 1 {
                Text("Tap an account to switch. Swipe left to sign out.")
            }
        }
    }
}
