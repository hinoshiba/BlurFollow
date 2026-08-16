import SwiftUI

@main
struct BlurFollowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: MaskStore
    @StateObject private var tracker: WindowTracker
    @StateObject private var overlay: OverlayCoordinator
    @StateObject private var selector: RegionSelectionCoordinator
    @StateObject private var picker: ContentPickerService
    @StateObject private var permission: ScreenCapturePermission
    @StateObject private var sharePreview: SharePreviewSession

    init() {
        let store = MaskStore()
        let tracker = WindowTracker()
        _store = StateObject(wrappedValue: store)
        _tracker = StateObject(wrappedValue: tracker)
        _overlay = StateObject(wrappedValue: OverlayCoordinator(store: store, tracker: tracker))
        _selector = StateObject(wrappedValue: RegionSelectionCoordinator())
        _picker = StateObject(wrappedValue: ContentPickerService())
        _permission = StateObject(wrappedValue: ScreenCapturePermission())
        _sharePreview = StateObject(wrappedValue: SharePreviewSession(store: store, tracker: tracker))
    }

    var body: some Scene {
        Window("BlurFollow", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(tracker)
                .environmentObject(overlay)
                .environmentObject(selector)
                .environmentObject(picker)
                .environmentObject(permission)
                .environmentObject(sharePreview)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    overlay.start()
                    permission.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)

        Window(String(localized: "BlurFollow Share Preview"), id: "share-preview") {
            SharePreviewView()
                .environmentObject(store)
                .environmentObject(picker)
                .environmentObject(sharePreview)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(sharePreview)
        } label: {
            Label("BlurFollow", systemImage: store.masksEnabled ? "rectangle.inset.filled.and.person.filled" : "rectangle.dashed")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(permission)
                .frame(width: 620, height: 480)
        }
    }
}
