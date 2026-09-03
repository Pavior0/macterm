import SwiftUI

/// Live horizontal-tab icon shared by process status, agent identity, and icon preferences.
struct HorizontalTabIcon: View {
    let tab: TerminalTab
    let index: Int
    @AppStorage(Preferences.Keys.tabIconSymbol)
    private var tabIconSymbol = "terminal"
    @AppStorage(Preferences.Keys.showAgentIcons)
    private var showAgentIcons = true
    @AppStorage(Preferences.Keys.showTabStatusIndicator)
    private var showTabStatusIndicator = false
    @AppStorage(Preferences.Keys.showSpinnerOverAgentIcons)
    private var showSpinnerOverAgentIcons = true

    private var agentIcon: AgentIcon? { showAgentIcons ? tab.agentIcon : nil }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if showTabStatusIndicator, tab.executionState == .running,
               agentIcon == nil || showSpinnerOverAgentIcons
            {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                baseIcon
            }

            if showTabStatusIndicator, tab.executionState == .done {
                Circle()
                    .fill(.background)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().fill(MactermTheme.success).frame(width: 5, height: 5))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 15, height: 15)
    }

    @ViewBuilder
    private var baseIcon: some View {
        if let agentIcon {
            HorizontalAgentIconMark(agent: agentIcon, size: 14)
        } else if Preferences.numberIconChoices.contains(tabIconSymbol) {
            Text("\(index)")
                .font(.system(size: 10, design: .rounded).monospacedDigit())
        } else if tabIconSymbol != Preferences.noIcon {
            Image(systemName: tabIconSymbol)
                .font(.system(size: 12))
        }
    }
}

/// Consistent branded mark for an AI agent shown in horizontal-tab chrome.
struct HorizontalAgentIconMark: View {
    let agent: AgentIcon
    let size: CGFloat

    var body: some View {
        Image(agent.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(agent.brandColor)
            .frame(width: size, height: size)
    }
}

extension AgentIcon {
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .cursor: "Cursor Agent"
        case .gemini: "Gemini CLI"
        case .copilot: "GitHub Copilot"
        case .grok: "Grok"
        case .pi: "Pi"
        case .antigravity: "Antigravity"
        }
    }

    /// Brand tint used anywhere a live AI agent replaces the configured tab icon.
    var brandColor: Color {
        switch self {
        case .claude: Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex: Color(red: 0xAB / 255, green: 0xAB / 255, blue: 0xAB / 255)
        case .gemini: Color(red: 0x42 / 255, green: 0x85 / 255, blue: 0xF4 / 255)
        case .copilot: Color(red: 0x89 / 255, green: 0x57 / 255, blue: 0xE5 / 255)
        case .antigravity: Color(red: 0x31 / 255, green: 0x86 / 255, blue: 0xFF / 255)
        case .opencode,
             .cursor,
             .grok,
             .pi: .primary
        }
    }
}
