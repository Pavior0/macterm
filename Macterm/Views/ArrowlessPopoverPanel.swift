import AppKit
import SwiftUI

// A compact anchored panel without NSPopover's arrow or long system reveal.

/// The panel is still spatially tied to its trigger, but arrives immediately
/// enough to preserve the pointer-down → response relationship.
struct ArrowlessPopoverPresenter: NSViewRepresentable {
    @Binding
    var isPresented: Bool
    let preferredWidth: CGFloat
    let acceptsKeyboardInput: Bool
    let content: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ anchorView: NSView, context: Context) {
        context.coordinator.update(
            anchorView: anchorView,
            isPresented: $isPresented,
            preferredWidth: preferredWidth,
            acceptsKeyboardInput: acceptsKeyboardInput,
            content: content
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        _ = nsView
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        private var panel: ArrowlessPopoverPanel?
        private var hostingView: NSHostingView<AnyView>?

        func update(
            anchorView: NSView,
            isPresented: Binding<Bool>,
            preferredWidth: CGFloat,
            acceptsKeyboardInput: Bool,
            content: AnyView
        ) {
            guard isPresented.wrappedValue else {
                dismiss()
                return
            }
            guard anchorView.window != nil else { return }

            let panel = panel ?? makePanel(acceptsKeyboardInput: acceptsKeyboardInput)
            let hostingView = hostingView ?? NSHostingView(rootView: content)
            hostingView.rootView = content
            hostingView.frame.size.width = preferredWidth
            hostingView.layoutSubtreeIfNeeded()

            let fittingHeight = max(1, hostingView.fittingSize.height)
            let contentSize = NSSize(width: preferredWidth, height: fittingHeight)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            panel.contentView = hostingView
            panel.setContentSize(contentSize)
            panel.acceptsKeyboardInput = acceptsKeyboardInput
            panel.onResignKey = acceptsKeyboardInput ? {
                isPresented.wrappedValue = false
            } : nil
            panel.onCancel = {
                isPresented.wrappedValue = false
            }

            self.panel = panel
            self.hostingView = hostingView
            let finalOrigin = position(panel, below: anchorView)

            guard !panel.isVisible else { return }
            panel.alphaValue = 0
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !reduceMotion {
                let approachesFromAbove = finalOrigin.y < anchorScreenRect(for: anchorView).minY
                panel.setFrameOrigin(NSPoint(
                    x: finalOrigin.x,
                    y: finalOrigin.y + (approachesFromAbove ? 3 : -3)
                ))
            }
            if acceptsKeyboardInput {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFront(nil)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                if !reduceMotion {
                    panel.animator().setFrameOrigin(finalOrigin)
                }
            }
        }

        func dismiss() {
            panel?.onResignKey = nil
            panel?.onCancel = nil
            panel?.orderOut(nil)
            panel = nil
            hostingView = nil
        }

        private func makePanel(acceptsKeyboardInput: Bool) -> ArrowlessPopoverPanel {
            let panel = ArrowlessPopoverPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.acceptsKeyboardInput = acceptsKeyboardInput
            panel.isOpaque = false
            panel.backgroundColor = .clear
            if #available(macOS 26.0, *) {
                // Liquid Glass draws its own adaptive edge and depth. A window
                // shadow directly beneath it reads as a second black border.
                panel.hasShadow = false
            } else {
                panel.hasShadow = true
            }
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = true
            panel.animationBehavior = .none
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            return panel
        }

        private func position(_ panel: NSPanel, below anchorView: NSView) -> NSPoint {
            let anchorRect = anchorScreenRect(for: anchorView)
            let visibleFrame = anchorView.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let preferredX = anchorRect.minX
            let clampedX = min(
                max(preferredX, visibleFrame.minX + 8),
                visibleFrame.maxX - panel.frame.width - 8
            )
            let belowY = anchorRect.minY - panel.frame.height - 6
            let aboveY = anchorRect.maxY + 6
            let y = belowY >= visibleFrame.minY + 8 ? belowY : aboveY
            let origin = NSPoint(x: clampedX, y: y)
            panel.setFrameOrigin(origin)
            return origin
        }

        private func anchorScreenRect(for anchorView: NSView) -> NSRect {
            guard let window = anchorView.window else { return .zero }
            let windowRect = anchorView.convert(anchorView.bounds, to: nil)
            return window.convertToScreen(windowRect)
        }
    }
}

private final class ArrowlessPopoverPanel: NSPanel {
    var acceptsKeyboardInput = false
    var onResignKey: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboardInput }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        onCancel?()
    }
}
