import XCTest
@testable import Detour

final class ExtensionTabIDMapTests: XCTestCase {

    func testIntIDAutoIncrements() {
        let map = ExtensionTabIDMap()
        let id1 = UUID()
        let id2 = UUID()
        let int1 = map.intID(for: id1)
        let int2 = map.intID(for: id2)
        XCTAssertEqual(int1, 1)
        XCTAssertEqual(int2, 2)
    }

    func testIntIDIsStableForSameUUID() {
        let map = ExtensionTabIDMap()
        let uuid = UUID()
        let first = map.intID(for: uuid)
        let second = map.intID(for: uuid)
        XCTAssertEqual(first, second)
    }

    func testUUIDLookup() {
        let map = ExtensionTabIDMap()
        let uuid = UUID()
        let intID = map.intID(for: uuid)
        XCTAssertEqual(map.uuid(for: intID), uuid)
    }

    func testUUIDLookupReturnsNilForUnknown() {
        let map = ExtensionTabIDMap()
        XCTAssertNil(map.uuid(for: 999))
    }

    func testRemoveByUUID() {
        let map = ExtensionTabIDMap()
        let uuid = UUID()
        let intID = map.intID(for: uuid)
        map.remove(uuid: uuid)
        XCTAssertNil(map.uuid(for: intID))
        XCTAssertFalse(map.hasMapping(for: uuid))
    }

    func testRemoveByIntID() {
        let map = ExtensionTabIDMap()
        let uuid = UUID()
        let intID = map.intID(for: uuid)
        map.remove(intID: intID)
        XCTAssertNil(map.uuid(for: intID))
        XCTAssertFalse(map.hasMapping(for: uuid))
    }

    func testRemoveDoesNotAffectOtherMappings() {
        let map = ExtensionTabIDMap()
        let uuid1 = UUID()
        let uuid2 = UUID()
        let int1 = map.intID(for: uuid1)
        let int2 = map.intID(for: uuid2)
        map.remove(uuid: uuid1)
        XCTAssertEqual(map.uuid(for: int2), uuid2)
        XCTAssertNil(map.uuid(for: int1))
    }

    func testHasMapping() {
        let map = ExtensionTabIDMap()
        let uuid = UUID()
        XCTAssertFalse(map.hasMapping(for: uuid))
        _ = map.intID(for: uuid)
        XCTAssertTrue(map.hasMapping(for: uuid))
    }

    func testNewIDAfterRemoveUsesNextValue() {
        let map = ExtensionTabIDMap()
        let uuid1 = UUID()
        _ = map.intID(for: uuid1)  // 1
        map.remove(uuid: uuid1)
        let uuid2 = UUID()
        let int2 = map.intID(for: uuid2)
        // Should NOT reuse 1; should be 2
        XCTAssertEqual(int2, 2)
    }

    func testManyMappingsAreUnique() {
        let map = ExtensionTabIDMap()
        var intIDs = Set<Int>()
        for _ in 0..<100 {
            let id = map.intID(for: UUID())
            intIDs.insert(id)
        }
        XCTAssertEqual(intIDs.count, 100)
    }

    func testRemoveNonexistentUUIDIsNoOp() {
        let map = ExtensionTabIDMap()
        let uuid = UUID()
        map.remove(uuid: uuid)  // Should not crash
        XCTAssertFalse(map.hasMapping(for: uuid))
    }

    func testRemoveNonexistentIntIDIsNoOp() {
        let map = ExtensionTabIDMap()
        map.remove(intID: 9999)  // Should not crash
        XCTAssertNil(map.uuid(for: 9999))
    }

    func testSeparateMapsAreIndependent() {
        let tabMap = ExtensionTabIDMap()
        let spaceMap = ExtensionTabIDMap()
        let uuid = UUID()
        let tabID = tabMap.intID(for: uuid)
        let spaceID = spaceMap.intID(for: uuid)
        // Both start at 1 independently
        XCTAssertEqual(tabID, 1)
        XCTAssertEqual(spaceID, 1)
        // But they're separate maps
        tabMap.remove(uuid: uuid)
        XCTAssertNil(tabMap.uuid(for: tabID))
        XCTAssertEqual(spaceMap.uuid(for: spaceID), uuid)
    }
}
