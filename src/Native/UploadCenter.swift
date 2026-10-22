import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Native uploads from the header's Upload menu: picks photos, a camera shot or files and
/// uploads them to Nextcloud (the open folder in Folders view, else the first timeline
/// folder), never overwriting existing files.
@MainActor
@Observable
final class UploadCenter {
    enum Source {
        case photoLibrary
        case camera
        case files
    }

    static let shared = UploadCenter()

    private(set) var progress: String?
    @ObservationIgnored private var presenter: PickerPresenter?

    /// Returns a message for the user when something went wrong, nil on success or cancel.
    func upload(from source: Source, folder: String?) async -> String? {
        guard let context = ShellHost.shared.uploadContext else {
            return "Uploading needs the local Memories server, which isn't running."
        }
        let staging = FileManager.default.temporaryDirectory.appending(path: "native-uploads/\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            do {
                if FileManager.default.fileExists(atPath: staging.path) {
                    try FileManager.default.removeItem(at: staging)
                }
            } catch {
                DiagnosticsLog.shared.add("upload", "Removing temporary upload files failed: \(error.localizedDescription)")
            }
        }

        let files: [URL]
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let presenter = PickerPresenter(staging: staging)
            self.presenter = presenter
            defer { self.presenter = nil }
            files = try await presenter.pick(source)
        } catch {
            return "Couldn't prepare the files: \(error.localizedDescription)"
        }
        guard !files.isEmpty else { return nil }

        do {
            let destination: String
            if let folder {
                destination = folder
            } else {
                destination = try await context.proxy.timelineFolder(webRoot: context.webRoot)
            }
            let now = Int(Date().timeIntervalSince1970)
            for (index, file) in files.enumerated() {
                progress = files.count == 1 ? "Uploading…" : "Uploading \(index + 1) of \(files.count)…"
                let path = (destination.hasSuffix("/") ? destination : destination + "/") + file.lastPathComponent
                let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                _ = try await context.proxy.upload(
                    file: file, to: path, user: context.user, webRoot: context.webRoot, mtime: now, contentType: type
                )
            }
            progress = nil
            await PageState.shared.libraryChanged()
            return nil
        } catch {
            progress = nil
            DiagnosticsLog.shared.add("upload", "Upload failed: \(error.localizedDescription)")
            return "Upload failed: \(error.localizedDescription)"
        }
    }
}

/// Presents the system pickers and copies the chosen items into a staging folder.
@MainActor
private final class PickerPresenter: NSObject, PHPickerViewControllerDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    private let staging: URL
    private var continuation: CheckedContinuation<[URL], Error>?

    init(staging: URL) {
        self.staging = staging
    }

    func pick(_ source: UploadCenter.Source) async throws -> [URL] {
        guard let top = Self.topViewController() else { return [] }
        let picker: UIViewController
        switch source {
        case .photoLibrary:
            var config = PHPickerConfiguration()
            config.filter = .any(of: [.images, .videos])
            config.selectionLimit = 0
            // Originals as captured, not converted.
            config.preferredAssetRepresentationMode = .current
            let controller = PHPickerViewController(configuration: config)
            controller.delegate = self
            picker = controller
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                throw PhotoLibraryError(reason: "This device has no camera.")
            }
            let controller = UIImagePickerController()
            controller.sourceType = .camera
            controller.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            controller.delegate = self
            picker = controller
        case .files:
            let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie], asCopy: true)
            controller.allowsMultipleSelection = true
            controller.delegate = self
            picker = controller
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            top.present(picker, animated: true)
        }
    }

    private func finish(_ result: Result<[URL], Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    // MARK: Photo library

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            do {
                var files: [URL] = []
                for result in results {
                    files.append(try await self.copy(result.itemProvider))
                }
                self.finish(.success(files))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    /// The provider's file only exists during the callback, so it's copied right away.
    private func copy(_ provider: NSItemProvider) async throws -> URL {
        let type = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .movie) || type.conforms(to: .image)
        } ?? UTType.image.identifier
        let staging = self.staging
        let name = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? PhotoLibraryError(reason: "The item has no file."))
                    return
                }
                let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
                let base = name ?? url.deletingPathExtension().lastPathComponent
                let destination = UpstreamProxy.uniqueDestination(in: staging, for: ext.isEmpty ? base : "\(base).\(ext)")
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Camera

    nonisolated func imagePickerController(
        _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            let stamp = Int(Date().timeIntervalSince1970)
            do {
                if let movie = info[.mediaURL] as? URL {
                    let destination = UpstreamProxy.uniqueDestination(in: self.staging, for: "VID_\(stamp).\(movie.pathExtension)")
                    try FileManager.default.copyItem(at: movie, to: destination)
                    self.finish(.success([destination]))
                } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.92) {
                    let destination = UpstreamProxy.uniqueDestination(in: self.staging, for: "IMG_\(stamp).jpg")
                    try data.write(to: destination)
                    self.finish(.success([destination]))
                } else {
                    self.finish(.success([]))
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            self.finish(.success([]))
        }
    }

    // MARK: Files

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor in
            do {
                let files = try urls.map { url in
                    let destination = UpstreamProxy.uniqueDestination(in: self.staging, for: url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: destination)
                    return destination
                }
                self.finish(.success(files))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in self.finish(.success([])) }
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
