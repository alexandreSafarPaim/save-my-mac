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

                // A blocked scan used to land here showing "Nothing scanned yet",
                // which is the same thing a tidy Mac shows. Three states now,
                // not two: never scanned, blocked, and scanned-and-empty.
                if state.files.looksBlocked && !state.isScanningFiles {
                    PermissionNotice(
                        palette: palette,
                        deniedCount: state.files.deniedDirectories,
                        examples: state.files.deniedExamples
                    ) { state.openFullDiskAccessSettings() }
                } else if state.files.largeFiles.isEmpty
                            && !state.isScanningFiles
                            && state.lastFilesScanDate == nil {
                    EmptyStateView(
                        symbol: "square.stack.3d.up",
                        title: L("Nothing scanned yet"),
                        message: L("Walks your home folder and lists anything over 500 MB, sorted by kind. The same scan finds the duplicates."),
                        palette: palette,
                        hint: L("Files that exist only in iCloud and already-offloaded content are excluded.")
                    )
                    .frame(minHeight: 320)
                } else if state.files.largeFiles.isEmpty && !state.isScanningFiles {
                    EmptyStateView(
                        symbol: "checkmark.circle",
                        title: L("No files over 500 MB"),
                        message: L("The scan visited %d files and found %d above 2 MB, none above 500 MB.",
                                  state.files.visitedFiles, state.files.scannedFiles),
                        palette: palette,
                        hint: state.files.deniedDirectories > 0
                            ? L("%d folder(s) could not be read — the result may be incomplete.", state.files.deniedDirectories)
                            : L("Hidden folders and developer caches are skipped here — the Cleanup tab covers those.")
                    )
                    .frame(minHeight: 320)
                } else if !state.files.largeFiles.isEmpty {
                    scopeNote
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

    /// What the scan looked at, stated on screen.
    ///
    /// A count with no scope invites the wrong conclusion. "Nothing found" read as
    /// "your Mac is clean" when it actually meant "I did not look where your files
    /// are" — and there was no way to tell the two apart from the interface.
    private var scopeNote: some View {
        Text(L("Scope: your home folder, including ~/Library. Hidden folders, developer caches, symlinks and iCloud-only files are skipped. Visited %d files.",
               state.files.visitedFiles))
            .font(Typo.monoTiny)
            .foregroundStyle(palette.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader(
            eyebrow: L("Large files"),
            title: state.files.largeFiles.isEmpty
                ? L("Files over 500 MB")
                : L("%@ across %d huge files", Fmt.bytes(state.files.largeTotal), state.files.largeFiles.count),
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if let date = state.lastFilesScanDate {
                    Text(L("Last scan: %@", Fmt.shortDate(date)))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                if state.isScanningFiles {
                    GhostButton(title: L("Cancel"), palette: palette) { state.cancelFilesScan() }
                } else {
                    GhostButton(title: L("Scan files"), systemImage: "magnifyingglass", palette: palette) {
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
                        Text(L("Filtering by %@", kindFilter.label))
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
                    Text(L("Click a band to filter the list"))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                Spacer()
                Text(L("%d files walked", state.files.scannedFiles))
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
                Text(L("%@ in identical copies", Fmt.bytes(state.files.duplicateTotal)))
                    .font(Typo.ui(14, .semibold))
                    .foregroundStyle(palette.t1)
                Text(L("The same scan found %d duplicate groups.", state.files.duplicates.count))
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
            }
            Spacer()
            GhostButton(title: L("See duplicates"), palette: palette, tint: palette.cyan) {
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
                        Button(L("Show in Finder")) { state.reveal(file.path) }
                        Button(L("Copy path")) { state.copyToClipboard(file.path) }
                        Divider()
                        Button(L("Offload to another disk…")) {
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
                    Button(L("Show in Finder")) { state.reveal(file.path) }
                    Button(L("Copy path")) { state.copyToClipboard(file.path) }
                }
            }
        }
    }
}
