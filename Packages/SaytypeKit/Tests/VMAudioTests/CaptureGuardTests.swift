import Foundation
import Testing
@testable import VMAudio

@Suite struct CaptureGuardTests {
    @Test func anObjectiveCExceptionBecomesAnEngineError() {
        #expect {
            try AudioCapture.guarded {
                NSException(name: .genericException, reason: "Failed to create tap due to format mismatch").raise()
            }
        } throws: { error in
            guard case AudioCapture.CaptureError.engine(let reason) = error else { return false }
            return reason.contains("format mismatch")
        }
    }

    @Test func aSwiftErrorPassesThrough() {
        #expect(throws: AudioCapture.CaptureError.self) {
            try AudioCapture.guarded { throw AudioCapture.CaptureError.noInputDevice }
        }
    }

    @Test func aValueComesBack() throws {
        #expect(try AudioCapture.guarded { 42 } == 42)
    }
}
