import Foundation
import Observation
import StoreKit

/// Optional tips through in-app purchase. Tips are donations: they unlock nothing,
/// and nothing about them is kept after the purchase is finished (see docs/decisions/0006).
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()

    /// Consumables, created in App Store Connect with these ids.
    static let productIDs = [
        "io.github.keasbeexd.cloudroll.tip.small",
        "io.github.keasbeexd.cloudroll.tip.medium",
        "io.github.keasbeexd.cloudroll.tip.large",
    ]

    enum LoadState: Equatable {
        case loading
        case ready
        case unavailable
    }

    private(set) var products: [Product] = []
    private(set) var loadState = LoadState.loading
    /// Set after a completed tip, so the screen can say thank you.
    private(set) var thanked = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    private static let firstUseKey = "tips.firstUse"
    private static let askedKey = "tips.asked"
    private static let askAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Finishes tips that completed while the app wasn't running, e.g. after Ask to Buy.
    func start() {
        guard updates == nil else { return }
        if UserDefaults.standard.object(forKey: Self.firstUseKey) == nil {
            UserDefaults.standard.set(Date.now, forKey: Self.firstUseKey)
        }
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    func load() async {
        guard products.isEmpty else { return }
        loadState = .loading
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            loadState = products.isEmpty ? .unavailable : .ready
        } catch {
            DiagnosticsLog.shared.add("tips", "Loading tips failed: \(error.localizedDescription)")
            loadState = .unavailable
        }
    }

    /// Returns a message for the user when the purchase didn't go through, nil otherwise.
    func complete(_ result: Product.PurchaseResult) async -> String? {
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            thanked = true
            return nil
        case .success(.unverified(_, let error)):
            DiagnosticsLog.shared.add("tips", "Unverified tip: \(error.localizedDescription)")
            return "The App Store couldn't verify this tip. Please try again later."
        case .pending:
            return "Your tip is waiting for approval. Thank you!"
        case .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    // MARK: One-time ask

    /// True once, 30 days after first use. The caller checks that nothing is in progress.
    var shouldAsk: Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.askedKey),
              let firstUse = defaults.object(forKey: Self.firstUseKey) as? Date
        else { return false }
        return Date.now.timeIntervalSince(firstUse) >= Self.askAfter
    }

    func markAsked() {
        UserDefaults.standard.set(true, forKey: Self.askedKey)
    }
}
