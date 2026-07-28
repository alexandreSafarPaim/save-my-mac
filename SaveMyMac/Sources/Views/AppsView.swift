import SwiftUI

struct AppsView: View {
    @EnvironmentObject var state: AppState
    @State private var pendingUninstall: InstalledApp?
    @State private var detailApp: InstalledApp?

    private var palette: Palette { state.palette }
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if state.isScanningApps {
                    ScanningBanner(
                        status: state.appsStatus,
                        progress: state.appsProgress,
                        palette: palette
                    )
                }

                if state.appInventory.isEmpty && !state.isScanningApps {
                    EmptyStateView(
                        symbol: "square.grid.2x2",
                        title: "Nenhum app analisado ainda",
                        message: "Lista os apps instalados com tamanho real, último uso e todo o cache e dados de apoio que cada um deixou espalhado pela Library.",
                        palette: palette,
                        hint: "O último uso vem do Spotlight. Apps do sistema ficam de fora."
                    )
                    .frame(minHeight: 320)
                } else if !state.appInventory.isEmpty {
                    filters
                    summary
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(state.filteredApps) { app in
                            appCard(app)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .riseIn()
        }
        .confirmationDialog(
            pendingUninstall.map { "Desinstalar \($0.name) completamente?" } ?? "",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let app = pendingUninstall {
                Button("Mover tudo para a Lixeira", role: .destructive) {
                    state.uninstall(app: app)
                    pendingUninstall = nil
                }
            }
            Button(L("Cancel"), role: .cancel) { pendingUninstall = nil }
        } message: {
            if let app = pendingUninstall {
                Text("Vão para a Lixeira o app (\(Fmt.bytes(app.bundleSize))) e \(app.residues.count) itens de dados de apoio (\(Fmt.bytes(app.residueSize))). Total: \(Fmt.bytes(app.totalSize)).\n\nNada é apagado de forma irreversível — você pode restaurar da Lixeira.")
            }
        }
        .sheet(item: $detailApp) { app in
            AppDetailSheet(app: app, palette: palette) { detailApp = nil }
                .environmentObject(state)
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        ScreenHeader(
            eyebrow: "Aplicativos",
            title: state.appInventory.isEmpty
                ? "Aplicativos instalados"
                : "\(state.appInventory.apps.count) apps · \(state.appInventory.staleCount) sem uso há 90 dias",
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if let date = state.lastAppsScanDate {
                    Text("Última análise: \(Fmt.shortDate(date))")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                if state.isScanningApps {
                    GhostButton(title: L("Cancel"), palette: palette) { state.cancelAppsScan() }
                } else {
                    GhostButton(title: "Analisar apps", systemImage: "magnifyingglass", palette: palette) {
                        state.startAppsScan()
                    }
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("", selection: $state.appFilter) {
                ForEach(AppState.AppFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.t3)
                TextField("Filtrar por nome…", text: $state.appSearch)
                    .textFieldStyle(.plain)
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(palette.card2))
            .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: 1))
            .frame(maxWidth: 260)

            Spacer()

            Text("\(state.filteredApps.count) exibidos")
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            summaryStat(
                value: Fmt.bytes(state.appInventory.totalSize),
                label: "ocupado por apps e seus dados",
                tint: palette.t1
            )
            summaryStat(
                value: Fmt.bytes(state.appInventory.totalCache),
                label: "só em cache, removível sem perda",
                tint: palette.ok
            )
            summaryStat(
                value: "\(state.appInventory.staleCount)",
                label: "sem uso há mais de 90 dias",
                tint: state.appInventory.staleCount > 0 ? palette.warn : palette.t2
            )
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private func summaryStat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typo.mono(21, .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(palette.t2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Card de app

    private func appCard(_ app: InstalledApp) -> some View {
        Panel(palette: palette, cornerRadius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AppIconView(path: app.path, size: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(Typo.rowTitle)
                            .foregroundStyle(palette.t1)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(app.lastUsedLabel)
                                .font(Typo.monoTiny)
                                .foregroundStyle(app.isStale ? palette.warn : palette.t3)
                            if app.version != "—" {
                                Text("v\(app.version)")
                                    .font(Typo.monoTiny)
                                    .foregroundStyle(palette.t3)
                            }
                        }
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(app.totalSize))
                            .font(Typo.mono(14, .bold))
                            .foregroundStyle(palette.t1)
                        if app.residueSize > 0 {
                            Text("+\(Fmt.bytes(app.residueSize)) fora do app")
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.t3)
                        }
                    }
                }

                if app.cacheSize > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.ok)
                        Text("\(Fmt.bytes(app.cacheSize)) em cache")
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t2)
                        Spacer()
                        Button {
                            detailApp = app
                        } label: {
                            Text("ver \(app.residues.count) itens")
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        state.clearCache(of: app)
                    } label: {
                        Text("Limpar cache")
                            .font(Typo.caption)
                            .foregroundStyle(app.cacheSize > 0 ? palette.t1 : palette.t3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(palette.card2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(palette.stroke2, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(app.cacheSize == 0 || state.isRemoving)

                    Button {
                        pendingUninstall = app
                    } label: {
                        Text("Desinstalar")
                            .font(Typo.caption)
                            .foregroundStyle(app.canUninstall ? palette.danger : palette.t3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(palette.danger.opacity(app.canUninstall ? 0.10 : 0))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        app.canUninstall ? palette.danger.opacity(0.4) : palette.stroke,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!app.canUninstall || state.isRemoving)
                }
            }
        }
        .contextMenu {
            Button("Abrir no Finder") { state.reveal(app.path) }
            Button("Ver todos os dados de apoio") { detailApp = app }
            Button("Copiar identificador") { state.copyToClipboard(app.bundleID) }
        }
    }
}

// MARK: - Detalhe de um app

struct AppDetailSheet: View {
    var app: InstalledApp
    var palette: Palette
    var dismiss: () -> Void

    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppIconView(path: app.path, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(Typo.ui(18, .semibold))
                        .foregroundStyle(palette.t1)
                    Text(app.bundleID)
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t3)
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.bytes(app.totalSize))
                        .font(Typo.mono(17, .bold))
                        .foregroundStyle(palette.t1)
                    Text(app.lastUsedLabel)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
            }

