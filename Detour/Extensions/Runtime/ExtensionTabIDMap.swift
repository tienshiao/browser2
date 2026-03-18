import Foundation

/// Bidirectional mapping between Detour's UUID-based tab/space IDs and
/// Chrome's integer-based IDs. Session-scoped (not persisted).
class ExtensionTabIDMap {
    private var uuidToInt: [UUID: Int] = [:]
    private var intToUUID: [Int: UUID] = [:]
    private var nextID: Int = 1

    /// Returns the integer ID for a UUID, creating one if needed.
    func intID(for uuid: UUID) -> Int {
        if let existing = uuidToInt[uuid] { return existing }
        let id = nextID
        nextID += 1
        uuidToInt[uuid] = id
        intToUUID[id] = uuid
        return id
    }

    /// Returns the UUID for an integer ID, or nil if not mapped.
    func uuid(for intID: Int) -> UUID? {
        intToUUID[intID]
    }

    /// Remove a mapping (e.g. when a tab is closed).
    func remove(uuid: UUID) {
        if let intID = uuidToInt.removeValue(forKey: uuid) {
            intToUUID.removeValue(forKey: intID)
        }
    }

    /// Remove a mapping by integer ID.
    func remove(intID: Int) {
        if let uuid = intToUUID.removeValue(forKey: intID) {
            uuidToInt.removeValue(forKey: uuid)
        }
    }

    /// Check if a UUID already has a mapping.
    func hasMapping(for uuid: UUID) -> Bool {
        uuidToInt[uuid] != nil
    }
}
