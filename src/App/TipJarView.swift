import StoreKit
import SwiftUI

/// The tip jar in Settings, also shown once as a sheet after 30 days of use.
struct TipJarView: View {
    /// Set when shown as the one-time ask, which adds a "Not Now" button.
    var onDismiss: (() -> Void)?

    @Environment(\.purchase) private var purchase
    @State private var tips = TipJar.shared
    @State private var buying: Product.ID?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tips.thanked ? "Thank you!" : "Support Cloudroll")
                        .font(.title2.weight(.semibold))
                    Text(tips.thanked
                        ? "Your tip helps keep Cloudroll going."
                        : "Cloudroll is free and open source. If it's useful to you, a tip helps cover development costs and the hours that go into it.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                switch tips.loadState {
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Loading tips…").foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("Tips aren't available right now. Check your connection and try again later.")
                        .foregroundStyle(.secondary)
                case .ready:
                    ForEach(tips.products) { product in
                        Button {
                            Task { await buy(product) }
                        } label: {
                            HStack {
                                Text(product.displayName).foregroundStyle(.primary)
                                Spacer()
                                if buying == product.id {
                                    ProgressView()
                                } else {
                                    Text(product.displayPrice)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .disabled(buying != nil)
                    }
                }
            } footer: {
                if let message {
                    Text(message)
                } else {
                    Text("Tips are one-time payments through the App Store.")
                }
            }

            if let onDismiss {
                Section {
                    Button("Not Now", action: onDismiss)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Support Cloudroll")
        .navigationBarTitleDisplayMode(.inline)
        .task { await tips.load() }
    }

    private func buy(_ product: Product) async {
        buying = product.id
        message = nil
        defer { buying = nil }
        do {
            message = await tips.complete(try await purchase(product))
        } catch {
            message = "The tip didn't go through: \(error.localizedDescription)"
        }
    }
}
