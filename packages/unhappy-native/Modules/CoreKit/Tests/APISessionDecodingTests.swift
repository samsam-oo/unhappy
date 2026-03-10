import Foundation
import Testing
@testable import CoreKit

struct APISessionDecodingTests {
    @Test
    func decodesNumericCodexThreadTimestampsIntoISOStrings() throws {
        let data = Data(
            """
            {
              "threads": [
                {
                  "id": "thread-1",
                  "name": "Main",
                  "cwd": "/Users/skyline23/Downloads/unhappy",
                  "createdAt": 1772793902,
                  "updatedAt": 1773116421
                }
              ],
              "hasNext": false,
              "nextCursor": null
            }
            """.utf8
        )

        let page = try JSONDecoder().decode(APICodexThreadsPage.self, from: data)

        #expect(page.threads.first?.createdAt == "2026-03-06T10:45:02Z")
        #expect(page.threads.first?.updatedAt == "2026-03-10T04:20:21Z")
    }
}
