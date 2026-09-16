import Testing
@testable import VMSystem

@Suite struct PermissionsTests {
    @Test func coversTheThreePermissions() {
        #expect(Set(Permission.allCases) == [.microphone, .accessibility, .inputMonitoring])
    }
}
