import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var state: AppState
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
                            // Ancorado no próprio card, não num EmptyView: dois
                            // modificadores de apresentação no mesmo nó competem
                            // e só um abre.
                            .confirmationDialog(
                                "Esvaziar a Lixeira: \(state.trash.count) itens (\(Fmt.bytes(state.trash.totalBytes)))?",
                                isPresented: $confirmingEmptyTrash,
                                titleVisibility: .visible
                            ) {
                                Button("Esvaziar definitivamente", role: .destructive) {
                                    state.emptyTrash()
                                }
                                Button("Cancelar", role: .cancel) {}
                            } message: {
                                Text(emptyTrashMessage)
                            }
                    }

                    if state.categories.isEmpty && !state.isScanning {
                        VStack(spacing: 14) {
                            EmptyStateView(
                                symbol: "sparkles.rectangle.stack",
                                title: "Nada analisado ainda",
                                message: "Mapeia caches, logs, builds do Xcode, caches de gerenciadores de pacotes, backups de iPhone e sobras de apps.",
                                palette: palette,
                                hint: "A varredura é somente leitura."
                            )
                            GhostButton(
                                title: "Conceder Acesso Total ao Disco",
                                systemImage: "lock.shield",
                                palette: palette,
                                tint: palette.cyan
                            ) {
                                state.openFullDiskAccessSettings()
                            }
                            .help("Sem essa permissão várias pastas voltam vazias e os números ficam subestimados.")
                        }
                        .frame(minHeight: 320)
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
            "\(state.cleanupMode.label): \(state.selectedItems.count) itens (\(Fmt.bytes(state.selectedSize)))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(state.cleanupMode.label, role: .destructive) {
                state.removeSelected()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var emptyTrashMessage: String {
        var text = "Isto é permanente: não existe mover para a Lixeira o que já está nela. É a única ação do app sem volta."
        if let oldest = state.trash.oldestLabel {
            text += "\n\nO item mais antigo foi descartado \(oldest)."
        }
        text += "\n\nEscopo: apenas a Lixeira do Mac. A Lixeira dos discos externos não é tocada."
        return text
    }

    // MARK: - Card da Lixeira

    private var trashCard: some View {
        HStack(spacing: 16) {
            IconTile(symbol: "trash", palette: palette, size: 40, gradient: true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Lixeira")
                        .font(Typo.rowTitle)
                        .foregroundStyle(palette.t1)
                    Chip(text: "PERMANENTE", palette: palette, color: palette.danger)
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
                    GhostButton(title: "Abrir no Finder", palette: palette) {
                        state.openTrashInFinder()
                    }
                    PrimaryButton(
                        title: "Esvaziar",
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

    // MARK: - Cabeçalho

    private var header: some View {
        ScreenHeader(
            eyebrow: "Limpeza de disco",
            title: state.selectedSize > 0
                ? "\(Fmt.bytes(state.selectedSize)) prontos para sair"
                : "\(Fmt.bytes(state.totalReclaimable)) recuperáveis",
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if let date = state.lastScanDate {
                    Text("Última análise: \(Fmt.shortDate(date))")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                if state.isScanning {
                    GhostButton(title: "Cancelar", palette: palette) { state.cancelScan() }
                } else {
                    GhostButton(title: "Analisar o Mac", systemImage: "magnifyingglass", palette: palette) {
                        state.startScan()
                    }
                }
                if !state.categories.isEmpty {
                    Menu {
                        Button("Marcar só os seguros") { state.selectAll(maximumRisk: .safe) }
                        Button("Marcar seguros + atenção") { state.selectAll(maximumRisk: .caution) }
                        Button("Marcar tudo") { state.selectAll(maximumRisk: .review) }
                        Divider()
                        Button("Desmarcar tudo") { state.clearSelection() }
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
                        Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
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
                        Text("+ \(category.items.count - 200) itens não listados (todos incluídos na seleção)")
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
            Button("Mostrar no Finder") { state.reveal(item.path) }
            Button("Copiar caminho") { state.copyToClipboard(item.path) }
        }
        .help(item.path.tildeShortened)
    }

    private func toggleExpansion(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: - Rodapé

    private var footer: some View {
        StickyActionBar(palette: palette) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.selectedCategoryCount) categoria\(state.selectedCategoryCount == 1 ? "" : "s") · \(state.selectedItems.count) itens")
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                    Text("\(Fmt.bytes(state.selectedSize)) a liberar")
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
                        title: "Limpar agora",
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
            text += "\n\nAtenção: \(reviewCount) itens estão em categorias marcadas como \"Revisar\" — podem ser arquivos seus."
        }
        return text
    }
}
