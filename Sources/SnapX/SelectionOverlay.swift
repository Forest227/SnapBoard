import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class SelectionOverlayWindowController: NSWindowController {
    let screen: NSScreen

    init(
        screen: NSScreen,
        mode: CaptureSelectionMode,
        hotKeyHint: String,
        frozenImage: CGImage?,
        captureHandler: @escaping (ScreenshotCaptureRequest) -> Void,
        cancelHandler: @escaping () -> Void
    ) {
        self.screen = screen

        let window = SelectionOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: true)

        let contentView = SelectionOverlayCanvasView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            mode: mode,
            hotKeyHint: hotKeyHint,
            frozenImage: frozenImage,
            captureHandler: captureHandler,
            cancelHandler: cancelHandler
        )
        window.contentView = contentView

        if frozenImage != nil {
            window.isOpaque = true
            contentView.display()
        }

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func contains(globalRect: CGRect) -> Bool {
        screen.frame.intersects(globalRect)
    }

    func takeWindowForTransition() -> NSWindow? {
        let retainedWindow = window
        window = nil
        return retainedWindow
    }
}

private final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct HighlightedCaptureTarget: Equatable {
    let highlightRect: CGRect
    let contentSize: CGSize
    let displayName: String
    let captureRequest: ScreenshotCaptureRequest
}

private enum ResizeHandle {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
}

private enum AdjustAction {
    case moving
    case resizing(ResizeHandle)
}

