import SwiftUI

/// A label whose characters roll to their new ones, after Daniel White's slot-text: each character that changes rolls
/// up and out as its new one rolls up into place, with a slight overshoot and tilt, left to right a beat apart, each
/// a little off in time so they don't move as one, blurred as they move and faded rather than cut at the line's edges.
/// A character keeps its place counted from the end, so a count that goes up rolls only the digits that changed. It
/// shrinks to fit, as a `Text` with `minimumScaleFactor` does.
struct SlotText: View {
    let text: String
    var shrink: CGFloat = 0.6
    @State private var previous: String
    @State private var fitted: CGFloat = 0
    @State private var natural: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String, shrink: CGFloat = 0.6) {
        self.text = text
        self.shrink = shrink
        _previous = State(initialValue: text)
    }

    var body: some View {
        if reduceMotion {
            Text(text).lineLimit(1).minimumScaleFactor(shrink)
        } else {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(shrink)
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fitted = $0 }
                .overlay(alignment: .leading) {
                    slots
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { natural = $0 }
                        .scaleEffect(natural > fitted ? fitted / natural : 1, anchor: .leading)
                }
                .onChange(of: text) { previous = text }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        }
    }

    private var slots: some View {
        let characters = Array(text), before = Array(previous)
        let changed = characters.indices.first { index in
            let place = characters.count - index
            return place > before.count || before[before.count - place] != characters[index]
        } ?? 0
        return HStack(spacing: 0) {
            ForEach(characters.indices.map { characters.count - $0 }, id: \.self) { place in
                let index = characters.count - place
                Slot(character: characters[index], order: max(0, index - changed), place: place)
                    .transition(Roll(tilt: 0))
            }
        }
        .animation(Slot.curve(duration: Slot.duration), value: characters.count)
    }
}

/// One character's place: its character rolls out as the next rolls in.
private struct Slot: View {
    let character: Character
    let order: Int
    let place: Int

    static let duration = 0.3

    static func curve(duration: Double) -> Animation {
        .timingCurve(0.34, 1.56, 0.64, 1, duration: duration)
    }

    var body: some View {
        ZStack {
            Text(String(character))
                .id(character)
                .transition(Roll(tilt: 3 * jitter(3)))
        }
        .animation(
            Self.curve(duration: Self.duration * (1 + 0.27 * jitter(1))).delay(0.045 * Double(order) * (1 + 0.15 * jitter(2))),
            value: character
        )
    }

    /// slot-text's steady randomness, -1 to 1, the same for a place and character each time.
    private func jitter(_ channel: Double) -> Double {
        let seed = sin(Double(place) * 12.9898 + Double(character.unicodeScalars.first?.value ?? 0) * 0.1 + channel * 78.233) * 43758.5453
        return (seed - seed.rounded(.down)) * 2 - 1
    }
}

/// In from below and out the top, three quarters of its line's height, tilting and blurred as it goes.
private struct Roll: Transition {
    let tilt: Double

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(Rolling(progress: phase.value, tilt: tilt))
    }
}

/// A character `progress` of the way out of its slot (-1 below, 0 in place, 1 above), faded at its line's top and
/// bottom while it moves, so it never leaves the line, and whole at rest, its descender too.
private struct Rolling: ViewModifier, Animatable {
    var progress: Double
    let tilt: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let progress = progress, edge = Color.black.opacity(1 - min(1, abs(progress) * 4))
        content
            .rotationEffect(.degrees(-progress * tilt))
            .blur(radius: abs(progress) * 3)
            .opacity(1 - max(0, abs(progress) - 0.6) / 0.4)
            .visualEffect { content, proxy in
                content.offset(y: -progress * proxy.size.height * 0.75)
            }
            .mask {
                LinearGradient(stops: [.init(color: edge, location: 0), .init(color: .black, location: 0.3), .init(color: .black, location: 0.75), .init(color: edge, location: 1)], startPoint: .top, endPoint: .bottom)
                    .padding(.horizontal, -8)
            }
    }
}
