import Foundation

struct SavedMeasurement: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let date: Date
    let perimeter: Float
    let area: Float
    let volume: Float
    let severity: Int?
    let patientName: String?
    let bodyArea: String?
    let laterality: String?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        perimeter: Float,
        area: Float,
        volume: Float,
        severity: Int? = nil,
        patientName: String? = nil,
        bodyArea: String? = nil,
        laterality: String? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.perimeter = perimeter
        self.area = area
        self.volume = volume
        self.severity = severity
        self.patientName = patientName
        self.bodyArea = bodyArea
        self.laterality = laterality
    }
}
