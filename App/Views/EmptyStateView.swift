import SwiftUI

/// An invitation, not an apology. No "you have no cards" and no sad icon.
struct EmptyStateView: View {
    var onAddCard: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Text("Add the cards you carry")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Once they are here, you get a nudge before you pay telling you which one earns the most.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(action: onAddCard) {
                Text("Add a card")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView {}
}
