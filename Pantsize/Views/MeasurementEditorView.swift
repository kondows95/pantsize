import SwiftUI
import UIKit

struct MeasurementEditorView: View {
    let projectID: UUID

    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var loadedImage: UIImage?
    @State private var projectTitle = ""

    @State private var measurements: [MeasurementItem] = []
    @State private var activeID: UUID?
    @State private var referenceID: UUID?
    @State private var referenceCmByID: [UUID: String] = [:]
    @State private var canvasSize: CGSize = .zero
    @State private var deleteMeasurementConfirmID: UUID?
    @FocusState private var isTitleFocused: Bool
    @State private var didLoad = false
    @State private var referenceCmAppendDecimalSignal = 0
    @State private var isReferenceCmFocused = false
    @State private var referenceFieldFocusToken = 0
    @State private var referenceFieldDismissSignal = 0

    var body: some View {
        Group {
            if let image = loadedImage {
                VStack(spacing: 0) {
                    referenceCmControlRow(placement: .aboveCanvas)
                        .layoutPriority(2)

                    ImageMeasurementCanvas(
                        image: image,
                        measurements: $measurements,
                        activeID: activeID,
                        referenceID: referenceID,
                        onUserInteraction: dismissKeyboard
                    )
                    .overlay(alignment: .top) {
                        editorToolbarOverlay
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: canvasMaxHeight)
                    .background(Color.black)
                    .layoutPriority(isReferenceCmFocused ? 0 : 1)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { newSize in
                        guard newSize.width > 1, newSize.height > 1 else { return }
                        if !isReferenceCmFocused {
                            canvasSize = newSize
                        }
                    }

                    measurementListPanel(image: image)
                        .layoutPriority(isReferenceCmFocused ? 2 : 1)
                }
            } else {
                ProgressView("読み込み中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("", text: $projectTitle, prompt: Text("タイトル").foregroundStyle(.secondary))
                    .focused($isTitleFocused)
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .submitLabel(.done)
                    .onSubmit {
                        dismissKeyboard()
                    }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if isReferenceCmFocused {
                    Button(".") {
                        referenceCmAppendDecimalSignal += 1
                    }
                }
                Spacer()
                Button("完了") {
                    dismissKeyboard()
                }
            }
        }
        .onAppear {
            loadProjectIfNeeded()
        }
        .onChange(of: projectID) { _, _ in
            resetEditorState()
            loadProjectIfNeeded()
        }
        .onDisappear {
            commitTitleEditing()
            persistProject()
        }
        .onChange(of: measurements) { _, items in
            syncReferenceState(with: items)
            persistProject()
        }
        .onChange(of: activeID) { oldID, newID in
            if oldID != newID {
                dismissKeyboard()
            }
            persistProject()
        }
        .onChange(of: referenceID) { oldID, newID in
            applyReferenceSelectionChange(from: oldID, to: newID)
            persistProject()
        }
        .onChange(of: isReferenceCmFocused) { _, isFocused in
            if !isFocused {
                persistProject()
            }
        }
        .onChange(of: isTitleFocused) { _, isFocused in
            if !isFocused {
                commitTitleEditing()
            }
        }
        .alert("計測を削除しますか？", isPresented: deleteMeasurementConfirmBinding) {
            Button("削除", role: .destructive) {
                if let id = deleteMeasurementConfirmID {
                    removeMeasurements(withIDs: [id])
                }
                deleteMeasurementConfirmID = nil
            }
            Button("キャンセル", role: .cancel) {
                deleteMeasurementConfirmID = nil
            }
        } message: {
            if let id = deleteMeasurementConfirmID {
                Text("計測 \(measurementIndex(for: id)) の線と実測値を削除します。")
            }
        }
    }

    /// キーボード表示中はキャンバスを縮め、直上の実測値入力欄が隠れないようにする。
    private var canvasMaxHeight: CGFloat? {
        guard isReferenceCmFocused else { return nil }
        let fallback: CGFloat = 180
        guard canvasSize.height > 0 else { return fallback }
        return min(max(canvasSize.height * 0.38, 120), 220)
    }

    private var deleteMeasurementConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteMeasurementConfirmID != nil },
            set: { if !$0 { deleteMeasurementConfirmID = nil } }
        )
    }

    @ViewBuilder
    private var editorToolbarOverlay: some View {
        if let activeID,
           let item = measurements.first(where: { $0.id == activeID }),
           !item.line.isComplete {
            Text(item.line.start == nil ? "始点をタップ（既存の点に近づけると吸着）" : "終点をタップ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemBackground).opacity(0.92))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func measurementListPanel(image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("計測一覧")
                    .font(.headline)
                Spacer()
                Button("追加", systemImage: "plus.circle.fill") {
                    addMeasurement()
                }
                .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if measurements.isEmpty {
                Text("計測がありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(measurements) { item in
                            measurementRow(item: item, image: image)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(height: isReferenceCmFocused ? 168 : 196)
                .scrollDisabled(isReferenceCmFocused)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    private enum ReferenceCmRowPlacement {
        case aboveCanvas
        case inList
    }

    @ViewBuilder
    private func referenceCmControlRow(placement: ReferenceCmRowPlacement = .inList) -> some View {
        let selectable = referencePickerOptions
        HStack(spacing: 8) {
            Text("実測値")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
                .frame(width: 52, alignment: .leading)

            if selectable.isEmpty {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("基準計測", selection: referenceIDBinding) {
                    ForEach(selectable, id: \.id) { item in
                        let index = measurementIndex(for: item.id)
                        Text("計測 \(index)")
                            .tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 88, alignment: .leading)

                if let referenceID,
                   let item = measurements.first(where: { $0.id == referenceID }) {
                    if item.line.isComplete {
                        DecimalCmTextField(
                            text: referenceCmByID[referenceID] ?? "",
                            placeholder: "cm",
                            appendDecimalSignal: referenceCmAppendDecimalSignal,
                            focusRequestToken: referenceFieldFocusToken,
                            dismissSignal: referenceFieldDismissSignal,
                            onFocusChange: { isReferenceCmFocused = $0 },
                            onCommit: { committed in
                                if committed.isEmpty {
                                    referenceCmByID.removeValue(forKey: referenceID)
                                } else {
                                    referenceCmByID[referenceID] = committed
                                }
                                persistProject()
                            }
                        )
                        .frame(width: 88, height: 36)
                        .padding(.horizontal, 8)
                        .background(Color(.systemBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(.separator), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        if isReferenceCmFocused {
                            Button("完了") {
                                dismissKeyboard()
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    } else {
                        Text("線を完成させてください")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, placement == .aboveCanvas ? 8 : 10)
        .background(
            placement == .aboveCanvas
                ? Color(.systemBackground)
                : Color(.secondarySystemGroupedBackground)
        )
        .overlay(alignment: .bottom) {
            if placement == .aboveCanvas {
                Divider()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: placement == .aboveCanvas ? 0 : 10))
    }

    private var referencePickerOptions: [MeasurementItem] {
        measurements
    }

    private var referenceIDBinding: Binding<UUID> {
        Binding(
            get: {
                if let referenceID,
                   measurements.contains(where: { $0.id == referenceID }) {
                    return referenceID
                }
                if let first = measurements.first?.id {
                    return first
                }
                return referenceID ?? UUID()
            },
            set: { referenceID = $0 }
        )
    }

    @ViewBuilder
    private func measurementRow(item: MeasurementItem, image: UIImage) -> some View {
        let index = measurementIndex(for: item.id)
        let color = MeasurementPalette.color(at: index)
        let isActive = item.id == activeID
        let px = pixelDistance(for: item, image: image)
        let cm = centimeters(for: item, image: image, px: px)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    selectMeasurement(item.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                        Text("計測 \(index)")
                            .fontWeight(isActive ? .bold : .regular)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if canDeleteMeasurement(id: item.id) {
                    Button(role: .destructive) {
                        deleteMeasurementConfirmID = item.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.body)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("計測 \(index) を削除")
                }
            }

            HStack(alignment: .top) {
                Button {
                    selectMeasurement(item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(pxText(px, complete: item.line.isComplete))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    selectMeasurement(item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("換算値")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(cmText(cm, complete: item.line.isComplete, hasReference: referenceIsReady(image: image)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(hasReferenceScale(image: image) ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(isActive ? color.opacity(0.08) : Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color, lineWidth: 2)
            }
        }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityHint("タップしてこの計測を選択")
    }

    private func resetEditorState() {
        didLoad = false
        loadedImage = nil
        projectTitle = ""
        measurements = []
        activeID = nil
        referenceID = nil
        referenceCmByID = [:]
        canvasSize = .zero
        deleteMeasurementConfirmID = nil
        isReferenceCmFocused = false
    }

    private func loadProjectIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let record = store.record(id: projectID),
              let image = store.loadImage(id: projectID) else {
            dismiss()
            return
        }
        loadedImage = image
        projectTitle = record.title
        var loaded = record.measurements
        let rect = ImageCoordinateMapper.displayRect(
            imageSize: image.size,
            in: canvasSize.width > 0 ? canvasSize : CGSize(width: 390, height: 400)
        )
        for index in loaded.indices {
            loaded[index].line.migrateLegacyViewPointsIfNeeded(displayRect: rect)
        }
        measurements = loaded
        activeID = record.activeMeasurementID ?? record.measurements.last?.id
        referenceID = record.referenceMeasurementID
        referenceCmByID = record.referenceCmByID
        if measurements.isEmpty {
            addMeasurement()
        }
        syncReferenceState(with: measurements)
    }

    private func titleForPersistence() -> String {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return store.record(id: projectID)?.title ?? "無題"
    }

    private func commitTitleEditing() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            projectTitle = store.record(id: projectID)?.title ?? projectTitle
        } else if trimmed != projectTitle {
            projectTitle = trimmed
        }
        persistProject()
    }

    private func persistProject() {
        guard didLoad else { return }
        let title = titleForPersistence()
        var record = MeasurementProjectRecord(
            id: projectID,
            title: title,
            createdAt: store.record(id: projectID)?.createdAt ?? Date(),
            updatedAt: Date(),
            measurements: measurements,
            activeMeasurementID: activeID,
            referenceMeasurementID: referenceID,
            referenceCmTextByMeasurementID: [:]
        )
        record.referenceCmByID = referenceCmByID
        try? store.save(record, image: nil)
    }

    private func syncReferenceState(with items: [MeasurementItem]) {
        if let activeID, !items.contains(where: { $0.id == activeID }) {
            self.activeID = items.last?.id
        }
        if referenceID == nil, let first = items.first {
            referenceID = first.id
        }
        if let referenceID, !items.contains(where: { $0.id == referenceID }) {
            self.referenceID = items.first?.id
        }
    }

    private func applyReferenceSelectionChange(from oldID: UUID?, to newID: UUID?) {
        guard let newID, let image = loadedImage,
              let newItem = measurements.first(where: { $0.id == newID }),
              newItem.line.isComplete else { return }

        guard let oldID, oldID != newID,
              measurements.first(where: { $0.id == oldID })?.line.isComplete == true else { return }

        let existing = referenceCmByID[newID] ?? ""
        guard existing.isEmpty,
              let itemPx = pixelDistance(for: newItem, image: image),
              let cm = centimeters(usingReferenceID: oldID, itemPx: itemPx, image: image) else { return }

        referenceCmByID[newID] = formatCmForInput(cm)
    }

    private func measurementIndex(for id: UUID) -> Int {
        (measurements.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }

    private func selectMeasurement(_ id: UUID) {
        if activeID != id {
            dismissKeyboard()
        }
        activeID = id
    }

    private func addMeasurement() {
        let item = MeasurementItem()
        measurements.append(item)
        activeID = item.id
    }

    private func canDeleteMeasurement(id: UUID) -> Bool {
        guard let index = measurements.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0
    }

    private func removeMeasurements(withIDs removedIDs: [UUID]) {
        let allowed = removedIDs.filter(canDeleteMeasurement)
        guard !allowed.isEmpty else { return }
        measurements.removeAll { allowed.contains($0.id) }
        if let activeID, allowed.contains(activeID) {
            self.activeID = measurements.last?.id
        }
        if let referenceID, allowed.contains(referenceID) {
            self.referenceID = measurements.first?.id
        }
        allowed.forEach { referenceCmByID[$0] = nil }
    }

    private func displayRect(for image: UIImage) -> CGRect {
        let layoutSize: CGSize
        if canvasSize.width > 1, canvasSize.height > 1 {
            layoutSize = canvasSize
        } else {
            layoutSize = CGSize(width: 390, height: 400)
        }
        return ImageCoordinateMapper.displayRect(imageSize: image.size, in: layoutSize)
    }

    private func pixelDistance(for item: MeasurementItem, image: UIImage) -> CGFloat? {
        item.line.distanceInImageSpace(imageSize: image.size, displayRect: displayRect(for: image))
    }

    private func referenceIsReady(image: UIImage) -> Bool {
        guard let referenceID,
              let refItem = measurements.first(where: { $0.id == referenceID }),
              refItem.line.isComplete,
              let refPx = pixelDistance(for: refItem, image: image),
              let refCm = MeasurementScale.parseCm(referenceCmByID[referenceID] ?? ""),
              refCm > 0, refPx > 0 else { return false }
        return true
    }

    private func hasReferenceScale(image: UIImage) -> Bool {
        referenceIsReady(image: image)
    }

    private func centimeters(for item: MeasurementItem, image: UIImage, px: CGFloat?) -> Double? {
        guard let referenceID, item.id != referenceID, let px else { return nil }
        return centimeters(usingReferenceID: referenceID, itemPx: px, image: image)
    }

    private func centimeters(usingReferenceID refID: UUID, itemPx: CGFloat, image: UIImage) -> Double? {
        guard let refItem = measurements.first(where: { $0.id == refID }),
              refItem.line.isComplete,
              let refPx = pixelDistance(for: refItem, image: image),
              let refCm = MeasurementScale.parseCm(referenceCmByID[refID] ?? ""),
              refCm > 0, refPx > 0 else { return nil }
        return MeasurementScale.centimeters(forPx: itemPx, referencePx: refPx, referenceCm: refCm)
    }

    private func formatCmForInput(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func pxText(_ value: CGFloat?, complete: Bool) -> String {
        guard complete else { return "—" }
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }

    private func cmText(_ value: Double?, complete: Bool, hasReference: Bool) -> String {
        guard complete else { return "—" }
        guard hasReference else { return "—" }
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private func dismissKeyboard() {
        isTitleFocused = false
        referenceFieldDismissSignal += 1
        KeyboardDismiss.endEditing()
    }
}
