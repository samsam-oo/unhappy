import Foundation
import Testing
@testable import FeatureInbox

@MainActor
struct InboxViewModelTests {
    @Test
    func loadPublishesItems() async {
        let item = InboxItem(
            id: "inbox-1",
            title: "Title",
            subtitle: "Subtitle",
            timestamp: Date()
        )
        let viewModel = InboxViewModel(
            loader: MockInboxLoader(result: .success([item]))
        )

        await viewModel.load()

        #expect(viewModel.items == [item])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test
    func loadPublishesError() async {
        let viewModel = InboxViewModel(
            loader: MockInboxLoader(result: .failure(InboxTestError.failed))
        )

        await viewModel.load()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.isLoading == false)
    }
}

private enum InboxTestError: LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

private struct MockInboxLoader: InboxLoadingAction {
    let result: Result<[InboxItem], Error>

    func loadInboxItems() async throws -> [InboxItem] {
        try result.get()
    }
}
