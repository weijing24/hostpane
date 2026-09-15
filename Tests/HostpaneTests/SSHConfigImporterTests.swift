import Foundation
import XCTest
@testable import HostpaneCore

final class SSHConfigImporterTests: XCTestCase {
    func testImportsConcreteHostsAndSkipsPatterns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let included = directory.appendingPathComponent("extra")
        try """
        Host extra-box
          HostName extra.example.test
          User deploy
          Port 2222
        """.write(to: included, atomically: true, encoding: .utf8)

        let config = directory.appendingPathComponent("config")
        try """
        Host *
          Port 22
          User fallback
        Host jp01
          User ubuntu
        Host *.internal
          User nobody
        Include extra
        Host jump-only
          HostName jump.example.test
          IdentityFile \(directory.path)/id_ed25519
        """.write(to: config, atomically: true, encoding: .utf8)

        try Data("dummy".utf8).write(to: directory.appendingPathComponent("id_ed25519"))

        let hosts = try SSHConfigImporter().importHosts(configURL: config)
        let names = Set(hosts.map(\.name))
        XCTAssertTrue(names.contains("jp01"))
        XCTAssertTrue(names.contains("extra-box"))
        XCTAssertTrue(names.contains("jump-only"))
        XCTAssertFalse(names.contains("*"))
        XCTAssertFalse(names.contains("*.internal"))

        let jp01 = try XCTUnwrap(hosts.first { $0.name == "jp01" })
        XCTAssertEqual(jp01.username, "ubuntu")
        XCTAssertEqual(jp01.hostname, "jp01")
        XCTAssertEqual(jp01.authKind, .agent)

        let extra = try XCTUnwrap(hosts.first { $0.name == "extra-box" })
        XCTAssertEqual(extra.hostname, "extra.example.test")
        XCTAssertEqual(extra.port, 2222)
        XCTAssertEqual(extra.username, "deploy")

        let jump = try XCTUnwrap(hosts.first { $0.name == "jump-only" })
        XCTAssertEqual(jump.authKind, .privateKey)
        XCTAssertTrue(jump.privateKeyPath?.hasSuffix("id_ed25519") == true)
    }

    func testUsernameFillIgnoresTypedValues() {
        XCTAssertEqual(
            SSHConfigImporter.usernameToApply(current: "jim", fromConfig: "ubuntu", macUsername: "jim"),
            "ubuntu"
        )
        XCTAssertNil(
            SSHConfigImporter.usernameToApply(current: "root", fromConfig: "ubuntu", macUsername: "jim")
        )
        XCTAssertEqual(
            SSHConfigImporter.usernameToApply(
                current: "ubuntu",
                fromConfig: "root",
                macUsername: "jim",
                lastAutoFilled: "ubuntu"
            ),
            "root"
        )
    }
}
