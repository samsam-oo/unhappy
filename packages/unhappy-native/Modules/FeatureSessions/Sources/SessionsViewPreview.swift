import SwiftUI
import CoreKit
import SessionKit

#Preview {
    SessionsView(
        serverURLString: "https://api.unhappy.im",
        token: "",
        makeViewModel: { SessionsViewModel(service: URLSessionSessionsService()) },
        makeProjectPickerSheet: { _, _ in AnyView(Text("Project Picker")) },
        makeProjectStartSheet: { _, _ in AnyView(Text("New Session")) },
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
