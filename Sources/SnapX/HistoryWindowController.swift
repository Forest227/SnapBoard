import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    private static var shared: HistoryWindowController?

    static func present(appState: AppState) {
        if shared == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "截图历史"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: HistoryView()
                    .environmentObject(appState)
            )
            shared = HistoryWindowController(window: window)
        }
        shared?.showWindow(nil)
        shared?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var history = ScreenshotHistory.shared
    @State private var selectedItem: HistoryItem?
    @State private var selectedIDs: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        if history.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("暂无截图历史")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(history.items) { item in
                        ThumbnailCell(
                            item: item,
                            isSelected: selectedIDs.contains(item.id),
                            onSelect: { selectedItem = item },
                            onToggleSelect: { toggleSelect(item) },
                            onDelete: { history.remove(item) },
                            onCopy: { copyImages(for: item) }
                        )
                    }
                }
                .padding(16)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("清空历史") { history.clear() }
                        .foregroundStyle(.red)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        pinSelected()
                    } label: {
                        Label("钉住所选", systemImage: "pin")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        copySelected()
                    } label: {
                        Label("复制所选", systemImage: "doc.on.doc")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        deleteSelected()
                    } label: {
                        Label("删除所选", systemImage: "trash")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .sheet(item: $selectedItem) { item in
                ImagePreviewView(item: item)
                    .frame(minWidth: 900, minHeight: 650)
            }
        }
    }

    private func toggleSelect(_ item: HistoryItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func pinSelected() {
        history.items
            .filter { selectedIDs.contains($0.id) }
            .forEach { appState.pinImage($0.image) }
        selectedIDs.removeAll()
    }

    private func deleteSelected() {
        history.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()
    }

    private func copySelected() {
        let images = history.items.filter { selectedIDs.contains($0.id) }.map(\.image)
        copyImagesToPasteboard(images)
        selectedIDs.removeAll()
    }

    /// Copies images for a single item, or all selected items if this item is in the selection.
    private func copyImages(for item: HistoryItem) {
        if selectedIDs.contains(item.id), selectedIDs.count > 1 {
            let images = history.items.filter { selectedIDs.contains($0.id) }.map(\.image)
            copyImagesToPasteboard(images)
            selectedIDs.removeAll()
        } else {
            copyImagesToPasteboard([item.image])
        }
    }

    private func copyImagesToPasteboard(_ images: [NSImage]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(images)
    }
}

private struct ThumbnailCell: View {
    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleSelect: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)

                Text(item.date, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("复制")

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
            }
            .overlay(alignment: .topLeading) {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Button {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private struct ImagePreviewView: View {
    let item: HistoryItem
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.date.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.pinImage(item.image)
                    dismiss()
                } label: {
                    Label("钉住", systemImage: "pin")
                }
                .buttonStyle(.bordered)
                Button("关闭") { dismiss() }
            }
            .padding(16)

            ZoomableImageView(image: item.image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MagnifyScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 20
        scrollView.backgroundColor = .windowBackgroundColor

        // Use centering clip view so the image stays centered when smaller than viewport
        let clipView = CenteringClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleNone
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.documentView = imageView

        // fit to window on first layout
        DispatchQueue.main.async {
            let viewSize = scrollView.bounds.size
            guard viewSize.width > 0, viewSize.height > 0, image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(viewSize.width / image.size.width, viewSize.height / image.size.height)
            scrollView.magnification = scale
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// A clip view that centers the document when the document is smaller than the visible area.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView = documentView else { return rect }

        let docFrame = documentView.frame

        if docFrame.width < rect.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if docFrame.height < rect.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }

        return rect
    }
}

private final class MagnifyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // pinch gesture — use default
        if event.phase != [] || !event.momentumPhase.isEmpty {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor = delta > 0 ? 1.08 : 1 / 1.08
        let newMag = (magnification * factor).clamped(to: minMagnification...maxMagnification)
        setMagnification(newMag, centeredAt: convert(event.locationInWindow, from: nil))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
