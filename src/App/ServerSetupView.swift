import SwiftUI

struct ServerSetupView: View {
    @Binding var serverURL: String
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://cloud.example.com", text: $input)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(connect)
                } header: {
                    Text("Nextcloud server")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Button("Connect", action: connect)
            }
            .navigationTitle("Cloudroll")
        }
    }

    private func connect() {
        guard MemoriesURL.make(from: input) != nil else {
            error = "Enter the full https:// address of your Nextcloud, e.g. https://cloud.example.com"
            return
        }
        serverURL = input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
