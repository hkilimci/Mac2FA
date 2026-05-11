import Foundation

struct OTPAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var issuer: String
    var label: String
    var secretIdentifier: String
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var type: OTPType
    var counter: UInt64?
    var createdAt: Date
    var updatedAt: Date
}
