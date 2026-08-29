import SwiftUI

@main
struct BlurFollowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: MaskStore
    @StateObject private var tracker: WindowTracker
    @StateObject private var overlay: OverlayCoordinator
    @StateObject private var textFollow: TextFollowCoordinator
    @StateObject private var selector: RegionSelectionCoordinator
    @StateObject private var picker: ContentPickerService
    @StateObject private var permission: ScreenCapturePermission
    @StateObject private var sharePreview: SharePreviewSession
    @StateObject private var purchases: PurchaseManager
    @StateObject private var reviewPrompts: ReviewPromptCoordinator

    init() {
        let store = MaskStore()
        let tracker = WindowTracker()
        let textFollow = TextFollowCoordinator(store: store, tracker: tracker)
        let permission = ScreenCapturePermission()
        _store = StateObject(wrappedValue: store)
        _tracker = StateObject(wrappedValue: tracker)
        _overlay = StateObject(wrappedValue: OverlayCoordinator(store: store, tracker: tracker))
        _textFollow = StateObject(wrappedValue: textFollow)
        _selector = StateObject(wrappedValue: RegionSelectionCoordinator())
        _permission = StateObject(wrappedValue: permission)
        _picker = StateObject(wrappedValue: ContentPickerService(
            onLegacyAccessRequestCompleted: { permission.recordLegacyRequestResult($0) },
            onPickerAuthorization: { permission.recordPickerAuthorization() },
            onAccessDenied: { permission.recordDenial() }
        ))
        _sharePreview = StateObject(wrappedValue: SharePreviewSession(
            store: store,
            tracker: tracker,
            textFollow: textFollow,
            onAccessDenied: { permission.recordDenial() }
        ))
        _purchases = StateObject(wrappedValue: PurchaseManager())
        _reviewPrompts = StateObject(wrappedValue: ReviewPromptCoordinator())
    }

    var body: some Scene {
        Window("BlurFollow", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(tracker)
                .environmentObject(overlay)
                .environmentObject(textFollow)
                .environmentObject(selector)
                .environmentObject(picker)
                .environmentObject(permission)
                .environmentObject(sharePreview)
                .environmentObject(purchases)
                .environmentObject(reviewPrompts)
                .preferredColorScheme(BlurFollowTheme.colorScheme)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    overlay.start()
                    textFollow.start()
                    permission.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)

        Window(String(localized: "BlurFollow Share Preview"), id: "share-preview") {
            SharePreviewView()
                .environmentObject(store)
                .environmentObject(picker)
                .environmentObject(permission)
                .environmentObject(sharePreview)
                .environmentObject(purchases)
                .environmentObject(reviewPrompts)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(sharePreview)
                .environmentObject(textFollow)
        } label: {
            Label("BlurFollow", systemImage: store.masksEnabled ? "rectangle.inset.filled.and.person.filled" : "rectangle.dashed")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(permission)
                .environmentObject(purchases)
                .preferredColorScheme(BlurFollowTheme.colorScheme)
                .frame(width: 620, height: 480)
        }
    }
}