            Divider().overlay(palette.stroke)

            HStack(spacing: 18) {
                labelled("Bundle do app", Fmt.bytes(app.bundleSize))
                labelled("Cache", Fmt.bytes(app.cacheSize))
                labelled("Outros dados", Fmt.bytes(app.residueSize - app.cacheSize))
            }

            Text("Dados de apoio encontrados (\(app.residues.count))")
                .font(Typo.cardTitle)
                .foregroundStyle(palette.t1)

            if app.residues.isEmpty {
                Text("Este app não deixou nada identificável na Library.")
                    .font(Typo.caption)
                    .foregroundStyle(palette.t3)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(app.residues) { residue in
                            HStack(spacing: 10) {
                                Image(systemName: residue.isCache ? "shippingbox" : "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(residue.isCache ? palette.ok : palette.t3)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(residue.label)
                                        .font(Typo.caption)
                                        .foregroundStyle(palette.t1)
                                    Text(residue.path.tildeShortened)
                                        .font(Typo.monoTiny)
                                        .foregroundStyle(palette.t3)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Text(Fmt.bytes(residue.size))
                                    .font(Typo.monoCaption)
                                    .foregroundStyle(palette.t1)
                            }
                            .padding(.vertical, 6)
                            .contextMenu {
                                Button("Mostrar no Finder") { state.reveal(residue.path) }
                                Button("Copiar caminho") { state.copyToClipboard(residue.path) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Text("Cache é regenerável. O resto só faz sentido remover junto com o app.")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                Spacer()
                GhostButton(title: "Fechar", palette: palette) { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(palette.bg2)
    }

    private func labelled(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MicroLabel(text: key, palette: palette)
            Text(value)
                .font(Typo.monoCaption)
                .foregroundStyle(palette.t1)
        }
    }
}
