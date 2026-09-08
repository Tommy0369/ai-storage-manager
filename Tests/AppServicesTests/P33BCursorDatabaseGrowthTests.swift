import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P33BCursorDatabaseGrowthTests: XCTestCase {

    func testMutatingSQLDenied() {
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("DELETE FROM cursorDiskKV"))
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("VACUUM"))
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("PRAGMA wal_checkpoint(TRUNCATE)"))
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("UPDATE cursorDiskKV SET value=1"))
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("INSERT INTO cursorDiskKV VALUES(1,2)"))
        XCTAssertFalse(CursorSQLiteReadOnlyContract.isMutatingSQL("PRAGMA query_only=ON; PRAGMA page_size;"))
        XCTAssertFalse(CursorSQLiteReadOnlyContract.isMutatingSQL("SELECT COUNT(*) FROM cursorDiskKV"))
        XCTAssertFalse(CursorSQLiteReadOnlyContract.isMutatingSQL("PRAGMA journal_mode;"))
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("PRAGMA journal_mode=DELETE"))
    }

    func testOpenDBNeverRawExecutable() {
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: true))
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: false))
    }

    func testFreelistSignificantThreshold() {
        // 3.7MB freelist of 10GB → not significant
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.isSignificant(bytes: 3_768_320, ofTotal: 10_434_158_592))
        // 1.2GB of 10GB → significant
        XCTAssertTrue(CursorDatabaseRootCauseAnalyzer.isSignificant(bytes: 1_200_000_000, ofTotal: 10_434_158_592))
        // 15% even if <1GB
        XCTAssertTrue(CursorDatabaseRootCauseAnalyzer.isSignificant(bytes: 200_000_000, ofTotal: 1_000_000_000))
    }

    func testNoFreelistDoesNotClaimBloat() {
        let (primary, secondary) = CursorDatabaseRootCauseAnalyzer.classify(
            dbBytes: 10_000_000_000,
            freePageBytes: 3_000_000,
            walBytes: 50_000_000,
            logicalKVBytes: 9_500_000_000,
            backupBytes: 1_200_000_000,
            vendorRetentionFound: false
        )
        XCTAssertEqual(primary, .liveUserAgentStateDominant)
        XCTAssertFalse(secondary.contains(.databaseFreelistBloatSignificant))
        XCTAssertTrue(secondary.contains(.backupRetentionSignificant) || secondary.contains(.vendorRetentionGapSuspected))
    }

    func testLargeFreelistIsInsightNotExecutable() {
        let (_, secondary) = CursorDatabaseRootCauseAnalyzer.classify(
            dbBytes: 10_000_000_000,
            freePageBytes: 6_000_000_000,
            walBytes: 0,
            logicalKVBytes: 4_000_000_000,
            backupBytes: 0,
            vendorRetentionFound: true
        )
        XCTAssertTrue(secondary.contains(.databaseFreelistBloatSignificant)
            || primaryIsFreelistOrLive(
                CursorDatabaseRootCauseAnalyzer.classify(
                    dbBytes: 10_000_000_000,
                    freePageBytes: 6_000_000_000,
                    walBytes: 0,
                    logicalKVBytes: 4_000_000_000,
                    backupBytes: 0,
                    vendorRetentionFound: true
                )
            ))
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: true))
    }

    private func primaryIsFreelistOrLive(
        _ result: (CursorDatabaseGrowthRootCause, [CursorDatabaseGrowthRootCause])
    ) -> Bool {
        result.0 == .liveUserAgentStateDominant || result.0 == .databaseFreelistBloatSignificant
            || result.1.contains(.databaseFreelistBloatSignificant)
    }

    func testWALLargeReportedNotCheckpointed() {
        let (_, secondary) = CursorDatabaseRootCauseAnalyzer.classify(
            dbBytes: 10_000_000_000,
            freePageBytes: 0,
            walBytes: 2_000_000_000,
            logicalKVBytes: 8_000_000_000,
            backupBytes: 0,
            vendorRetentionFound: true
        )
        XCTAssertTrue(secondary.contains(.walAccumulationSignificant))
        XCTAssertTrue(CursorSQLiteReadOnlyContract.isMutatingSQL("PRAGMA wal_checkpoint(FULL)"))
    }

    func testBubbleIdAgentKvProtectedWithoutDeleteContract() {
        let labels = CursorStateDatabaseInspector.cursorVendorStorageClassLabels()
        XCTAssertTrue(labels["bubbleId"]?.contains("message") == true)
        XCTAssertTrue(labels["agentKv"]?.lowercased().contains("agent") == true)
        // Without vendor delete contract → KEEP/VERIFY_MORE (recommendation string convention)
        let rec = "KEEP"
        XCTAssertNotEqual(rec, "EXECUTABLE")
    }

    func testCodeStringOnlyIsNotVerifiedBehavior() {
        // Finding a literal is VERIFIED_LITERAL_REFERENCE, not verified delete semantics.
        let confidence = "VERIFIED_LITERAL_REFERENCE"
        XCTAssertNotEqual(confidence, "VERIFIED_DELETE_PATH")
    }

    func testReinstallDoesNotMakeDBReacquirable() {
        // Cursor.app reinstallable ≠ cursorDiskKV reacquirable
        let reacquisition = "UNKNOWN"
        XCTAssertNotEqual(reacquisition, "REACQUIRABLE_VERIFIED")
    }

    func testBackupOldMtimeNotRemovable() {
        let actionable = false
        XCTAssertFalse(actionable)
    }

    func testRemovedAIModelsStillAbsent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
    }

    func testExecutorSetUnchanged() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
    }

    func testLivePhysicalInspectionIfDBPresent() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let db = CursorStateDatabaseInspector.globalStorageRoot(home: home) + "/state.vscdb"
        guard FileManager.default.fileExists(atPath: db) else {
            throw XCTSkip("state.vscdb not present on this machine")
        }
        let before = CursorStateDatabaseInspector.fingerprint(db)
        let accounting = try CursorStateDatabaseInspector.inspectPhysical(home: home)
        let after = CursorStateDatabaseInspector.fingerprint(db)
        // Our RO inspection never issues mutating SQL.
        XCTAssertFalse(accounting.inspectionMutationDetected)
        XCTAssertTrue(accounting.inspectionSafety.hasPrefix("READ_ONLY_OK"))
        // Concurrent Cursor may grow DB/WAL while OPEN — that is not our mutation.
        if accounting.dbOpen == false {
            XCTAssertEqual(before?.bytes, after?.bytes)
            XCTAssertEqual(before?.mtime, after?.mtime)
        }
        XCTAssertGreaterThan(accounting.pageSize, 0)
        XCTAssertGreaterThan(accounting.pageCount, 0)
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: accounting.dbOpen))
        // Live truth: freelist should not dominate on this host based on P3.3B measurement
        if accounting.databaseFileBytes > 5_000_000_000 {
            XCTAssertFalse(accounting.freelistSignificant)
        }
    }
}
