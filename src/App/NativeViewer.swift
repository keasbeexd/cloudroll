import AVKit
import MapKit
import SwiftUI
import UIKit

/// Full-screen native photo and video viewer. Memories' hidden viewer stays the source of
/// truth for which photo is current; swipes and actions are forwarded to it.
struct NativeViewer: View {
    let photo: ViewerPhoto
    let media: ViewerMedia
    /// The photos either side, shown next to this one while swiping.
    let previous: ViewerMedia?
    let next: ViewerMedia?
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
    @State private var previousImage: UIImage?
    @State private var nextImage: UIImage?
    /// The neighbour that was swiped in, shown until its own load replaces it, so the switch
    /// to Memories' next photo doesn't blink.
    @State private var handoff: UIImage?
    /// Between a committed swipe and Memories reporting the new photo.
    @State private var paging = false
    @State private var showsInfo = false
    /// The motion part of a Live Photo, played over the still.
    @State private var livePlayer: AVPlayer?
    @State private var livePlaying = false
    @State private var showsEditor = false
    /// Bumped after an edit, so the photo loads again.
    @State private var revision = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(max(0.3, 1 - abs(offset.height) / 500))
                .ignoresSafeArea()

            // The neighbours ride along beside the current photo while swiping.
            if offset.width != 0 {
                neighbourView(previousImage)
                    .offset(x: offset.width - width - Self.gap)
                neighbourView(nextImage)
                    .offset(x: offset.width + width + Self.gap)
            }

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
        // Keyed on the URLs, so toggling Favorite doesn't reload the photo.
        .task(id: MediaLoad(media: media, revision: revision)) {
            var settle = Transaction()
            settle.disablesAnimations = true
            withTransaction(settle) { offset = .zero }
            paging = false
            await load()
        }
        .task(id: [previous, next]) { await loadNeighbours() }
        .sheet(isPresented: $showsInfo) {
            PhotoInfoSheet(photo: photo, controller: controller)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .fullScreenCover(isPresented: $showsEditor) {
            PhotoEditorView(fileID: photo.fileid) { changed in
                showsEditor = false
                guard changed else { return }
                Task {
                    await ShellImageLoader.shared.forget([media.preview, media.full])
                    revision += 1
                }
            }
        }
        .onChange(of: isZoomed) { _, zoomed in
            if zoomed { stopLive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard let item = note.object as? AVPlayerItem, item === livePlayer?.currentItem else { return }
            withAnimation(.easeOut(duration: 0.25)) { livePlaying = false }
        }
        .onDisappear {
            player?.pause()
            livePlayer?.pause()
        }
    }

    /// Space between photos while swiping, as in Photos.
    private static let gap: CGFloat = 20

    private func neighbourView(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if let player {
            VideoPlayer(player: player)
        } else if let image = full ?? preview {
            ZoomableImage(image: image, isZoomed: $isZoomed) { pressing in
                pressing ? playLive(muted: false) : stopLive()
            }
            .overlay {
                if let livePlayer {
                    PlayerLayer(player: livePlayer)
                        .opacity(livePlaying ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
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
                if livePlayer != nil {
                    Button { playLive(muted: false) } label: {
                        Label("Live", systemImage: livePlaying ? "livephoto.play" : "livephoto")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    .modifier(GlassBackground(shape: Capsule()))
                    .accessibilityLabel("Play Live Photo")
                    .accessibilityHint("Or touch and hold the photo.")
                }
                Spacer()
                Text(Self.title(for: photo))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .modifier(GlassBackground(shape: Capsule()))
                if photo.editable == true || (photo.local && !photo.video) {
                    // Phone photos open Cloudroll's editor. Server photos open Memories' one,
                    // and the native viewer hides while it's open.
                    Button {
                        if photo.local {
                            stopLive()
                            showsEditor = true
                            return
                        }
                        Task {
                            if !(await controller.perform(.edit)) {
                                onError("Editing isn't available for this photo.")
                            }
                        }
                    } label: {
                        Text("Edit")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                    }
                    .modifier(GlassBackground(shape: Capsule()))
                }
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
                Button { showsInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Info")
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

    /// Horizontal swipes page through photos, with the neighbour following the finger; a
    /// downward swipe closes and an upward one shows the info. Disabled while zoomed.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isZoomed, !paging else { return }
                let dx = value.translation.width
                if abs(dx) > abs(value.translation.height) {
                    // Resist at either end of the list.
                    let hasNeighbour = dx < 0 ? next != nil : previous != nil
                    offset = CGSize(width: hasNeighbour ? dx : dx / 3, height: 0)
                } else {
                    offset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                guard !isZoomed, !paging else { return }
                let dx = value.predictedEndTranslation.width
                let dy = value.predictedEndTranslation.height
                let upward = abs(value.translation.height) > abs(value.translation.width) && value.translation.height < 0
                if offset.height > 0, dy > 220 {
                    Task { await controller.close() }
                } else if upward, dy < -120 {
                    showsInfo = true
                } else if offset.width != 0, abs(dx) > min(160, width / 3) {
                    let toNext = dx < 0
                    if toNext ? next != nil : previous != nil {
                        page(toNext: toNext)
                        return
                    }
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = .zero }
            }
    }

    /// Finishes the slide so the neighbour is centred, then moves Memories to it. The neighbour's
    /// image stays up as the new photo's preview until the full one loads.
    private func page(toNext: Bool) {
        paging = true
        handoff = toNext ? nextImage : previousImage
        let leaving = photo.fileid
        let target = (toNext ? -1 : 1) * (width + Self.gap)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.95)) {
            offset = CGSize(width: target, height: 0)
        } completion: {
            Task {
                toNext ? await controller.next() : await controller.previous()
                // If Memories didn't move (the list changed under us), come back.
                try? await Task.sleep(for: .milliseconds(600))
                guard controller.state.photo?.fileid == leaving else { return }
                handoff = nil
                paging = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = .zero }
            }
        }
    }

    /// The neighbours' previews first, then their full images, so a swipe shows them sharp.
    private func loadNeighbours() async {
        previousImage = nil
        nextImage = nil
        // Let the current photo load first.
        try? await Task.sleep(for: .milliseconds(150))
        for (media, isNext) in [(previous, false), (next, true)] {
            guard let media, let image = try? await ShellImageLoader.shared.image(at: media.preview, cookie: cookie),
                  !Task.isCancelled else { continue }
            if isNext { nextImage = image } else { previousImage = image }
        }
        for (media, isNext) in [(previous, false), (next, true)] {
            guard let media, media.video == nil,
                  let image = try? await ShellImageLoader.shared.image(at: media.full, cookie: cookie),
                  !Task.isCancelled else { continue }
            if isNext { nextImage = image } else { previousImage = image }
        }
    }

    private func load() async {
        player?.pause()
        player = nil
        livePlayer?.pause()
        livePlayer = nil
        livePlaying = false
        preview = handoff
        handoff = nil
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
            // Loads are shared with prefetching and outlive this task, so check before showing.
            let preview = try await ShellImageLoader.shared.image(at: media.preview, cookie: cookie)
            try Task.checkCancellation()
            self.preview = preview
            let full = try await ShellImageLoader.shared.image(at: media.full, cookie: cookie)
            try Task.checkCancellation()
            self.full = full
            await loadLive()
        } catch is CancellationError {
            // The user moved to another photo.
        } catch {
            if preview == nil {
                onError(error.localizedDescription)
            }
            DiagnosticsLog.shared.add("viewer", "Loading \(photo.basename) failed: \(error.localizedDescription)")
        }
    }

    /// Finds the Live Photo's motion part (PhotoKit for phone photos, Memories for server ones)
    /// and plays it once, muted, the way Photos does when you arrive at a Live Photo.
    private func loadLive() async {
        do {
            let file: URL?
            if photo.local {
                file = try await PhotoLibrary.shared.pairedVideoFile(fileID: photo.fileid)
            } else if let live = media.live {
                file = try await LiveVideoLoader.shared.file(at: live, cookie: cookie)
            } else {
                file = nil
            }
            guard let file, !Task.isCancelled else { return }
            let player = AVPlayer(url: file)
            player.actionAtItemEnd = .pause
            livePlayer = player
            playLive(muted: true)
        } catch {
            DiagnosticsLog.shared.add("viewer", "Live Photo for \(photo.basename) failed: \(error.localizedDescription)")
        }
    }

    private func playLive(muted: Bool) {
        guard let livePlayer, !isZoomed else { return }
        livePlayer.isMuted = muted
        livePlayer.seek(to: .zero)
        livePlayer.play()
        withAnimation(.easeIn(duration: 0.15)) { livePlaying = true }
    }

    private func stopLive() {
        guard livePlaying else { return }
        livePlayer?.pause()
        withAnimation(.easeOut(duration: 0.25)) { livePlaying = false }
    }

    /// Memories' day IDs count days since 1970 in the photo's local time.
    static func title(for photo: ViewerPhoto) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(photo.dayid) * 86400)
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
    }
}

/// What the viewer loads, plus a revision for reloading the same photo after an edit.
private struct MediaLoad: Hashable {
    let media: ViewerMedia
    let revision: Int
}

/// Date, camera, file, location, people and albums for the current photo, from what Memories
/// loaded for it. Follows the viewer when the user swipes to another photo.
private struct PhotoInfoSheet: View {
    let photo: ViewerPhoto
    let controller: ViewerController

