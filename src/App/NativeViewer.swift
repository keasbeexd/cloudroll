import AVKit
import SwiftUI
import UIKit

/// Full-screen native photo and video viewer. Memories' hidden viewer stays the source of
/// truth for which photo is current; swipes and actions are forwarded to it.
struct NativeViewer: View {
    let photo: ViewerPhoto
    let media: ViewerMedia
    let cookie: String
    let controller: ViewerController
    let onError: (String) -> Void

    @State private var preview: UIImage?
    @State private var full: UIImage?
    @State private var isZoomed = false
    @State private var showsChrome = true
    @State private var offset: CGSize = .zero
    @State private var player: AVPlayer?
    @State private var width: CGFloat = 400
    /// -1 after swiping to the next photo, 1 to the previous; the new photo slides in from that side.
    @State private var incoming: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(max(0.3, 1 - abs(offset.height) / 500))
                .ignoresSafeArea()

            // Videos sit between the glass bars so the player's own controls stay reachable.
            if player != nil {
                content
                    .offset(offset)
                    .padding(.top, 56)
                    .padding(.bottom, 80)
            } else {
                content
                    .offset(offset)
                    .ignoresSafeArea()
            }

            if showsChrome {
                chrome.transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .statusBarHidden(!showsChrome)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() } }
        .simultaneousGesture(swipe)
        .task(id: photo) {
            slideIn()
            await load()
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if let player {
            VideoPlayer(player: player)
        } else if let image = full ?? preview {
            ZoomableImage(image: image, isZoomed: $isZoomed)
        } else {
            ProgressView().tint(.white)
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { Task { await controller.close() } } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .modifier(GlassBackground(shape: Circle()))
                .accessibilityLabel("Close")
                Spacer()
                Text(Self.title(for: photo))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .modifier(GlassBackground(shape: Capsule()))
            }
            .padding(.horizontal, 16)

            Spacer()

            HStack(spacing: 0) {
                actionButton("Share", "square.and.arrow.up", .share)
                actionButton(
                    photo.favorite ? "Unfavorite" : "Favorite",
                    photo.favorite ? "star.fill" : "star",
                    .favorite,
                    tint: photo.favorite ? .yellow : nil
                )
                actionButton("Add to Album", "rectangle.stack.badge.plus", .addToAlbum)
                actionButton("Delete", "trash", .delete, tint: .red)
            }
            .frame(height: 58)
            .padding(.horizontal, 6)
            .modifier(GlassBackground(shape: Capsule()))
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .foregroundStyle(.primary)
        .environment(\.colorScheme, .dark)
    }

    private func actionButton(_ title: String, _ symbol: String, _ action: ViewerController.Action, tint: Color? = nil) -> some View {
        Button {
            Task {
                if !(await controller.perform(action)) {
                    onError("\(title) isn't available for this photo.")
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
        .accessibilityLabel(title)
    }

    /// Horizontal swipes page through photos; a downward swipe closes. Disabled while zoomed.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isZoomed else { return }
                offset = abs(value.translation.width) > abs(value.translation.height)
                    ? CGSize(width: value.translation.width, height: 0)
                    : CGSize(width: 0, height: max(0, value.translation.height))
            }
            .onEnded { value in
                guard !isZoomed else { return }
                let dx = value.predictedEndTranslation.width
                let dy = value.predictedEndTranslation.height
                if offset.height > 0, dy > 220 {
                    Task { await controller.close() }
                } else if offset.width != 0, abs(dx) > 160 {
                    // The current photo leaves fully before Memories moves to the next one.
                    let direction: CGFloat = dx < 0 ? -1 : 1
                    incoming = direction
                    withAnimation(.easeIn(duration: 0.16)) { offset = CGSize(width: direction * width, height: 0) }
                    let leaving = photo.fileid
                    Task { await page(direction: direction, leaving: leaving) }
                    return
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = .zero }
            }
    }

    /// Moves Memories to the neighbouring photo after the slide-out. At either end of the
    /// list nothing changes, so the photo slides back.
    private func page(direction: CGFloat, leaving: Int) async {
        do {
            try await Task.sleep(for: .milliseconds(160))
            direction < 0 ? await controller.next() : await controller.previous()
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return // The viewer closed meanwhile.
        }
        guard controller.state.photo?.fileid == leaving else { return }
        incoming = 0
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { offset = .zero }
    }

    /// Brings a newly current photo in from the side opposite the swipe.
    private func slideIn() {
        guard incoming != 0 else { return }
        var start = Transaction()
        start.disablesAnimations = true
        withTransaction(start) { offset = CGSize(width: -incoming * width, height: 0) }
        incoming = 0
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { offset = .zero }
    }

    private func load() async {
        player?.pause()
        player = nil
        preview = nil
        full = nil
        isZoomed = false
        if let video = media.video {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": cookie], for: video)
            let asset = AVURLAsset(url: video, options: [AVURLAssetHTTPCookiesKey: cookies])
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            player.play()
            return
        }
        do {
            preview = try await ShellImageLoader.shared.image(at: media.preview, cookie: cookie)
            full = try await ShellImageLoader.shared.image(at: media.full, cookie: cookie)
        } catch is CancellationError {
            // The user moved to another photo.
        } catch {
            if preview == nil {
                onError(error.localizedDescription)
            }
            DiagnosticsLog.shared.add("viewer", "Loading \(photo.basename) failed: \(error.localizedDescription)")
        }
    }

    /// Memories' day IDs count days since 1970 in the photo's local time.
    static func title(for photo: ViewerPhoto) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(photo.dayid) * 86400)
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
    }
}

/// Pinch and double-tap zoom for a still image.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isZoomed: $isZoomed) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isScrollEnabled = false
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        if imageView.image !== image {
            imageView.image = image
        }
        if scrollView.zoomScale == 1 {
            imageView.frame = scrollView.bounds
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        @Binding var isZoomed: Bool

        init(isZoomed: Binding<Bool>) {
            _isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            scrollView.isScrollEnabled = zoomed
            if isZoomed != zoomed {
                isZoomed = zoomed
            }
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }
    }
}
