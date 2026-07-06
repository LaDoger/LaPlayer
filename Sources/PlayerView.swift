import Cocoa
import AVFoundation

final class PlayerView: NSView {
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer!
    private var videoURL: URL?
    private var durationSeconds: Double = 0
    private var frameRate: Double = 0

    private var trimStart: CMTime?
    private var trimEnd: CMTime?
    private var exportSession: AVAssetExportSession?

    private let overlay = NSView()
    private let transportIcon = NSImageView()
    private let centerMessageLabel = NSTextField(labelWithString: "")
    private let progressBar = ProgressBarView()
    private let currentTimeLabel = NSTextField(labelWithString: "0:00:00.00")
    private let durationLabel = NSTextField(labelWithString: "0:00:00.00")
    private let legendLabel = NSTextField(labelWithString: "")
    private let resolutionLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "Drop a video file here, or press ⌘O")

    private static let legend: NSAttributedString = {
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .backgroundColor: NSColor.white.withAlphaComponent(0.18),
        ]
        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let items: [(key: String, desc: String)] = [
            ("space", "play/pause"),
            ("←", "-3s"),
            ("→", "+3s"),
            ("<", "prev frame"),
            (">", "next frame"),
            ("?", "snapshot"),
            ("i", "trim start"),
            ("o", "trim end"),
        ]
        let result = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "     ", attributes: descAttrs)) }
            result.append(NSAttributedString(string: " \(item.key) ", attributes: keyAttrs))
            result.append(NSAttributedString(string: " \(item.desc)", attributes: descAttrs))
        }
        return result
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        setupVideoLayer()
        setupOverlay()
        setupTransportIcon()
        setupCenterMessage()
        setupHint()

        registerForDraggedTypes([.fileURL])

        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.updateProgressUI()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    // MARK: - Setup

    private func setupVideoLayer() {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    private func setupOverlay() {
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        overlay.layer?.cornerRadius = 12
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)

        currentTimeLabel.textColor = .white
        durationLabel.textColor = .white
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        legendLabel.font = .systemFont(ofSize: 11, weight: .regular)
        legendLabel.alignment = .center
        legendLabel.attributedStringValue = Self.legend

        resolutionLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        resolutionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        resolutionLabel.alignment = .right

        for field in [currentTimeLabel, durationLabel, legendLabel, resolutionLabel] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = false
            field.isBordered = false
            field.drawsBackground = false
        }

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.onSeek = { [weak self] fraction in
            self?.seek(toFraction: fraction)
        }

        overlay.addSubview(currentTimeLabel)
        overlay.addSubview(durationLabel)
        overlay.addSubview(progressBar)
        overlay.addSubview(legendLabel)
        overlay.addSubview(resolutionLabel)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            overlay.heightAnchor.constraint(equalToConstant: 48),

            currentTimeLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 10),
            currentTimeLabel.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),

            durationLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            durationLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),

            progressBar.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
            progressBar.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            progressBar.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 14),

            legendLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            legendLabel.topAnchor.constraint(equalTo: currentTimeLabel.bottomAnchor, constant: 4),

            resolutionLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            resolutionLabel.centerYAnchor.constraint(equalTo: legendLabel.centerYAnchor),
        ])
    }

    private func setupTransportIcon() {
        transportIcon.translatesAutoresizingMaskIntoConstraints = false
        transportIcon.imageScaling = .scaleProportionallyUpOrDown
        transportIcon.contentTintColor = .white
        transportIcon.wantsLayer = true
        transportIcon.alphaValue = 0
        addSubview(transportIcon)

        NSLayoutConstraint.activate([
            transportIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            transportIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            transportIcon.widthAnchor.constraint(equalToConstant: 100),
            transportIcon.heightAnchor.constraint(equalToConstant: 100),
        ])
    }

    private func showTransportIcon(playing: Bool) {
        let name = playing ? "play.fill" : "pause.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 84, weight: .regular)
        transportIcon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        // Commit the starting alpha this tick, then animate to zero on the next tick so the
        // fade-out reads 0.5 as its starting (presentation) value rather than the leftover 0.
        transportIcon.layer?.removeAllAnimations()
        transportIcon.alphaValue = 0.5
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1.0
                self.transportIcon.animator().alphaValue = 0
            }
        }
    }

    private func setupCenterMessage() {
        centerMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        centerMessageLabel.isEditable = false
        centerMessageLabel.isBordered = false
        centerMessageLabel.drawsBackground = false
        centerMessageLabel.alignment = .center
        centerMessageLabel.textColor = .white
        centerMessageLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        centerMessageLabel.wantsLayer = true
        centerMessageLabel.alphaValue = 0
        centerMessageLabel.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.8)
            s.shadowBlurRadius = 6
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        addSubview(centerMessageLabel)

        NSLayoutConstraint.activate([
            centerMessageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerMessageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerMessageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            centerMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
    }

    /// Flash a message in the center that fades out, mirroring the transport icon HUD.
    private func showCenterMessage(_ text: String) {
        centerMessageLabel.stringValue = text
        centerMessageLabel.layer?.removeAllAnimations()
        centerMessageLabel.alphaValue = 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1.6
                self.centerMessageLabel.animator().alphaValue = 0
            }
        }
    }

    private func setupHint() {
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.drawsBackground = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Loading

    func load(url: URL) {
        videoURL = url
        durationSeconds = 0
        frameRate = 0
        clearTrimMarks()
        UserDefaults.standard.set(url.path, forKey: "lastVideoPath")

        let savedPosition = UserDefaults.standard.double(forKey: Self.positionKey(url))
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if savedPosition > 0 {
            player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: .zero)
        }

        hintLabel.isHidden = true
        legendLabel.attributedStringValue = Self.legend
        resolutionLabel.stringValue = ""
        window?.title = url.path
        window?.representedURL = url

        Task { [weak self] in
            guard let self else { return }
            let duration = try? await item.asset.load(.duration)
            let track = try? await item.asset.loadTracks(withMediaType: .video).first
            let fps = try? await track?.load(.nominalFrameRate)
            let dimensions: (width: Int, height: Int)? = await {
                guard let track else { return nil }
                guard let size = try? await track.load(.naturalSize),
                      let transform = try? await track.load(.preferredTransform) else { return nil }
                let display = size.applying(transform)
                return (Int(abs(display.width).rounded()), Int(abs(display.height).rounded()))
            }()
            await MainActor.run {
                if let duration, duration.seconds.isFinite {
                    self.durationSeconds = duration.seconds
                }
                if let fps, fps > 0 {
                    self.frameRate = Double(fps)
                }
                if let dimensions, dimensions.width > 0, dimensions.height > 0 {
                    let ratio = Double(dimensions.width) / Double(dimensions.height)
                    self.resolutionLabel.stringValue = String(
                        format: "%d * %d (%.2f:1)", dimensions.width, dimensions.height, ratio)
                }
                // If the saved position was at (or near) the very end, restart from the beginning.
                if savedPosition > 0, self.durationSeconds > 0,
                   savedPosition >= self.durationSeconds - 0.5 {
                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                self.updateProgressUI()
            }
        }

        window?.makeFirstResponder(self)

        player.play()
        showTransportIcon(playing: true)
    }

    // MARK: - Transport

    private func seek(to time: CMTime) {
        guard let item = player.currentItem else { return }
        let clamped = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, duration: item.duration))
        player.seek(to: clamped, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.updateProgressUI() }
        }
    }

    func seek(toFraction fraction: CGFloat) {
        guard durationSeconds > 0 else { return }
        seek(to: CMTime(seconds: Double(fraction) * durationSeconds, preferredTimescale: 600))
    }

    func jump(bySeconds seconds: Double) {
        guard player.currentItem != nil else { return }
        seek(to: CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600)))
    }

    func stepFrame(by count: Int) {
        guard let item = player.currentItem else { return }
        player.pause()
        item.step(byCount: count)
        DispatchQueue.main.async { [weak self] in self?.updateProgressUI() }
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if player.rate == 0 {
            let atEnd = durationSeconds > 0 && player.currentTime().seconds >= durationSeconds - 0.05
            if atEnd {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    self?.player.play()
                }
            } else {
                player.play()
            }
            showTransportIcon(playing: true)
        } else {
            player.pause()
            showTransportIcon(playing: false)
        }
    }

    private func updateProgressUI() {
        let current = player.currentTime().seconds
        currentTimeLabel.stringValue = formatTime(current)
        durationLabel.stringValue = formatTime(durationSeconds)
        if durationSeconds > 0 {
            progressBar.progress = CGFloat(current / durationSeconds)
        }
        saveCurrentPosition()
    }

    private static func positionKey(_ url: URL) -> String {
        "position:" + url.path
    }

    private func saveCurrentPosition() {
        guard let videoURL, durationSeconds > 0 else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        UserDefaults.standard.set(current, forKey: Self.positionKey(videoURL))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00:00.00" }
        let whole = Int(seconds)
        let frame = frameRate > 0 ? Int((seconds - Double(whole)) * frameRate) : 0
        return String(format: "%d:%02d:%02d.%02d", whole / 3600, (whole % 3600) / 60, whole % 60, frame)
    }

    // MARK: - Snapshot

    private func takeSnapshot() {
        guard let item = player.currentItem, let videoURL else {
            NSSound.beep()
            return
        }

        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = player.currentTime()
        generator.generateCGImageAsynchronously(for: time) { [weak self] cgImage, _, error in
            guard let self, let cgImage, error == nil else {
                DispatchQueue.main.async { NSSound.beep() }
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                DispatchQueue.main.async { NSSound.beep() }
                return
            }
            let destination = self.nextSnapshotURL(for: videoURL)
            do {
                try data.write(to: destination)
                DispatchQueue.main.async {
                    self.showCenterMessage("Saved \(destination.lastPathComponent)")
                }
            } catch {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    private func nextSnapshotURL(for videoURL: URL) -> URL {
        let folder = videoURL.deletingLastPathComponent()
        let base = videoURL.deletingPathExtension().lastPathComponent
        var index = 1
        var candidate: URL
        repeat {
            candidate = folder.appendingPathComponent("\(base)\(index).jpg")
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    // MARK: - Trim

    private func markTrim(isStart: Bool) {
        guard player.currentItem != nil, durationSeconds > 0 else {
            NSSound.beep()
            return
        }
        let time = player.currentTime()
        let fraction = CGFloat(time.seconds / durationSeconds)

        if isStart {
            // A start after the existing end invalidates that end: drop it and keep only the new start.
            if let end = trimEnd, time > end {
                trimEnd = nil
                progressBar.trimEndFraction = nil
            }
            trimStart = time
            progressBar.trimStartFraction = fraction
            showCenterMessage("Start frame for trimming the clip is marked at \(formatTime(time.seconds))")
        } else {
            // An end before the existing start invalidates that start: drop it and keep only the new end.
            if let start = trimStart, time < start {
                trimStart = nil
                progressBar.trimStartFraction = nil
            }
            trimEnd = time
            progressBar.trimEndFraction = fraction
            showCenterMessage("End frame for trimming the clip is marked at \(formatTime(time.seconds))")
        }

        if let start = trimStart, let end = trimEnd {
            exportClip(start: start, end: end)
        }
    }

    private func clearTrimMarks() {
        trimStart = nil
        trimEnd = nil
        progressBar.trimStartFraction = nil
        progressBar.trimEndFraction = nil
    }

    private func exportClip(start: CMTime, end: CMTime) {
        guard let videoURL, let asset = player.currentItem?.asset else {
            NSSound.beep()
            return
        }
        let lo = min(start, end)
        let hi = max(start, end)
        guard hi.seconds - lo.seconds > 0.01 else {
            showCenterMessage("Trim start and end are the same frame")
            return
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            NSSound.beep()
            return
        }
        let destination = nextClipURL(for: videoURL)
        session.outputURL = destination
        session.outputFileType = Self.exportFileType(for: videoURL)
        session.timeRange = CMTimeRange(start: lo, end: hi)
        exportSession = session

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                switch session.status {
                case .completed:
                    self.clearTrimMarks()
                    self.showCenterMessage("Clip saved as \(destination.lastPathComponent)")
                default:
                    NSSound.beep()
                    self.showCenterMessage("Clip export failed")
                }
                self.exportSession = nil
            }
        }
    }

    private func nextClipURL(for videoURL: URL) -> URL {
        let folder = videoURL.deletingLastPathComponent()
        let base = videoURL.deletingPathExtension().lastPathComponent
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        var index = 1
        var candidate: URL
        repeat {
            candidate = folder.appendingPathComponent("\(base)_\(index).\(ext)")
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func exportFileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "mp4": return .mp4
        case "m4v": return .m4v
        default: return .mov
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: jump(bySeconds: -3); return // left arrow
        case 124: jump(bySeconds: 3); return  // right arrow
        default: break
        }

        if let chars = event.charactersIgnoringModifiers {
            switch chars {
            case ".": stepFrame(by: 1); return
            case ",": stepFrame(by: -1); return
            case "/": takeSnapshot(); return
            case " ": togglePlayPause(); return
            case "i": markTrim(isStart: true); return
            case "o": markTrim(isStart: false); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL else {
            return false
        }
        load(url: url)
        return true
    }
}
