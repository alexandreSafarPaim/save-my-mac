import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @State private var confirming = false

    private var palette: Palette { state.palette }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if state.isScanningFiles {
                        ScanningBanner(
                            status: state.filesStatus,
                            progress: state.filesProgress,
                            palette: palette
                        )
                    }

                    if state.files.duplicates.isEmpty && !state.isScanningFiles {
                        EmptyStateView(
                            symbol: "square.on.square",
                            title: state.lastFilesScanDate == nil
                                ? L("Nothing scanned yet")
                                : L("No duplicates found"),
                            message: state.lastFilesScanDate == nil
                                ? L("The comparison is by content: it first groups by exact size, then checks 256 KB samples from the start, middle and end of each file.")
                                : L("Your files have no identical copies over 2 MB. Nothing to do here."),
                            palette: palette,
                            hint: state.lastFilesScanDate == nil
                                ? L("Name and date don't matter — only content does.")
                                : nil
                        )
                        .frame(minHeight: 320)
                    } else {
                        ForEach(state.files.duplicates) { group in
                            groupCard(group)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .riseIn()
            }

            if !state.files.duplicates.isEmpty {
                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
            }
        }
        .confirmationDialog(
            L("Remove %d copies (%@)?", state.selectedDuplicates.count, Fmt.bytes(state.selectedDuplicateSize)),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(state.cleanupMode.label, role: .destructive) {
                state.removeSelectedDuplicates()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The oldest copy in each group is always preserved and never appears in the removal.\n\n%@", state.cleanupMode.description))
        }
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader(
            eyebrow: L("Duplicates"),
            title: state.files.duplicates.isEmpty
                ? L("Duplicate files")
                : L("%@ in identical copies", Fmt.bytes(state.files.duplicateTotal)),
            subtitle: L("Compared by content — name and date don't matter. The oldest copy in each group is preserved."),
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if state.isScanningFiles {
                    GhostButton(title: L("Cancel"), palette: palette) { state.cancelFilesScan() }
                } else {
                    GhostButton(title: L("Scan"), systemImage: "magnifyingglass", palette: palette) {
                        state.startFilesScan()
                    }
                }
                if !state.files.duplicates.isEmpty {
                    GhostButton(title: L("Check everything"), palette: palette) {
                        state.selectAllDuplicates()
                    }
                }
            }
        }
    }

    // MARK: - Grupo

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GradientCheckbox(
                    state: state.selectedDuplicateIDs.contains(group.id),
                    palette: palette
                ) {
                    state.toggleDuplicateGroup(group)
                }

                IconTile(symbol: group.kind.symbol, palette: palette, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(palette.t1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(L("%d copies of %@ · keeps the oldest", group.copyCount, Fmt.bytes(group.fileSize)))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.bytes(group.reclaimable))
                        .font(Typo.mono(15, .bold))
                        .foregroundStyle(palette.ok)
                    Text(L("reclaimable"))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.copies) { copy in
                    HStack(spacing: 8) {
                        if copy.isOriginal {
                            Chip(text: L("KEEPS"), palette: palette, color: palette.ok)
                        } else {
                            Chip(text: L("REMOVES"), palette: palette, color: palette.danger)
                        }
                        PathChip(text: copy.directory, palette: palette)
                        Text(Fmt.shortDate(copy.modified))
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                        Spacer(minLength: 4)
                        Button {
                            state.reveal(copy.path)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.t3)
                        }
                        .buttonStyle(.plain)
                        .help("Mostrar no Finder")
                    }
                    .contextMenu {
                        Button(L("Show in Finder")) { state.reveal(copy.path) }
                        Button(L("Copy path")) { state.copyToClipboard(copy.path) }
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        StickyActionBar(palette: palette) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%d groups · %d copies", state.selectedDuplicateIDs.count, state.selectedDuplicates.count))
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                    Text(L("%@ to free", Fmt.bytes(state.selectedDuplicateSize)))
                        .font(Typo.statValue)
                        .foregroundStyle(state.selectedDuplicateSize > 0 ? palette.ok : palette.t3)
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
                    PrimaryButton(
                        title: L("Remove copies"),
                        systemImage: "square.on.square.badge.person.crop",
                        suffix: state.selectedDuplicateSize > 0
                            ? "+\(GameStore.xpReward(forBytes: state.selectedDuplicateSize)) XP"
                            : nil,
                        palette: palette
                    ) {
                        confirming = true
                    }
                    .opacity(state.selectedDuplicates.isEmpty ? 0.45 : 1)
                    .disabled(state.selectedDuplicates.isEmpty)
                }
            }
        }
    }
}