private final class SelectionOverlayCanvasView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let dragActivationDistance: CGFloat = 4
    private let screen: NSScreen
    private let mode: CaptureSelectionMode
    private let hotKeyHint: String
    private let dockDisplayName: String
    private let frozenImage: CGImage?
    private let captureHandler: (ScreenshotCaptureRequest) -> Void
    private let cancelHandler: () -> Void

    private var trackingArea: NSTrackingArea?
    private var dragStartPoint: CGPoint?
    private var dragCurrentPoint: CGPoint?
    private var isAreaSelectionActive = false
    private var highlightedTarget: HighlightedCaptureTarget?
    private var isPointerInsideScreen = false

    private var confirmedRect: CGRect?
    private var adjustAction: AdjustAction?
    private var adjustDragOrigin: CGPoint?
    private var adjustOriginalRect: CGRect?
    private let handleSize: CGFloat = 8
    private let handleHitTolerance: CGFloat = 6

    init(
        frame frameRect: CGRect,
        screen: NSScreen,
        mode: CaptureSelectionMode,
        hotKeyHint: String,
        frozenImage: CGImage?,
        captureHandler: @escaping (ScreenshotCaptureRequest) -> Void,
        cancelHandler: @escaping () -> Void
    ) {
        self.screen = screen
        self.mode = mode
        self.hotKeyHint = hotKeyHint
        self.frozenImage = frozenImage
        dockDisplayName = Self.resolveDockDisplayName()
        self.captureHandler = captureHandler
        self.cancelHandler = cancelHandler
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        refreshHoverState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(for: event)

        switch mode {
        case .framed:
            isPointerInsideScreen = true

            if let rect = confirmedRect {
                if event.clickCount == 2, rect.contains(point) {
                    confirmSelection()
                    return
                }

                if let handle = handleAtPoint(point, in: rect) {
                    adjustAction = .resizing(handle)
                    adjustDragOrigin = point
                    adjustOriginalRect = rect
                    return
                }

                if rect.contains(point) {
                    adjustAction = .moving
                    adjustDragOrigin = point
                    adjustOriginalRect = rect
                    NSCursor.closedHand.set()
                    return
                }

                confirmedRect = nil
                adjustAction = nil
            }

            dragStartPoint = point
            dragCurrentPoint = point
            isAreaSelectionActive = false
            updateHighlightedTarget(at: point)

        case .display:
            isPointerInsideScreen = true
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .framed else { return }

        let point = clampedPoint(for: event)

        if let action = adjustAction,
           let origin = adjustDragOrigin,
           let originalRect = adjustOriginalRect {
            let dx = point.x - origin.x
            let dy = point.y - origin.y

            switch action {
            case .moving:
                var newRect = originalRect
                newRect.origin.x += dx
                newRect.origin.y += dy
                newRect.origin.x = max(0, min(newRect.origin.x, bounds.width - newRect.width))
                newRect.origin.y = max(0, min(newRect.origin.y, bounds.height - newRect.height))
                confirmedRect = newRect.integral

            case .resizing(let handle):
                confirmedRect = resizedRect(originalRect, handle: handle, dx: dx, dy: dy)
            }

            needsDisplay = true
            return
        }

        guard let dragStartPoint else { return }
        dragCurrentPoint = point
        if !isAreaSelectionActive,
           dragDistance(from: dragStartPoint, to: point) >= dragActivationDistance {
            isAreaSelectionActive = true
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = clampedPoint(for: event)

        switch mode {
        case .framed:
            if let rect = confirmedRect {
                updateAdjustCursor(at: point, in: rect)
                if !isPointerInsideScreen {
                    isPointerInsideScreen = true
                    needsDisplay = true
                }
                return
            }

            updateHighlightedTarget(at: point)
            if !isPointerInsideScreen {
                isPointerInsideScreen = true
                needsDisplay = true
            }

        case .display:
            if !isPointerInsideScreen {
                isPointerInsideScreen = true
                needsDisplay = true
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = clampedPoint(for: event)

        switch mode {
        case .framed:
            if adjustAction != nil {
                adjustAction = nil
                adjustDragOrigin = nil
                adjustOriginalRect = nil
                if let rect = confirmedRect {
                    updateAdjustCursor(at: point, in: rect)
                }
                needsDisplay = true
                return
            }

            dragCurrentPoint = point
            let shouldTreatAsAreaSelection: Bool
            if let dragStartPoint {
                shouldTreatAsAreaSelection =
                    isAreaSelectionActive || dragDistance(from: dragStartPoint, to: point) >= dragActivationDistance
            } else {
                shouldTreatAsAreaSelection = isAreaSelectionActive
            }

            if shouldTreatAsAreaSelection, !isAreaSelectionActive {
                isAreaSelectionActive = true
            }

            let rect = areaSelectionRect

            defer {
                dragStartPoint = nil
                dragCurrentPoint = nil
                isAreaSelectionActive = false
                needsDisplay = true
            }

            if shouldTreatAsAreaSelection {
                guard let rect, rect.width >= 8, rect.height >= 8 else {
                    NSSound.beep()
                    return
                }

                confirmedRect = rect
                highlightedTarget = nil
                return
            }

            updateHighlightedTarget(at: point)
            guard let highlightedTarget else {
                NSSound.beep()
                return
            }

            captureHandler(highlightedTarget.captureRequest)

        case .display:
            isPointerInsideScreen = true
            guard let displaySelection = makeFullScreenSelection() else {
                cancelHandler()
                return
            }

            captureHandler(.display(displaySelection))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if confirmedRect != nil {
                confirmedRect = nil
                adjustAction = nil
                adjustDragOrigin = nil
                adjustOriginalRect = nil
                NSCursor.crosshair.set()
                needsDisplay = true
                return
            }
            cancelHandler()
            return
        }

        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            if confirmedRect != nil {
                confirmSelection()
                return
            }
        }

        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelHandler()
    }

    override func mouseEntered(with event: NSEvent) {
        switch mode {
        case .framed:
            isPointerInsideScreen = true
            if let rect = confirmedRect {
                updateAdjustCursor(at: clampedPoint(for: event), in: rect)
            } else {
                updateHighlightedTarget(at: clampedPoint(for: event))
            }

        case .display:
            isPointerInsideScreen = true
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        switch mode {
        case .framed:
            isPointerInsideScreen = false
            if confirmedRect == nil {
                highlightedTarget = nil
            }
            NSCursor.arrow.set()
            needsDisplay = true

        case .display:
            isPointerInsideScreen = false
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // In freeze-first mode, draw the frozen screenshot as background
        if let frozenImage, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            // NSView is flipped, so we need to flip the drawing
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(frozenImage, in: CGRect(origin: .zero, size: bounds.size))
            context.restoreGState()
        } else {
            NSColor.clear.setFill()
            dirtyRect.fill()
        }

        let overlayPath = NSBezierPath(rect: bounds)

        switch mode {
        case .framed:
            if let areaSelectionRect {
                overlayPath.appendRect(areaSelectionRect)
            } else if let confirmedRect {
                overlayPath.appendRect(confirmedRect)
            } else if let highlightedTargetRect {
                overlayPath.appendRect(highlightedTargetRect)
            }

        case .display:
            if isPointerInsideScreen {
                overlayPath.appendRect(bounds)
            }
        }

        overlayPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        overlayPath.fill()

        switch mode {
        case .framed:
            if let areaSelectionRect {
                drawHighlightOutline(for: areaSelectionRect)
                drawFloatingLabel(
                    "\(Int(areaSelectionRect.width)) × \(Int(areaSelectionRect.height))",
                    near: areaSelectionRect
                )
            } else if let confirmedRect {
                drawHighlightOutline(for: confirmedRect)
                drawResizeHandles(for: confirmedRect)
                drawFloatingLabel(
                    "\(Int(confirmedRect.width)) × \(Int(confirmedRect.height)) · Enter 确认",
                    near: confirmedRect
                )
            } else if let highlightedTargetRect, let highlightedTarget {
                drawHighlightOutline(for: highlightedTargetRect)
                drawFloatingLabel(
                    "\(highlightedTarget.displayName) • \(Int(highlightedTarget.contentSize.width)) × \(Int(highlightedTarget.contentSize.height))",
                    near: highlightedTargetRect
                )
            } else {
                drawInstructionLabel()
            }

        case .display:
            if isPointerInsideScreen {
                let highlightRect = bounds.insetBy(dx: 8, dy: 8)
                drawHighlightOutline(for: highlightRect)
                drawFloatingLabel(
                    "整个屏幕 • \(Int(bounds.width)) × \(Int(bounds.height))",
                    near: highlightRect
                )
            } else {
                drawInstructionLabel()
            }
        }
    }

    private var areaSelectionRect: CGRect? {
        guard isAreaSelectionActive,
              let dragStartPoint,
              let dragCurrentPoint else { return nil }

        return CGRect(
            x: min(dragStartPoint.x, dragCurrentPoint.x),
            y: min(dragStartPoint.y, dragCurrentPoint.y),
            width: abs(dragCurrentPoint.x - dragStartPoint.x),
            height: abs(dragCurrentPoint.y - dragStartPoint.y)
        ).integral
    }

    private var highlightedTargetRect: CGRect? {
        guard let highlightedTarget else { return nil }

        let clippedRect = highlightedTarget.highlightRect.intersection(bounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return nil }

        return clippedRect.integral
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func drawInstructionLabel() {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]

        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.78),
        ]

        let title = mode.instructionTitle as NSString
        let caption = mode.instructionCaption(hotKeyHint: hotKeyHint) as NSString

        let titleSize = title.size(withAttributes: titleAttributes)
        let captionSize = caption.size(withAttributes: captionAttributes)
        let totalHeight = titleSize.height + captionSize.height + 12
        let startY = (bounds.height - totalHeight) / 2

        title.draw(
            at: CGPoint(x: (bounds.width - titleSize.width) / 2, y: startY),
            withAttributes: titleAttributes
        )
        caption.draw(
            at: CGPoint(x: (bounds.width - captionSize.width) / 2, y: startY + titleSize.height + 12),
            withAttributes: captionAttributes
        )
    }

    private func drawHighlightOutline(for rect: CGRect) {
        let highlightPath = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.92).setStroke()
        highlightPath.lineWidth = 2
        highlightPath.stroke()
    }

    private func drawFloatingLabel(_ text: String, near rect: CGRect) {
        let label = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]

        let size = label.size(withAttributes: attributes)
        let padding = CGSize(width: 12, height: 8)
        let backgroundRect = CGRect(
            x: min(max(rect.minX, 14), max(bounds.width - size.width - padding.width * 2 - 14, 14)),
            y: max(rect.minY - size.height - padding.height * 2 - 10, 14),
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )

        let chip = NSBezierPath(roundedRect: backgroundRect, xRadius: 11, yRadius: 11)
        NSColor.black.withAlphaComponent(0.68).setFill()
        chip.fill()

        label.draw(
            at: CGPoint(
                x: backgroundRect.minX + padding.width,
                y: backgroundRect.minY + padding.height
            ),
            withAttributes: attributes
        )
    }

    private func refreshHoverState() {
        let mouseLocation = NSEvent.mouseLocation
        let isInsideCurrentScreen = screen.frame.contains(mouseLocation)

        switch mode {
        case .framed:
            isPointerInsideScreen = isInsideCurrentScreen
            if isInsideCurrentScreen {
                updateHighlightedTarget(at: localPoint(fromGlobalCocoaPoint: mouseLocation))
            } else if highlightedTarget != nil {
                highlightedTarget = nil
                needsDisplay = true
            }

        case .display:
            if isPointerInsideScreen != isInsideCurrentScreen {
                isPointerInsideScreen = isInsideCurrentScreen
                needsDisplay = true
            }
        }
    }

    private func updateHighlightedTarget(at point: CGPoint) {
        let nextTarget = captureTarget(at: point)
        guard nextTarget != highlightedTarget else { return }

        highlightedTarget = nextTarget
        needsDisplay = true
    }

    private func dragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func confirmSelection() {
        guard let rect = confirmedRect, rect.width >= 8, rect.height >= 8 else {
            NSSound.beep()
            return
        }

        guard let displaySelection = makeScreenSelection(with: rect) else {
            cancelHandler()
            return
        }

        confirmedRect = nil
        adjustAction = nil
        captureHandler(.area(displaySelection))
    }

    private func handleAtPoint(_ point: CGPoint, in rect: CGRect) -> ResizeHandle? {
        let tolerance = handleHitTolerance + handleSize / 2
        let corners: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
        ]

        for (handle, center) in corners {
            if hypot(point.x - center.x, point.y - center.y) <= tolerance {
                return handle
            }
        }

        let edgeTolerance = handleHitTolerance
        if abs(point.y - rect.minY) <= edgeTolerance, point.x >= rect.minX, point.x <= rect.maxX {
            return .top
        }
        if abs(point.y - rect.maxY) <= edgeTolerance, point.x >= rect.minX, point.x <= rect.maxX {
            return .bottom
        }
        if abs(point.x - rect.minX) <= edgeTolerance, point.y >= rect.minY, point.y <= rect.maxY {
            return .left
        }
        if abs(point.x - rect.maxX) <= edgeTolerance, point.y >= rect.minY, point.y <= rect.maxY {
            return .right
        }

        return nil
    }

    private func resizedRect(_ original: CGRect, handle: ResizeHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY
        let minSize: CGFloat = 16

        switch handle {
        case .topLeft:     minX += dx; minY += dy
        case .top:         minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .left:        minX += dx
        case .right:       maxX += dx
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottom:      maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        }

        if maxX - minX < minSize {
            switch handle {
            case .topLeft, .left, .bottomLeft: minX = maxX - minSize
            default: maxX = minX + minSize
            }
        }
        if maxY - minY < minSize {
            switch handle {
            case .topLeft, .top, .topRight: minY = maxY - minSize
            default: maxY = minY + minSize
            }
        }

        minX = max(0, minX)
        minY = max(0, minY)
        maxX = min(bounds.width, maxX)
        maxY = min(bounds.height, maxY)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    private func drawResizeHandles(for rect: CGRect) {
        let hs = handleSize
        let handlePoints: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]

        for center in handlePoints {
            let handleRect = CGRect(x: center.x - hs / 2, y: center.y - hs / 2, width: hs, height: hs)
            NSColor.white.setFill()
            let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            path.fill()
            NSColor.black.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    private func updateAdjustCursor(at point: CGPoint, in rect: CGRect) {
        if let handle = handleAtPoint(point, in: rect) {
            switch handle {
            case .top, .bottom:
                NSCursor.resizeUpDown.set()
            case .left, .right:
                NSCursor.resizeLeftRight.set()
            case .topLeft, .bottomRight, .topRight, .bottomLeft:
                NSCursor.crosshair.set()
            }
        } else if rect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    private func captureTarget(at point: CGPoint) -> HighlightedCaptureTarget? {
        if let systemSurfaceTarget = systemSurfaceCaptureTarget(at: point) {
            return systemSurfaceTarget
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        for windowInfo in windowInfoList {
            guard let selection = WindowCaptureSelection(windowInfo: windowInfo, excludingProcessID: currentProcessID) else {
                continue
            }

            let localRect = localRect(fromGlobalScreenRect: selection.bounds)
            if localRect.contains(point) {
                return HighlightedCaptureTarget(
                    highlightRect: localRect.integral,
                    contentSize: selection.bounds.size,
                    displayName: selection.displayName,
                    captureRequest: .window(selection)
                )
            }
        }

        return nil
    }

    private func makeScreenSelection(with rect: CGRect) -> ScreenSelection? {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            return nil
        }

        return ScreenSelection(
            displayID: displayID,
            rect: rect,
            scaleFactor: screen.backingScaleFactor
        )
    }

    private func makeFullScreenSelection() -> ScreenSelection? {
        makeScreenSelection(with: CGRect(origin: .zero, size: screen.frame.size))
    }

    private func systemSurfaceCaptureTarget(at point: CGPoint) -> HighlightedCaptureTarget? {
        if let menuBarRect = menuBarHighlightRect,
           menuBarRect.contains(point),
           let selection = makeScreenSelection(with: menuBarRect) {
            return HighlightedCaptureTarget(
                highlightRect: menuBarRect.integral,
                contentSize: menuBarRect.size,
                displayName: "菜单栏",
                captureRequest: .area(selection)
            )
        }

        if let dockRect = dockHighlightRect,
           dockRect.contains(point),
           let selection = makeScreenSelection(with: dockRect) {
            return HighlightedCaptureTarget(
                highlightRect: dockRect.integral,
                contentSize: dockRect.size,
                displayName: dockDisplayName,
                captureRequest: .area(selection)
            )
        }

        return nil
    }

    private var menuBarHighlightRect: CGRect? {
        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        guard topInset > 0 else { return nil }

        return CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: topInset
        ).integral
    }

    private var dockHighlightRect: CGRect? {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame

        let leftInset = visibleFrame.minX - frame.minX
        let rightInset = frame.maxX - visibleFrame.maxX
        let bottomInset = visibleFrame.minY - frame.minY
        let topInset = frame.maxY - visibleFrame.maxY

        if bottomInset >= leftInset, bottomInset >= rightInset, bottomInset > 0 {
            return CGRect(
                x: 0,
                y: bounds.height - bottomInset,
                width: bounds.width,
                height: bottomInset
            ).integral
        }

        if leftInset >= rightInset, leftInset > 0 {
            return CGRect(
                x: 0,
                y: topInset,
                width: leftInset,
                height: bounds.height - topInset
            ).integral
        }

        if rightInset > 0 {
            return CGRect(
                x: bounds.width - rightInset,
                y: topInset,
                width: rightInset,
                height: bounds.height - topInset
            ).integral
        }

        return nil
    }

    private static func resolveDockDisplayName() -> String {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return "Dock"
        }

        for windowInfo in windowInfoList {
            let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? ""
            let windowName = (windowInfo[kCGWindowName as String] as? String) ?? ""
            if windowName == "Dock", !ownerName.isEmpty {
                return ownerName
            }
        }

        return "Dock"
    }

    private func localPoint(fromGlobalCocoaPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - screen.frame.minX,
            y: screen.frame.maxY - point.y
        )
    }

    private func localRect(fromGlobalScreenRect rect: CGRect) -> CGRect {
        let desktopTopEdge = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
        let cocoaRect = CGRect(
            x: rect.minX,
            y: desktopTopEdge - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        return CGRect(
            x: cocoaRect.minX - screen.frame.minX,
            y: screen.frame.maxY - cocoaRect.maxY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }
}

private extension WindowCaptureSelection {
    init?(windowInfo: [String: Any], excludingProcessID processID: pid_t) {
        guard let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        let sharingState = (windowInfo[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 1
        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? "Unknown App"
        let isOnScreen = (windowInfo[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true

        guard ownerPID != processID,
              layer == 0,
              alpha > 0.01,
              sharingState != 0,
              isOnScreen,
              bounds.width >= 60,
              bounds.height >= 60 else {
            return nil
        }

        self.init(
            windowID: windowID,
            bounds: bounds,
            ownerName: ownerName,
            windowName: windowInfo[kCGWindowName as String] as? String
        )
    }
}
