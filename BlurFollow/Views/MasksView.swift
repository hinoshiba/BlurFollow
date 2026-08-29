import SwiftUI

struct MasksView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var overlay: OverlayCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Masks")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Manage manual masks and automatic Text Follow rules as separate features.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Manual Masks", systemImage: "rectangle.3.group")
                            .font(.headline)
                        Spacer()
                        Text(String.localizedStringWithFormat(
                            String(localized: "%lld saved"),
                            Int64(store.regions.count)
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Display Pins and Window Pins keep a rectangle at a saved geometric position.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if store.regions.isEmpty {
                        GlassCard {
                            ContentUnavailableView(
                                "No Manual Masks",
                                systemImage: "rectangle.dashed",
                                description: Text("Create a Display Pin or Window Pin from Home.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 170)
                        }
                    } else {
                        ForEach(store.regions) { region in
                            MaskEditorCard(region: region)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 8) {
                            Label("Text Follow Rules", systemImage: "text.viewfinder")
                                .font(.headline)
                                .foregroundStyle(BlurFollowTheme.mint)
                            BetaBadge()
                        }
                        Spacer()
                        Text(String.localizedStringWithFormat(
                            String(localized: "%lld saved"),
                            Int64(store.textRules.count)
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Text Follow is independent from Window Pin. One rule mosaics every matching text block and still uses only one plan slot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if store.textRules.isEmpty {
                        GlassCard {
                            ContentUnavailableView(
                                "No Text Follow Rules",
                                systemImage: "text.viewfinder",
                                description: Text("Create a rule from Home to match text as a window's content changes.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 170)
                        }
                    } else {
                        ForEach(store.textRules) { rule in
                            TextFollowRuleEditorCard(rule: rule)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onDisappear {
            overlay.endEditing()
            store.flushPersistence()
        }
    }
}

private struct MaskEditorCard: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var overlay: OverlayCoordinator
    @State private var reconnectMessage: String?
    let region: MaskRegion

    private func binding<Value>(_ keyPath: WritableKeyPath<MaskRegion, Value>) -> Binding<Value> {
        Binding(
            get: { store.regions.first(where: { $0.id == region.id })?[keyPath: keyPath] ?? region[keyPath: keyPath] },
            set: { newValue in
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current[keyPath: keyPath] = newValue
                store.update(current)
            }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { store.regions.first(where: { $0.id == region.id })?.strength ?? region.strength },
            set: { newValue in
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current.strength = newValue
                store.updateLive(current)
            }
        )
    }

    private var granularityBinding: Binding<Double> {
        Binding(
            get: { store.regions.first(where: { $0.id == region.id })?.granularity ?? region.granularity },
            set: { newValue in
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current.granularity = newValue
                store.updateLive(current)
            }
        )
    }

    private var liveRegion: MaskRegion {
        store.regions.first(where: { $0.id == region.id }) ?? region
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: region.mode.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            (region.mode == .window ? BlurFollowTheme.cyan : BlurFollowTheme.iris).gradient,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Mask Name", text: binding(\.name))
                            .textFieldStyle(.plain)
                            .font(.headline)
                        Text(targetDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        title: maskStatus.title,
                        state: maskStatus.state
                    )
                    Toggle("", isOn: binding(\.isEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                }

                Divider()

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mask Style")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Mask Style", selection: binding(\.style)) {
                            ForEach(MaskStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text(liveRegion.style.detail)
                            .font(.caption)
                            .foregroundStyle(liveRegion.style == .frost ? BlurFollowTheme.amber : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if liveRegion.style != .redact {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Strength"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(
                                value: strengthBinding,
                                in: 0.2...1,
                                onEditingChanged: { isEditing in
                                    if !isEditing { store.flushPersistence() }
                                }
                            )
                            .tint(BlurFollowTheme.iris)
                            Text(String.localizedStringWithFormat(
                                String(localized: "%lld%%"),
                                Int64(liveRegion.strength * 100)
                            ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .frame(width: 170)
                    }
                }

                if liveRegion.style == .frost || liveRegion.style == .mosaic {
                    Divider()

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Granularity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(
                                value: granularityBinding,
                                in: 0...1,
                                onEditingChanged: { isEditing in
                                    if !isEditing { store.flushPersistence() }
                                }
                            )
                            .tint(BlurFollowTheme.cyan)
                            HStack {
                                Text("Fine")
                                Spacer()
                                Text(String.localizedStringWithFormat(
                                    String(localized: "%lld%%"),
                                    Int64(liveRegion.granularity * 100)
                                ))
                                    .monospacedDigit()
                                Spacer()
                                Text("Coarse")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color Tone")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Color Tone", selection: binding(\.tint)) {
                                ForEach(MaskTint.allCases) { tint in
                                    Text(tint.title).tag(tint)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        Toggle("Border", isOn: binding(\.borderEnabled))
                            .toggleStyle(.switch)
                            .tint(BlurFollowTheme.mint)
                            .padding(.top, 19)
                    }
                }

                HStack {
                    if region.mode == .window {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                String.localizedStringWithFormat(
                                    String(localized: "Moves and resizes with %@"),
                                    region.windowAnchor?.applicationName ?? String(localized: "selected window")
                                ),
                                systemImage: "arrow.up.left.and.arrow.down.right"
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let reconnectMessage {
                                Text(reconnectMessage)
                                    .font(.caption)
                                    .foregroundStyle(BlurFollowTheme.coral)
                            }
                        }
                    } else {
                        Label("Pinned to this display", systemImage: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if isMoving {
                            overlay.endEditing()
                        } else {
                            overlay.beginEditing(regionID: region.id)
                        }
                    } label: {
                        Label(
                            isMoving ? String(localized: "Cancel Move") : String(localized: "Move…"),
                            systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isMoving && !canMove)
                    if region.mode == .window {
                        Button("Reconnect…", action: reconnectWindow)
                            .buttonStyle(.borderless)
                            .disabled(picker.isPicking)
                    }
                    Button(role: .destructive) {
                        store.remove(id: region.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                if isMoving {
                    Label(
                        "Drag the mask itself to move it. Release to save; press Esc to cancel.",
                        systemImage: "hand.draw"
                    )
                    .font(.caption)
                    .foregroundStyle(BlurFollowTheme.iris)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var isMoving: Bool {
        overlay.editingRegionID == region.id
    }

    private var canMove: Bool {
        store.masksEnabled && region.isEnabled && maskStatus.state == .positionKnown
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

    private var targetDescription: String {
        switch region.mode {
        case .display:
            return String(localized: "Display Pin")
        case .window:
            let app = region.windowAnchor?.applicationName ?? String(localized: "Unknown App")
            return String.localizedStringWithFormat(
                String(localized: "%@ · %@"),
                app,
                String(localized: "Window-following")
            )
        }
    }

    private func reconnectWindow() {
        let returnTarget = AppWindowReturnTarget()
        reconnectMessage = nil
        picker.pickWindow { result in
            defer { returnTarget.restore() }
            switch result {
            case .success(let selection):
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current.windowAnchor = selection.candidate.anchor
                tracker.bind(selection.candidate, to: current.id)
                store.update(current)
            case .failure(let error):
                if case .cancelled = error { return }
                reconnectMessage = error.localizedDescription
            }
        }
    }
}

private struct TextFollowRuleEditorCard: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var textFollow: TextFollowCoordinator
    @State private var reconnectMessage: String?
    @State private var nameDraft: String
    @State private var matchModeDraft: TextMatchMode
    @State private var patternDraft: String

    let rule: TextFollowRule

    init(rule: TextFollowRule) {
        self.rule = rule
        _nameDraft = State(initialValue: rule.name)
        _matchModeDraft = State(initialValue: rule.matchMode)
        _patternDraft = State(initialValue: rule.pattern)
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: "text.viewfinder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(BlurFollowTheme.mint.gradient, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Rule Name", text: $nameDraft)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .onSubmit(commitName)
                        Text(String.localizedStringWithFormat(
                            String(localized: "Text Follow · %@"),
                            liveRule.windowAnchor.applicationName
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        StatusPill(
                            title: runtimeState.localizedTitle,
                            state: runtimeState.trackingState
                        )
                        Text(textFollowMatchCountText(textFollow.matchedCount(for: rule.id)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Toggle("", isOn: Binding(
                        get: { liveRule.isEnabled },
                        set: { store.setTextRuleEnabled($0, for: rule.id) }
                    ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                }

                Divider()

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Match Mode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Match Mode", selection: $matchModeDraft) {
                            ForEach(TextMatchMode.allCases) { mode in
                                Text(modeTitle(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(width: 300)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text Pattern")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Text Pattern", text: $patternDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .onSubmit(commitPatternIfValid)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let validationMessage {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            Text("Invalid changes are not applied; the saved rule remains active.")
                        }
                        .font(.caption)
                        .foregroundStyle(BlurFollowTheme.coral)
                    } else if hasUnappliedPatternChanges {
                        Label(
                            "Review the match changes, then apply them to restart the local scan.",
                            systemImage: "pencil.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "Every matching text block is mosaicked; multiple matches still count as one saved rule.",
                            systemImage: "rectangle.3.group.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply Match", action: commitPatternIfValid)
                        .buttonStyle(.bordered)
                        .disabled(validationMessage != nil || !hasUnappliedPatternChanges)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                HStack(alignment: .top, spacing: 22) {
                    sliderControl(
                        title: String(localized: "Strength"),
                        value: liveBinding(\.strength),
                        range: 0.2...1,
                        tint: BlurFollowTheme.iris,
                        valueText: percentText(liveRule.strength)
                    )
                    sliderControl(
                        title: String(localized: "Granularity"),
                        value: liveBinding(\.granularity),
                        range: 0...1,
                        tint: BlurFollowTheme.cyan,
                        valueText: percentText(liveRule.granularity)
                    )
                    sliderControl(
                        title: String(localized: "Padding"),
                        value: liveBinding(\.padding),
                        range: 0...TextFollowRule.maximumPadding,
                        tint: BlurFollowTheme.mint,
                        valueText: String.localizedStringWithFormat(
                            String(localized: "%lld pt"),
                            Int64(liveRule.padding.rounded())
                        )
                    )
                }

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color Tone")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Color Tone", selection: binding(\.tint)) {
                            ForEach(MaskTint.allCases) { tint in
                                Text(tint.title).tag(tint)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    sliderControl(
                        title: String(localized: "Corner Radius"),
                        value: liveBinding(\.cornerRadius),
                        range: 0...40,
                        tint: BlurFollowTheme.iris,
                        valueText: String.localizedStringWithFormat(
                            String(localized: "%lld pt"),
                            Int64(liveRule.cornerRadius.rounded())
                        )
                    )

                    Toggle("Border", isOn: binding(\.borderEnabled))
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                        .padding(.top, 19)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            String.localizedStringWithFormat(
                                String(localized: "Recognizes text locally in %@"),
                                liveRule.windowAnchor.applicationName
                            ),
                            systemImage: "lock.shield"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let reconnectMessage {
                            Text(reconnectMessage)
                                .font(.caption)
                                .foregroundStyle(BlurFollowTheme.coral)
                        }
                    }
                    Spacer()
                    Button("Reconnect…", action: reconnectWindow)
                        .buttonStyle(.borderless)
                        .disabled(picker.isPicking)
                    Button(role: .destructive) {
                        store.removeTextRule(id: rule.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onDisappear {
            commitName()
            store.flushPersistence()
        }
    }

    private var liveRule: TextFollowRule {
        store.textRules.first(where: { $0.id == rule.id }) ?? rule
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TextFollowRule, Value>) -> Binding<Value> {
        Binding(
            get: { liveRule[keyPath: keyPath] },
            set: { newValue in
                guard var current = store.textRules.first(where: { $0.id == rule.id }) else { return }
                current[keyPath: keyPath] = newValue
                store.updateTextRule(current)
            }
        )
    }

    private func liveBinding(_ keyPath: WritableKeyPath<TextFollowRule, Double>) -> Binding<Double> {
        Binding(
            get: { liveRule[keyPath: keyPath] },
            set: { newValue in
                guard var current = store.textRules.first(where: { $0.id == rule.id }) else { return }
                current[keyPath: keyPath] = newValue
                store.updateTextRuleLive(current)
            }
        )
    }

    @ViewBuilder
    private func sliderControl(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        tint: Color,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(
                value: value,
                in: range,
                onEditingChanged: { isEditing in
                    if !isEditing { store.flushPersistence() }
                }
            )
                .tint(tint)
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentText(_ value: Double) -> String {
        String.localizedStringWithFormat(
            String(localized: "%lld%%"),
            Int64(value * 100)
        )
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var current = store.textRules.first(where: { $0.id == rule.id }),
              current.name != trimmed else { return }
        nameDraft = trimmed
        current.name = trimmed
        store.updateTextRule(current)
    }

    private func commitPatternIfValid() {
        guard validationMessage == nil,
              var current = store.textRules.first(where: { $0.id == rule.id }),
              current.matchMode != matchModeDraft || current.pattern != patternDraft else { return }
        current.matchMode = matchModeDraft
        current.pattern = patternDraft
        store.updateTextRule(current)
    }

    private var hasUnappliedPatternChanges: Bool {
        liveRule.matchMode != matchModeDraft || liveRule.pattern != patternDraft
    }

    private var validationMessage: String? {
        do {
            _ = try TextPatternMatcher(mode: matchModeDraft, pattern: patternDraft)
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

    private var runtimeState: TextFollowRuntimeState {
        guard store.masksEnabled, liveRule.isEnabled else { return .disabled }
        return textFollow.state(for: rule.id)
    }

    private func modeTitle(_ mode: TextMatchMode) -> String {
        textFollowModeTitle(mode)
    }

    private func reconnectWindow() {
        let returnTarget = AppWindowReturnTarget()
        reconnectMessage = nil
        picker.pickWindow { result in
            defer { returnTarget.restore() }
            switch result {
            case .success(let selection):
                guard var current = store.textRules.first(where: { $0.id == rule.id }) else { return }
                current.windowAnchor = selection.candidate.anchor
                store.updateTextRule(current)
                textFollow.connect(selection, to: current.id)
            case .failure(let error):
                if case .cancelled = error { return }
                reconnectMessage = error.localizedDescription
            }
        }
    }
}

func textFollowModeTitle(_ mode: TextMatchMode) -> String {
    switch mode {
    case .exact: return String(localized: "Exact Match")
    case .prefix: return String(localized: "Prefix Match")
    case .contains: return String(localized: "Contains")
    case .regex: return String(localized: "Regular Expression")
    }
}

func textFollowMatchCountText(_ count: Int) -> String {
    let format = count == 1
        ? String(localized: "%lld match")
        : String(localized: "%lld matches")
    return String.localizedStringWithFormat(format, Int64(count))
}

extension TextFollowRuntimeState {
    var localizedTitle: String {
        switch self {
        case .disabled: return String(localized: "Off")
        case .reconnectRequired: return String(localized: "Reconnect required")
        case .connecting: return String(localized: "Connecting")
        case .scanning: return String(localized: "Scanning text")
        case .following: return String(localized: "Following text")
        case .noMatches: return String(localized: "No matches")
        case .sourceUnavailable: return String(localized: "Source unavailable")
        case .failed: return String(localized: "Text recognition failed")
        }
    }

    var trackingState: TrackingState {
        switch self {
        case .following, .noMatches:
            return .positionKnown
        case .connecting, .scanning:
            return .reconnecting
        case .disabled, .reconnectRequired, .sourceUnavailable, .failed:
            return .unavailable
        }
    }
}
