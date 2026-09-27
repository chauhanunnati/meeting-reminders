import AppKit

/// Non-activating NSPanel — never becomes key/main, so it cannot steal focus.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Plane glyph + rounded pastel banner, sliding across the screen.
///
/// Window is transparent — only the plane emoji and the rounded banner show.
/// All visible elements are NSTextField / layer-backed NSView (no custom
/// draw), since custom draw inside layer-backed parents has been flaky on
/// recent macOS.
final class OverlayController {
    private let config: Config
    private var window: NSPanel?
    private var slideTimer: Timer?

    init(config: Config) {
        self.config = config
    }

    func show(title: String, startDate: Date? = nil, minutesUntil: Int, completion: (() -> Void)? = nil) {
        NSLog("[MeetingAirplane] show: title=\(title) minutesUntil=\(minutesUntil)")

        let mouse = NSEvent.mouseLocation
        let pick = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = pick else {
            NSLog("[MeetingAirplane] no screens — bailing")
            completion?()
            return
        }
        NSLog("[MeetingAirplane] using screen frame=\(screen.frame) (of \(NSScreen.screens.count) screens)")

        slideTimer?.invalidate()
        slideTimer = nil
        window?.orderOut(nil)
        window = nil

        let screenFrame = screen.frame

        // Build the content view, measure it, then size the window to fit.
        let content = makeContentView(title: title, startDate: startDate, minutesUntil: minutesUntil)
        let contentSize = content.fittingSize
        let windowHeight = contentSize.height
        let windowWidth = contentSize.width
        let yTop = screenFrame.maxY - windowHeight - 40

        let startFrame = NSRect(
            x: screenFrame.minX - windowWidth,
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
        NSLog("[MeetingAirplane] window ordered front at \(startFrame)")

        window = w

        // Manual 60Hz slide + fade.
        let startX = startFrame.origin.x
        let endX = screenFrame.maxX
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

            if progress >= fadeStart {
                let fadeProgress = (progress - fadeStart) / max(0.0001, 1.0 - fadeStart)
                w.alphaValue = CGFloat(max(0.0, 1.0 - fadeProgress))
            }

            if progress >= 1.0 {
                timer.invalidate()
                NSLog("[MeetingAirplane] slide done")
                self?.slideTimer = nil
                self?.window?.orderOut(nil)
                self?.window = nil
                completion?()
            }
        }
    }

    /// Builds a content view: banner.png-backed label on the left, plane.png
    /// NSImageView on the right. Sized via Auto Layout; caller asks for
    /// `fittingSize` to size the window.
    private func makeContentView(title: String, startDate: Date?, minutesUntil: Int) -> NSView {
        let planeSize: CGFloat = 220
        let bannerVerticalInset: CGFloat = 35      // top + bottom padding inside the banner PNG (visual rope/ribbon shape)
        let bannerHorizontalInset: CGFloat = 50    // left + right padding inside the banner PNG
        let textHorizontalPadding: CGFloat = 50
        let textVerticalPadding: CGFloat = 22
        let stackOverlap: CGFloat = -10            // negative spacing — plane overlaps banner so rope tucks behind

        let bannerImage = NSImage(named: "banner")
        let planeImage = NSImage(named: "plane")

        // Comic Sans MS, fallback to bold system font if absent.
        let font = NSFont(name: "Comic Sans MS", size: 28)
            ?? NSFont.systemFont(ofSize: 28, weight: .bold)

        let label = NSTextField(labelWithString: bannerText(title: title, startDate: startDate, minutesUntil: minutesUntil))
        label.font = font
        label.textColor = .white
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
            banner.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.65, alpha: 1.0).cgColor
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        let plane = NSImageView()
        plane.image = planeImage
        plane.imageScaling = .scaleProportionallyUpOrDown
        plane.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        container.addSubview(plane)

        NSLayoutConstraint.activate([
            // Plane on the right, fixed size, vertically centered.
            plane.widthAnchor.constraint(equalToConstant: planeSize),
            plane.heightAnchor.constraint(equalToConstant: planeSize),
            plane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            plane.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Banner on the left, hugging the plane with negative overlap so
            // the rope tucks behind it.
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: plane.leadingAnchor, constant: stackOverlap),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Label inside banner, padded.
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: textHorizontalPadding + bannerHorizontalInset),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -(textHorizontalPadding + bannerHorizontalInset)),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: textVerticalPadding + bannerVerticalInset),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -(textVerticalPadding + bannerVerticalInset)),

            // Container has a fixed height = plane height; width is driven by
            // banner+plane content.
            container.heightAnchor.constraint(equalToConstant: planeSize),
        ])

        return container
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
