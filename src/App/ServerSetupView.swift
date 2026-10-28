import SwiftUI

struct ServerSetupView: View {
    var title = "Cloudroll"
    let isBusy: Bool
    var onCancel: (() -> Void)?
    let onConnect: (String) -> Void

    @State private var input = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://cloud.example.com", text: $input)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { onConnect(input) }
                } header: {
                    Text("Nextcloud server")
                } footer: {
                    Text("You'll sign in on your server's page. Cloudroll never sees your password.")
                }
                Button {
                    onConnect(input)
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("Sign in")
                    }
                }
                .disabled(isBusy)
            }
            .navigationTitle(title)
            .toolbar {
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
        }
    }
}
