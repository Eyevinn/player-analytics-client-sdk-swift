import XCTest

// Throwaway: proves the build-test check fails on a failing test (#49 AC2). Never merge.
final class CIFailureCheckTests: XCTestCase {
    func testDeliberateFailure() {
        XCTFail("deliberate failure to prove CI goes red")
    }
}
