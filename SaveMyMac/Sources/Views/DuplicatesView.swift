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
                                ? "Nada analisado ainda"
                                : "Nenhum duplicado encontrado",
                            message: state.lastFilesScanDate == nil
                                ? "A comparação é por conteúdo: primeiro agrupa por tamanho exato, depois confere amostras de 256 KB do início, meio e fim de cada arquivo."
                                : "Seus arquivos estão sem cópias idênticas acima de 2 MB. Nada a fazer aqui.",
                            palette: palette,
                            hint: state.lastFilesScanDate == nil
                                ? "Nome e data não importam — só o conteúdo."
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
            "Remover \(state.selectedDuplicates.count) cópias (\(Fmt.bytes(state.selectedDuplicateSize)))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(state.cleanupMode.label, role: .destructive) {
                state.removeSelectedDuplicates()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A cópia mais antiga de cada grupo é sempre preservada e nunca aparece na remoção.\n\n\(state.cleanupMode.description)")
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        ScreenHeader(
            eyebrow: "Duplicados",
            title: state.files.duplicates.isEmpty
                ? "Arquivos duplicados"
                : "\(Fmt.bytes(state.files.duplicateTotal)) em cópias idênticas",
            subtitle: "Comparação por conteúdo — nome e data não importam. A cópia mais antiga de cada grupo é preservada.",
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if state.isScanningFiles {
                    GhostButton(title: "Cancelar", palette: palette) { state.cancelFilesScan() }
                } else {
                    GhostButton(title: "Analisar", systemImage: "magnifyingglass", palette: palette) {
                        state.startFilesScan()
                    }
                }
                if !state.files.duplicates.isEmpty {
                    GhostButton(title: "Marcar tudo", palette: palette) {
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
                    Text("\(group.copyCount) cópias de \(Fmt.bytes(group.fileSize)) · mantém a mais antiga")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.bytes(group.reclaimable))
                        .font(Typo.mono(15, .bold))
                        .foregroundStyle(palette.ok)
                    Text("recuperável")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.copies) { copy in
                    HStack(spacing: 8) {
                        if copy.isOriginal {
                            Chip(text: "PRESERVA", palette: palette, color: palette.ok)
                        } else {
                            Chip(text: "REMOVE", palette: palette, color: palette.danger)
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
                        Button("Mostrar no Finder") { state.reveal(copy.path) }
                        Button("Copiar caminho") { state.copyToClipboard(copy.path) }
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

    // MARK: - Rodapé

    private var footer: some View {
        StickyActionBar(palette: palette) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.selectedDuplicateIDs.count) grupos · \(state.selectedDuplicates.count) cópias")
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                    Text("\(Fmt.bytes(state.selectedDuplicateSize)) a liberar")
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
                        title: "Remover cópias",
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
