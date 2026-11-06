import PhotosUI
import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var navigationPath = NavigationPath()
    @State private var deleteProjectConfirmID: UUID?
    @State private var editMode: EditMode = .inactive

    private var isReordering: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if store.summaries.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("Pantsize")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Link(destination: URL(string: "https://kondows95.github.io/pantsize/")!) {
                            Label("サポート", systemImage: "questionmark.circle")
                        }
                        Link(destination: URL(string: "https://kondows95.github.io/pantsize/privacy.html")!) {
                            Label("プライバシーポリシー", systemImage: "hand.raised")
                        }
                    } label: {
                        Label("ヘルプ", systemImage: "questionmark.circle")
                    }
                }
                if !store.summaries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isReordering ? "完了" : "並び替え") {
                            withAnimation {
                                editMode = isReordering ? .inactive : .active
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("追加", systemImage: "plus")
                    }
                    .disabled(isReordering)
                }
            }
            .navigationDestination(for: UUID.self) { projectID in
                MeasurementEditorView(projectID: projectID)
                    .id(projectID)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await createProject(from: item) }
            }
            .alert("この項目を削除しますか？", isPresented: deleteProjectConfirmBinding) {
                Button("削除", role: .destructive) {
                    if let id = deleteProjectConfirmID {
                        try? store.deleteProject(id: id)
                    }
                    deleteProjectConfirmID = nil
                }
                Button("キャンセル", role: .cancel) {
                    deleteProjectConfirmID = nil
                }
            } message: {
                Text("画像と計測データが端末から削除されます。")
            }
        }
    }

    private var deleteProjectConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteProjectConfirmID != nil },
            set: { if !$0 { deleteProjectConfirmID = nil } }
        )
    }

    private var projectList: some View {
        List {
            ForEach(store.summaries) { summary in
                HStack(spacing: 12) {
                    if isReordering {
                        projectRow(summary: summary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        NavigationLink(value: summary.id) {
                            projectRow(summary: summary)
                        }

                        Button(role: .destructive) {
                            deleteProjectConfirmID = summary.id
                        } label: {
                            Image(systemName: "trash")
                                .font(.body)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("削除")
                    }
                }
            }
            .onMove { source, destination in
                store.moveSummaries(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
    }

    @ViewBuilder
    private func projectRow(summary: MeasurementProjectSummary) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: summary.id)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(summary.completeMeasurementCount)/\(summary.measurementCount) 件の計測")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(for projectID: UUID) -> some View {
        if let image = store.loadImage(id: projectID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color(.secondarySystemFill)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("保存された計測がありません", systemImage: "ruler")
        } description: {
            Text("右上の「＋」から商品画像を選ぶと、計測付きで保存できます。")
        } actions: {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("画像を追加")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func createProject(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run {
            selectedPhotoItem = nil
            guard let projectID = try? store.createProject(from: image) else { return }
            navigationPath = NavigationPath([projectID])
        }
    }
}

#Preview {
    ProjectListView()
        .environment(ProjectStore())
}
