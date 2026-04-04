import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    private static var shared: HistoryWindowController?

    static func present() {
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
            window.contentView = NSHostingView(rootView: HistoryView())
            shared = HistoryWindowController(window: window)
        }
        shared?.showWindow(nil)
        shared?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HistoryView: View {
    @ObservedObject private var history = ScreenshotHistory.shared
    @State private var selectedItem: HistoryItem?

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
                        ThumbnailCell(item: item) {
                            selectedItem = item
                        } onDelete: {
                            history.remove(item)
                        }
                    }
                }
                .padding(16)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("清空历史") { history.clear() }
                        .foregroundStyle(.red)
                }
            }
            .sheet(item: $selectedItem) { item in
                ImagePreviewView(item: item)
            }
        }
    }
}

private struct ThumbnailCell: View {
    let item: HistoryItem
    let onSelect: () -> Void
    let onDelete: () -> Void

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
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ImagePreviewView: View {
    let item: HistoryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.date.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)

            ZoomableImageView(image: item.image)
                .frame(minWidth: 400, minHeight: 300)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 10
        scrollView.backgroundColor = .windowBackgroundColor

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleNone
        imageView.frame = CGRect(origin: .zero, size: image.size)

        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
