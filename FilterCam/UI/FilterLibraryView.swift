import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilterLibraryView: View {
    @ObservedObject var store: FilterStore
    @ObservedObject var userLUTs: UserLUTLibrary
    let thumbnails: [String: UIImage]
    let selectedID: String
    let onSelect: (FilterPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: FilterCategory = .simulation
    @State private var isImporterPresented = false
    @State private var pendingURLs: [URL] = []
    @State private var isInputTypePromptVisible = false
    @State private var errorMessage: String?
    @State private var renamingLUT: UserLUT?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                categoryChips
                ScrollView {
                    if category == .mine && presets.isEmpty {
                        emptyMineView
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(presets) { preset in
                                cell(for: preset)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("滤镜库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .foregroundStyle(Theme.control)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.control)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [cubeType],
                allowsMultipleSelection: true
            ) { result in
                handleImportSelection(result)
            }
            .confirmationDialog(
                "这些 LUT 的输入类型？",
                isPresented: $isInputTypePromptVisible,
                titleVisibility: .visible
            ) {
                Button("F-Log2（富士官方 LUT）") { importAll(isFLog2: true) }
                Button("普通 sRGB / BT.709") { importAll(isFLog2: false) }
                Button("取消", role: .cancel) { pendingURLs = [] }
            } message: {
                Text("富士官方胶片模拟 LUT 请选 F-Log2；普通调色 LUT 选 sRGB。选错颜色会明显不对。")
            }
            .alert(
                "导入结果",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "重命名",
                isPresented: Binding(
                    get: { renamingLUT != nil },
                    set: { if !$0 { renamingLUT = nil } }
                )
            ) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) { renamingLUT = nil }
                Button("保存") {
                    if let lut = renamingLUT {
                        userLUTs.rename(lut.id, to: renameText)
                    }
                    renamingLUT = nil
                }
            }
        }
    }

    private var cubeType: UTType {
        UTType(filenameExtension: "cube") ?? .data
    }

    private var presets: [FilterPreset] {
        if category == .mine {
            return userLUTs.luts.map { .user($0) }
        }
        return PresetCatalog.presets(in: category)
    }

    private var emptyMineView: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(Theme.controlDim)
            Text("还没有导入 LUT")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.control)
            Text("点左上角「导入」选择 .cube 文件。\n富士官方 LUT 请选 F-Log2 输入。")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.controlDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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
                    if let lut = lut(for: preset) {
                        Text(lut.isFLog2 ? "F-Log2" : "sRGB")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
        .contextMenu {
            Button {
                store.toggleFavorite(preset.id)
                Haptics.selection()
            } label: {
                Label(
                    store.isFavorite(preset.id) ? "取消收藏" : "收藏",
                    systemImage: store.isFavorite(preset.id) ? "star.slash" : "star"
                )
            }
            if let lut = lut(for: preset) {
                Button {
                    renameText = lut.displayName
                    renamingLUT = lut
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    userLUTs.delete(lut.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func lut(for preset: FilterPreset) -> UserLUT? {
        guard let id = preset.userLUTID else { return nil }
        return userLUTs.luts.first { $0.id == id }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let cubes = urls.filter { $0.pathExtension.lowercased() == "cube" }
            guard !cubes.isEmpty else {
                errorMessage = "请选择 .cube 文件。"
                return
            }
            pendingURLs = cubes
            isInputTypePromptVisible = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importAll(isFLog2: Bool) {
        var failures: [String] = []
        for url in pendingURLs {
            do {
                _ = try userLUTs.importLUT(from: url, isFLog2: isFLog2)
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        pendingURLs = []
        category = .mine
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }
}
