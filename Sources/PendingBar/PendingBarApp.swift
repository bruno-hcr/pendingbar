import AppKit
import PendingKit
import SwiftUI

@main
struct PendingBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
                .environmentObject(model.preferences)
                .environmentObject(model.scheduler)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("PendingBar Settings", id: SettingsView.windowID) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.preferences)
                .environmentObject(model.scheduler)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let path = ProcessInfo.processInfo.environment["PENDINGBAR_SNAPSHOT"] {
                SnapshotRenderer.render(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
                return
            }
            AppModel.shared.start()
        }
    }
}

@MainActor
enum SnapshotRenderer {
    static func render(to directory: URL) {
        let model = AppModel.shared
        model.reload()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for order in TaskSortOrder.allCases {
                model.preferences.sortOrder = order
                let open = model.visibleTasks.filter(\.isOpen)
                let view = TaskListBody(sections: TaskSorting.sections(open, by: order, now: model.now), completed: [])
                    .frame(width: 400)
                    .environmentObject(model)
                    .environmentObject(model.preferences)
                    .environmentObject(model.scheduler)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard
                    let image = renderer.nsImage,
                    let tiff = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiff),
                    let png = bitmap.representation(using: .png, properties: [:])
                else { continue }
                let name = "panel-\(order.rawValue)-\(scheme == .dark ? "dark" : "light").png"
                try? png.write(to: directory.appendingPathComponent(name))
            }
        }
        model.preferences.sortOrder = .priority
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let count = model.badgeCount
        HStack(spacing: 3) {
            Image(systemName: model.overdueCount > 0 ? "checklist.unchecked" : "checklist")
            if count > 0 {
                Text("\(count)")
                    .monospacedDigit()
            }
        }
    }
}
