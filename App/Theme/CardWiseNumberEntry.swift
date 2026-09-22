import SwiftUI
import UIKit

/// Typing a number into this app, and getting back out again.
///
/// **The decimal pad has no return key.** Every amount, rate and fee in
/// CardWise is `.keyboardType(.decimalPad)`, which iOS draws as ten digits, a
/// separator and a backspace — and nothing else. On a screen where the field
/// is the last thing above the fold, the keyboard covers whatever would have
/// dismissed it and the only way out is a lucky tap on the page behind. That
/// is a real dead end, found on a real phone, not a nicety.
///
/// So two things live here. A keyboard toolbar with one button in it, applied
/// once per screen that takes typed input; and a field that knows a zero it
/// was given is a placeholder rather than a number somebody typed.

// MARK: - Getting the keyboard off the screen

enum KeyboardDismiss {
    /// Resigns whatever is first responder. Deliberately not tied to a
    /// `FocusState`: the toolbar is attached to a screen, and a screen can
    /// hold six fields that each own their own focus.
    @MainActor
    static func now() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct KeyboardDoneToolbar: ViewModifier {
    let title: String
    /// Screens where the button means something more than "stop typing" pass
    /// their own action — see `PurchaseAmountView`, where Done is the same
    /// Done as the one in the navigation bar. Two buttons with one word and
    /// two meanings is worse than no button.
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(title) {
                    if let action {
                        action()
                    } else {
                        KeyboardDismiss.now()
                    }
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}

extension View {
    /// One Done button above the keyboard, for the whole screen.
    ///
    /// Attach it **once**, to the `Form` or `ScrollView` that holds the
    /// fields, not to each field: SwiftUI merges keyboard toolbars from the
    /// active hierarchy, and a screen that applies it six times draws six
    /// Done buttons.
    func keyboardDoneButton(_ title: String = "Done", action: (() -> Void)? = nil) -> some View {
        modifier(KeyboardDoneToolbar(title: title, action: action))
    }
}

// MARK: - Reading a number back out of a string

/// Parsing and printing, in one place, so a field and the value behind it
/// always agree about what "12.5" means.
enum NumberEntry {
    /// A decimal pad on a comma-separator locale types a comma, and both
    /// `Double` and `Decimal` only parse a point.
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
    }

    static func double(from raw: String) -> Double? {
        let text = normalized(raw)
        guard !text.isEmpty else { return nil }
        return Double(text)
    }

    static func decimal(from raw: String) -> Decimal? {
        let text = normalized(raw)
        guard !text.isEmpty else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Plain digits, never grouped. `500` and not `500.0`, and `1500` rather
    /// than `1,500` — a separator the formatter adds is a separator the field
    /// cannot parse back when the user taps in to edit it.
    static func text(from value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    static func text(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - The field

private struct FixedWidth: ViewModifier {
    let width: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width)
        } else {
            content
        }
    }
}

/// A number field that empties itself when what it is showing is a zero
/// nobody typed.
///
/// **`TextField(value:format:)` cannot do this.** Bound to a `Double` that
/// starts at 0, it renders "0", puts the caret after it, and the next thing
/// typed makes "05". Every fee, cap and amount in the app starts at zero, so
/// every one of them did this. The fix is not a formatter — it is knowing the
/// difference between a zero that is the current value and a zero that is the
/// prompt, which only the focus state can tell you.
///
/// A non-zero value is left alone on focus, caret at the end, because 500 is
/// something the user put there and clearing it on a stray tap loses it.
struct NumberField<Value: Equatable>: View {
    private let placeholder: String
    @Binding private var value: Value
    private let zero: Value
    private let parse: (String) -> Value?
    private let render: (Value) -> String
    private let width: CGFloat?
    private let alignment: TextAlignment
    private let label: String?

    /// The text actually on screen. It leads the bound value while typing —
    /// "3." is not a number yet and must survive until the second digit.
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    fileprivate init(
        placeholder: String,
        value: Binding<Value>,
        zero: Value,
        width: CGFloat?,
        alignment: TextAlignment,
        label: String?,
        parse: @escaping (String) -> Value?,
        render: @escaping (Value) -> String
    ) {
        self.placeholder = placeholder
        self._value = value
        self.zero = zero
        self.width = width
        self.alignment = alignment
        self.label = label
        self.parse = parse
        self.render = render
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .modifier(FixedWidth(width: width))
            .accessibilityLabel(label ?? placeholder)
            .onAppear {
                // Once. A redraw must not overwrite a half-typed number.
                guard !loaded else { return }
                loaded = true
                text = render(value)
            }
            .onChange(of: value) { _, new in
                // The screens here load their card after the field appears,
                // so the value arrives late. While typing, the field is the
                // source of truth and this must not fight it.
                guard !focused else { return }
                let rendered = render(new)
                if rendered != text { text = rendered }
            }
            .onChange(of: text) { _, new in
                if let parsed = parse(new) {
                    value = parsed
                } else if NumberEntry.normalized(new).isEmpty {
                    value = zero
                }
                // Anything else — "3.4.5" — leaves the value where it was and
                // is tidied up when the field loses focus.
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    if value == zero { text = "" }
                } else {
                    text = render(value)
                }
            }
    }
}

extension NumberField where Value == Double {
    init(
        _ placeholder: String,
        value: Binding<Double>,
        width: CGFloat? = nil,
        alignment: TextAlignment = .leading,
        label: String? = nil
    ) {
        self.init(
            placeholder: placeholder,
            value: value,
            zero: 0,
            width: width,
            alignment: alignment,
            label: label,
            parse: { (raw: String) -> Double? in NumberEntry.double(from: raw) },
            render: { (value: Double) -> String in NumberEntry.text(from: value) }
        )
    }
}

extension NumberField where Value == Decimal {
    init(
        _ placeholder: String,
        value: Binding<Decimal>,
        width: CGFloat? = nil,
        alignment: TextAlignment = .leading,
        label: String? = nil
    ) {
        self.init(
            placeholder: placeholder,
            value: value,
            zero: 0,
            width: width,
            alignment: alignment,
            label: label,
            parse: { (raw: String) -> Decimal? in NumberEntry.decimal(from: raw) },
            render: { (value: Decimal) -> String in NumberEntry.text(from: value) }
        )
    }
}
