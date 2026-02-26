import Foundation
import Testing
@testable import FeatureInbox
import CoreKit

struct InboxUserLookupUseCasesTests {
    @Test
    func profileLoadThrowsMissingToken() async {
        let useCase = InboxUserProfileLoadUseCase(service: MockUserProfileService(profile: nil))

        await #expect(throws: InboxUserLookupError.missingToken) {
            _ = try await useCase.loadUserProfile(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                userID: "u1"
            )
        }
    }

    @Test
    func profileLoadMapsUserProfile() async throws {
        let profile = APIUserProfile(
            id: "u1",
            firstName: "Sky",
            lastName: "Line",
            avatar: nil,
            username: "skyline",
            bio: "bio",
            status: .friend
        )
        let useCase = InboxUserProfileLoadUseCase(service: MockUserProfileService(profile: profile))

        let loaded = try await useCase.loadUserProfile(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            userID: "u1"
        )

        #expect(loaded?.id == "u1")
        #expect(loaded?.displayName == "Sky Line")
        #expect(loaded?.status == .friend)
    }

    @Test
    func searchThrowsMissingQuery() async {
        let useCase = InboxUserSearchUseCase(service: MockUserSearchService(rows: []))

        await #expect(throws: InboxUserLookupError.missingQuery) {
            _ = try await useCase.searchUsers(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                query: " "
            )
        }
    }

    @Test
    func searchMapsUserProfiles() async throws {
        let rows = [
            APIUserProfile(
                id: "u1",
                firstName: "Sky",
                lastName: nil,
                avatar: nil,
                username: "skyline",
                bio: nil,
                status: .none
            )
        ]
        let useCase = InboxUserSearchUseCase(service: MockUserSearchService(rows: rows))

        let loaded = try await useCase.searchUsers(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            query: "sky"
        )

        #expect(loaded.count == 1)
        #expect(loaded[0].id == "u1")
        #expect(loaded[0].status == .none)
    }
}

private struct MockUserProfileService: UserProfileFetching {
    let profile: APIUserProfile?

    func fetchUserProfile(serverURL: URL, token: String, userID: String) async throws -> APIUserProfile? {
        profile
    }
}

private struct MockUserSearchService: UserSearchFetching {
    let rows: [APIUserProfile]

    func searchUsers(serverURL: URL, token: String, query: String) async throws -> [APIUserProfile] {
        rows
    }
}