    @State private var info: PhotoInfo?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let info {
                    details(info)
                } else if failed {
                    ContentUnavailableView("No details", systemImage: "info.circle", description: Text("Memories didn't return details for this photo."))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(info?.dateText ?? NativeViewer.title(for: photo))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: photo.fileid) {
            failed = false
            if info?.fileid != photo.fileid { info = nil }
            var loaded = await controller.info()
            guard !Task.isCancelled else { return }
            // The page answers for whichever photo is current by then.
            if loaded?.fileid != photo.fileid { loaded = nil }
            info = loaded
            failed = loaded == nil
        }
    }

    private func details(_ info: PhotoInfo) -> some View {
        List {
            if info.timeText != nil || info.title != nil || info.description != nil {
                Section {
                    if let time = info.timeText {
                        Label(time, systemImage: "clock")
                    }
                    if let title = info.title {
                        Text(title).font(.headline)
                    }
                    if let description = info.description {
                        Text(description)
                    }
                }
            }
            if info.camera != nil || info.exposureText != nil {
                Section {
                    row(info.camera ?? "Camera", [info.lens, info.exposureText].compactMap { $0 }, symbol: "camera")
                }
            }
            Section {
                row(info.basename, [info.filename, info.fileText].compactMap { $0 }, symbol: "photo")
            }
            if info.hasLocation, let latitude = info.latitude, let longitude = info.longitude {
                Section {
                    location(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), address: info.address)
                }
            } else if let address = info.address {
                Section { Label(address, systemImage: "mappin.and.ellipse") }
            }
            if !info.people.isEmpty {
                Section { Label(info.people.joined(separator: ", "), systemImage: "person.2") }
            }
            if !info.albums.isEmpty {
                Section { Label(info.albums.joined(separator: ", "), systemImage: "rectangle.stack") }
            }
            if !info.tags.isEmpty {
                Section { Label(info.tags.joined(separator: ", "), systemImage: "tag") }
            }
        }
        .textSelection(.enabled)
    }

    private func row(_ title: String, _ lines: [String], symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol)
        }
    }

    private func location(_ coordinate: CLLocationCoordinate2D, address: String?) -> some View {
        let text = address ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
        return VStack(alignment: .leading, spacing: 10) {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker("", coordinate: coordinate)
            }
            .id("\(coordinate.latitude),\(coordinate.longitude)")
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Label(text, systemImage: "mappin.and.ellipse")
            if let url = URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link("Open in Maps", destination: url)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Pinch and double-tap zoom for a still image.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool
    /// Touch and hold: true when it starts, false when it ends (Live Photos play meanwhile).
    var onPress: (Bool) -> Void = { _ in }

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
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.3
        scrollView.addGestureRecognizer(press)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onPress = onPress
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
        var onPress: (Bool) -> Void = { _ in }

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

        @objc func pressed(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: onPress(true)
            case .ended, .cancelled, .failed: onPress(false)
            default: break
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

/// A bare video layer for Live Photos: no controls, fitted like the still.
private struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
