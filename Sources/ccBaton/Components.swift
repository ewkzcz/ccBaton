/**
 * 通用组件：按钮、悬停提示、徽章、通知条、开关、勾选、页头、Toast 和对话框，样式对齐 cc-switch v7 设计系统。
 */
import AppKit
import SwiftUI

// MARK: - 按钮

/** SolidButton：主题色实心按钮，一个视图只放一个 */
struct SolidButton: ButtonStyle {
    var compact = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, compact: compact, destructive: destructive)
    }

    private struct Styled: View {
        let configuration: Configuration
        let compact: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let fill = destructive ? Theme.danger : (hover && enabled ? Theme.actionHover : Theme.action)
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: compact ? 28 : 32)
                .background(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).fill(fill))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/** NeutralButton：描边按钮，卡片和对话框里的次要操作 */
struct NeutralButton: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, compact: compact)
    }

    private struct Styled: View {
        let configuration: Configuration
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text1)
                .padding(.horizontal, 12)
                .frame(height: compact ? 28 : 32)
                .background(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                    .fill(hover && enabled ? Theme.bgSubtle : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                    .strokeBorder(Theme.borderStrong))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/** IconButton：纯图标按钮，文字放进 HoverTip */
struct IconButton: View {
    let icon: Icon
    let tip: String
    var size: CGFloat = 28
    var danger = false
    var bordered = false
    var tipSide: TipSide = .bottom
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            icon.image(size >= 32 ? 16 : 15)
                .foregroundStyle(hover && enabled ? (danger ? Theme.danger : Theme.text1) : Theme.text2)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                    .fill(hover && enabled ? Theme.bgSubtle : Color.clear))
                .overlay {
                    if bordered {
                        RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).strokeBorder(Theme.border)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .opacity(enabled ? 1 : 0.45)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .hoverTip(tip, side: tipSide)
        .accessibilityLabel(tip)
    }
}

/** PressScale：按下缩到 0.96 */
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// MARK: - 悬停提示

/** TipSide：提示出现在哪一侧 */
enum TipSide {
    case bottom, top, trailing
}

/** HoverTip：鼠标移上去立即出现的深色胶囊 */
private struct HoverTip: ViewModifier {
    let text: String
    let side: TipSide
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { show = h } }
            .overlay(alignment: alignment) {
                // 提示一直挂着、只改透明度：包进 if 后自定义对齐失效，提示会叠在按钮正中间
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inverseFg)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Theme.inverseBg))
                    .shadow(color: Theme.shadowMd, radius: 6, y: 3)
                    .fixedSize()
                    .scaleEffect(show ? 1 : 0.95)
                    .opacity(show && !text.isEmpty ? 1 : 0)
                    .alignmentGuide(VerticalAlignment.bottom) { d in side == .bottom ? d[.top] - 6 : d[.bottom] }
                    .alignmentGuide(VerticalAlignment.top) { d in side == .top ? d[.bottom] + 6 : d[.top] }
                    .alignmentGuide(HorizontalAlignment.trailing) { d in side == .trailing ? d[.leading] - 8 : d[.trailing] }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    private var alignment: Alignment {
        switch side {
        case .bottom: return .bottom
        case .top: return .top
        case .trailing: return .trailing
        }
    }
}

extension View {
    /** 挂一个悬停提示 */
    func hoverTip(_ text: String, side: TipSide = .bottom) -> some View {
        modifier(HoverTip(text: text, side: side))
    }
}

// MARK: - 徽章、通知条

/** Badge：高 20、全圆角、soft 底 + text 色 */
struct Badge: View {
    enum Tone { case neutral, success, warning, danger, direct, action }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.badge)
            .foregroundStyle(colors.fg)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(colors.bg))
    }

    private var colors: (fg: Color, bg: Color) {
        switch tone {
        case .neutral: return (Theme.text2, Theme.bgSubtle)
        case .success: return (Theme.successText, Theme.successSoft)
        case .warning: return (Theme.warningText, Theme.warningSoft)
        case .danger: return (Theme.dangerText, Theme.dangerSoft)
        case .direct: return (Theme.directText, Theme.directSoft)
        case .action: return (Theme.actionText, Theme.actionSoft)
        }
    }
}

/** Notice：通知条，圆角 10、左侧图标、soft 底，右侧可放一个按钮 */
struct Notice<Trailing: View>: View {
    enum Tone { case info, warning, danger }

    var tone: Tone = .info
    let title: String
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 10) {
            icon.image(16)
                .foregroundStyle(iconColor)
                .padding(.top, detail == nil ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text1)
                if let detail {
                    Text(detail).font(.captionText).foregroundStyle(Theme.text2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
                .frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous).fill(background))
    }

    private var icon: Icon {
        switch tone {
        case .info: return .info
        case .warning: return .alert
        case .danger: return .circleX
        }
    }

    private var iconColor: Color {
        switch tone {
        case .info: return Theme.text2
        case .warning: return Theme.warning
        case .danger: return Theme.danger
        }
    }

    private var background: Color {
        switch tone {
        case .info: return Theme.bgSubtle
        case .warning: return Theme.warningSoft
        case .danger: return Theme.dangerSoft
        }
    }
}

