import Foundation
import Testing
@testable import CoreKit

struct MachinesAPITests {
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
            environmentVariables: ["FOO": "BAR"]
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
}
