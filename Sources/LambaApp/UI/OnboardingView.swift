import AppKit
import SwiftUI

/// First-run window: explains the one-time password prompt before it appears,
/// or tells the user this Mac has no MagSafe LED.
struct OnboardingView: View {
    enum Step { case welcome, done, unsupported }

    @State var step: Step
    /// Runs the helper install; returns true on success.
    let install: () -> Bool
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            switch step {
            case .welcome: welcome
            case .done: done
            case .unsupported: unsupported
            }
        }
        .padding(28)
        .frame(width: 420)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Header(title: L10n.onboardingTitle, subtitle: L10n.onboardingSubtitle)
            VStack(alignment: .leading, spacing: 12) {
                Feature(symbol: "lightbulb.fill", title: L10n.onboardingLightTitle, text: L10n.onboardingLightBody)
                Feature(symbol: "timer", title: L10n.onboardingPomodoroTitle, text: L10n.onboardingPomodoroBody)
                Feature(symbol: "sparkles", title: L10n.onboardingClaudeTitle, text: L10n.onboardingClaudeBody)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text(L10n.onboardingPassword)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            HStack {
                Button(L10n.onboardingLater, action: finish)
                Spacer()
                Button(L10n.onboardingInstall) {
                    if install() { step = .done }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Header(title: L10n.onboardingDoneTitle, subtitle: L10n.onboardingDoneBody)
            Button(L10n.onboardingDone, action: finish)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var unsupported: some View {
        VStack(spacing: 18) {
            Header(title: L10n.unsupportedTitle, subtitle: L10n.unsupportedBody)
            Button(L10n.continueLabel, action: finish)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hosts `OnboardingView` in a small, centered window.
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(step: OnboardingView.Step, install: @escaping () -> Bool, finish: @escaping () -> Void) {
        let view = OnboardingView(step: step, install: install, finish: { [weak self] in
            self?.window?.close()
            self?.window = nil
            finish()
        })
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.appName
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
