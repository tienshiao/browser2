import XCTest
import WebKit
@testable import Detour

/// Tests for EventRelayHandler, particularly around safe re-registration.
@MainActor
final class EventRelayHandlerTests: XCTestCase {

    /// Registering the relay handler twice on the same WKUserContentController
    /// must not crash. Before the fix, this threw NSInvalidArgumentException:
    /// "Attempt to add script message handler with name 'extensionEventRelay'
    /// when one already exists."
    func testDoubleRegistrationOnSameControllerDoesNotCrash() {
        let controller = WKUserContentController()
        let world = WKContentWorld.world(name: "test-relay-\(UUID().uuidString)")

        // First registration — should succeed
        EventRelayHandler.shared.register(on: controller, contentWorld: world)

        // Second registration on the SAME controller — must not crash
        EventRelayHandler.shared.register(on: controller, contentWorld: world)
    }

    /// Registering on two different controllers should succeed (both get the handler).
    func testRegistrationOnDifferentControllers() {
        let controller1 = WKUserContentController()
        let controller2 = WKUserContentController()
        let world = WKContentWorld.world(name: "test-relay-\(UUID().uuidString)")

        EventRelayHandler.shared.register(on: controller1, contentWorld: world)
        EventRelayHandler.shared.register(on: controller2, contentWorld: world)
    }

    /// Registering different content worlds on the same controller should
    /// accumulate worlds without crashing.
    func testMultipleWorldsOnSameController() {
        let controller = WKUserContentController()
        let world1 = WKContentWorld.world(name: "test-relay-a-\(UUID().uuidString)")
        let world2 = WKContentWorld.world(name: "test-relay-b-\(UUID().uuidString)")

        EventRelayHandler.shared.register(on: controller, contentWorld: world1)
        EventRelayHandler.shared.register(on: controller, contentWorld: world2)
    }
}
