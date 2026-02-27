import Foundation
import Testing
@testable import CoreKit

struct MachinesAPITests {
    @Test
    func endpointUnavailableErrorHasActionableDescription() {
        let error = MachinesAPIError.endpointUnavailable("/v1/machines/:id/commands/list-directory")
        let description = error.errorDescription ?? ""

        #expect(description.contains("Server endpoint is unavailable"))
        #expect(description.contains("list-directory"))
    }

    @Test
    func listRequestIncludesExpectedHeadersAndPath() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeListRequest(serverURL: baseURL, token: "abc123")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/machines")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func spawnRequestUsesExpectedPathBodyAndMethod() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeSpawnSessionRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1",
            directory: "/tmp/work",
            agent: .codex,
            codexResumeThreadID: "thread-1",
            claudeResumeSessionID: nil,
            approvedNewDirectoryCreation: true,
            sessionToken: "session-token",
            environmentVariables: ["FOO": "BAR"],
            model: "gpt-5-codex",
            reasoningEffort: .high
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/machines/machine-1/spawn")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["directory"] as? String == "/tmp/work")
        #expect(payload?["agent"] as? String == "codex")
        #expect(payload?["codexResumeThreadId"] as? String == "thread-1")
        #expect(payload?["approvedNewDirectoryCreation"] as? Bool == true)
        #expect(payload?["token"] as? String == "session-token")
        #expect(payload?["model"] as? String == "gpt-5-codex")
        #expect(payload?["reasoningEffort"] as? String == "high")
    }

    @Test
    func stopDaemonRequestUsesExpectedPathAndMethod() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeStopDaemonRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/machines/machine-1/daemon/stop")
    }

    @Test
    func updateDaemonRequestUsesExpectedPathAndMethod() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeUpdateDaemonRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/machines/machine-1/daemon/update")
    }

    @Test
    func codexThreadsRequestUsesExpectedPathAndQuery() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeCodexThreadsRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1",
            limit: 33,
            cwd: nil
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/machines/machine-1/codex/threads?limit=33")
    }

    @Test
    func claudeSessionsRequestIncludesCWDWhenProvided() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeClaudeSessionsRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1",
            limit: 12,
            cwd: "/tmp/workspace"
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.unhappy.im/v1/machines/machine-1/claude/sessions?limit=12&cwd=/tmp/workspace"
        )
    }

    @Test
    func codexThreadsRequestIncludesCursorWhenProvided() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeCodexThreadsRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1",
            limit: 33,
            cwd: "/tmp/workspace",
            cursor: "66"
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.unhappy.im/v1/machines/machine-1/codex/threads?limit=33&cwd=/tmp/workspace&cursor=66"
        )
    }

    @Test
    func claudeSessionsRequestIncludesCursorWhenProvided() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try MachinesAPI.makeClaudeSessionsRequest(
            serverURL: baseURL,
            token: "abc123",
            machineID: "machine-1",
            limit: 12,
            cwd: "/tmp/workspace",
            cursor: "24"
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.unhappy.im/v1/machines/machine-1/claude/sessions?limit=12&cwd=/tmp/workspace&cursor=24"
        )
    }

    @Test
    func decodeListResponseParsesMachineRows() throws {
        let json = """
        [
          {
            "id": "machine-1",
            "seq": 10,
            "active": true,
            "activeAt": 1700000000,
            "createdAt": 1699999900,
            "updatedAt": 1700000010,
            "metadataVersion": 1,
            "metadata": "encrypted",
            "daemonStateVersion": 1,
            "daemonState": "encrypted-state",
            "dataEncryptionKey": null
          }
        ]
        """.data(using: .utf8)!

        let machines = try MachinesAPI.decodeListResponse(json)

        #expect(machines.count == 1)
        #expect(machines.first?.id == "machine-1")
        #expect(machines.first?.active == true)
        #expect(machines.first?.daemonStateVersion == 1)
    }

    @Test
    func decodeListResponseNormalizesMillisecondTimestampsToSeconds() throws {
        let json = """
        [
          {
            "id": "machine-1",
            "seq": 10,
            "active": true,
            "activeAt": 1700000000000,
            "createdAt": 1699999900000,
            "updatedAt": 1700000010000,
            "metadataVersion": 1,
            "metadata": "encrypted",
            "daemonStateVersion": 1,
            "daemonState": "encrypted-state",
            "dataEncryptionKey": null
          }
        ]
        """.data(using: .utf8)!

        let machines = try MachinesAPI.decodeListResponse(json)
        let machine = try #require(machines.first)

        #expect(machine.activeAt == 1_700_000_000)
        #expect(machine.createdAt == 1_699_999_900)
        #expect(machine.updatedAt == 1_700_000_010)
    }

    @Test
    func decodeCommandResponseParsesPayload() throws {
        let json = """
        {
          "success": true,
          "message": "Daemon update requested"
        }
        """.data(using: .utf8)!

        let result = try MachinesAPI.decodeCommandResponse(json)

        #expect(result.success == true)
        #expect(result.message == "Daemon update requested")
    }

    @Test
    func decodeCodexThreadsResponseParsesRows() throws {
        let json = """
        {
          "success": true,
          "threads": [
            {
              "id": "thread-1",
              "name": "Bugfix",
              "cwd": "/repo",
              "updatedAt": "2026-02-26T01:23:45.000Z",
              "createdAt": "2026-02-26T01:00:00.000Z",
              "archived": false,
              "model": "gpt-5-codex",
              "effort": "xhigh"
            }
          ]
        }
        """.data(using: .utf8)!

        let rows = try MachinesAPI.decodeCodexThreadsResponse(json)

        #expect(rows.count == 1)
        #expect(rows.first?.id == "thread-1")
        #expect(rows.first?.name == "Bugfix")
        #expect(rows.first?.model == "gpt-5-codex")
        #expect(rows.first?.effort == .xhigh)
    }

    @Test
    func decodeCodexThreadsPageResponseParsesPaginationMetadata() throws {
        let json = """
        {
          "success": true,
          "threads": [
            {
              "id": "thread-1",
              "name": "Bugfix",
              "cwd": "/repo",
              "updatedAt": "2026-02-26T01:23:45.000Z",
              "createdAt": "2026-02-26T01:00:00.000Z",
              "archived": false
            }
          ],
          "nextCursor": "20",
          "hasNext": true
        }
        """.data(using: .utf8)!

        let page = try MachinesAPI.decodeCodexThreadsPageResponse(json)

        #expect(page.threads.count == 1)
        #expect(page.nextCursor == "20")
        #expect(page.hasNext == true)
    }

    @Test
    func decodeClaudeSessionsResponseParsesRows() throws {
        let json = """
        {
          "success": true,
          "sessions": [
            {
              "id": "c7a2f5d1-1111-2222-3333-444444444444",
              "cwd": "/repo",
              "updatedAt": "2026-02-26T01:23:45.000Z",
              "createdAt": "2026-02-26T01:00:00.000Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let rows = try MachinesAPI.decodeClaudeSessionsResponse(json)

        #expect(rows.count == 1)
        #expect(rows.first?.id == "c7a2f5d1-1111-2222-3333-444444444444")
        #expect(rows.first?.cwd == "/repo")
    }

    @Test
    func decodeClaudeSessionsPageResponseParsesPaginationMetadata() throws {
        let json = """
        {
          "success": true,
          "sessions": [
            {
              "id": "c7a2f5d1-1111-2222-3333-444444444444",
              "cwd": "/repo",
              "updatedAt": "2026-02-26T01:23:45.000Z",
              "createdAt": "2026-02-26T01:00:00.000Z"
            }
          ],
          "nextCursor": "12",
          "hasNext": true
        }
        """.data(using: .utf8)!

        let page = try MachinesAPI.decodeClaudeSessionsPageResponse(json)

        #expect(page.sessions.count == 1)
        #expect(page.nextCursor == "12")
        #expect(page.hasNext == true)
    }
}
