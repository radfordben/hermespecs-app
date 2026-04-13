/*
 * Quick Vision Settings View
 * 快速识图设置 - 模式选择、自定义提示词、历史记录
 */

import SwiftUI

struct QuickVisionSettingsView: View {
    @ObservedObject var modeManager = QuickVisionModeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showHistory = false

    var body: some View {
        NavigationView {
            List {
                // 识图模式选择
                Section {
                    ForEach(QuickVisionMode.allCases) { mode in
                        Button {
                            modeManager.setMode(mode)
                        } label: {
                            HStack {
                                Image(systemName: mode.icon)
                                    .foregroundColor(modeColor(mode))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.displayName)
                                        .foregroundColor(.primary)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if modeManager.currentMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("quickvision.settings.mode".localized)
                }

                // 翻译目标语言（仅在翻译模式显示）
                if modeManager.currentMode == .translate {
                    Section {
                        ForEach(QuickVisionModeManager.supportedLanguages, id: \.code) { language in
                            Button {
                                modeManager.setTranslateTargetLanguage(language.code)
                            } label: {
                                HStack {
                                    Text(language.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if modeManager.translateTargetLanguage == language.code {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("quickvision.settings.targetlanguage".localized)
                    }
                }

                // 自定义提示词（仅在自定义模式显示）
                if modeManager.currentMode == .custom {
                    Section {
                        TextEditor(text: $modeManager.customPrompt)
                            .frame(minHeight: 150)
                            .font(.body)
                    } header: {
                        Text("quickvision.settings.customprompt".localized)
                    }
                }

                // 识图历史
                Section {
                    Button {
                        showHistory = true
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                            Text("quickvision.settings.history".localized)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(QuickVisionStorage.shared.recordCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("quickvision.settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                QuickVisionHistoryView()
            }
        }
    }

    private func modeColor(_ mode: QuickVisionMode) -> Color {
        switch mode {
        case .standard:
            return .blue
        case .health:
            return .red
        case .blind:
            return .purple
        case .reading:
            return .green
        case .translate:
            return .orange
        case .encyclopedia:
            return .brown
        case .custom:
            return .gray
        }
    }
}

// MARK: - Quick Vision History View

struct QuickVisionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [QuickVisionRecord] = []
    @State private var showClearConfirm = false
    @State private var selectedRecord: QuickVisionRecord?

    var body: some View {
        NavigationView {
            Group {
                if records.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("quickvision.history.empty".localized)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(records) { record in
                            Button {
                                selectedRecord = record
                            } label: {
                                QuickVisionRecordRow(record: record)
                            }
                        }
                        .onDelete(perform: deleteRecords)
                    }
                }
            }
            .navigationTitle("quickvision.history".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !records.isEmpty {
                        Button {
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized) {
                        dismiss()
                    }
                }
            }
            .alert("quickvision.history.clear".localized, isPresented: $showClearConfirm) {
                Button("cancel".localized, role: .cancel) {}
                Button("delete".localized, role: .destructive) {
                    clearAllRecords()
                }
            } message: {
                Text("quickvision.history.clear.confirm".localized)
            }
            .sheet(item: $selectedRecord) { record in
                QuickVisionRecordDetailView(record: record)
            }
            .onAppear {
                loadRecords()
            }
        }
    }

    private func loadRecords() {
        records = QuickVisionStorage.shared.loadAllRecords()
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            QuickVisionStorage.shared.deleteRecord(record.id)
        }
        records.remove(atOffsets: offsets)
    }

    private func clearAllRecords() {
        QuickVisionStorage.shared.deleteAllRecords()
        records = []
    }
}

// MARK: - Record Row

struct QuickVisionRecordRow: View {
    let record: QuickVisionRecord

    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            if let thumbnail = record.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: record.mode.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(record.mode.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(record.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(record.summary)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Record Detail View

struct QuickVisionRecordDetailView: View {
    let record: QuickVisionRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 缩略图
                    if let thumbnail = record.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                    }

                    // 模式和时间
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: record.mode.icon)
                            Text(record.mode.displayName)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                        Spacer()

                        Text(record.formattedDate)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // 识图结果
                    VStack(alignment: .leading, spacing: 8) {
                        Text("quickvision.result".localized)
                            .font(.headline)

                        Text(record.result)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("quickvision.result".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
}
