/**
 * 主题令牌：颜色、字号、圆角、阴影集中定义，取值对齐 cc-switch v7 设计系统，自动适配浅色和深色模式。
 */
import AppKit
import SwiftUI

/** Theme：界面统一取值 */
enum Theme {
    // 中性面：骨架是中性灰，彩色只表达“能操作”和“是什么状态”
    static let bgApp = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let bgSidebar = dynamic(light: 0xF5F5F7, dark: 0x161618)
    static let bgSubtle = dynamic(light: 0xEFEFF2, dark: 0x26262A)
    static let bgSelected = dynamic(light: 0xE4E4EA, dark: 0x313136)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2E2E33)
    static let border = dynamic(light: 0xE4E4E9, dark: 0x3E3E45)
    static let borderStrong = dynamic(light: 0xCFCFD6, dark: 0x4A4A52)
    static let text1 = dynamic(light: 0x18181B, dark: 0xE4E4E7)
    static let text2 = dynamic(light: 0x52525B, dark: 0xABABB3)
    static let text3 = dynamic(light: 0x65656E, dark: 0x9A9AA2)
    static let inverseBg = dynamic(light: 0x18181B, dark: 0xF4F4F5)
    static let inverseFg = dynamic(light: 0xFFFFFF, dark: 0x18181B)
    static let controlOff = dynamic(light: 0x888890, dark: 0x6F6F77)
    static let overlay = dynamic(NSColor(white: 0.035, alpha: 0.36), NSColor(white: 0, alpha: 0.55))

    // 主题色（操作色）：只落在能点的东西上，一个视图只有一个实心橙按钮
    static let action = dynamic(light: 0xF97316, dark: 0xEA580C)
    static let actionHover = dynamic(light: 0xEA620A, dark: 0xF06D1F)
    static let actionText = dynamic(light: 0xC2410C, dark: 0xFB923C)
    static let actionSoft = dynamic(NSColor(hex: 0xFFF1E6), NSColor(hex: 0xF97315, alpha: 0.12))

    // 当前生效的账号用直连模式色：soft 底 + fill 描边
    static let directFill = dynamic(light: 0x0A84FF, dark: 0x4A8FD9)
    static let directText = dynamic(light: 0x0063C7, dark: 0x8FB8E6)
    static let directSoft = dynamic(NSColor(hex: 0xEAF3FF), NSColor(hex: 0x4A8FD9, alpha: 0.12))
    static let directBorder = dynamic(NSColor(hex: 0x0A84FF), NSColor(hex: 0x4A8FD9, alpha: 0.5))

    // 语义色
    static let success = dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let successText = dynamic(light: 0x007634, dark: 0x4ADE80)
    static let successSoft = dynamic(light: 0xE8F7EE, dark: 0x0F2B1A)
    static let warning = dynamic(light: 0xD97706, dark: 0xFBBF24)
    static let warningText = dynamic(light: 0xA64A00, dark: 0xFCD34D)
    static let warningSoft = dynamic(light: 0xFEF3C7, dark: 0x33260A)
    static let danger = dynamic(light: 0xDC2626, dark: 0xF87171)
    static let dangerText = dynamic(light: 0xB91C1C, dark: 0xFCA5A5)
    static let dangerSoft = dynamic(light: 0xFEE2E2, dark: 0x3A1414)

    // 阴影：平面靠描边分层，阴影只给浮起来的东西
    static let shadowSm = dynamic(NSColor(srgbRed: 16 / 255, green: 24 / 255, blue: 40 / 255, alpha: 0.06),
                                  NSColor(white: 0, alpha: 0.4))
    static let shadowMd = dynamic(NSColor(srgbRed: 16 / 255, green: 24 / 255, blue: 40 / 255, alpha: 0.10),
                                  NSColor(white: 0, alpha: 0.45))
    static let shadowLg = dynamic(NSColor(srgbRed: 16 / 255, green: 24 / 255, blue: 40 / 255, alpha: 0.16),
                                  NSColor(white: 0, alpha: 0.5))

    static let termBg = NSColor(hex: 0x141317)
    static let termFg = NSColor(hex: 0xE9E6DF)

    // 圆角：控件 6、卡片 10、对话框 14
    static let rControl: CGFloat = 6
    static let rPanel: CGFloat = 10
    static let rDialog: CGFloat = 14

    // 侧栏宽度：展开 200、收起 72
    static let sidebarWidth: CGFloat = 200
    static let sidebarCollapsed: CGFloat = 72

    /** 生成随系统外观切换的颜色 */
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(NSColor(hex: light), NSColor(hex: dark))
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/** Appearance：外观设置，浅色、深色或跟随系统 */
enum Appearance: String, CaseIterable {
    case light, dark, system

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    var icon: Icon {
        switch self {
        case .light: return .sun
        case .dark: return .moon
        case .system: return .monitor
        }
    }

    /** 应用到整个应用，跟随系统时清空覆盖 */
    func apply() {
        switch self {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}

/** 字号角色：只用这几档 */
extension Font {
    static let page = Font.system(size: 18, weight: .semibold)
    static let title = Font.system(size: 16, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let strong = Font.system(size: 14, weight: .medium)
    static let bodyText = Font.system(size: 13)
    static let captionText = Font.system(size: 12)
    static let badge = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
}

extension NSColor {
    /** 用 0xRRGGBB 构造颜色 */
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
