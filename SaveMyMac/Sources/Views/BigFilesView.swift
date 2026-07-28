import SwiftUI

struct BigFilesView: View {
    @EnvironmentObject var state: AppState
    @Binding var selection: AppSection
    @State private var kindFilter: FileKind?

    private var palette: Palette { state.palette }

    private var visibleFiles: [LargeFile] {
        guard let kindFilter else { return state.files.largeFiles }
        return state.files.largeFiles.filter { $0.kind == kindFilter }
    }

    var body: some View {
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

                if state.files.largeFiles.isEmpty && !state.isScanningFiles {
                    EmptyStateView(
                        symbol: "square.stack.3d.up",
                        title: "Nada analisado ainda",
                        message: "Percorre sua pasta pessoal e lista o que passa de 500 MB, classificado por tipo. A mesma varredura encontra os duplicados.",
                        palette: palette,
                        hint: "Arquivos que só existem no iCloud e conteúdo já descarregado ficam de fora."
                    )
                    .frame(minHeight: 320)
                } else if !state.files.largeFiles.isEmpty {
                    treemap
                    if state.files.duplicateTotal > 0 {
                        duplicateTeaser
                    }
                    fileList
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .riseIn()
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        ScreenHeader(
            eyebrow: "Grandes arquivos",
            title: state.files.largeFiles.isEmpty
                ? "Arquivos acima de 500 MB"
                : "\(Fmt.bytes(state.files.largeTotal)) em \(state.files.largeFiles.count) arquivos gigantes",
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if let date = state.lastFilesScanDate {
                    Text("Última análise: \(Fmt.shortDate(date))")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                if state.isScanningFiles {
                    GhostButton(title: "Cancelar", palette: palette) { state.cancelFilesScan() }
                } else {
                    GhostButton(title: "Analisar arquivos", systemImage: "magnifyingglass", palette: palette) {
                        state.startFilesScan()
                    }
                }
            }
        }
    }

    // MARK: - Treemap

    private var treemap: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(state.files.treemap) { slice in
                        let fraction = state.files.largeTotal > 0
                            ? Double(slice.bytes) / Double(state.files.largeTotal)
                            : 0
                        Button {
                            kindFilter = (kindFilter == slice.kind) ? nil : slice.kind
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slice.kind.label)
                                    .font(Typo.ui(11.5, .semibold))
                                    .lineLimit(1)
                                Text(Fmt.bytes(slice.bytes))
                                    .font(Typo.monoTiny)
                                    .opacity(0.78)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(width: max(0, geo.size.width * fraction), height: 56, alignment: .leading)
                            .background(gradient(for: slice.kind))
                            .clipped()
                            .overlay(alignment: .top) {
                                if kindFilter == slice.kind {
                                    Rectangle().fill(Color.white).frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("\(slice.count) arquivo(s) · clique para filtrar")
                    }
                }
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.stroke2, lineWidth: 1)
            )

            HStack {
                if let kindFilter {
                    HStack(spacing: 6) {
                        Text("Filtrando por \(kindFilter.label)")
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.cyan)
                        Button {
                            self.kindFilter = nil
                        } label: {
                            Text("limpar")
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.t3)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Clique numa faixa para filtrar a lista")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                Spacer()
                Text("\(state.files.scannedFiles) arquivos percorridos")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
            }
        }
    }

    private func gradient(for kind: FileKind) -> LinearGradient {
        let pairs: [FileKind: (Color, Color)] = [
            .video: (palette.accent, Color(hex: 0x5B3BE0)),
            .virtualMachine: (palette.cyan, Color(hex: 0x0F9CC4)),
            .diskImage: (palette.ok, Color(hex: 0x1EA873)),
            .backup: (palette.warn, Color(hex: 0xD07E00)),
            .audio: (Color(hex: 0xFF6B9D), Color(hex: 0xC93B6E)),
            .image: (Color(hex: 0x9C6BFF), Color(hex: 0x6E3BC9)),
            .archive: (Color(hex: 0x6BC4FF), Color(hex: 0x2E86C9)),
            .data: (Color(hex: 0x8A88A8), Color(hex: 0x5E5C78))
        ]
        let pair = pairs[kind] ?? (Color(hex: 0x8A88A8), Color(hex: 0x5E5C78))
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Chamariz para duplicados

    private var duplicateTeaser: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "square.on.square", palette: palette, size: 34, gradient: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.bytes(state.files.duplicateTotal)) em cópias idênticas")
                    .font(Typo.ui(14, .semibold))
                    .foregroundStyle(palette.t1)
                Text("A mesma varredura encontrou \(state.files.duplicates.count) grupos de duplicados.")
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
            }
            Spacer()
            GhostButton(title: "Ver duplicados", palette: palette, tint: palette.cyan) {
                selection = .duplicates
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.cyan.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.cyan.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Lista

    private var fileList: some View {
        VStack(spacing: 8) {
            ForEach(visibleFiles) { file in
                HStack(spacing: 14) {
                    IconTile(symbol: file.kind.symbol, palette: palette, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(Typo.ui(13.5, .semibold))
                            .foregroundStyle(palette.t1)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(file.directory.tildeShortened)
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(file.kind.label)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                        .frame(width: 130, alignment: .trailing)

                    Text(file.ageLabel)
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t2)
                        .frame(width: 80, alignment: .trailing)

                    Text(Fmt.bytes(file.size))
                        .font(Typo.mono(15, .bold))
                        .foregroundStyle(palette.t1)
                        .frame(width: 84, alignment: .trailing)

                    Menu {
                        Button("Mostrar no Finder") { state.reveal(file.path) }
                        Button("Copiar caminho") { state.copyToClipboard(file.path) }
                        Divider()
                        Button("Descarregar para outro disco…") {
                            selection = .offload
                        }
                    } label: {
                        Text("Offload")
                            .font(Typo.monoTiny)
                    }
                    .menuIndicator(.hidden)
                    .frame(width: 78)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.stroke, lineWidth: 1)
                )
                .contextMenu {
                    Button("Mostrar no Finder") { state.reveal(file.path) }
                    Button("Copiar caminho") { state.copyToClipboard(file.path) }
                }
            }
        }
    }
}
