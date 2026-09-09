import SwiftUI

/// The first screen of a fresh install, and the whole of onboarding.
///
/// The wallet ships empty on purpose. There is no starter set and nothing to
/// import, so this screen carries the entire job of explaining what the app
/// wants and why it is safe to give it — the two questions a finance app is
/// asked at install time.
///
/// An invitation, not an apology. No "you have no cards" and no sad icon.
struct EmptyStateView: View {
    var onAddCard: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Text("Add the cards you carry")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("One at a time: what it is, what it looks like, and what it earns.")
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
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
