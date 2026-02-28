import SwiftUI

public enum AppPalette {
    public static let primaryText = Color.primary
    public static let secondaryText = Color.secondary
    public static let accent = Color(red: 0.11, green: 0.39, blue: 0.95)
    public static let chatBackgroundTop = Color(red: 0.95, green: 0.97, blue: 1.00)
    public static let chatBackgroundBottom = Color(red: 0.98, green: 0.99, blue: 1.00)
    public static let chatUserBubble = accent.opacity(0.16)
    public static let chatAgentBubble = Color.primary.opacity(0.05)
    public static let chatBubbleStroke = Color.primary.opacity(0.10)
    public static let chatToolBackground = Color.primary.opacity(0.04)
    public static let composerFieldBackground = Color.primary.opacity(0.065)
    public static let composerFieldStroke = Color.primary.opacity(0.12)
    public static let dockDivider = Color.primary.opacity(0.09)
    public static let chipBackground = Color.primary.opacity(0.08)
    public static let chipStroke = Color.primary.opacity(0.11)
    public static let chipPrimaryBackground = accent.opacity(0.2)
    public static let chipPrimaryStroke = accent.opacity(0.35)
    public static let chromeSurface = Color.primary.opacity(0.055)
    public static let chromeSurfaceStroke = Color.primary.opacity(0.13)
    public static let chromeDivider = Color.primary.opacity(0.10)
    public static let chromeShadow = Color.black.opacity(0.10)
    public static let controlSurface = chromeSurface
    public static let controlSurfaceStroke = chromeSurfaceStroke
    public static let sendGradientTop = accent.opacity(0.98)
    public static let sendGradientBottom = accent.opacity(0.74)
    public static let liveActivity = Color(red: 0.19, green: 0.77, blue: 0.37)
    public static let liveActivityMuted = liveActivity.opacity(0.18)
    public static let terminalLineUser = Color(red: 0.18, green: 0.45, blue: 0.96)
    public static let terminalLineAgent = Color(red: 0.18, green: 0.72, blue: 0.46)
    public static let terminalLineTool = Color.secondary.opacity(0.65)
}
