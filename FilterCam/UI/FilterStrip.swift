import SwiftUI

struct FilterStrip: View {
    let presets: [FilterPreset]
    let thumbnails: [String: UIImage]
    let selectedID: String
    let onSelect: (FilterPreset) -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(spacing: 6) {
                            thumbnail(for: preset)
                            Text(preset.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    selectedID == preset.id ? Theme.control : Theme.controlDim
                                )
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOpenLibrary) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.14))
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.control)
                        }
                        .frame(width: 54, height: 54)
                        Text("全部")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.controlDim)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    private func thumbnail(for preset: FilterPreset) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let image = thumbnails[preset.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            Circle()
                .stroke(
                    selectedID == preset.id ? Color.white : Color.white.opacity(0.15),
                    lineWidth: 2
                )
        }
        .frame(width: 54, height: 54)
        .clipShape(Circle())
    }
}
