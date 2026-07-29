import SwiftUI

struct OffloadView: View {
    @EnvironmentObject var state: AppState
    @State private var pendingMigration: OffloadCandidate?
    @State private var pendingRelease: MigrationJournalEntry?

    private var palette: Palette { state.palette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                // Agrupado em dois `Group` de propósito: o ViewBuilder clássico
                // vai até 10 filhos, e este bloco tinha 12.
                Group {
                    if state.isScanningOffload {
                        ScanningBanner(
                            status: state.offloadStatus,
                            progress: state.offloadProgress,
                            palette: palette
                        )
                    }

                    if state.isMigrating {
                        migrationBanner
                    }

                    destinationCard

                    if !state.journal.unfinished.isEmpty {
                        unfinishedWarning
                    }

                    if state.offload.savedBytes > 0 || !state.offload.links.isEmpty {
                        summaryCard
                    }
                }

                Group {
                    if !state.candidates.isEmpty {
                        candidatesSection
                    }

                    ForEach(state.offload.groups) { group in
                        volumeCard(group)
                    }

                    if !state.journal.quarantined.isEmpty {
                        quarantineCard
                            // Ancorado no card, não num EmptyView: dois
                            // modificadores de apresentação no mesmo nó competem.
                            .confirmationDialog(
                                pendingRelease.map { L("Release the quarantine for %@?", $0.name) } ?? "",
                                isPresented: Binding(
                                    get: { pendingRelease != nil },
                                    set: { if !$0 { pendingRelease = nil } }
                                ),
                                titleVisibility: .visible
                            ) {
                                if let entry = pendingRelease {
                                    Button(L("Release %@", Fmt.bytes(entry.bytes)), role: .destructive) {
                                        state.releaseQuarantine(entry)
                                        pendingRelease = nil
                                    }
                                }
                                Button(L("Cancel"), role: .cancel) { pendingRelease = nil }
                            } message: {
                                Text(L("The original goes to the Trash and the space returns to the Mac's disk. After that the migration can no longer be undone with one click.\n\nThe app checks first that the link and the target are intact."))
                            }
                    }

                    if !state.offload.orphans.isEmpty {
                        orphansCard
                    }

                    if state.offload.isEmpty && state.candidates.isEmpty && !state.isScanningOffload {
                        EmptyStateView(
                            symbol: "link",
                            title: state.lastOffloadScanDate == nil
                                ? L("Nothing checked yet")
                                : L("No links and no candidates"),
                            message: L("Here you move a heavy folder to an external disk and leave a symlink in its place. macOS keeps finding everything; the space comes back to the SSD."),
                            palette: palette,
                            hint: L("The check is read-only.")
                        )
                        .frame(minHeight: 300)
                    }
                }

                notesCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .riseIn()
        }
        .confirmationDialog(
            pendingMigration.map { L("Move %@ to the external disk?", $0.displayName) } ?? "",
            isPresented: Binding(
                get: { pendingMigration != nil },
                set: { if !$0 { pendingMigration = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let candidate = pendingMigration {
                Button(L("Move and create the link")) {
                    state.migrate(candidate: candidate)
                    pendingMigration = nil
                }
            }
            Button(L("Cancel"), role: .cancel) { pendingMigration = nil }
        } message: {
            if let candidate = pendingMigration {
                Text(migrationExplanation(candidate))
            }
        }
    }

    private func migrationExplanation(_ candidate: OffloadCandidate) -> String {
        """
        \(Fmt.bytes(candidate.size)) serão copiados para \(state.destinationRoot).

        A ordem é: copia com ditto → confere contagem de arquivos e bytes → move o original para uma quarentena → publica no destino → cria o link → testa leitura e escrita pelo link.

        O original NÃO é apagado: ele fica na quarentena até você liberar. Qualquer falha reverte tudo automaticamente.
        """
    }

    // MARK: - Cabeçalho

    private var header: some View {
        ScreenHeader(
            eyebrow: L("Symlink offload"),
            title: state.offload.savedBytes > 0
                ? L("%@ off the Mac's disk", Fmt.bytes(state.offload.savedBytes))
                : L("Offload heavy folders"),
            palette: palette
        ) {
            FlowLayout(spacing: 10, lineSpacing: 8) {
                if let date = state.lastOffloadScanDate {
                    Text(L("Last check: %@", Fmt.shortDate(date)))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
                if state.isScanningOffload {
                    GhostButton(title: L("Cancel"), palette: palette) { state.cancelOffloadScan() }
                } else {
                    GhostButton(title: L("Check links"), systemImage: "arrow.clockwise", palette: palette) {
                        state.startOffloadScan()
                    }
                }
            }
        }
    }

    private var migrationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.migrationPhase.label)
                    .font(Typo.ui(13, .semibold))
                    .foregroundStyle(palette.t1)
                Spacer()
                Text(Fmt.percent(state.migrationProgress))
                    .font(Typo.monoCaption)
                    .foregroundStyle(palette.cyan)
            }
            GradientBar(value: state.migrationProgress, palette: palette, height: 6, glow: true)
            Text(state.migrationStatus)
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t2)
            Text(L("Do not disconnect the external disk right now."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.warn)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Destino

    private var destinationCard: some View {
        HStack(spacing: 16) {
            IconTile(symbol: "externaldrive.badge.plus", palette: palette, size: 40, gradient: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L("Offload destination"))
                    .font(Typo.ui(14.5, .semibold))
                    .foregroundStyle(palette.t1)
                if state.destinationRoot.isEmpty {
                    Text(L("No destination chosen. Create a dedicated folder on the external disk — for example, a mac-offload folder at the root."))
                        .font(Typo.bodySmall)
                        .foregroundStyle(palette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(state.destinationRoot)
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.cyan)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            PrimaryButton(
                title: state.destinationRoot.isEmpty ? L("Set destination") : L("Change"),
                palette: palette
            ) {
                state.chooseDestination()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.cyan.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(palette.cyan.opacity(0.45))
        )
    }

    // MARK: - Resumo

    private var summaryCard: some View {
        Panel(palette: palette) {
            HStack(alignment: .top, spacing: 28) {
                stat(Fmt.bytes(state.offload.savedBytes), L("off the Mac's disk"), palette.ok)
                stat("\(state.offload.links.filter(\.savesSpace).count)", L("active links"), palette.cyan)
                stat("\(state.offload.brokenCount)", L("with problems"),
                     state.offload.brokenCount > 0 ? palette.danger : palette.t3)
                if state.journal.quarantineBytes > 0 {
                    stat(Fmt.bytes(state.journal.quarantineBytes), L("in quarantine"), palette.warn)
                }
                if state.offload.orphanBytes > 0 {
                    stat(Fmt.bytes(state.offload.orphanBytes), L("orphans at the destination"), palette.warn)
                }
                Spacer()
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typo.mono(23, .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(palette.t2)
        }
    }

    // MARK: - Candidatos

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Offload candidates"))
                    .font(Typo.cardTitle)
                    .foregroundStyle(palette.t1)
                Spacer()
                Text(L("%d found", state.candidates.count))
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
            }

            Text(L("Not everything large should become a link. The verdict on each row says why."))
                .font(Typo.caption)
                .foregroundStyle(palette.t3)

            ForEach(state.candidates) { candidate in
                candidateRow(candidate)
            }
        }
    }

    private func candidateRow(_ candidate: OffloadCandidate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol(for: candidate.recommendation), palette: palette,
                     size: 36, tint: tint(for: candidate.recommendation))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    Text(candidate.displayName)
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(palette.t1)
                    Chip(text: candidate.recommendation.label, palette: palette,
                         color: tint(for: candidate.recommendation), mono: false)
                }
                Text(candidate.reason)
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = candidate.nativeSettingHint {
                    Text(hint)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(candidate.path.tildeShortened)
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(Fmt.bytes(candidate.size))
                    .font(Typo.mono(15, .bold))
                    .foregroundStyle(palette.t1)

                if candidate.recommendation == .move {
                    Button {
                        pendingMigration = candidate
                    } label: {
                        Text(L("Move and link"))
                            .font(Typo.caption)
                            .foregroundStyle(canMigrate ? palette.cyan : palette.t3)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(palette.cyan.opacity(canMigrate ? 0.10 : 0))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        canMigrate ? palette.cyan.opacity(0.4) : palette.stroke,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMigrate)
                    .help(state.destinationRoot.isEmpty
                          ? L("Choose the destination folder first")
                          : candidate.recommendation.explanation)
                } else {
                    Text(candidate.recommendation.explanation)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 190)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
        .contextMenu {
            Button(L("Show in Finder")) { state.reveal(candidate.path) }
            Button(L("Copy path")) { state.copyToClipboard(candidate.path) }
        }
    }

    private var canMigrate: Bool {
        !state.destinationRoot.isEmpty && !state.isMigrating
    }

    private func symbol(for recommendation: OffloadRecommendation) -> String {
        switch recommendation {
        case .move: return "arrow.right.circle"
        case .deleteInstead: return "trash"
        case .useNativeSetting: return "gearshape"
        case .never: return "hand.raised"
        }
    }

    private func tint(for recommendation: OffloadRecommendation) -> Color {
        switch recommendation {
        case .move: return palette.cyan
        case .deleteInstead: return palette.ok
        case .useNativeSetting: return palette.warn
        case .never: return palette.danger
        }
    }

    // MARK: - Volume

    private func volumeCard(_ group: OffloadVolumeGroup) -> some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconTile(
                        symbol: group.isMounted ? "externaldrive.connected.to.line.below" : "externaldrive.badge.questionmark",
                        palette: palette,
                        size: 34,
                        tint: group.isMounted ? palette.cyan : palette.warn
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name)
                            .font(Typo.cardTitle)
                            .foregroundStyle(palette.t1)
                        Text(group.mountPoint)
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if group.isMounted {
                        Text(L("%@ offloaded", Fmt.bytes(group.offloadedSize)))
                            .font(Typo.monoCaption)
                            .foregroundStyle(palette.t1)
                    } else {
                        Chip(text: L("NOT MOUNTED"), palette: palette, color: palette.warn)
                    }
                }

