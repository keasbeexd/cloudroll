import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Cloudroll's own editor for phone photos (server photos use Memories' editor): light and
/// colour, filters, rotate and crop. Edits are saved through PhotoKit, so they show in Photos
/// and can be reverted there.
struct PhotoEditorView: View {
    let fileID: Int
    /// True when the photo changed.
    let onClose: (Bool) -> Void

    @State private var session: PhotoEditSession?
    @State private var edit = PhotoEdit()
    @State private var rendered: UIImage?
    @State private var filterPreviews: [PhotoEdit.Filter: UIImage] = [:]
    @State private var mode = Mode.adjust
    @State private var adjustment = Adjustment.exposure
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false
    @State private var confirmsRevert = false

    enum Mode: String, CaseIterable {
        case adjust = "Adjust"
        case filters = "Filters"
        case crop = "Crop"

        var symbol: String {
            switch self {
            case .adjust: "dial.medium"
            case .filters: "camera.filters"
            case .crop: "crop.rotate"
            }
        }
    }

    enum Adjustment: String, CaseIterable {
        case exposure = "Exposure"
        case contrast = "Contrast"
        case saturation = "Saturation"
        case warmth = "Warmth"

        var symbol: String {
            switch self {
            case .exposure: "plusminus.circle"
            case .contrast: "circle.lefthalf.filled"
            case .saturation: "drop"
            case .warmth: "thermometer.medium"
            }
        }

        var keyPath: WritableKeyPath<PhotoEdit, Double> {
            switch self {
            case .exposure: \.exposure
            case .contrast: \.contrast
            case .saturation: \.saturation
            case .warmth: \.warmth
            }
        }
    }

    /// Aspect ratios offered for cropping; nil is the photo's own.
    private static let aspects: [(String, CGFloat?)] = [
        ("Original", nil), ("Square", 1), ("4:3", 4.0 / 3), ("3:4", 3.0 / 4), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
    ]

    /// The crop is drawn over the whole rotated photo, so it's left out while cropping.
    private var shownEdit: PhotoEdit {
        var shown = edit
        if mode == .crop { shown.crop = PhotoEdit.fullCrop }
        return shown
    }

