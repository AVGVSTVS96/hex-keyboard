import KeyboardStore
import KeyboardCore
import KeyboardUI
import SwiftUI

/// iikb drawn as these settings make it on the screen the app is on, at the width it's offered.
struct KeyboardPreview: UIViewRepresentable {
    let settings: KeyboardSettings

    func makeUIView(context: Context) -> KeyboardPreviewView {
        let view = KeyboardPreviewView()
        view.layer.cornerRadius = 26
        view.layer.borderWidth = 1
        return view
    }

    func updateUIView(_ view: KeyboardPreviewView, context: Context) {
        view.show(settings, dark: context.environment.colorScheme == .dark, screen: context.environment.window)
        view.layer.borderColor = AppStyle.edge.resolvedColor(with: view.traitCollection).cgColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyboardPreviewView, context: Context) -> CGSize? {
        let width = min(proposal.width ?? 390, 520)
        return CGSize(width: width, height: KeyboardPreviewView.height(forWidth: width, settings: settings, screen: context.environment.window))
    }
}

/// iikb as it will look, over a pill that brings up the real keyboard in a field, so a change can be tried at once.
struct TryPreview: View {
    @State private var trying = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.window) private var window
    private let model = SettingsModel.shared

    var body: some View {
        VStack(spacing: 14) {
            if trying {
                TextField("Type to try iikb", text: $text, axis: .vertical)
                    .font(.title3)
                    .focused($focused)
                    .lineLimit(3 ... 6)
                    .padding(18)
                    .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, focused in if !focused { withAnimation(.snappy) { trying = false } } }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                KeyboardPreview(settings: model.settings)
                    .transition(.opacity)
                Button {
                    withAnimation(.snappy) { trying = true }
                } label: {
                    Text("Tap to try")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.appCard, in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.appEdge))
                }
                .buttonStyle(CardPress())
                .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
    }

    /// Wide enough to read, short enough to leave the settings in view: at most two fifths of the window's height.
    private var maxWidth: CGFloat {
        min(520, window.height * 0.4 / (KeyboardPreviewView.height(forWidth: 100, settings: model.settings, screen: window) / 100))
    }
}

/// What the settings pages read and write: the keyboard's switches through `SettingsStore`, so the keyboard and
/// Settings › Apps › iikb see the same values, and the sources iikb tells what you type.
@Observable final class SettingsModel {
    static let shared = SettingsModel()

    private(set) var settings = SettingsStore.load()
    private(set) var sources = SourceStore.load()
    private(set) var keepMicOn = SettingsStore.keepMicOn

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsModel.shared.reload() }
        }
    }

    func reload() {
        settings = SettingsStore.load()
        sources = SourceStore.load()
        keepMicOn = SettingsStore.keepMicOn
    }

    func update(_ change: (inout KeyboardSettings) -> Void) {
        change(&settings)
        SettingsStore.save(settings)
    }

    func binding<Value>(_ path: WritableKeyPath<KeyboardSettings, Value>) -> Binding<Value> {
        Binding { self.settings[keyPath: path] } set: { value in self.update { $0[keyPath: path] = value } }
    }

    func keepMicOn(_ seconds: Int) {
        keepMicOn = seconds
        SettingsStore.keepMicOn = seconds
        Listener.shared.keepMicOn()
    }

    /// Adds a source, or puts `replacing` back with its new values.
    func save(_ source: Source, replacing old: Source?) {
        var sources = SourceStore.load()
        if let old, let index = sources.firstIndex(of: old) { sources[index] = source } else { sources.append(source) }
        SourceStore.save(sources)
        self.sources = sources
    }

    func delete(_ offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        SourceStore.save(sources)
    }

    func move(_ offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        SourceStore.save(sources)
    }
}

/// Everything about how the keyboard looks, on one page: its theme, what a pressed key shows, and how its keys are laid out.
struct AppearanceSettings: View {
    var body: some View {
        ThemeSettings()
        CharacterPreviewPicker()
        LayoutSettings()
    }
}

