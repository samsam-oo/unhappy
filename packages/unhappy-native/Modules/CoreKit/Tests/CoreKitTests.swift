import Testing
@testable import CoreKit

struct CoreKitTests {
    @Test
    func accentColorIsDefined() {
        _ = AppPalette.accent
    }
}
