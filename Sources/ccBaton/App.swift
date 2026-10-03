/**
 * 应用入口：单窗口，关闭窗口即退出。
 */
import AppKit
import SwiftUI

/** AppDelegate：关闭最后一个窗口时退出 */
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/** CcBatonApp：应用主体 */
@main
struct CcBatonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AccountStore()

    var body: some Scene {
        Window("ccBaton", id: "main") {
            ContentView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 580, height: 600)
    }
}
