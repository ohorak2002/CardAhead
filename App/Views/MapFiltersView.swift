import SwiftUI
import CardKit

/// The map's filter sheet: what kinds of place, and how far out.
///
/// **It edits a draft and applies it on a button, rather than changing the map
/// live behind the sheet.** Every change of category or radius is a billed
/// lookup, and somebody working down a list of eight checkboxes would fire
/// eight of them. It also makes Cancel mean something.
struct MapFiltersView: View {

    @Binding var filter: MapFilter
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MapFilter

    init(filter: Binding<MapFilter>) {
        _filter = filter
        _draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Row(
                        symbolName: "square.grid.2x2.fill",
                        tint: .cardWiseBlue,
                        title: "All",
                        isOn: draft.isShowingEverything
                    ) {
                        draft.showEverything()
                    }
                    ForEach(MapCategory.allCases, id: \.self) { category in
                        Row(
                            symbolName: category.symbolName,
                            tint: tint(for: category),
                            title: category.displayName,
                            isOn: !draft.isShowingEverything && draft.categories.contains(category)
                        ) {
                            draft.toggle(category)
                        }
                    }
                } header: {
                    Text("Show me").textCase(nil)
                }

                Section {
                    ForEach(MapDistance.allCases, id: \.self) { distance in
                        Button {
                            draft.distance = distance
                        } label: {
                            HStack {
                                Text(distance.displayName)
                                    .foregroundStyle(Color.primary)
                                Spacer(minLength: Metric.tight)
                                if draft.distance == distance {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.cardWiseBlue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Distance").textCase(nil)
                } footer: {
                    Text("Ten miles is a lot of ground for twenty results. Narrow the distance and the map has room to show what is actually walkable.")
                }

                Section {
                    Picker("Order", selection: $draft.sort) {
                        ForEach(MapSort.allCases, id: \.self) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                } header: {
                    Text("Order the list by").textCase(nil)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    filter = draft
                    dismiss()
                } label: {
                    Text("Apply filters")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Metric.snug)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, Metric.margin)
                .padding(.vertical, Metric.snug)
                .background(.bar)
            }
        }
    }

    /// A glyph on a list row, not a pin, so it follows the interface style.
    /// See `BrandTint.solid` for the pin's different answer.
    private func tint(for category: MapCategory) -> Color {
        category.listTint
    }

    /// One tickable kind of place.
    private struct Row: View {
        let symbolName: String
        let tint: Color
        let title: String
        let isOn: Bool
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Metric.snug) {
                    CategoryIcon(symbolName: symbolName, tint: tint, size: 32)
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: Metric.tight)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.cardWiseBlue)
                    }
                }
            }
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
    }
}

#Preview {
    MapFiltersView(filter: .constant(.standard))
}
