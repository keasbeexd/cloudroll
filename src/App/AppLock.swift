import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Optional Face ID (or Touch ID, or passcode) lock, applied whenever the app leaves the screen.
/// The lock screen gets a window of its own, so it also covers sheets and the editor.
@MainActor
@Observable
final class AppLock {
    static let enabledKey = "appLock.enabled"

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    private(set) var isLocked: Bool {
        didSet { updateWindow() }
    }
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var isAuthenticating = false
    /// Face ID's own prompt makes the app inactive and active again, so the lock asks
    /// automatically only on coming back from the background, never after a cancelled prompt.
    @ObservationIgnored private var asksWhenActive: Bool

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isLocked = enabled
        asksWhenActive = enabled
    }

    /// "Face ID", "Touch ID" or "Passcode", whichever unlocks this device.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static var methodSymbol: String {
        switch methodName {
        case "Face ID": "faceid"
        case "Touch ID": "touchid"
        case "Optic ID": "opticid"
        default: "lock"
        }
    }

    /// Without a passcode set, iOS has nothing to check.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func sceneChanged(to phase: ScenePhase) {
        // At launch the scene only exists once the first phase arrives.
        updateWindow()
        switch phase {
        case .background:
            guard isEnabled else { return }
            isLocked = true
            asksWhenActive = true
        case .active:
            guard isLocked, asksWhenActive else { return }
            asksWhenActive = false
            Task { await unlock() }
        default:
            break
        }
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate(reason: "Unlock Cloudroll to see your photos.") {
            isLocked = false
        }
    }

    /// Turning the lock on or off asks first, so someone holding an unlocked phone can't
    /// simply switch it off.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        let reason = enabled ? "Turn on the lock for Cloudroll." : "Turn off the lock for Cloudroll."
        guard await authenticate(reason: reason) else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    private func updateWindow() {
        guard isLocked else {
            window?.isHidden = true
            window = nil
            return
        }
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: LockScreen(lock: self))
        window.isHidden = false
        self.window = window
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            return try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Shown while locked, including in the app switcher.
struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Cloudroll is locked")
                .font(.title3.weight(.semibold))
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(AppLock.methodName)", systemImage: AppLock.methodSymbol)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
