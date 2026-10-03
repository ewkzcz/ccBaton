/**
 * 主题常量：颜色、圆角、字号集中定义，自动适配浅色和深色模式。
 */
import AppKit
import SwiftUI

/** Theme：界面统一取值 */
enum Theme {
    static let bg = dynamic(light: 0xF6F4EF, dark: 0x16151A)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x201F25)
    static let cardHover = dynamic(light: 0xFBFAF7, dark: 0x27262D)
    static let line = dynamic(light: 0xE7E3DA, dark: 0x2E2D34)
    static let text = dynamic(light: 0x1C1B1F, dark: 0xF2F0EB)
    static let muted = dynamic(light: 0x7A766E, dark: 0x8E8B93)
    static let accent = dynamic(light: 0xC96442, dark: 0xE08A68)
    static let accentSoft = dynamic(light: 0xF6E6DE, dark: 0x3A2620)
    static let danger = dynamic(light: 0xC0392B, dark: 0xF07466)

    static let termBg = NSColor(hex: 0x141317)
    static let termFg = NSColor(hex: 0xE9E6DF)

    static let radius: CGFloat = 14
    static let avatarColors: [UInt32] = [0xC96442, 0x5B7DB1, 0x5A9A78, 0x9A6FB0, 0xB8893A]

    /** 生成随系统外观切换的颜色 */
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    /** 用 0xRRGGBB 构造颜色 */
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
