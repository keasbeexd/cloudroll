import SwiftUI

/// Shows recent problems so the user can share them when reporting a bug.
struct DiagnosticsView: View {
    let source: MemoriesSource?

    private var log: DiagnosticsLog { .shared }

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List(log.entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.date.formatted(date: .omitted, time: .standard)) · \(entry.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.message)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .overlay {
            if log.entries.isEmpty {
                ContentUnavailableView("No problems recorded", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: log.report(appVersion: Self.appVersion, source: source))
            }
        }
    }
}
