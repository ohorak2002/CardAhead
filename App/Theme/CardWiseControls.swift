import SwiftUI

/// The controls CardWise draws itself, because the system's own are the
/// loudest thing announcing that nobody designed this.
///
/// **`.borderedProminent` was in eight places.** It is a perfectly good button
/// and it is also the button every SwiftUI tutorial produces — tinted capsule,
/// system corner radius, no sense of weight. An app asking somebody to trust
/// it with a financial decision cannot have its primary action look like the
/// default.
///
/// What is here is deliberately small. A primary button, a quieter secondary,
/// a search field and a chip — the four controls that actually repeat across
/// this app. Everything else stays system, because a bespoke version of a
/// control iOS already does well is just drift waiting to happen.

// MARK: - Buttons

/// The one action a screen most wants you to take. Navy-to-blue, the same
/// gradient as the header, so the affirmative button and the app's own
/// identity are the same colour.
///
/// Full width by default: a primary action at the bottom of a screen is a
/// destination, not a word in a sentence.
struct CardWisePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metric.regular)
            .padding(.horizontal, Metric.roomy)
            .background {
                RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
                    .fill(.cardWiseHeader)
                    // Dimmed rather than greyed. A disabled button that turns
                    // grey looks broken; one that recedes looks unavailable.
                    .opacity(isEnabled ? 1 : 0.4)
            }
            // A press is a physical event, so it moves. Small — 2% — because
            // a button that leaps under a thumb reads as a toy.
            .scaleEffect(pressScale(configuration.isPressed))
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private func pressScale(_ pressed: Bool) -> CGFloat {
        guard pressed, !reduceMotion else { return 1 }
        return 0.98
    }
}

/// The other thing you might do. Reads as a button without competing with the
/// primary one — a tinted ground rather than a filled one, and the brand blue
/// for the text instead of white.
struct CardWiseSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.cardWiseActionInk : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metric.regular)
            .padding(.horizontal, Metric.roomy)
            .background {
                RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
                    .fill(Color.cardWiseBlue.opacity(isEnabled ? 0.10 : 0.05))
            }
            .scaleEffect(pressScale(configuration.isPressed))
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private func pressScale(_ pressed: Bool) -> CGFloat {
        guard pressed, !reduceMotion else { return 1 }
        return 0.98
    }
}

extension ButtonStyle where Self == CardWisePrimaryButtonStyle {
    /// `Button("Add to Wallet") { }.buttonStyle(.cardWisePrimary)`
    static var cardWisePrimary: CardWisePrimaryButtonStyle { CardWisePrimaryButtonStyle() }
}

extension ButtonStyle where Self == CardWiseSecondaryButtonStyle {
    static var cardWiseSecondary: CardWiseSecondaryButtonStyle { CardWiseSecondaryButtonStyle() }
}

// MARK: - Search