    private var hasChanges: Bool {
        edit != (session?.previous ?? PhotoEdit())
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
            if session != nil {
                controls
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task { await open() }
        .task(id: shownEdit) { await render(shownEdit) }
        .alert("Couldn't edit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {
                if session == nil { onClose(false) }
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { onClose(false) }
        }
        .confirmationDialog(
            "The photo goes back to how it was taken. Edits made in Photos or other apps are removed too.",
            isPresented: $confirmsRevert,
            titleVisibility: .visible
        ) {
            Button("Revert to Original", role: .destructive) { Task { await revert() } }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                if hasChanges { confirmsDiscard = true } else { onClose(false) }
            }
            Spacer()
            if session?.hasAdjustments == true {
                Button("Revert") { confirmsRevert = true }
                    .tint(.red)
                    .disabled(isSaving)
                Spacer()
            }
            if isSaving {
                ProgressView()
            } else {
                Button("Done") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let area = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 16, dy: 16)
            ZStack {
                if let rendered {
                    let frame = AVMakeRect(aspectRatio: rendered.size, insideRect: area)
                    Image(uiImage: rendered)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    if mode == .crop {
                        CropOverlay(crop: $edit.crop, frame: frame)
                    }
                } else {
                    ProgressView().position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            switch mode {
            case .adjust: adjustControls
            case .filters: filterControls
            case .crop: cropControls
            }
            HStack(spacing: 0) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Button { mode = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 19))
                            Text(item.rawValue).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(mode == item ? Color.yellow : Color.secondary)
                    }
                }
            }
            .frame(height: 50)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var adjustControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Adjustment.allCases, id: \.self) { item in
                    let value = edit[keyPath: item.keyPath]
                    Button { adjustment = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 17))
                            Text(value == 0 ? item.rawValue : "\(Int((value * 100).rounded()))")
                                .font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(adjustment == item ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(value == 0 ? Color.primary : Color.yellow)
                    }
                    .accessibilityLabel(item.rawValue)
                }
            }
            HStack(spacing: 12) {
                Slider(value: $edit[dynamicMember: adjustment.keyPath], in: -1...1)
                    .tint(.yellow)
                Button("Reset") { edit[keyPath: adjustment.keyPath] = 0 }
                    .font(.footnote)
                    .disabled(edit[keyPath: adjustment.keyPath] == 0)
            }
        }
        .padding(.horizontal, 20)
    }

    private var filterControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PhotoEdit.Filter.allCases, id: \.self) { filter in
                    Button { edit.filter = filter } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let preview = filterPreviews[filter] {
                                    Image(uiImage: preview).resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.1)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(edit.filter == filter ? Color.yellow : .clear, lineWidth: 2)
                            }
                            Text(filter.title)
                                .font(.caption2)
                                .foregroundStyle(edit.filter == filter ? Color.yellow : Color.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 96)
    }

    private var cropControls: some View {
        HStack(spacing: 18) {
            Button { edit.rotateLeft() } label: {
                Image(systemName: "rotate.left").font(.system(size: 20))
            }
            .accessibilityLabel("Rotate")
            Menu {
                ForEach(Self.aspects.indices, id: \.self) { index in
                    let (name, aspect) = Self.aspects[index]
                    Button(name) { edit.crop = crop(forAspect: aspect) }
                }
            } label: {
                Label("Aspect", systemImage: "aspectratio").font(.subheadline)
            }
            Spacer()
            Button("Reset") {
                edit.turns = 0
                edit.crop = PhotoEdit.fullCrop
            }
            .font(.subheadline)
            .disabled(!edit.changesGeometry)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    /// Ratios are of the photo as it's shown, so a turned photo keeps its look.
    private func crop(forAspect aspect: CGFloat?) -> CGRect {
        guard let aspect, let rendered, rendered.size.height > 0 else { return PhotoEdit.fullCrop }
        return PhotoEdit.centredCrop(aspect: aspect, imageAspect: rendered.size.width / rendered.size.height)
    }

    // MARK: Loading and saving

    private func open() async {
        do {
            let session = try await PhotoLibrary.shared.editSession(fileID: fileID)
            self.session = session
            edit = session.previous ?? PhotoEdit()
            filterPreviews = await EditPreviewRenderer.shared.filterPreviews(of: session.preview)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func render(_ shown: PhotoEdit) async {
        guard let session else { return }
        if let image = await EditPreviewRenderer.shared.render(shown, of: session.preview), !Task.isCancelled {
            rendered = image
        }
    }

    private func save() async {
        guard let session else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Undoing every change of an earlier Cloudroll edit is the same as reverting it.
            if edit.isOriginal {
                try await PhotoLibrary.shared.revert(session)
            } else {
                try await PhotoLibrary.shared.save(edit, in: session)
            }
            onClose(true)
        } catch is EditCancelled {
            // The user said no in iOS's prompt; the editor stays open.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revert() async {
        guard let session else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibrary.shared.revert(session)
            onClose(true)
        } catch is EditCancelled {
            // Declined in iOS's prompt.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Renders the editor's previews off the main thread. Slider drags queue many renders, and
/// those already replaced by a newer one are skipped.
private actor EditPreviewRenderer {
    static let shared = EditPreviewRenderer()

    private let context = CIContext()

    func render(_ edit: PhotoEdit, of image: CIImage) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let output = edit.apply(to: image)
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func filterPreviews(of image: CIImage) -> [PhotoEdit.Filter: UIImage] {
        let scale = 160 / max(image.extent.width, image.extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var previews: [PhotoEdit.Filter: UIImage] = [:]
        for filter in PhotoEdit.Filter.allCases {
            var edit = PhotoEdit()
            edit.filter = filter
            if let preview = render(edit, of: small) {
                previews[filter] = preview
            }
        }
        return previews
    }
}

/// The crop frame over the photo: drag a corner to resize it, or inside it to move it.
private struct CropOverlay: View {
    @Binding var crop: CGRect
    /// Where the photo is drawn.
    let frame: CGRect

    @State private var start: CGRect?

    var body: some View {
        let rect = CGRect(
            x: frame.minX + crop.minX * frame.width,
            y: frame.minY + crop.minY * frame.height,
            width: crop.width * frame.width,
            height: crop.height * frame.height
        )
        ZStack {
            Path { path in
                path.addRect(frame)
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .background(gridLines)
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(drag { PhotoEdit.moved($0, by: $1) })

            ForEach(PhotoEdit.Corner.allCases, id: \.self) { corner in
                handle
                    .position(point(of: corner, in: rect))
                    .gesture(drag { PhotoEdit.resized($0, corner: corner, by: $1) })
            }
        }
    }

    private var gridLines: some View {
        GeometryReader { proxy in
            Path { path in
                for third in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: proxy.size.width * third, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width * third, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * third))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * third))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
    }

    /// A large touch target with a small visible corner.
    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func point(of corner: PhotoEdit.Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// Translations become fractions of the photo, applied to the crop the drag started from.
    private func drag(_ change: @escaping (CGRect, CGSize) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let from = start ?? crop
                start = from
                let delta = CGSize(width: value.translation.width / frame.width, height: value.translation.height / frame.height)
                crop = change(from, delta)
            }
            .onEnded { _ in start = nil }
    }
}
