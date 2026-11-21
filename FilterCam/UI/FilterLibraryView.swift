import SwiftUI

struct FilterLibraryView: View {
    @ObservedObject var store: FilterStore
    let thumbnails: [String: UIImage]
    let selectedID: String
    let onSelect: (FilterPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: FilterCategory = .simulation

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                categoryChips
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(PresetCatalog.presets(in: category)) { preset in
                            cell(for: preset)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("滤镜库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.control)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(category == item ? Color.black : Theme.control)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                category == item ? Color.white : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func cell(for preset: FilterPreset) -> some View {
        Button {
            onSelect(preset)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Color.white.opacity(0.10))
                    if let image = thumbnails[preset.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(
                            selectedID == preset.id ? Color.white : Color.white.opacity(0.12),
                            lineWidth: 2
                        )
                    if store.isFavorite(preset.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                Text(preset.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selectedID == preset.id ? Theme.control : Theme.controlDim)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            store.toggleFavorite(preset.id)
            Haptics.selection()
        }
    }
}
