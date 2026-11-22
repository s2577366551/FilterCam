import SwiftUI
import UIKit

struct FilterStrip: View {
    let presets: [FilterPreset]
    let thumbnails: [String: UIImage]
    let selectedID: String
    let onSelect: (FilterPreset) -> Void
    let onOpenLibrary: () -> Void

    private let itemSize: CGFloat = 50
    private let labelWidth: CGFloat = 58

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presets) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(spacing: 5) {
                                thumbnail(for: preset)
                                Text(preset.stripName)
                                    .font(.system(
                                        size: 10,
                                        weight: selectedID == preset.id ? .semibold : .regular
                                    ))
                                    .foregroundStyle(
                                        selectedID == preset.id ? Theme.control : Theme.controlDim
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: labelWidth)
                            }
                            .opacity(selectedID == preset.id ? 1 : 0.78)
                        }
                        .buttonStyle(.plain)
                        .id(preset.id)
                    }

                    Button(action: onOpenLibrary) {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.14))
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Theme.control)
                            }
                            .frame(width: itemSize, height: itemSize)
                            Text("全部")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.controlDim)
                                .frame(width: labelWidth)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(selectedID, anchor: .center)
            }
            .onChange(of: selectedID) { _, newValue in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func thumbnail(for preset: FilterPreset) -> some View {
        let isSelected = selectedID == preset.id
        return ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let image = thumbnails[preset.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            Circle()
                .strokeBorder(
                    isSelected ? Color.white : Color.white.opacity(0.14),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .frame(width: itemSize, height: itemSize)
        .clipShape(Circle())
    }
}
