import AppKit
import SwiftUI

@MainActor
final class PinnedScreenshotWindowController: NSWindowController, NSWindowDelegate {
    private let image: NSImage
    private let onClose: (PinnedScreenshotWindowController) -> Void
    private let scaleModel = PinnedScaleModel()
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 3.0

    init(image: NSImage, onClose: @escaping (PinnedScreenshotWindowController) -> Void) {
        self.image = image
        self.onClose = onClose

        let initialSize = Self.initialWindowSize(for: image.size)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow(window, initialSize: initialSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }

    func setWindowOpacity(_ opacity: Double) {
        window?.alphaValue = CGFloat(min(max(opacity, 0.25), 1))
    }

    func setMousePassthrough(_ enabled: Bool) {
        window?.ignoresMouseEvents = enabled
    }

    func zoomIn() {
        setScale(scaleModel.scale * 1.2)
    }

    func zoomOut() {
        setScale(scaleModel.scale / 1.2)
    }

    func resetZoom() {
        setScale(1.0)
    }

    private func setScale(_ scale: CGFloat) {
        let newScale = min(max(scale, minScale), maxScale)
        guard newScale != scaleModel.scale else { return }

        scaleModel.scale = newScale

        guard let window = window else { return }

        let imageSize = image.size
        let newWidth = imageSize.width * newScale + 24
        let newHeight = imageSize.height * newScale + 24

        let currentFrame = window.frame
        let newSize = CGSize(width: max(newWidth, 220), height: max(newHeight, 160))

        let newOrigin = CGPoint(
            x: currentFrame.midX - newSize.width / 2,
            y: currentFrame.midY - newSize.height / 2
        )

        let newFrame = CGRect(origin: newOrigin, size: newSize)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        })
    }

    private func configureWindow(_ window: NSWindow, initialSize: CGSize) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.alphaValue = 1
        window.contentAspectRatio = image.size
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = PinnedScreenshotView(
            image: image,
            scaleModel: scaleModel,
            onCopy: { [weak self] in self?.copyImage() },
            onClose: { [weak window] in window?.performClose(nil) },
            onZoomIn: { [weak self] in self?.zoomIn() },
            onZoomOut: { [weak self] in self?.zoomOut() },
            onResetZoom: { [weak self] in self?.resetZoom() }
        )

        window.contentView = NSHostingView(rootView: rootView)
        positionWindow(window, size: initialSize)

        addScrollMonitor(to: window)
    }

    private func addScrollMonitor(to window: NSWindow) {
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  window.isKeyWindow else {
                return event
            }

            let mouseLocation = NSEvent.mouseLocation
            let windowFrame = window.frame
            guard windowFrame.contains(mouseLocation) else {
                return event
            }

            let deltaY = event.scrollingDeltaY
            if abs(deltaY) > 0.5 {
                if deltaY > 0 {
                    self.zoomIn()
                } else {
                    self.zoomOut()
                }
            }
            return nil
        }
    }

    private func positionWindow(_ window: NSWindow, size: CGSize) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let mouseLocation = NSEvent.mouseLocation

        let origin = CGPoint(
            x: min(max(mouseLocation.x + 24, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(mouseLocation.y - size.height - 24, visibleFrame.minY), visibleFrame.maxY - size.height)
        )

        window.setFrameOrigin(origin)
    }

    private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private static func initialWindowSize(for imageSize: CGSize) -> CGSize {
        let maxWidth: CGFloat = 520
        let maxHeight: CGFloat = 360
        let widthScale = maxWidth / max(imageSize.width, 1)
        let heightScale = maxHeight / max(imageSize.height, 1)
        let scale = min(1, widthScale, heightScale)

        return CGSize(
            width: max(imageSize.width * scale + 24, 220),
            height: max(imageSize.height * scale + 24, 160)
        )
    }
}

@MainActor
private final class PinnedScaleModel: ObservableObject {
    @Published var scale: CGFloat = 1.0
}

private struct PinnedScreenshotView: View {
    let image: NSImage
    @ObservedObject var scaleModel: PinnedScaleModel
    let onCopy: () -> Void
    let onClose: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .padding(12)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    floatingButton(symbol: "minus.magnifyingglass", action: onZoomOut)
                    floatingButton(symbol: "plus.magnifyingglass", action: onZoomIn)
                    floatingButton(symbol: "arrow.counterclockwise", action: onResetZoom)
                }

                HStack(spacing: 8) {
                    floatingButton(symbol: "doc.on.doc", action: onCopy)
                    floatingButton(symbol: "xmark", action: onClose)
                }
            }
            .padding(18)
            .opacity(isHovering ? 1 : 0)
            .animation(.smooth(duration: 0.2), value: isHovering)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.94),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.9),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func floatingButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
