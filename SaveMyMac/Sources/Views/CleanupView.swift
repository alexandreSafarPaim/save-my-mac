import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localization
    @State private var expanded: Set<UUID> = []
    @State private var confirming = false
    @State private var confirmingEmptyTrash = false

    private var palette: Palette { state.palette }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if state.isScanning {
                        ScanningBanner(
                            status: state.scanStatus,
                            progress: state.scanProgress,
                            palette: palette,
                            indeterminate: false
                        )
                    }

                    if !state.trash.isEmpty {
                        trashCard
                            // Anchored on the card itself, not on an EmptyView:
                            // two presentation modifiers on the same node compete
                            // and only one opens.
                            .confirmationDialog(
                                L("Empty the Trash: %d items (%@)?", state.trash.count, Fmt.bytes(state.trash.totalBytes)),
                                isPresented: $confirmingEmptyTrash,
                                titleVisibility: .visible
                            ) {
                                Button(L("Empty permanently"), role: .destructive) {
                                    state.emptyTrash()
                                }
                                Button(L("Cancel"), role: .cancel) {}
                            } message: {
                                Text(emptyTrashMessage)
                            }
                    }

                    if state.categories.isEmpty && !state.isScanning {
                        VStack(spacing: 14) {
                            EmptyStateView(
                                symbol: "sparkles.rectangle.stack",
                                title: L("Nothing scanned yet"),
                                message: L("It maps caches, logs, Xcode builds, package manager caches, iPhone backups and app leftovers."),
                                palette: palette,
                                hint: L("The scan is read-only.")
                            )
                            GhostButton(
                                title: L("Grant Full Disk Access"),
                                systemImage: "lock.shield",
                                palette: palette,
                                tint: palette.cyan
                            ) {
                                state.openFullDiskAccessSettings()
                            }
                            .help(L("Without that permission several folders come back empty and the numbers are underestimated."))
                        }
                    } else {
                        ForEach(state.categories) { category in
                            categoryRow(category)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .riseIn()
            }

            if !state.categories.isEmpty {
                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
            }
        }
        .confirmationDialog(
            L("%@: %d items (%@)?", state.cleanupMode.label, state.selectedItems.count, Fmt.bytes(state.selectedSize)),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(state.cleanupMode.label, role: .destructive) {
                state.removeSelected()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var emptyTrashMessage: String {
        var text = L("This is permanent: there is no moving to the Trash what is already in it. It is the only action in the app with no way back.")
        if let oldest = state.trash.oldestLabel {
            text += L("\n\nThe oldest item was discarded %@.", oldest)
        }
        text += L("\n\nScope: the Mac's Trash only. The Trash on external disks is not touched.")
        return text
    }

    // MARK: - Card da Lixeira

    private var trashCard: some View {
        HStack(spacing: 16) {
            IconTile(symbol: "trash", palette: palette, size: 40, gradient: true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L("Trash"))
                        .font(Typo.rowTitle)
                        .foregroundStyle(palette.t1)
                    Chip(text: L("PERMANENT"), palette: palette, color: palette.danger)
                }
                Text(trashSubtitle)
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Fmt.bytes(state.trash.totalBytes))
                .font(Typo.statValue)
                .foregroundStyle(palette.warn)

            if state.isEmptyingTrash {
                VStack(alignment: .trailing, spacing: 5) {
                    GradientBar(value: state.trashProgress, palette: palette, glow: true)
                        .frame(width: 160)
                    Text(state.trashStatus)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t2)
                        .lineLimit(1)
                }
            } else {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    GhostButton(title: L("Open in Finder"), palette: palette) {
                        state.openTrashInFinder()
                    }
                    PrimaryButton(
                        title: L("Empty"),
                        systemImage: "trash",
                        suffix: "+\(GameStore.xpReward(forBytes: state.trash.totalBytes)) XP",
                        palette: palette
                    ) {
                        confirmingEmptyTrash = true
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.warn.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.warn.opacity(0.35), lineWidth: 1)
        )
    }

    private var trashSubtitle: String {
        var text = "\(state.trash.count) item\(state.trash.count == 1 ? "" : "s") ainda ocupando o disco"
        if let oldest = state.trash.oldestLabel {
            text += " · mais antigo \(oldest)"
        }
        return text
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader(
            eyebrow: L("Disk cleanup"),
            title: state.selectedSize > 0
                ? L("%@ ready to go", Fmt.bytes(state.selectedSize))
                : L("%@ reclaimable", Fmt.bytes(state.totalReclaimable)),
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if let date = state.lastScanDate {
                    Text(L("Last scan: %@", Fmt.shortDate(date)))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                if state.isScanning {
                    GhostButton(title: L("Cancel"), palette: palette) { state.cancelScan() }
                } else {
                    GhostButton(title: L("Analyze my Mac"), systemImage: "magnifyingglass", palette: palette) {
                        state.startScan()
                    }
                }
                if !state.categories.isEmpty {
                    Menu {
                        Button(L("Check only the safe ones")) { state.selectAll(maximumRisk: .safe) }
                        Button(L("Check safe + caution")) { state.selectAll(maximumRisk: .caution) }
                        Button(L("Check everything")) { state.selectAll(maximumRisk: .review) }
                        Divider()
                        Button(L("Uncheck everything")) { state.clearSelection() }
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .menuIndicator(.hidden)
                    .frame(width: 42)
                }
            }
        }
    }

    // MARK: - Categoria

    private func categoryRow(_ category: CleanupCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                GradientCheckbox(
                    state: state.selectionState(for: category),
                    palette: palette
                ) {
                    state.toggleCategory(category)
                }

                IconTile(symbol: category.symbol, palette: palette)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 9) {
                        Text(category.name)
                            .font(Typo.rowTitle)
                            .foregroundStyle(palette.t1)
                        RiskPill(text: category.risk.label, score: category.riskScore, palette: palette)
                        Text(Lp("%d item", "%d items", count: category.items.count))
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                    }
                    Text(category.subtitle)
                        .font(Typo.bodySmall)
                        .foregroundStyle(palette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RiskMeter(score: category.riskScore, palette: palette)
                    .help(category.risk.explanation)

                Text(Fmt.bytes(category.totalSize))
                    .font(Typo.sizeValue)
                    .foregroundStyle(palette.t1)
                    .frame(width: 92, alignment: .trailing)

                Button {
                    toggleExpansion(category.id)
                } label: {
                    Image(systemName: expanded.contains(category.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.t3)
                }
                .buttonStyle(.plain)
                .frame(width: 22)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpansion(category.id) }

            if expanded.contains(category.id) {
                Rectangle().fill(palette.stroke).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(category.items.prefix(200)) { item in
                        itemRow(item)
                    }
                    if category.items.count > 200 {
                        Text(L("+ %d items not listed (all included in the selection)", category.items.count - 200))
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(spacing: 12) {
            GradientCheckbox(state: state.isSelected(item), palette: palette, size: 18) {
                state.toggle(item)
            }
            .padding(.leading, 18)

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(palette.t3)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = item.note {
                    Text(note)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 10)

            if let modified = item.modified {
                Text(Fmt.relativeDate(modified))
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .frame(width: 130, alignment: .trailing)
            }

            Text(Fmt.bytes(item.size))
                .font(Typo.monoCaption)
                .foregroundStyle(palette.t1)
                .frame(width: 84, alignment: .trailing)
                .padding(.trailing, 18)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { state.toggle(item) }
        .contextMenu {
            Button(L("Show in Finder")) { state.reveal(item.path) }
            Button(L("Copy path")) { state.copyToClipboard(item.path) }
        }
        .help(item.path.tildeShortened)
    }

    private func toggleExpansion(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: - Footer

    private var footer: some View {
        StickyActionBar(palette: palette) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Lp("%d category · %d items", "%d categories · %d items",
                          count: state.selectedCategoryCount,
                          state.selectedCategoryCount, state.selectedItems.count))
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                    Text(L("%@ to free", Fmt.bytes(state.selectedSize)))
                        .font(Typo.statValue)
                        .foregroundStyle(state.selectedSize > 0 ? palette.ok : palette.t3)
                }

                Spacer()

                if state.isRemoving {
                    VStack(alignment: .trailing, spacing: 5) {
                        GradientBar(value: state.removeProgress, palette: palette, glow: true)
                            .frame(width: 220)
                        Text(state.removeStatus)
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t2)
                            .lineLimit(1)
                    }
                } else {
                    Picker("", selection: $state.cleanupMode) {
                        ForEach(CleanupMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help(state.cleanupMode.description)

                    PrimaryButton(
                        title: L("Clean now"),
                        systemImage: "trash",
                        suffix: state.selectedSize > 0
                            ? "+\(GameStore.xpReward(forBytes: state.selectedSize)) XP"
                            : nil,
                        palette: palette
                    ) {
                        confirming = true
                    }
                    .opacity(state.selectedItems.isEmpty ? 0.45 : 1)
                    .disabled(state.selectedItems.isEmpty)
                }
            }
        }
    }

    private var confirmMessage: String {
        var text = state.cleanupMode.description
        let reviewCount = state.categories
            .filter { $0.risk == .review }
            .flatMap(\.items)
            .filter { state.selectedItemIDs.contains($0.id) }
            .count
        if reviewCount > 0 {
            text += L("\n\nCaution: %d items are in categories marked \"Review\" — they may be your own files.", reviewCount)
        }
        return text
    }
}
