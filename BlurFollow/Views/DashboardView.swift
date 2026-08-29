import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var selector: RegionSelectionCoordinator
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var sharePreview: SharePreviewSession
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var textFollow: TextFollowCoordinator
    @Environment(\.openWindow) private var openWindow

    @State private var transientMessage: String?
    @State private var isPreparingSharePicker = false
    @State private var unlimitedMasksTrigger: UnlimitedMasksTrigger?
    @State private var pendingMaskCreationAfterUnlock: UnlimitedMasksTrigger?
    @State private var isShowingTextFollowCreator = false
    @State private var pendingTextFollowDraft: TextFollowDraft?
    let onMaskCreated: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                actionGrid
                sharePreviewCard
                recentMasks
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .sheet(item: $unlimitedMasksTrigger, onDismiss: resumeUnlockedMaskCreationIfNeeded) { trigger in
            UnlimitedMasksView(
                purchases: purchases,
                trigger: trigger,
                onUnlocked: {
                    pendingMaskCreationAfterUnlock = trigger
                    unlimitedMasksTrigger = nil
                }
            )
        }
        .sheet(
            isPresented: $isShowingTextFollowCreator,
            onDismiss: beginPendingTextFollowSelectionIfNeeded
        ) {
            TextFollowCreationView(
                onCancel: {
                    pendingTextFollowDraft = nil
                    isShowingTextFollowCreator = false
                },
                onContinue: { draft in
                    pendingTextFollowDraft = draft
                    isShowingTextFollowCreator = false
                }
            )
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(
                    title: dashboardStatus.title,
                    state: dashboardStatus.state
                )
                Spacer()
                if let transientMessage {
                    Text(transientMessage)
                        .font(.caption)
                        .foregroundStyle(BlurFollowTheme.coral)
                }
            }
            Text("Blur that follows your window.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(BlurFollowTheme.ink)
            Text("Place a blur on the display, or let it follow a selected window as you move and resize it.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var dashboardStatus: (title: String, state: TrackingState) {
        guard store.recoveryIssue == nil else { return (String(localized: "Review masks"), .unavailable) }
        guard store.masksEnabled else { return (String(localized: "Masks paused"), .unavailable) }
        let enabledMasks = store.regions.filter(\.isEnabled)
        let enabledRules = store.textRules.filter(\.isEnabled)
        guard !enabledMasks.isEmpty || !enabledRules.isEmpty else {
            return (String(localized: "No masks or rules"), .unavailable)
        }

        let maskStates = enabledMasks.map { store.trackingStates[$0.id] }
        let ruleStates = enabledRules.map { textFollow.state(for: $0.id) }
        let masksReady = maskStates.allSatisfy { $0 == .positionKnown }
        let rulesReady = ruleStates.allSatisfy { $0 == .following || $0 == .noMatches }
        if masksReady && rulesReady {
            return (String(localized: "Masks and text scan active"), .positionKnown)
        }
        if maskStates.contains(where: { $0 == .reconnecting })
            || ruleStates.contains(where: { $0 == .connecting || $0 == .scanning }) {
            return (String(localized: "Updating masks"), .reconnecting)
        }
        return (String(localized: "Check placement"), .unavailable)
    }

    private var actionGrid: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ActionCard(
                    title: String(localized: "Display Pin"),
                    detail: String(localized: "Keep a mask at one place on a display."),
                    icon: "display",
                    tint: BlurFollowTheme.iris,
                    action: { requestMaskCreation(for: .displayPin) }
                )
                ActionCard(
                    title: String(localized: "Window Pin"),
                    detail: String(localized: "Keep the selected area aligned as its window moves."),
                    icon: "macwindow.badge.plus",
                    tint: BlurFollowTheme.cyan,
                    action: { requestMaskCreation(for: .windowPin) }
                )
                .disabled(picker.isPicking)
            }

            TextFollowActionCard {
                requestMaskCreation(for: .textFollowRule)
            }
            .disabled(picker.isPicking)
        }
    }

    private var sharePreviewCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(BlurFollowTheme.ink)
                        .frame(width: 64, height: 64)
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(BlurFollowTheme.cyan)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Share Preview")
                        .font(.title3.weight(.bold))
                    Text("Apply matching Window Pins and ready Text Follow results to a separate preview, then inspect it before sharing.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: startSharePreview) {
                    Label(
                        sharePreview.isRunning
                            ? String(localized: "Change Source")
                            : String(localized: "Open Share Preview"),
                        systemImage: "play.rectangle.on.rectangle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(BlurFollowTheme.ink)
                .disabled(store.recoveryIssue != nil || picker.isPicking || isPreparingSharePicker)
            }
        }
    }

    @ViewBuilder
    private var recentMasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Masks and Rules")
                    .font(.headline)
                Spacer()
                Text(maskCountSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.regions.isEmpty && store.textRules.isEmpty {
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: "viewfinder")
                            .font(.title)
                            .foregroundStyle(BlurFollowTheme.iris)
                        VStack(alignment: .leading) {
                            Text("No masks or rules yet")
                                .font(.headline)
                            Text("Create a Display Pin, Window Pin, or a separate Text Follow rule.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(store.regions.prefix(3)) { region in
                    CompactMaskRow(region: region)
                }
                ForEach(store.textRules.prefix(3)) { rule in
                    CompactTextFollowRow(rule: rule)
                }
            }
        }
    }

    private func addDisplayPin() {
        selector.select(on: NSScreen.screens.map(\.frame)) { rect in
            guard let rect, let screen = NSScreen.bestMatch(for: rect) else { return }
            let region = MaskRegion(
                name: String.localizedStringWithFormat(
                    String(localized: "Display Mask %lld"),
                    Int64(store.regions.filter { $0.mode == .display }.count + 1)
                ),
                mode: .display,
                normalizedRect: UnitRect(rect: rect, in: screen.frame),
                displayIdentifier: screen.blurFollowIdentifier,
                style: .frost
            )
            guard store.add(
                region,
                hasUnlimitedAccess: purchases.hasUnlimitedAccess
            ) != nil else {
                unlimitedMasksTrigger = .displayPin
                return
            }
        }
    }

    private func addWindowPin() {
        let returnTarget = AppWindowReturnTarget()
        transientMessage = nil
        picker.pickWindow { result in
            switch result {
            case .success(let selection):
                let windowFrame = selection.candidate.appKitFrame
                selector.select(on: [windowFrame]) { rect in
                    defer { returnTarget.restore() }
                    guard let rect else { return }
                    let region = MaskRegion(
                        name: String.localizedStringWithFormat(
                            String(localized: "%@ Mask"),
                            selection.candidate.applicationName
                        ),
                        mode: .window,
                        normalizedRect: UnitRect(rect: rect, in: windowFrame),
                        windowAnchor: selection.candidate.anchor,
                        style: .frost
                    )
                    guard let addedRegion = store.add(
                        region,
                        hasUnlimitedAccess: purchases.hasUnlimitedAccess
                    ) else {
                        unlimitedMasksTrigger = .windowPin
                        return
                    }
                    tracker.bind(selection.candidate, to: addedRegion.id)
                    onMaskCreated()
                }
            case .failure(let error):
                returnTarget.restore()
                if case .cancelled = error { return }
                transientMessage = error.localizedDescription
            }
        }
    }

    private func beginPendingTextFollowSelectionIfNeeded() {
        guard let draft = pendingTextFollowDraft else { return }
        pendingTextFollowDraft = nil
        let returnTarget = AppWindowReturnTarget()
        transientMessage = nil
        picker.pickWindow { result in
            defer { returnTarget.restore() }
            switch result {
            case .success(let selection):
                let rule = TextFollowRule(
                    name: draft.name,
                    matchMode: draft.matchMode,
                    pattern: draft.pattern,
                    windowAnchor: selection.candidate.anchor
                )
                guard let addedRule = store.addTextRule(
                    rule,
                    hasUnlimitedAccess: purchases.hasUnlimitedAccess
                ) else {
                    unlimitedMasksTrigger = .textFollowRule
                    return
                }
                textFollow.connect(selection, to: addedRule.id)
                onMaskCreated()
            case .failure(let error):
                if case .cancelled = error { return }
                transientMessage = error.localizedDescription
            }
        }
    }

    private func requestMaskCreation(for trigger: UnlimitedMasksTrigger) {
        guard let planKind = planKind(for: trigger) else { return }
        guard purchases.canCreateMask(kind: planKind, usage: store.planUsage) else {
            unlimitedMasksTrigger = trigger
            return
        }
        resumeMaskCreation(for: trigger)
    }

    private func resumeMaskCreation(for trigger: UnlimitedMasksTrigger) {
        switch trigger {
        case .displayPin:
            addDisplayPin()
        case .windowPin:
            addWindowPin()
        case .textFollowRule:
            isShowingTextFollowCreator = true
        case .settings:
            break
        }
    }

    private func resumeUnlockedMaskCreationIfNeeded() {
        guard let trigger = pendingMaskCreationAfterUnlock else { return }
        pendingMaskCreationAfterUnlock = nil
        // sheet(onDismiss:) runs only after the purchase surface has finished closing. This keeps
        // the selection overlay/system picker attached to the real app window, not a retiring sheet.
        resumeMaskCreation(for: trigger)
    }

    private var maskCountSummary: String {
        let usage = store.planUsage
        if purchases.hasUnlimitedAccess {
            return String.localizedStringWithFormat(
                String(localized: "Display %lld · Window %lld · Text Follow %lld · Unlimited"),
                Int64(usage.displayMaskCount),
                Int64(usage.windowMaskCount),
                Int64(usage.textFollowRuleCount)
            )
        }
        return String.localizedStringWithFormat(
            String(localized: "Display %lld/%lld · Window %lld/%lld · Text Follow %lld/%lld"),
            Int64(usage.displayMaskCount),
            Int64(MaskAccessPolicy.freeDisplayMaskLimit),
            Int64(usage.windowMaskCount),
            Int64(MaskAccessPolicy.freeWindowMaskLimit),
            Int64(usage.textFollowRuleCount),
            Int64(MaskAccessPolicy.freeTextFollowRuleLimit)
        )
    }

    private func planKind(for trigger: UnlimitedMasksTrigger) -> MaskPlanKind? {
        switch trigger {
        case .displayPin: return .displayMask
        case .windowPin: return .windowMask
        case .textFollowRule: return .textFollowRule
        case .settings: return nil
        }
    }

    private func startSharePreview() {
        guard !picker.isPicking, !isPreparingSharePicker else { return }
        isPreparingSharePicker = true
        Task {
            // Apple's picker allows one unassociated selection at a time. Stop the current output
            // first so source switching cannot exceed that limit; cancellation leaves the preview covered.
            if sharePreview.isRunning { await sharePreview.stop() }
            let acceptedRequest = picker.pickWindow { result in
                switch result {
                case .success(let selection):
                    // Show the transition immediately. Capture startup can take noticeable time,
                    // and waiting for it before opening the window made the button feel stuck.
                    openWindow(id: "share-preview")
                    NSApp.activate(ignoringOtherApps: true)
                    Task {
                        await sharePreview.start(selection)
                        isPreparingSharePicker = false
                    }
                case .failure(let error):
                    isPreparingSharePicker = false
                    if case .cancelled = error { return }
                    transientMessage = error.localizedDescription
                }
            }
            if acceptedRequest == nil { isPreparingSharePicker = false }
        }
    }
}

