import AppKit
import CoreImage
import IOSurface

/// Caches terminal preview snapshots without activating or resizing background tabs.
@MainActor @Observable
final class RecentTabPreviewStore {
    private enum CaptureResult {
        case image(CGImage)
        case placeholder
        case unavailable
    }

    private static let maximumPreviewPixelSize = CGSize(width: 512, height: 320)

    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let previewColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        ?? CGColorSpaceCreateDeviceRGB()

    private var paneImages: [UUID: CGImage] = [:]

    /// Returns the last completed terminal preview for a pane.
    func previewImage(for paneID: UUID) -> CGImage? {
        paneImages[paneID]
    }

    /// Refreshes every tab preview progressively while preserving cached images during the refresh.
    func refreshTabPreviews(_ tabs: [TerminalTab]) async {
        let panes = tabs.flatMap { $0.splitRoot.allPanes() }
        let livePaneIDs = Set(panes.map(\.id))
        paneImages = paneImages.filter { livePaneIDs.contains($0.key) }
        let benchmarkStart = BenchmarkControl.isEnabled ? ContinuousClock.now : nil
        var maximumCaptureMilliseconds = 0.0
        var imageCount = 0
        var placeholderCount = 0
        var unavailableCount = 0

        for pane in panes {
            await waitForNextMainRunLoopTurn()
            guard !Task.isCancelled else { return }

            let captureStart = benchmarkStart == nil ? nil : ContinuousClock.now
            let result = capturePanePreview(pane)
            if let captureStart {
                maximumCaptureMilliseconds = max(
                    maximumCaptureMilliseconds,
                    Self.milliseconds(captureStart.duration(to: ContinuousClock.now))
                )
            }

            switch result {
            case let .image(image):
                paneImages[pane.id] = image
                imageCount += 1
            case .placeholder:
                paneImages[pane.id] = nil
                placeholderCount += 1
            case .unavailable:
                unavailableCount += 1
            }
        }

        if let benchmarkStart {
            BenchmarkControl.recordRecentTabPreviewMetrics(
                totalMilliseconds: Self.milliseconds(benchmarkStart.duration(to: ContinuousClock.now)),
                maximumCaptureMilliseconds: maximumCaptureMilliseconds,
                counts: BenchmarkControl.RecentTabPreviewCounts(
                    panes: panes.count,
                    images: imageCount,
                    placeholders: placeholderCount,
                    unavailable: unavailableCount
                )
            )
        }
    }

    /// Gives AppKit one input/render turn before materializing the next preview.
    private func waitForNextMainRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func capturePanePreview(_ pane: Pane) -> CaptureResult {
        guard let view = pane.nsView,
              view.surface != nil
        else { return .placeholder }

        guard let ioSurface = view.layer?.contents as? IOSurface else { return .unavailable }
        let source = CIImage(
            ioSurface: ioSurface,
            options: [.colorSpace: previewColorSpace]
        )
        guard !source.extent.isEmpty else { return .unavailable }

        let scale = min(
            Self.maximumPreviewPixelSize.width / source.extent.width,
            Self.maximumPreviewPixelSize.height / source.extent.height,
            1
        )
        let preview = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = imageContext.createCGImage(
            preview,
            from: preview.extent.integral,
            format: .BGRA8,
            colorSpace: previewColorSpace
        )
        else { return .unavailable }
        return hasVisibleTerminalPixels(image) ? .image(image) : .placeholder
    }

    /// Uniform IOSurfaces do not provide a useful preview.
    private func hasVisibleTerminalPixels(_ image: CGImage) -> Bool {
        guard image.bitsPerPixel >= 24,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return true }

        let bytesPerPixel = image.bitsPerPixel / 8
        let background = (bytes[0], bytes[1], bytes[2])
        for y in 0 ..< image.height {
            let row = y * image.bytesPerRow
            for x in 0 ..< image.width {
                let offset = row + (x * bytesPerPixel)
                if abs(Int(bytes[offset]) - Int(background.0)) > 12
                    || abs(Int(bytes[offset + 1]) - Int(background.1)) > 12
                    || abs(Int(bytes[offset + 2]) - Int(background.2)) > 12
                {
                    return true
                }
            }
        }
        return false
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1e15
    }
}
