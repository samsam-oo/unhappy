import SwiftUI
import CoreKit

@MainActor
public struct MachinesView: View {
    private let serverURLString: String
    private let token: String
    @StateObject private var viewModel: MachinesViewModel

    public init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> MachinesViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading machines…")
                    Spacer()
                }
            } else if let error = viewModel.errorMessage, viewModel.machines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unable to load machines")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.machines.isEmpty {
                Text("No machines")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.machines) { machine in
                    NavigationLink {
                        MachineDetailView(
                            machine: machine,
                            viewModel: viewModel,
                            serverURLString: serverURLString,
                            token: token
                        )
                    } label: {
                        MachineRow(machine: machine)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: !machine.active) {
                        if !machine.active {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await viewModel.deleteMachine(
                                        machineID: machine.id,
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            }
                            .disabled(viewModel.isDeleting(machineID: machine.id))
                        }
                    }
                }
            }
        }
        .navigationTitle("Machines")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(serverURLString)|\(token)") {
            await viewModel.loadMachines(serverURLString: serverURLString, token: token)
        }
        .refreshable {
            await viewModel.loadMachines(serverURLString: serverURLString, token: token)
        }
    }
}

private struct MachineRow: View {
    let machine: APIMachine

    var body: some View {
        let displayName = MachineDisplayNameResolver.displayName(for: machine)
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if displayName != machine.id {
                Text(machine.id)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Updated \(Date(timeIntervalSince1970: machine.updatedAt), style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if machine.active { return "Online" }
        if machine.isExplicitlyStopped { return "Stopped" }
        return "Unknown"
    }

    private var statusColor: Color {
        if machine.active { return .green }
        if machine.isExplicitlyStopped { return .orange }
        return .gray
    }
}
