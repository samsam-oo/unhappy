import SwiftUI
import CoreKit
import FeatureNewSession

#Preview {
    SessionsView(
        serverURLString: "https://api.unhappy.im",
        token: "",
        makeViewModel: { SessionsViewModel(service: URLSessionSessionsService()) },
        makeNewSessionViewModel: {
            let service = URLSessionMachinesService()
            return NewSessionViewModel(
                machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                directoryLister: NewSessionDirectoryListUseCase(service: service),
                spawner: NewSessionSpawnUseCase(service: service),
                recentProjectsManager: NewSessionNoopRecentProjectsManager(),
                profilesManager: NewSessionNoopProfilesManager(),
                modelsLoader: NewSessionModelsLoadUseCase(service: service),
                codexThreadsLoader: NewSessionCodexThreadsLoadUseCase(service: service),
                claudeSessionsLoader: NewSessionClaudeSessionsLoadUseCase(service: service)
            )
        },
        makeDirectSessionViewModel: { identity in
            let service = URLSessionMachinesService()
            return DirectSessionViewModel(
                identity: identity,
                loader: DirectSessionMessagesLoadUseCase(
                    codexService: service,
                    claudeService: service,
                    geminiService: service
                ),
                sender: DirectSessionMessageSendUseCase(
                    codexService: service,
                    claudeService: service,
                    geminiService: service
                )
            )
        }
    )
}
