import AppKit

/// Non-activating NSPanel — never becomes key/main, so it cannot steal focus.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Walking cat (looping PNG frames) + rounded pastel banner trailing behind
/// it, sliding right-to-left across the screen.
///
/// Window is transparent — only the cat and the rounded banner show.
/// All visible elements are NSTextField / layer-backed NSView (no custom
/// draw), since custom draw inside layer-backed parents has been flaky on
/// recent macOS.
final class OverlayController {
    private let config: Config
    private var window: NSPanel?
    private var slideTimer: Timer?
    private lazy var catFrames: [NSImage] = loadCatFrames()

    /// Frame rate of the source walk-cycle video (art/source/cat_moving.mp4).
    private let catFPS: Double = 29.97

    init(config: Config) {
        self.config = config
    }

    /// Loads Resources/cat/cat_000.png, cat_001.png, ... in order.
    private func loadCatFrames() -> [NSImage] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: "cat") ?? []
        let frames = urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { NSImage(contentsOf: $0) }
        NSLog("[MeetingCat] loaded \(frames.count) cat frames")
        return frames
    }

    func show(title: String, startDate: Date? = nil, minutesUntil: Int, completion: (() -> Void)? = nil) {
        NSLog("[MeetingCat] show: title=\(title) minutesUntil=\(minutesUntil)")

        let mouse = NSEvent.mouseLocation
        let pick = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = pick else {
            NSLog("[MeetingCat] no screens — bailing")
            completion?()
            return
        }
        NSLog("[MeetingCat] using screen frame=\(screen.frame) (of \(NSScreen.screens.count) screens)")

        slideTimer?.invalidate()
        slideTimer = nil
        window?.orderOut(nil)
        window = nil

        let screenFrame = screen.frame

        // Build the content view, measure it, then size the window to fit.
        let (content, catView) = makeContentView(title: title, startDate: startDate, minutesUntil: minutesUntil)
        let contentSize = content.fittingSize
        let windowHeight = contentSize.height
        let windowWidth = contentSize.width
        let yTop = screenFrame.maxY - windowHeight - 40

        // Cat faces left, so it enters from the right edge.
        let startFrame = NSRect(
            x: screenFrame.maxX,
            y: yTop,
            width: windowWidth,
            height: windowHeight
        )

        let w = OverlayPanel(
            contentRect: startFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.contentView = content

        w.orderFrontRegardless()
        NSLog("[MeetingCat] window ordered front at \(startFrame)")

        window = w

        // Manual 60Hz slide + fade + walk-cycle frame stepping.
        let startX = startFrame.origin.x
        let endX = screenFrame.minX - windowWidth
        let frames = catFrames
        let fps = catFPS
        let duration = config.slideDuration
        let fadeDuration = config.fadeDuration
        let fadeStart = max(0.0, (duration - fadeDuration) / duration)
        let t0 = Date()
        slideTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak w] timer in
            guard let w = w else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(t0)
            let progress = min(1.0, elapsed / duration)
            let x = startX + (endX - startX) * CGFloat(progress)
            w.setFrameOrigin(NSPoint(x: x, y: yTop))

            if !frames.isEmpty {
                catView.image = frames[Int(elapsed * fps) % frames.count]
            }

            if progress >= fadeStart {
                let fadeProgress = (progress - fadeStart) / max(0.0001, 1.0 - fadeStart)
                w.alphaValue = CGFloat(max(0.0, 1.0 - fadeProgress))
            }

            if progress >= 1.0 {
                timer.invalidate()
                NSLog("[MeetingCat] slide done")
                self?.slideTimer = nil
                self?.window?.orderOut(nil)
                self?.window = nil
                completion?()
            }
        }
    }

    /// Builds a content view: cat NSImageView on the left, banner.png-backed
    /// label trailing on the right. Sized via Auto Layout; caller asks for
    /// `fittingSize` to size the window. Returns the cat view so the slide
    /// timer can step its frames.
    private func makeContentView(title: String, startDate: Date?, minutesUntil: Int) -> (NSView, NSImageView) {
        let catHeight: CGFloat = 90
        let bannerVerticalInset: CGFloat = 12      // top + bottom padding inside the banner PNG (ragged ribbon edge)
        let bannerHorizontalInset: CGFloat = 20    // left + right padding inside the banner PNG
        let textHorizontalPadding: CGFloat = 20
        let textVerticalPadding: CGFloat = 8
        let stackOverlap: CGFloat = -6             // negative spacing — banner tucks behind the cat's tail

        // Sky blue ribbon + navy text to match the navy/light-blue cat.
        let bannerColor = NSColor(srgbRed: 0.56, green: 0.80, blue: 0.94, alpha: 1.0)
        let textColor = NSColor(srgbRed: 0.08, green: 0.15, blue: 0.23, alpha: 1.0)

        // Mirrored so the banner's ragged edge sits at the trailing (right) end,
        // then recolored from the source pink.
        let bannerImage = NSImage(named: "banner").map { tinted(mirrored($0), with: bannerColor) }
        let firstFrame = catFrames.first
        let catAspect: CGFloat = firstFrame.map { $0.size.width / max(1, $0.size.height) } ?? 2.35

        // Comic Sans MS, fallback to bold system font if absent.
        let font = NSFont(name: "Comic Sans MS", size: 18)
            ?? NSFont.systemFont(ofSize: 18, weight: .bold)

        let text = bannerText(title: title, startDate: startDate, minutesUntil: minutesUntil)
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = textColor
        label.alignment = .center
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        // Banner container — uses the banner PNG as its layer contents so it
        // stretches behind the label.
        let banner = NSView()
        banner.wantsLayer = true
        banner.layer?.contentsGravity = .resize
        if let img = bannerImage {
            banner.layer?.contents = img
        } else {
            // Asset missing: visible regression so we don't ship invisibly.
            banner.layer?.backgroundColor = bannerColor.cgColor
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        let cat = NSImageView()
        cat.image = firstFrame
        cat.imageScaling = .scaleProportionallyUpOrDown
        cat.translatesAutoresizingMaskIntoConstraints = false
        // Soft light glow so the dark cat stays visible on dark wallpapers.
        cat.wantsLayer = true
        cat.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.white.withAlphaComponent(0.8)
            s.shadowBlurRadius = 4
            s.shadowOffset = .zero
            return s
        }()

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        container.addSubview(cat)

        NSLayoutConstraint.activate([
            // Cat on the left, fixed size, vertically centered.
            cat.heightAnchor.constraint(equalToConstant: catHeight),
            cat.widthAnchor.constraint(equalToConstant: catHeight * catAspect),
            cat.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cat.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Banner trailing on the right, overlapping the cat's tail.
            banner.leadingAnchor.constraint(equalTo: cat.trailingAnchor, constant: stackOverlap),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Label inside banner, padded.
            // Explicit width from the measured string: NSTextField's intrinsic
            // width comes up a few points short at small sizes and truncates.
            label.widthAnchor.constraint(equalToConstant: ceil((text as NSString).size(withAttributes: [.font: font]).width) + 8),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: textHorizontalPadding + bannerHorizontalInset),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -(textHorizontalPadding + bannerHorizontalInset)),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: textVerticalPadding + bannerVerticalInset),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -(textVerticalPadding + bannerVerticalInset)),

            // Container is as tall as the taller of cat and banner; width is
            // driven by cat+banner content.
            container.heightAnchor.constraint(greaterThanOrEqualTo: cat.heightAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: banner.heightAnchor),
        ])
        let hug = container.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .defaultLow
        hug.isActive = true

        return (container, cat)
    }

    /// Replaces every opaque pixel's color with `color`, keeping the alpha
    /// (so the banner's ragged edge shape is preserved).
    private func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private func mirrored(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            let t = NSAffineTransform()
            t.translateX(by: rect.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
            image.draw(in: rect)
            return true
        }
    }

    private func bannerText(title: String, startDate: Date?, minutesUntil: Int) -> String {
        let mins = minutesUntil == 1 ? "in 1 min" : "in \(minutesUntil) min"
        if let startDate = startDate {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return "\(title)  \u{2022}  \(f.string(from: startDate))  \u{2022}  \(mins)"
        }
        return "\(title)  \u{2022}  \(mins)"
    }
}
