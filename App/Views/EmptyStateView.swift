import SwiftUI

/// The first screen of a fresh install, and the whole of onboarding.
///
/// The wallet ships empty on purpose. There is no starter set and nothing to
/// import, so this screen carries the entire job of explaining what the app
/// wants and why it is safe to give it — the two questions a finance app is
/// asked at install time.
///
/// An invitation, not an apology. No "you have no cards" and no sad icon.
///
/// The promise in the second line is the product: nobody should have to type
/// out their own card's earn rates. Adding one is picking it off a list.
struct EmptyStateView: View {
    var onAddCard: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Text("Add the cards you carry")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Say which card it is. We already know what it earns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            // The trust question comes before the effort question. Someone who
            // just installed a card app is deciding whether to trust it at all.
            Label("No card numbers and no bank login, ever.", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onAddCard) {
                Text("Add your first card")
            }
            .buttonStyle(.cardAheadPrimary)
            .frame(maxWidth: 320)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView {}
}
