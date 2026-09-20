import Foundation

/// A completion may publish only while it owns the latest search generation.
public struct PlaceRequestGate: Sendable {
    private var generation = UUID()
    public init() {}
    @discardableResult public mutating func invalidate() -> UUID { generation = UUID(); return generation }
    public func accepts(_ token: UUID) -> Bool { token == generation }
}