private struct ThemeSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(header: "Theme", footer: "Automatic follows the app you’re typing in, light or dark.") {
            ForEach(ThemeName.allCases, id: \.self) { theme in
                let picked = model.settings.theme == theme
                ChoiceRow(title: theme.title, detail: Self.detail(of: theme), picked: picked) {
                    withAnimation(.snappy) { model.update { $0.theme = theme } }
                }
                if picked, theme.hasAppearance {
                    HStack(spacing: 0) {
                        ForEach(ThemeAppearance.allCases, id: \.self) { appearance in
                            Button {
                                model.update { $0.themeAppearance = appearance }
                            } label: {
                                VStack(spacing: 8) {
                                    Swatch(theme: theme, appearance: appearance)
                                    Text(appearance.title).font(.subheadline)
                                    Radio(picked: model.settings.themeAppearance == appearance)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(appearance.title)
                            .accessibilityAddTraits(model.settings.themeAppearance == appearance ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    static func detail(of theme: ThemeName) -> String {
        switch theme {
        case .standard: "iikb’s own keys, flat, as iOS 27 draws them."
        case .clear: "Only the letters, no keys around them."
        case .physical: "Solid keys, dark or light."
        case .mechanical: "Raised keycaps you can almost press."
        case .classic: "The glossy keyboard of 2011."
        }
    }
}

/// Raycast's A and B keycaps, as a theme draws them in light, dark, or (for Automatic) one of each.
private struct Swatch: UIViewRepresentable {
    let theme: ThemeName
    let appearance: ThemeAppearance

    func makeUIView(context: Context) -> KeycapSwatchView { KeycapSwatchView() }

    func updateUIView(_ view: KeycapSwatchView, context: Context) {
        view.show(theme, appearance: appearance, dark: context.environment.colorScheme == .dark)
    }
}

struct TypingSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(footer: "Predictive Text shows three suggestions above the keys, and the next word before you type it. Slide to Type types a word as you swipe across its letters.") {
            ToggleRow(title: "Auto-Capitalization", isOn: model.binding(\.autoCapitalization))
            ToggleRow(title: "Auto-Correction", isOn: model.binding(\.autoCorrection))
            ToggleRow(title: "Predictive Text", isOn: model.binding(\.predictiveText))
            ToggleRow(title: "Slide to Type", isOn: model.binding(\.slideToType))
        }
        Box(footer: "Smart Punctuation curls quotes and turns two hyphens into a dash.") {
            ToggleRow(title: "Smart Punctuation", isOn: model.binding(\.smartPunctuation))
            ToggleRow(title: "Enable Caps Lock", detail: "Double-tap shift.", isOn: model.binding(\.capsLock))
            ToggleRow(title: "“.” Shortcut", detail: "Double-tap space for a period and a space.", isOn: model.binding(\.periodShortcut))
        }
        Box(header: "Text Replacements") {
            Button { AppStatus.openSettings() } label: {
                HStack {
                    RowText(title: "Open Settings", detail: "iikb types the ones in General › Keyboard › Text Replacement. This opens Settings › Apps › iikb.")
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                }
                .row()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LayoutSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(header: "Size and Shape", footer: "Less space between the keys makes them bigger. The keyboard stays the same size.") {
            StopSlider(title: "Space Between Keys", label: "Key Spacing", level: model.binding(\.keySpacing), levels: KeySpacing.allCases, name: \.title, ends: ("Bigger Keys", "More Space"))
            StopSlider(title: "Corners", label: "Key Roundness", level: model.binding(\.keyRoundness), levels: KeyRoundness.allCases, name: \.title, ends: ("Sharper", "Rounder"))
        }
        Box(header: "Keys") {
            ToggleRow(title: "Number Row", detail: "1 to 0 above the letters. The keyboard grows upward.", isOn: model.binding(\.numberRow))
            ToggleRow(title: "Emoji Key", detail: "Every emoji, from beside the space bar. Without it, a word’s emoji still show in the suggestions.", isOn: model.binding(\.emojiKey))
            ToggleRow(title: "Record Key", detail: "The record button left of 123, in the globe’s place, instead of at the right of the bar. The globe goes to the keyboard’s menu.", isOn: model.binding(\.micKey))
        }
        Box(header: "Globe Key", footer: "At the far left of the bottom row, on iPhones with no globe under the keyboard, like the Duo. As a spacer it keeps 123 away from the corner and does nothing when tapped. As a spacer or hidden, Next Keyboard is in the keyboard’s menu.") {
            ForEach(GlobeKey.allCases, id: \.self) { globe in
                ChoiceRow(title: globe.title, picked: model.settings.globeKey == globe) { model.update { $0.globeKey = globe } }
            }
        }
        Box(header: "Emoji and GIFs") {
            MenuRow(title: "Skin Tone", selection: model.binding(\.skinTone), choices: [nil] + SkinTone.allCases.map(Optional.some)) { tone in
                "✋\(tone.map { String($0.modifier) } ?? "") \(tone?.title ?? "Default")"
            }
            ToggleRow(title: "Compact Emoji & GIFs", detail: "One row that scrolls sideways, as in landscape, so the keyboard stays short in portrait too.", isOn: model.binding(\.compactPanels))
        }
        Box(header: "Split and One-Handed", footer: "Split puts half the keys under each thumb on the open iPhone Duo in landscape. One-Handed moves them toward one thumb on an iPhone in portrait, on the Duo only folded. The keyboard’s menu has both too.") {
            ToggleRow(title: "Split Keyboard", isOn: model.binding(\.split))
            MenuRow(title: "One-Handed Keyboard", selection: model.binding(\.oneHanded), choices: OneHanded.allCases, label: Self.title(of:))
        }
        Box(header: "Keyboard Menu", footer: "Where to open layouts, Next Keyboard and iikb Settings: hold 123 or emoji and slide, or tap the menu button above the keys.") {
            ForEach(KeyboardMenu.allCases, id: \.self) { place in
                ChoiceRow(title: place.title, picked: model.settings.keyboardMenu == place) { model.update { $0.keyboardMenu = place } }
            }
        }
    }

    static func title(of hand: OneHanded) -> String {
        switch hand {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// What shows above a key as you press it, each choice drawn.
private struct CharacterPreviewPicker: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(header: "Character Preview") {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(CharacterPreview.allCases, id: \.self) { preview in
                    Button {
                        model.update { $0.characterPreview = preview }
                    } label: {
                        VStack(spacing: 10) {
                            PreviewDrawing(preview: preview)
                            Text(preview.title).font(.subheadline)
                            Radio(picked: model.settings.characterPreview == preview)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preview.title)
                    .accessibilityAddTraits(model.settings.characterPreview == preview ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
        }
    }
}

/// A key and what pressing it shows above it, drawn small, as Raycast's picker draws them.
private struct PreviewDrawing: View {
    let preview: CharacterPreview

    var body: some View {
        let key = Color.appSecondary.opacity(0.45), bubble = Color.appSecondary.opacity(0.7)
        ZStack(alignment: .bottom) {
            switch preview {
            case .none:
                letter.frame(width: 38, height: 40).background(key, in: .rect(cornerRadius: 7))
            case .detached:
                VStack(spacing: 5) {
                    letter.font(.title3).frame(width: 52, height: 42).background(bubble, in: .rect(cornerRadius: 9))
                    letter.frame(width: 38, height: 40).background(key, in: .rect(cornerRadius: 7))
                }
            case .attached:
                UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 7, bottomTrailingRadius: 7, topTrailingRadius: 9)
                    .fill(bubble)
                    .frame(width: 52, height: 88)
                    .mask {
                        VStack(spacing: 0) {
                            Rectangle().frame(width: 52, height: 48)
                            Rectangle().frame(width: 38, height: 40)
                        }
                    }
                    .overlay(alignment: .top) { letter.font(.title3).padding(.top, 10) }
            }
        }
        .frame(height: 90, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var letter: some View { Text("q").foregroundStyle(.primary) }
}

/// Levels as stops on one track, Standard in the middle, named at its ends.
struct StopSlider<Level: Hashable>: View {
    let title: String
    let label: String
    @Binding var level: Level
    let levels: [Level]
    let name: (Level) -> String
    let ends: (low: String, high: String)
    var picked: (Level) -> Void = { _ in }
    private let thumb: CGFloat = 28

    private var index: Int { levels.firstIndex(of: level) ?? levels.count / 2 }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(name(level)).foregroundStyle(Color.appSecondary)
            }
            GeometryReader { geometry in
                let step = (geometry.size.width - thumb) / CGFloat(levels.count - 1)
                let x = thumb / 2 + CGFloat(index) * step
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appDivider).frame(height: 4)
                    Capsule().fill(Color.blue).frame(width: x, height: 4)
                    ForEach(levels.indices, id: \.self) { stop in
                        Circle()
                            .fill(stop <= index ? Color.blue : Color.appSecondary.opacity(0.45))
                            .frame(width: 8, height: 8)
                            .position(x: thumb / 2 + CGFloat(stop) * step, y: thumb / 2)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .frame(width: thumb, height: thumb)
                        .position(x: x, y: thumb / 2)
                }
                .frame(height: thumb)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    pick(Int(((drag.location.x - thumb / 2) / step).rounded()))
                })
                .animation(.snappy(duration: 0.18), value: index)
            }
            .frame(height: thumb)
            HStack {
                Text(ends.low)
                Spacer()
                Text(ends.high)
            }
            .overlay { Text("Standard") }
            .font(.footnote)
            .foregroundStyle(Color.appSecondary)
        }
        .row()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(name(level))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: pick(index + 1)
            case .decrement: pick(index - 1)
            @unknown default: break
            }
        }
    }

    private func pick(_ stop: Int) {
        let next = levels[min(max(stop, 0), levels.count - 1)]
        guard next != level else { return }
        level = next
        picked(next)
    }
}

/// The key haptics' strengths, each stop tapping at its strength as it's picked, so the levels can be felt apart.
struct HapticSlider: View {
    @Binding var level: HapticFeedback
    @State private var haptics = KeyHaptics()

    var body: some View {
        StopSlider(title: "Strength", label: "Haptic Strength", level: $level, levels: HapticFeedback.levels, name: \.title, ends: ("Lighter", "Stronger")) { picked in
            haptics.strength = Float(picked.strength)
            haptics.play(.input)
        }
    }
}

/// A row whose value opens a menu of the others, as Raycast's pop-up rows do.
struct MenuRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let label: (Value) -> String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.self) { Text(label($0)).tag($0) }
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(label(selection)).foregroundStyle(Color.appSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
            }
            .row()
        }
        .buttonStyle(.plain)
    }
}

struct FeedbackSettings: View {
    private let model = SettingsModel.shared
    private let status = AppStatus.shared
    @AppStorage("hapticsBeforeOff") private var lastLevel = HapticFeedback.standard

    private var hapticsOn: Binding<Bool> {
        Binding { model.settings.haptics != .off } set: { on in
            if !on { lastLevel = model.settings.haptics }
            withAnimation(.snappy) { model.update { $0.haptics = on ? lastLevel : .off } }
        }
    }

    var body: some View {
        Box(header: "Haptics", footer: status.fullAccess ? "Standard is Apple’s keyboard’s own tap. Each step taps as you pick it." : "Haptics need Allow Full Access.") {
            ToggleRow(title: "Key Haptics", isOn: hapticsOn)
            if model.settings.haptics != .off {
                HapticSlider(level: model.binding(\.haptics))
            }
            if !status.fullAccess {
                ActionRow(title: "Allow Full Access", symbol: "arrow.up.forward") { AppStatus.openSettings() }
            }
        }
        Box {
            ToggleRow(title: "Sound", detail: "The key click, while Keyboard Clicks is on in iOS Settings › Sounds & Haptics.", isOn: model.binding(\.sound))
        }
    }
}
