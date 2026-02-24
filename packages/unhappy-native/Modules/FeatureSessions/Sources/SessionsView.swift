import SwiftUI
import CoreKit

@MainActor
public struct SessionsView: View {
    @StateObject private var viewModel: SessionsViewModel
    private let serverURLString: String
    private let token: String

    public init(
        serverURLString: String,
        token: String,
        viewModel: SessionsViewModel? = nil
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: viewModel ?? SessionsViewModel())
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.badge.gearshape")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Multi-Agent")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(viewModel.multiAgentInProgress ? "진행중" : "완료됨")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(viewModel.multiAgentInProgress ? Color.green.opacity(0.16) : Color.gray.opacity(0.14))
                        .foregroundStyle(viewModel.multiAgentInProgress ? Color.green : Color.secondary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Group {
                    if viewModel.isLoading {
                        ProgressView("Loading sessions…")
                    } else if let error = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Unable to load sessions")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else if viewModel.sessions.isEmpty {
                        Text("No sessions")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        List(viewModel.sessions) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.id)
                                    .font(.footnote.monospaced())
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(session.active ? .green : .gray)
                                        .frame(width: 8, height: 8)
                                    Text(session.active ? "Active" : "Inactive")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Updated \(Date(timeIntervalSince1970: session.updatedAt), style: .relative)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Sessions")
            .task(id: "\(serverURLString)|\(token)") {
                await viewModel.load(serverURLString: serverURLString, token: token)
            }
            .refreshable {
                await viewModel.load(serverURLString: serverURLString, token: token)
            }
        }
    }
}

#Preview {
    SessionsView(serverURLString: "https://api.unhappy.im", token: "")
}