private struct TextFollowDraft {
    var name: String
    var matchMode: TextMatchMode
    var pattern: String
}

private struct TextFollowCreationView: View {
    @State private var name = ""
    @State private var matchMode: TextMatchMode = .exact
    @State private var pattern = ""

    let onCancel: () -> Void
    let onContinue: (TextFollowDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(BlurFollowTheme.mint)
                    .frame(width: 62, height: 62)
                    .background(BlurFollowTheme.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Create Text Follow Rule")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        BetaBadge()
                    }
                    Text("Text Follow is separate from Window Pin. It recognizes text blocks in the selected window and moves mosaic masks when the content changes.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Rule Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Rule Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Match Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Match Mode", selection: $matchMode) {
                    ForEach(TextMatchMode.allCases) { mode in
                        Text(modeTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(modeDetail(matchMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Pattern")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Text Pattern", text: $pattern, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BlurFollowTheme.coral)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Text Follow is a beta feature. OCR can miss, misread, or delay matches, so use Strict Safety and verify every transition.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(BlurFollowTheme.ink)
                Label(
                    "Every text block matching this rule is mosaicked at the same time.",
                    systemImage: "rectangle.3.group.fill"
                )
                Label(
                    "One saved rule uses one free slot, even when it matches multiple blocks.",
                    systemImage: "1.circle.fill"
                )
                Label(
                    "Matching is case-sensitive. Always check the visible result after a page change.",
                    systemImage: "eye.fill"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlurFollowTheme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Window…") {
                    onContinue(TextFollowDraft(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        matchMode: matchMode,
                        pattern: pattern
                    ))
                }
                .buttonStyle(.borderedProminent)
                .tint(BlurFollowTheme.ink)
                .disabled(!canContinue)
            }
        }
        .padding(28)
        .frame(width: 620)
    }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validationMessage == nil
    }

    private var validationMessage: String? {
        do {
            _ = try TextPatternMatcher(mode: matchMode, pattern: pattern)
            return nil
        } catch let error as TextPatternMatcher.ValidationError {
            switch error {
            case .emptyPattern:
                return String(localized: "Enter a text pattern.")
            case .patternTooLong(let maximum):
                return String.localizedStringWithFormat(
                    String(localized: "The pattern must be %lld UTF-8 bytes or fewer."),
                    Int64(maximum)
                )
            case .invalidRegularExpression:
                return String(localized: "Enter a valid regular expression.")
            }
        } catch {
            return String(localized: "The text pattern is not valid.")
        }
    }

    private func modeTitle(_ mode: TextMatchMode) -> String {
        switch mode {
        case .exact: return String(localized: "Exact Match")
        case .prefix: return String(localized: "Prefix Match")
        case .contains: return String(localized: "Contains")
        case .regex: return String(localized: "Regular Expression")
        }
    }

    private func modeDetail(_ mode: TextMatchMode) -> String {
        switch mode {
        case .exact:
            return String(localized: "Matches only a text block whose complete recognized text is identical.")
        case .prefix:
            return String(localized: "Matches a text block whose recognized text starts with the pattern.")
        case .contains:
            return String(localized: "Matches a text block whose recognized text contains the pattern.")
        case .regex:
            return String(localized: "Searches each recognized text block with the regular expression.")
        }
    }
}

private struct TextFollowActionCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 16) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(BlurFollowTheme.mint.gradient, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("Text Follow")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            BetaBadge()
                        }
                        Text("Automatically mosaic every matching text block as pages and content change.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(BlurFollowTheme.mint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Creates a beta text-matching rule after you choose a window.")
    }
}

