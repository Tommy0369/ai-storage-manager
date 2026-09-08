import XCTest
@testable import SafetyCore

final class ActionArchitectureTests: XCTestCase {
    func testHardBlockMapsToNilNotKeep() {
        XCTAssertNil(ActionArchitecture.storageAction(from: .hardBlock))
        XCTAssertNil(ActionArchitecture.storageAction(from: .permanentDelete))
        XCTAssertEqual(ActionArchitecture.storageAction(from: .cloudEvictOnly), .removeLocalDownload)
        XCTAssertEqual(ActionArchitecture.storageAction(from: .moveToTrash), .moveToTrash)
    }

    func testLibraryPathsBlockMoveToICloudWithoutContract() {
        let path = "/Users/me/Library/Application Support/Cursor/User/globalStorage"
        XCTAssertFalse(ActionArchitecture.mayOfferMoveToICloud(
            path: path,
            userOwnedVerified: true,
            relocationContractVerified: false
        ))
    }

    func testUserDocumentMayOfferMoveToICloud() {
        let path = "/Users/me/Documents/video.mp4"
        XCTAssertTrue(ActionArchitecture.mayOfferMoveToICloud(
            path: path,
            userOwnedVerified: true,
            relocationContractVerified: false
        ))
    }

    func testRelocationContractOverridesBlock() {
        let path = "/Users/me/Library/Caches/foo"
        XCTAssertTrue(ActionArchitecture.mayOfferMoveToICloud(
            path: path,
            userOwnedVerified: false,
            relocationContractVerified: true
        ))
    }
}