extension Notice where Trailing == EmptyView {
    init(tone: Tone = .info, title: String, detail: String? = nil) {
        self.init(tone: tone, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: - 开关、勾选

/** SwitchStyle：30×18 的开关，开 = 主题色 */
struct SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? Theme.action : Theme.controlOff)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/** CheckMark：16px 勾选框或单选框，选中 = 主题色 */
struct CheckMark: View {
    let on: Bool
    var radio = false

    var body: some View {
        ZStack {
            if radio {
                Circle().strokeBorder(on ? Theme.action : Theme.borderStrong, lineWidth: on ? 5 : 1.5)
                    .background(Circle().fill(Theme.card))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on ? Theme.action : Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(on ? Color.clear : Theme.borderStrong, lineWidth: 1.5))
                if on { Icon.check.image(11).foregroundStyle(.white) }
            }
        }
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - 页头

/** PageHeader：内容区页头，高 52，整条可拖动窗口；左边图标 + 标题，右边操作 */
struct PageHeader<Leading: View, Extra: View, Actions: View>: View {
    var icon: Icon?
    let title: String
    /** 应用页用 16px 标题 + 灰色页面名；全局页用 18px 标题 */
    var subtitle: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var extra: () -> Extra
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            leading()
            if let icon {
                icon.image(18).foregroundStyle(Theme.text1).frame(width: 22, height: 22)
            }
            Text(title)
                .font(subtitle == nil ? .page : .title)
                .foregroundStyle(Theme.text1)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.bodyText).foregroundStyle(Theme.text3)
            }
            extra()
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions() }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(WindowDragArea())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

extension PageHeader where Leading == EmptyView {
    init(icon: Icon? = nil, title: String, subtitle: String? = nil,
         @ViewBuilder extra: @escaping () -> Extra, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(icon: icon, title: title, subtitle: subtitle, leading: { EmptyView() }, extra: extra, actions: actions)
    }
}

/** WindowDragArea：按住拖动窗口，双击缩放，放在页头和侧栏顶部的背景上 */
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/** EmptyState：列表为空时的占位 */
struct EmptyState: View {
    let icon: Icon
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            icon.image(24).foregroundStyle(Theme.text3)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.bgSubtle))
                .padding(.bottom, 4)
            Text(title).font(.strong).foregroundStyle(Theme.text1)
            Text(detail).font(.captionText).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Toast

/** Toast：底部居中的白卡片，状态只看图标颜色，几秒后自动消失 */
struct Toast: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if pending {
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
            } else {
                kind.icon.image(16).foregroundStyle(kind.color)
            }
            Text(text)
                .font(.bodyText)
                .foregroundStyle(Theme.text1)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onClose) {
                Icon.close.image(12).foregroundStyle(Theme.text3).frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: Theme.shadowMd, radius: 12, y: 4)
    }

    /** 以省略号结尾的是进行中的提示 */
    var pending: Bool { text.hasSuffix("…") }

    private var kind: (icon: Icon, color: Color) {
        if ["失败", "找不到"].contains(where: text.contains) { return (.circleX, Theme.danger) }
        if ["没有", "请手动", "请先", "请在"].contains(where: text.contains) { return (.alert, Theme.warning) }
        return (.circleCheck, Theme.success)
    }
}

// MARK: - 对话框

/** DialogSpec：一个确认框，可以带一个输入框 */
struct DialogSpec: Identifiable {
    let id = UUID()
    var title: String
    var message: String = ""
    var confirm: String
    var destructive = false
    /** 不为空时显示输入框，值是初始内容 */
    var input: String? = nil
    var placeholder = ""
    var action: (String) -> Void
}

/** Dialogs：全窗口共用的对话框入口 */
final class Dialogs: ObservableObject {
    @Published var current: DialogSpec?

    func present(_ spec: DialogSpec) {
        withAnimation(.easeOut(duration: 0.15)) { current = spec }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) { current = nil }
    }
}

/** DialogHost：遮罩 + 居中对话框，圆角 14、shadow-lg */
struct DialogHost: View {
    @EnvironmentObject var dialogs: Dialogs

    var body: some View {
        ZStack {
            if let spec = dialogs.current {
                Theme.overlay
                    .ignoresSafeArea()
                    .onTapGesture { dialogs.dismiss() }
                    .transition(.opacity)
                DialogCard(spec: spec) { dialogs.dismiss() }
                    .id(spec.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

private struct DialogCard: View {
    let spec: DialogSpec
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(spec.title).font(.title).foregroundStyle(Theme.text1)
            if !spec.message.isEmpty {
                Text(spec.message)
                    .font(.bodyText)
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if spec.input != nil {
                TextField(spec.placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.bodyText)
                    .foregroundStyle(Theme.text1)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                        .strokeBorder(focused ? Theme.action : Theme.borderStrong))
                    .overlay(RoundedRectangle(cornerRadius: Theme.rControl + 3, style: .continuous)
                        .stroke(Theme.action.opacity(focused ? 0.25 : 0), lineWidth: 3).padding(-3))
                    .focused($focused)
                    .onSubmit(confirm)
                    .padding(.top, 14)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("取消", action: close)
                    .buttonStyle(NeutralButton())
                    .keyboardShortcut(.cancelAction)
                Button(spec.confirm, action: confirm)
                    .buttonStyle(SolidButton(destructive: spec.destructive))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: Theme.rDialog, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.rDialog, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: Theme.shadowLg, radius: 20, y: 10)
        .onAppear {
            text = spec.input ?? ""
            if spec.input != nil { DispatchQueue.main.async { focused = true } }
        }
    }

    private func confirm() {
        close()
        spec.action(text)
    }
}
