import SwiftUI
import PhotosUI

struct StickerLibraryView: View {
    @Bindable var model: StickerLibraryViewModel
    @State private var selectedID: UUID?
    @State private var showingDetail = false
    @State private var pendingEdit: Sticker?
    @State private var showingPicker = false
    @State private var selection: PhotosPickerItem?
    @State private var showingBulkPicker = false
    @State private var bulkSelection: [PhotosPickerItem] = []
    @State private var showingFiles = false
    @State private var filesForSheet = false
    @State private var fileURLs: [URL] = []
    @State private var showingSheetPicker = false
    @State private var sheetSelection: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSearch = false
    @State private var selectedStickers: Set<UUID> = []
    @State private var confirmingDelete = false
    @FocusState private var searchFocused: Bool
    @ScaledMetric private var tileWidth: CGFloat = 105

    /// Long-pressing a sticker starts selection; deselecting the last one ends it.
    private var isSelecting: Bool { !selectedStickers.isEmpty }

    private var isPresentingFlow: Bool {
        isSelecting ||
        showingPicker || showingBulkPicker || showingFiles || showingSheetPicker || showingDetail || pendingEdit != nil ||
        selection != nil || sheetSelection != nil || model.isLoadingPhoto || model.editor != nil || model.sheetReview != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSelecting { selectionHeader } else { header }
                if showingSearch { searchField.transition(.move(edge: .top).combined(with: .opacity)) }
                library
            }
            .animation(.easeInOut(duration: 0.2), value: showingSearch)
            .animation(.easeInOut(duration: 0.2), value: isSelecting)
            .sensoryFeedback(.selection, trigger: selectedStickers)
            .background(DeckTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button { showingPicker = true } label: {
                        HStack(spacing: 9) {
                            if model.isLoadingPhoto { ProgressView().tint(DeckTheme.background) }
                            else { Image(systemName: "plus").font(.title3) }
                            Text(model.isLoadingPhoto ? "Opening photo" : "New sticker").font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 20).frame(minHeight: 54)
                        .foregroundStyle(DeckTheme.background)
                        .background(DeckTheme.ink, in: Capsule())
                    }
                    // Each picker sits on its own view so the single, bulk, and sheet pickers never collide.
                    .photosPicker(isPresented: $showingSheetPicker, selection: $sheetSelection, matching: .images)
                    importMenu
                }
                .disabled(isPresentingFlow || model.loadFailed)
                .opacity(isPresentingFlow ? 0 : 1)
                .accessibilityHidden(isPresentingFlow)
                .allowsHitTesting(!isPresentingFlow)
                .padding(.leading, 20).padding(.vertical, 10)
            }
            .overlay(alignment: .bottom) {
                if !isPresentingFlow, let progress = model.importProgress {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Adding \(min(progress.done + 1, progress.total)) of \(progress.total)…").monospacedDigit()
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 83).allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                } else if let toast = model.toast, !isPresentingFlow {
                    Text(toast).font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 83).allowsHitTesting(false)
                        .accessibilityLabel(toast)
                }
            }
            .photosPicker(isPresented: $showingPicker, selection: $selection, matching: .images)
            .task(id: selection) {
                guard let item = selection else { return }
                await model.importPhoto { try await item.loadTransferable(type: Data.self) }
                selection = nil
            }
            // Cleared only after the batch finishes: changing the id earlier would cancel the running import.
            .task(id: bulkSelection) {
                guard !bulkSelection.isEmpty else { return }
                await model.importBatch(bulkSelection.map { item in
                    StickerImport(name: nil) { try await item.loadTransferable(type: Data.self) }
                })
                bulkSelection = []
            }
            .task(id: fileURLs) {
                guard !fileURLs.isEmpty else { return }
                await model.importFiles(fileURLs)
                fileURLs = []
            }
            .task(id: sheetSelection) {
                guard let item = sheetSelection else { return }
                await model.reviewSheet { try await item.loadTransferable(type: Data.self) }
                sheetSelection = nil
            }
            // "New" marks last until the app is closed; leaving for the home screen counts as closing.
            .onChange(of: scenePhase) { _, phase in if phase == .background { model.clearNewMarks() } }
            .sheet(isPresented: $showingDetail, onDismiss: {
                if let sticker = pendingEdit { pendingEdit = nil; model.edit(sticker) }
            }) {
                if let selectedID {
                    StickerDetailView(model: model, stickerID: selectedID) { sticker in
                        pendingEdit = sticker
                        showingDetail = false
                    }
                    .presentationBackground(DeckTheme.background)
                    .presentationBackgroundInteraction(.disabled)
                }
            }
            .fullScreenCover(item: $model.editor) { editor in
                StickerEditorView(model: editor, library: model)
                    .presentationBackground(DeckTheme.background)
                    .presentationBackgroundInteraction(.disabled)
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { model.errorMessage != nil && model.editor == nil && !showingDetail },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
        .tint(DeckTheme.accent)
    }

    /// Bulk add: several photos (subjects lifted automatically) or sticker files (kept as they are).
    private var importMenu: some View {
        Menu {
            Section("Add several at once") {
                Button("Choose from Photos", systemImage: "photo.on.rectangle.angled") { showingBulkPicker = true }
                Button("Choose Files", systemImage: "folder") { filesForSheet = false; showingFiles = true }
            }
            Section("Split a sticker sheet") {
                Button("Sheet from Photos", systemImage: "square.grid.3x3.square") { showingSheetPicker = true }
                Button("Sheet from Files", systemImage: "doc.viewfinder") { filesForSheet = true; showingFiles = true }
            }
        } label: {
            Group {
                if model.isImporting { ProgressView() }
                else { Image(systemName: "square.and.arrow.down.on.square").font(.title3) }
            }
            .frame(width: 54, height: 54)
            .foregroundStyle(DeckTheme.ink)
            .background(DeckTheme.surface, in: Circle())
        }
        .disabled(model.isImporting)
        .accessibilityLabel(model.isImporting ? "Adding stickers" : "Add several stickers")
        .photosPicker(isPresented: $showingBulkPicker, selection: $bulkSelection, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: .images)
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image], allowsMultipleSelection: !filesForSheet) { result in
            guard case .success(let urls) = result else { return }
            if filesForSheet, let url = urls.first { Task { await model.reviewSheetFile(url) } }
            else { fileURLs = urls }
        }
    }

    private var filtersActive: Bool { model.filter != .all || model.collection != nil }

    private var header: some View {
        HStack(spacing: 2) {
            Image("Logo").resizable().scaledToFit().frame(height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Sticker Deck")
            Spacer()
            Menu {
                Picker("Show", selection: $model.filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Collection", selection: $model.collection) {
                    Text("All collections").tag(nil as StickerCollection?)
                    ForEach(StickerCollection.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
                Picker("Sort", selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .disabled(model.filter == .recent)
            } label: {
                Text("Filters").font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10).frame(minHeight: 44)
            }
            .accessibilityLabel(filtersActive ? "Filters, active" : "Filters")
            Button { toggleSearch() } label: {
                Image(systemName: "magnifyingglass").font(.body).frame(width: 44, height: 44)
                    .foregroundStyle(showingSearch ? DeckTheme.background : DeckTheme.accent)
                    .background(showingSearch ? DeckTheme.ink : Color.clear, in: Circle())
            }
            .accessibilityLabel(showingSearch ? "Hide search" : "Search stickers")
        }
        .padding(.leading, 20).padding(.trailing, 8).padding(.top, 10).padding(.bottom, 8)
    }
    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search stickers", text: $model.search).autocorrectionDisabled()
                .focused($searchFocused)
                .accessibilityLabel("Search stickers")
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 46)
        .background(DeckTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .padding(.horizontal, 20).padding(.bottom, 10)
        .onAppear { searchFocused = true }
    }
    private func toggleSearch() {
        showingSearch.toggle()
        if !showingSearch { model.search = ""; searchFocused = false }
    }
    private func toggleSelection(_ sticker: Sticker) {
        if selectedStickers.remove(sticker.id) == nil { selectedStickers.insert(sticker.id) }
    }
    /// Selection mode: Deselect replaces the logo, Delete replaces the trailing controls.
    private var selectionHeader: some View {
        HStack(spacing: 8) {
            Button { selectedStickers = [] } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    .foregroundStyle(DeckTheme.ink)
                    .background(DeckTheme.surface, in: Circle())
            }
            .accessibilityLabel("Deselect all")
            Text("\(selectedStickers.count) selected").font(.headline).monospacedDigit()
            Spacer()
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.titleAndIcon).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
            }
            .confirmationDialog(selectedStickers.count == 1 ? "Delete this sticker?" : "Delete \(selectedStickers.count) stickers?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(selectedStickers.count == 1 ? "Delete sticker" : "Delete \(selectedStickers.count) stickers", role: .destructive) {
                    if model.delete(ids: selectedStickers) { selectedStickers = [] }
                }
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.top, 10).padding(.bottom, 8)
    }
    private var library: some View {
        ScrollView {
            if model.loadFailed {
                ContentUnavailableView {
                    Label("Collection unavailable", systemImage: "exclamationmark.folder")
                } description: { Text("Retry to load your saved stickers.") } actions: {
                    Button("Retry") { model.reload() }.buttonStyle(.bordered)
                }
            } else if model.visibleStickers.isEmpty {
                ContentUnavailableView {
                    Label(model.stickers.isEmpty ? "Your stickers belong here" : "No stickers found", systemImage: model.stickers.isEmpty ? "square.on.square" : "magnifyingglass")
                } description: {
                    Text(model.stickers.isEmpty ? "Choose a photo to create your first sticker, or add several at once." : model.filter == .recent ? "Stickers you copy appear here." : "Try another search or filter.")
                }
                .padding(.top, 30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 6)], spacing: 4) {
                    ForEach(model.visibleStickers) { sticker in
                        StickerTile(sticker: sticker, image: model.image(for: sticker), isNew: model.isNew(sticker),
                                    isSelected: isSelecting ? selectedStickers.contains(sticker.id) : nil, onTap: {
                            if isSelecting { toggleSelection(sticker) } else { model.copy(sticker) }
                        }, onLongPress: {
                            toggleSelection(sticker)
                        }, onPreview: {
                            selectedID = sticker.id
                            showingDetail = true
                        })
                        .aspectRatio(0.92, contentMode: .fit)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $model.sheetReview) { review in
            StickerSheetReviewView(review: review) { pieces in
                Task { await model.addSheetPieces(pieces, outlined: review.needsOutline) }
            }
            .presentationBackground(DeckTheme.background)
            .presentationBackgroundInteraction(.disabled)
        }
    }
}
