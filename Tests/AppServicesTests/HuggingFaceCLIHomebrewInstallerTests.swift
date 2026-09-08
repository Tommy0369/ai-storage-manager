import Foundation
import XCTest
@testable import SafetyCore

final class HuggingFaceCLIHomebrewInstallerTests: XCTestCase {
    func testInstallRequiresHFScopeNotOllama() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: "x")
        let result = HuggingFaceCLIHomebrewInstaller.install(
            authorization: &auth,
            context: .init(processRunner: FakeProcessRunner())
        )
        XCTAssertFalse(result.installationSucceeded)
        XCTAssertEqual(result.failureReason, "INSTALL_AUTHORIZATION_MISSING_OR_OUT_OF_SCOPE")
        XCTAssertFalse(result.cacheRmExecuted)
        XCTAssertFalse(result.cleanupPermitCreated)
    }

    func testInstallConsumesAuthAndNeverRm() {
        var auth = SoftwareInstallationAuthorization.authorizeHuggingFaceCLIInstall(
            entityID: HuggingFaceCLIHomebrewInstaller.entityID
        )
        let fake = FakeProcessRunner(nextResult: .init(outcome: .commandAccepted, exitCode: 0, stdout: "ok\n"))
        // No real brew; unresolved brew path via empty candidates by injecting missing brew URL
        // Use a temp brew stub that responds, and fixed hf path that won't exist → contract fail but auth consumed
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("brew-stub-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("#!/bin/sh\n".utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        fake.resultsByArguments = [
            ["install", "hf"]: .init(outcome: .commandAccepted, exitCode: 0, stdout: "poured\n"),
            ["--prefix"]: .init(outcome: .commandAccepted, exitCode: 0, stdout: "/tmp/no-prefix\n"),
        ]
        let result = HuggingFaceCLIHomebrewInstaller.install(
            authorization: &auth,
            context: .init(
                processRunner: fake,
                brewExecutableURL: tmp
            )
        )
        XCTAssertTrue(result.authorizationConsumed)
        XCTAssertTrue(auth.isConsumed)
        XCTAssertEqual(result.argv, ["install", "hf"])
        XCTAssertFalse(result.cacheRmExecuted)
        XCTAssertFalse(result.cleanupPermitCreated)
        XCTAssertFalse(result.cacheModified)
        // Without real hf binary, contract fails honestly.
        XCTAssertFalse(result.installationSucceeded)
    }

    func testSecondInstallRejectedAfterConsume() {
        var auth = SoftwareInstallationAuthorization.authorizeHuggingFaceCLIInstall(entityID: "e")
        XCTAssertTrue(auth.consume())
        let result = HuggingFaceCLIHomebrewInstaller.install(
            authorization: &auth,
            context: .init(processRunner: FakeProcessRunner())
        )
        XCTAssertEqual(result.failureReason, "INSTALL_AUTHORIZATION_CONSUMED")
    }
}