/// One search field, used by every screen that searches.
///
/// The map had its own, assembled inline, and Add Card used a plain `List`
/// with `.searchable` — two different search experiences in one app for no
/// reason anybody chose.
///
/// **The fill is `secondarySystemGroupedBackground` and that is load-bearing.**
/// `.background.secondary` is visible at night and resolves to very nearly the
/// page's own grey in daylight, which is how the map's field came to be
/// invisible in light mode. The grouped-secondary role is the one that means
/// "a control sitting on a grouped page".
struct CardWiseSearchField: View {
    let placeholder: String
    @Binding var text: String
    /// Called on the keyboard's Search key. Screens that filter as you type
    /// can leave it nil.
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)? = nil
    @FocusState private var focused: Bool
    /// What is behind it. See `ControlGround` — a field floating over a map
    /// needs a different answer from one sitting on a page.
    var ground: ControlGround = .page

    var body: some View {
        HStack(spacing: Metric.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .accessibilityLabel(placeholder)
                .frame(minHeight: Metric.minimumTarget)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .onSubmit { focused = false; onSubmit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .frame(width: Metric.minimumTarget, height: Metric.minimumTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Metric.snug)
        .padding(.vertical, 2)
        .background(
            ground.fill,
            in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
        )
        .shadow(color: Color.cardWiseNavy.opacity(ground.shadowOpacity), radius: 14, y: 5)
        .animation(.snappy(duration: 0.2), value: text.isEmpty)
    }
}

// MARK: - What a control is sitting on

/// The two grounds a floating control can have in this app, and the only two.
///
/// **A control drawn for one and placed on the other disappears**, which this
/// repo has now proved twice: `.background.secondary` vanished against the
/// light grouped page, and a control filled with the grouped-page colour
/// placed over the map reads as a solid card punched into the middle of it.
/// Rather than a third hex value, a control says where it is standing and the
/// answer comes from here.
enum ControlGround {
    /// Sitting on a grouped page, the ordinary case.
    case page
    /// Floating over a map or a photograph. Translucent, so the thing
    /// underneath stays visible — which is the whole reason the control is
    /// floating rather than in a bar — and lifted, because it genuinely is.
    case floating
    /// Blue wash used by the redesigned bank picker and map header.
    case tinted

    var fill: AnyShapeStyle {
        switch self {
        case .page: return AnyShapeStyle(Color(.secondarySystemGroupedBackground))
        case .floating: return AnyShapeStyle(.regularMaterial)
        case .tinted: return AnyShapeStyle(InterfacePalette.wash)
        }
    }

    /// A shadow means "above the page". Only one of these is.
    var shadowOpacity: Double {
        switch self {
        case .page: return 0
        case .floating: return 0.18
        case .tinted: return 0
        }
    }
}

// MARK: - Chips

/// A one-tap filter. Promoted out of `NearbyMapView`, which is the only place
/// it existed even though the benefits and wallet screens want the same thing.
///
/// **On is a solid fill with white on it; off is a panel with primary text.**
/// Not an outline — an outlined "on" state and a filled "off" state read the
/// same from a foot away, and this row is scanned rather than read.
struct CardWiseChip: View {
    let title: String
    /// Only some chips carry one. A row where every chip has a symbol reads as
    /// a toolbar; one symbol among plain chips reads as the odd one out, which
    /// is usually exactly the point.
    var symbolName: String?
    let isOn: Bool
    /// The colour of the *on* state. Defaults to the brand blue; a category
    /// chip passes its own so the filter and the pin agree.
    var tint: Color = .cardWiseBlue
    /// What the *off* state sits on. Over the map this has to be translucent
    /// or the chip row becomes a solid white band across the top of it.
    var ground: ControlGround = .page
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            // Explicit `Color` on both branches. `.primary` resolves against
            // `ShapeStyle` and `Color.white` does not, and a ternary between
            // them fails to build — a trap this repo has hit twice.
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.horizontal, Metric.snug)
            .padding(.vertical, 7)
            .background(isOn ? AnyShapeStyle(tint) : ground.fill, in: Capsule())
            .shadow(color: Color.cardWiseNavy.opacity(ground.shadowOpacity), radius: 8, y: 3)
            .frame(minHeight: Metric.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Badges

/// A small status word. Three tones, and the tone is never the only signal —
/// each carries its own wording, so somebody who cannot tell the green from
/// the amber still reads "Active" and "Ends soon".
struct CardWiseBadge: View {
    enum Tone {
        case neutral, positive, attention

        var tint: Color {
            switch self {
            case .neutral: return .cardWiseBlue
            case .positive: return .cardWiseSuccess
            case .attention: return .cardWiseWarning
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.tint)
            .padding(.horizontal, Metric.tight)
            .padding(.vertical, 4)
            .background(
                tone.tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: Metric.pillRadius, style: .continuous)
            )
    }
}

// MARK: - Empty states

/// What a screen says when it has nothing to say.
///
/// **An invitation, not an apology.** No sad icon, no "you have no items".
/// Every empty state in this app names the thing that is missing, says what
/// will happen once it is not, and — where there is one — carries the way out
/// as a button rather than telling somebody to go and find it.
struct CardWiseEmptyState<Action: View>: View {
    let symbolName: String
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: Metric.regular) {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.cardWiseBlue)
                .accessibilityHidden(true)

            VStack(spacing: Metric.tight) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)

            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metric.loose)
        .padding(.horizontal, Metric.roomy)
    }
}

extension CardWiseEmptyState where Action == EmptyView {
    init(symbolName: String, title: String, message: String) {
        self.init(symbolName: symbolName, title: title, message: message) { EmptyView() }
    }
}
