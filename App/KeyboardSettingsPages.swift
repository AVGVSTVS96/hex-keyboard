import KeyboardCore
import KeyboardUI
import SwiftUI

/// Hex drawn as these settings make it, at the width it's offered.
struct KeyboardPreview: UIViewRepresentable {
    let settings: KeyboardSettings

    func makeUIView(context: Context) -> KeyboardPreviewView {
        let view = KeyboardPreviewView()
        view.layer.cornerRadius = 26
        view.layer.borderWidth = 1
        return view
    }

    func updateUIView(_ view: KeyboardPreviewView, context: Context) {
        view.show(settings, dark: context.environment.colorScheme == .dark)
        view.layer.borderColor = HexStyle.edge.resolvedColor(with: view.traitCollection).cgColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyboardPreviewView, context: Context) -> CGSize? {
        let width = min(proposal.width ?? 390, 520)
        return CGSize(width: width, height: KeyboardPreviewView.height(forWidth: width, settings: settings))
    }
}

/// Hex as it will look, over a pill that brings up the real keyboard in a field, so a change can be tried at once.
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
                    .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
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
                        .background(Color.hexCard, in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.hexEdge))
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
        min(520, window.height * 0.4 / (KeyboardPreviewView.height(forWidth: 100, settings: model.settings) / 100))
    }
}

/// What the settings pages read and write: the keyboard's switches through `SettingsStore`, so the keyboard and
/// Settings › Apps › Hex see the same values, and the sources Hex tells what you type.
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

    var oneHanded: OneHanded {
        get { settings.oneHanded }
        set { update { $0.oneHanded = newValue } }
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

struct ThemeSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(footer: "Automatic follows the app you’re typing in, light or dark.") {
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
        Box(footer: "Predictive Text shows three suggestions above the keys, and the next word before you type it.") {
            ToggleRow(title: "Auto-Capitalization", isOn: model.binding(\.autoCapitalization))
            ToggleRow(title: "Auto-Correction", isOn: model.binding(\.autoCorrection))
            ToggleRow(title: "Predictive Text", isOn: model.binding(\.predictiveText))
        }
        Box(footer: "Smart Punctuation curls quotes and turns two hyphens into a dash.") {
            ToggleRow(title: "Smart Punctuation", isOn: model.binding(\.smartPunctuation))
            ToggleRow(title: "Enable Caps Lock", detail: "Double-tap shift.", isOn: model.binding(\.capsLock))
            ToggleRow(title: "“.” Shortcut", detail: "Double-tap space for a period and a space.", isOn: model.binding(\.periodShortcut))
        }
        Box(header: "Text Replacements") {
            Button { HexStatus.openSettings() } label: {
                HStack {
                    RowText(title: "Open Settings", detail: "iikb types the ones in General › Keyboard › Text Replacement. This opens Settings › Apps › iikb.")
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.hexSecondary)
                }
                .row()
            }
            .buttonStyle(.plain)
        }
    }
}

struct LayoutSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(header: "Rows") {
            ToggleRow(title: "Number Row", detail: "1 to 0 above the letters. The keyboard grows upward.", isOn: model.binding(\.numberRow))
        }
        Box(header: "Emoji") {
            ToggleRow(title: "Emoji Key", detail: "Every emoji, from beside the space bar. Without it, a word’s emoji still show in the suggestions.", isOn: model.binding(\.emojiKey))
            MenuRow(title: "Skin Tone", selection: model.binding(\.skinTone), choices: [nil] + SkinTone.allCases.map(Optional.some)) { tone in
                "✋\(tone.map { String($0.modifier) } ?? "") \(tone?.title ?? "Default")"
            }
            ToggleRow(title: "Compact Emoji & GIFs", detail: "One row that scrolls sideways, as in landscape, so the keyboard stays short in portrait too.", isOn: model.binding(\.compactPanels))
        }
        Box(footer: "On the open iPhone Duo in landscape, half the keys sit under each thumb. You can also hold 123 and slide, or tap … above the keys.") {
            ToggleRow(title: "Split Keyboard", isOn: model.binding(\.split))
        }
        Box(header: "One-Handed Keyboard", footer: "Moves the keys toward one thumb on an iPhone in portrait, on the Duo only folded. You can also hold 123 and slide.") {
            ForEach(OneHanded.allCases, id: \.self) { hand in
                ChoiceRow(title: Self.title(of: hand), picked: model.oneHanded == hand) { model.oneHanded = hand }
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

/// A key and what pressing it shows above it, drawn small, as Raycast's picker draws them.
private struct PreviewDrawing: View {
    let preview: CharacterPreview

    var body: some View {
        let key = Color.hexSecondary.opacity(0.45), bubble = Color.hexSecondary.opacity(0.7)
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

/// The key haptics' strengths as stops on one track, Standard in the middle; each stop taps at its strength as it's
/// picked, so the levels can be felt apart.
struct HapticSlider: View {
    @Binding var level: HapticFeedback
    @State private var haptics = KeyHaptics()
    private let levels = HapticFeedback.levels
    private let thumb: CGFloat = 28

    private var index: Int { levels.firstIndex(of: level) ?? levels.count / 2 }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Strength").foregroundStyle(.primary)
                Spacer()
                Text(level.title).foregroundStyle(Color.hexSecondary)
            }
            GeometryReader { geometry in
                let step = (geometry.size.width - thumb) / CGFloat(levels.count - 1)
                let x = thumb / 2 + CGFloat(index) * step
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hexDivider).frame(height: 4)
                    Capsule().fill(Color.blue).frame(width: x, height: 4)
                    ForEach(levels.indices, id: \.self) { stop in
                        Circle()
                            .fill(stop <= index ? Color.blue : Color.hexSecondary.opacity(0.45))
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
                Text("Lighter")
                Spacer()
                Text("Stronger")
            }
            .overlay { Text("Standard") }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
        }
        .row()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Haptic Strength")
        .accessibilityValue(level.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: pick(index + 1)
            case .decrement: pick(index - 1)
            @unknown default: break
            }
        }
    }

    private func pick(_ stop: Int) {
        let picked = levels[min(max(stop, 0), levels.count - 1)]
        guard picked != level else { return }
        level = picked
        haptics.strength = Float(picked.strength)
        haptics.play(.input)
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
                Text(label(selection)).foregroundStyle(Color.hexSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.hexSecondary)
            }
            .row()
        }
        .buttonStyle(.plain)
    }
}

struct FeedbackSettings: View {
    private let model = SettingsModel.shared
    private let status = HexStatus.shared
    @AppStorage("hapticsBeforeOff") private var lastLevel = HapticFeedback.standard

    private var hapticsOn: Binding<Bool> {
        Binding { model.settings.haptics != .off } set: { on in
            if !on { lastLevel = model.settings.haptics }
            withAnimation(.snappy) { model.update { $0.haptics = on ? lastLevel : .off } }
        }
    }

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
        Box(header: "Touch and Sound", footer: status.fullAccess ? "Standard is Apple’s keyboard’s own tap. Each step taps as you pick it." : "Haptics need Allow Full Access.") {
            ToggleRow(title: "Key Haptics", isOn: hapticsOn)
            if model.settings.haptics != .off {
                HapticSlider(level: model.binding(\.haptics))
            }
            ToggleRow(title: "Sound", detail: "The key click, while Keyboard Clicks is on in iOS Settings › Sounds & Haptics.", isOn: model.binding(\.sound))
            if !status.fullAccess {
                ActionRow(title: "Allow Full Access", symbol: "arrow.up.forward") { HexStatus.openSettings() }
            }
        }
    }
}
