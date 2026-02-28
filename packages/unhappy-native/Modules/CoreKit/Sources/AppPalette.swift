import SwiftUI

public enum AppPalette {
    public static let primaryText = Color.primary
    public static let secondaryText = Color.secondary
    public static let accent = Color(red: 0.11, green: 0.39, blue: 0.95)
    public static let chatBackgroundTop = Color(red: 0.94, green: 0.96, blue: 0.99)
    public static let chatBackgroundBottom = Color(red: 0.98, green: 0.99, blue: 1.00)
    public static let chatUserBubble = accent.opacity(0.3)
    public static let chatAgentBubble = Color.primary.opacity(0.08)
    public static let chatBubbleStroke = Color.primary.opacity(0.16)
    public static let chatToolBackground = Color.primary.opacity(0.07)
    public static let composerFieldBackground = Color.primary.opacity(0.09)
    public static let composerFieldStroke = Color.primary.opacity(0.16)
    public static let dockDivider = Color.primary.opacity(0.09)
    public static let chipBackground = Color.primary.opacity(0.08)
    public static let chipStroke = Color.primary.opacity(0.11)
    public static let chipPrimaryBackground = accent.opacity(0.95)
    public static let chipPrimaryStroke = accent
    public static let liveActivity = Color(red: 0.19, green: 0.77, blue: 0.37)
    public static let liveActivityMuted = liveActivity.opacity(0.18)
}