private struct ActionCard: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(tint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CompactMaskRow: View {
    @EnvironmentObject private var store: MaskStore
    let region: MaskRegion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: region.mode.systemImage)
                .foregroundStyle(region.mode == .window ? BlurFollowTheme.cyan : BlurFollowTheme.iris)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(region.name).font(.subheadline.weight(.semibold))
                Text(String.localizedStringWithFormat(
                    String(localized: "%@ · %@"),
                    region.mode.title,
                    region.style.title
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(title: maskStatus.title, state: maskStatus.state)
        }
        .padding(14)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
    }

    private var maskStatus: (title: String, state: TrackingState) {
        guard region.isEnabled else { return (String(localized: "Off"), .unavailable) }
        guard let state = store.trackingStates[region.id] else {
            return (String(localized: "Checking position"), .unavailable)
        }
        if state == .positionKnown {
            let title = region.mode == .window ? String(localized: "Following") : String(localized: "Placed")
            return (title, state)
        }
        return (state.title, state)
    }
}

private struct CompactTextFollowRow: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var textFollow: TextFollowCoordinator
    let rule: TextFollowRule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .foregroundStyle(BlurFollowTheme.mint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(liveRule.name)
                    .font(.subheadline.weight(.semibold))
                Text(String.localizedStringWithFormat(
                    String(localized: "%@ · %@"),
                    textFollowModeTitle(liveRule.matchMode),
                    liveRule.windowAnchor.applicationName
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                StatusPill(title: runtimeState.localizedTitle, state: runtimeState.trackingState)
                Text(textFollowMatchCountText(textFollow.matchedCount(for: rule.id)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
    }

    private var liveRule: TextFollowRule {
        store.textRules.first(where: { $0.id == rule.id }) ?? rule
    }

    private var runtimeState: TextFollowRuntimeState {
        guard store.masksEnabled, liveRule.isEnabled else { return .disabled }
        return textFollow.state(for: rule.id)
    }
}
