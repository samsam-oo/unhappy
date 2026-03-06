import SwiftUI
import CoreKit
import FeatureNewSession
import FeatureSessionTools

@MainActor
public struct SessionProjectDetailView: View {
    let group: SessionProjectGroup
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let defaultNewSessionAgent: APISessionSpawnAgent
    let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel

    @State private var isPresentingNewSession = false

    public init(
        group: SessionProjectGroup,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        defaultNewSessionAgent: APISessionSpawnAgent,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.group = group
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.defaultNewSessionAgent = defaultNewSessionAgent
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
    }

    public var body: some View {
        List {
            Section {
                summaryCard
            }

            if !group.mirroredSessions.isEmpty {
                Section("Project Sessions") {
                    ForEach(group.mirroredSessions) { session in
                        NavigationLink {
                            SessionDetailView(
                                session: session,
                                viewModel: viewModel,
                                serverURLString: serverURLString,
                                token: token,
                                makeSessionToolsViewModel: makeSessionToolsViewModel
                            )
                        } label: {
                            ProjectMirroredSessionRow(
                                session: session,
                                isDeleting: viewModel.isDeleting(sessionID: session.id)
                            )
                        }
                        .disabled(viewModel.isDeleting(sessionID: session.id))
                    }
                }
            }

            if !group.upstreamSessions.isEmpty {
                Section("Other Computer Sessions") {
                    ForEach(group.upstreamSessions) { row in
                        NavigationLink {
                            SessionUpstreamOpeningView(
                                row: row,
                                viewModel: viewModel,
                                serverURLString: serverURLString,
                                token: token
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                UpstreamSessionRow(
                                    summary: row.summary,
                                    isLinking: viewModel.linkingUpstreamSessionID == row.id
                                )
                                HStack(spacing: 6) {
                                    Text(row.summary.provider.displayName)
                                        .font(.caption2.weight(.semibold))
                                    Text("·")
                                        .font(.caption2)
                                    Text(row.machineDisplayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingNewSession) {
            NewSessionView(
                serverURLString: serverURLString,
                token: token,
                defaultAgent: defaultNewSessionAgent,
                initialMachineID: group.machineID,
                initialDirectoryPath: group.projectPath,
                makeViewModel: makeNewSessionViewModel
            )
        }
    }

    private var summaryCard: some View {
        SessionSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(group.machineDisplayName)
                        .modifier(DockChipModifier(tone: .neutral))
                    Text("\(group.allSessionCount) sessions")
                        .modifier(DockChipModifier(tone: .primary))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.projectPath)
                        .font(.body.monospaced())
                        .foregroundStyle(AppPalette.primaryText)
                        .textSelection(.enabled)
                    Text("Sessions on this machine path stay grouped here and new sessions start in the same project context.")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                Button {
                    isPresentingNewSession = true
                } label: {
                    Label("New Session in Project", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!group.hasConcreteProjectPath)
            }
            .padding(16)
        }
    }
}

private struct ProjectMirroredSessionRow: View {
    let session: APISession
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) ?? SessionDisplayTitleResolver.fallbackTitle(for: session))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(session.active ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(session.active ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Updated \(SessionTimestampPresentation.updatedLabel(for: session.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
