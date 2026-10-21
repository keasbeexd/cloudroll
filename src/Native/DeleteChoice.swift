import Foundation
import Observation

/// Where to delete photos that are both on this iPhone and on Nextcloud.
enum DeleteChoice: Equatable {
    case both
    case cloudOnly
    case phoneOnly
    case cancel
}

/// Asks the user, from the local server's delete endpoint, where to delete photos that
/// exist in both places. Memories' own delete flow can only remove both, so:
/// - cloud only: the following non-dry phone delete is skipped;
/// - phone only: the phone copies are deleted right away and Memories' flow is aborted
///   before it reaches the server (Memories ignores that failure silently).
@MainActor
@Observable
final class DeleteChoiceCenter {
    static let shared = DeleteChoiceCenter()

    /// Photos on both, while the question is shown.
    private(set) var pendingCount: Int?
    @ObservationIgnored private var continuation: CheckedContinuation<DeleteChoice, Never>?
    /// Set by "Nextcloud only" for the delete call that follows the dry run.
    @ObservationIgnored private var skipNextPhoneDelete = false

    func skipNextPhoneDeletion() {
        skipNextPhoneDelete = true
    }

    /// True once after "Nextcloud only" was chosen.
    func consumeSkipNextPhoneDeletion() -> Bool {
        defer { skipNextPhoneDelete = false }
        return skipNextPhoneDelete
    }

    func ask(count: Int) async -> DeleteChoice {
        continuation?.resume(returning: .cancel)
        pendingCount = count
        return await withCheckedContinuation { continuation = $0 }
    }

    func answer(_ choice: DeleteChoice) {
        pendingCount = nil
        continuation?.resume(returning: choice)
        continuation = nil
    }
}
