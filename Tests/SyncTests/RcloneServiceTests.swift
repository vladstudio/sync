import Foundation
import Testing
@testable import Sync

struct RcloneServiceTests {
    @Test
    func parseRemotesOutputSkipsInvalidLines() {
        let output = """
        drive: drive
        invalid
        : missing-name
        dropbox: dropbox
        """

        let remotes = RcloneService.parseRemotesOutput(output)

        #expect(remotes == [
            .init(name: "drive", type: "drive"),
            .init(name: "dropbox", type: "dropbox"),
        ])
    }

    @Test
    func buildArgumentsParsesQuotedExtraFlags() throws {
        var config = SyncConfig()
        config.localPath = "/tmp/local folder"
        config.remote = "drive"
        config.remotePath = "Docs"
        config.extraFlags = #"--header "A: B" --name 'two words' --path escaped\ value"#

        let args = try RcloneService().buildArguments(config: config)

        #expect(args.suffix(6).elementsEqual([
            "--header", "A: B",
            "--name", "two words",
            "--path", "escaped value",
        ]))
    }

    @Test
    func buildArgumentsThrowsOnUnterminatedQuotes() {
        var config = SyncConfig()
        config.localPath = "/tmp/local"
        config.remote = "drive"
        config.remotePath = "Docs"
        config.extraFlags = #"--header "unterminated"#

        do {
            _ = try RcloneService().buildArguments(config: config)
            Issue.record("Expected argument parsing to fail")
        } catch let error as RcloneService.ArgumentParsingError {
            #expect(error == .unterminatedDoubleQuote)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func syncConfigDecodingAppliesDefaults() throws {
        let json = """
        {
          "name": "Docs",
          "localPath": "/tmp/local",
          "remote": "drive"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let config = try decoder.decode(SyncConfig.self, from: json)

        #expect(config.name == "Docs")
        #expect(config.localPath == "/tmp/local")
        #expect(config.remote == "drive")
        #expect(config.direction == Direction.localToRemote)
        #expect(config.schedule == Schedule.manual)
        #expect(config.mode == SyncMode.copy)
        #expect(config.excludePatterns == [".DS_Store"])
        #expect(config.keepDeletedFiles)
        #expect(config.extraFlags == "")
    }
}
