import SwiftUI

struct WatermarkSheet: View {
    @ObservedObject var store: WatermarkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("添加水印", isOn: $store.isEnabled)
                } footer: {
                    Text("水印会直接印在照片和视频的右下角，分享出去也带着。")
                }

                Section("内容") {
                    Picker("内容", selection: $store.content) {
                        ForEach(WatermarkContent.allCases) { content in
                            Text(content.displayName).tag(content)
                        }
                    }
                    .pickerStyle(.segmented)

                    if store.content == .custom {
                        TextField("输入文字，例如 Sx Cam", text: $store.customText)
                            .textInputAutocapitalization(.never)
                    }
                }

                Section {
                    HStack {
                        Text("效果")
                        Spacer()
                        Text(store.displayText.isEmpty ? "—" : store.displayText)
                            .font(.system(size: Theme.Font.body, weight: .semibold))
                            .foregroundStyle(Theme.control)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .navigationTitle("水印")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
