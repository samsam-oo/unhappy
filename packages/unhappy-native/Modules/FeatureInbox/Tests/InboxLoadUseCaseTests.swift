import Testing
@testable import FeatureInbox

struct InboxLoadUseCaseTests {
    @Test
    func loadInboxItemsReturnsEmptyListByDefault() async throws {
        let useCase = InboxLoadUseCase()

        let items = try await useCase.loadInboxItems()

        #expect(items.isEmpty)
    }
}