                if group.isMounted && group.capacityTotal > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        GradientBar(
                            value: group.usedFraction,
                            palette: palette,
                            height: 6,
                            tint: LinearGradient(
                                colors: [palette.usageTint(group.usedFraction), palette.usageTint(group.usedFraction)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        HStack {
                            Text(L("%@ used", Fmt.percent(group.usedFraction)))
                            Spacer()
                            Text(L("%@ free of %@", Fmt.bytes(group.capacityAvailable), Fmt.bytes(group.capacityTotal)))
                        }
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t2)
                    }
                }

                Divider().overlay(palette.stroke)

                VStack(spacing: 0) {
                    ForEach(group.links) { link in
                        linkRow(link)
                    }
                }
            }
        }
    }

    private func linkRow(_ link: SymlinkEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: link.status))
                .font(.system(size: 12))
                .foregroundStyle(tint(for: link.status))
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(link.linkPath.tildeShortened)
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(palette.t3)
                    Text(link.targetPath)
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if link.status != .offloaded {
                    Text(link.status.explanation)
                        .font(Typo.monoTiny)
                        .foregroundStyle(tint(for: link.status))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            if link.savesSpace {
                Text(Fmt.bytes(link.size))
                    .font(Typo.monoCaption)
                    .foregroundStyle(palette.t1)
            } else {
                Chip(text: link.status.label.uppercased(), palette: palette, color: tint(for: link.status))
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(L("Show the link in Finder")) { state.reveal(link.linkPath) }
            Button(L("Show the target in Finder")) { state.reveal(link.targetPath) }
            Divider()
            Button(L("Copy command to recreate the link")) {
                state.copyToClipboard("ln -s \"\(link.targetPath)\" \"\(link.linkPath)\"")
            }
        }
    }

    private func symbol(for status: LinkStatus) -> String {
        switch status {
        case .offloaded: return "checkmark.circle.fill"
        case .volumeMissing: return "externaldrive.badge.xmark"
        case .broken: return "exclamationmark.triangle.fill"
        case .sameDisk: return "info.circle"
        }
    }

    private func tint(for status: LinkStatus) -> Color {
        switch status {
        case .offloaded: return palette.ok
        case .volumeMissing: return palette.warn
        case .broken: return palette.danger
        case .sameDisk: return palette.t3
        }
    }

    // MARK: - Quarentena

    private var quarantineCard: some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconTile(symbol: "archivebox", palette: palette, size: 32, tint: palette.warn)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Quarantine"))
                            .font(Typo.cardTitle)
                            .foregroundStyle(palette.t1)
                        Text(L("%@ still taking up the Mac's disk", Fmt.bytes(state.journal.quarantineBytes)))
                            .font(Typo.caption)
                            .foregroundStyle(palette.warn)
                    }
                    Spacer()
                    GhostButton(title: L("Release everything"), palette: palette, tint: palette.warn) {
                        state.releaseAllQuarantines()
                    }
                    .disabled(state.isMigrating)
                }

                Text(L("The originals are kept until you confirm everything works. **The space only comes back when you release them.** While they are here, each migration can be undone with one click."))
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(palette.stroke)

                ForEach(state.journal.quarantined) { entry in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(Typo.bodySmall)
                                .foregroundStyle(palette.t1)
                            Text(L("%d files · moved %@", entry.fileCount, Fmt.relativeDate(entry.startedAt)))
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.t3)
                        }
                        Spacer()
                        Text(Fmt.bytes(entry.bytes))
                            .font(Typo.monoCaption)
                            .foregroundStyle(palette.t1)
                        Button {
                            state.restore(entry)
                        } label: {
                            Text(L("Undo"))
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.t2)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isMigrating)
                        Button {
                            pendingRelease = entry
                        } label: {
                            Text(L("Release"))
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.warn)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isMigrating)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Operações interrompidas

    private var unfinishedWarning: some View {
        Panel(palette: palette, emphasized: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.danger)
                    Text(L("%d interrupted migration(s)", state.journal.unfinished.count))
                        .font(Typo.cardTitle)
                        .foregroundStyle(palette.t1)
                }
                Text(L("The journal records each step before it happens, so nothing was lost. Check the paths below before trying again."))
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(state.journal.unfinished) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("%@ — stopped at: %@", entry.name, entry.phase.label))
                            .font(Typo.monoCaption)
                            .foregroundStyle(palette.t1)
                        Text(L("source: %@", entry.sourcePath.tildeShortened))
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                        Text(L("quarantine: %@", entry.quarantinePath.tildeShortened))
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                    }
                }
            }
        }
    }

    // MARK: - Órfãos

    private var orphansCard: some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IconTile(symbol: "questionmark.folder", palette: palette, size: 32, tint: palette.warn)
                    Text(L("Orphan data at the destination"))
                        .font(Typo.cardTitle)
                        .foregroundStyle(palette.t1)
                    Spacer()
                    Text(Fmt.bytes(state.offload.orphanBytes))
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.warn)
                }

                Text(L("Folders inside your offload area that **no link points to**. Usually leftovers from a removed link, taking up space on the external disk for nothing — but check before deleting."))
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(state.offload.orphans) { orphan in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.warn)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((orphan.path as NSString).lastPathComponent)
                                .font(Typo.bodySmall)
                                .foregroundStyle(palette.t1)
                            Text(orphan.path)
                                .font(Typo.monoTiny)
                                .foregroundStyle(palette.t3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(Fmt.relativeDate(orphan.modified))
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                        Text(Fmt.bytes(orphan.size))
                            .font(Typo.monoCaption)
                            .foregroundStyle(palette.t1)
                    }
                    .padding(.vertical, 5)
                    .contextMenu {
                        Button(L("Show in Finder")) { state.reveal(orphan.path) }
                        Button(L("Copy path")) { state.copyToClipboard(orphan.path) }
                    }
                }
            }
        }
    }

    // MARK: - Notas

    private var notesCard: some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Worth knowing"))
                    .font(Typo.cardTitle)
                    .foregroundStyle(palette.t1)

                note(L("The destination disk has to support symlinks."),
                     L("exFAT and FAT do not. The app checks this before touching any file and refuses the destination."))
                note(L("A disconnected volume is the real risk."),
                     L("Some apps and installers recreate the folder over the link when the target is missing, and then two sets of data start diverging silently."))
                note(L("Time Machine on the internal disk backs up the link, not the content."),
                     L("Offloaded folders need their own backup."))
                note(L("The Cleanup tab ignores everything on the far side of a link."),
                     L("Deleting on the external disk would not give space back to the Mac, so those paths are left out of the list on purpose."))
            }
        }
    }

    private func note(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typo.ui(12.5, .medium))
                .foregroundStyle(palette.t1)
            Text(body)
                .font(Typo.caption)
                .foregroundStyle(palette.t2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
