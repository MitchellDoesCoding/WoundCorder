import Foundation

struct SavedMeasurement: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let date: Date
    let perimeter: Float
    let area: Float
    let volume: Float
    // Decode historical records without displaying or recomputing their retired score.
    let severity: Int?
    let patientID: UUID?
    let patientName: String?
    let bodyArea: String?
    let laterality: String?
    let context: WoundAnalysisContext?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        perimeter: Float,
        area: Float,
        volume: Float,
        severity: Int? = nil,
        patientID: UUID? = nil,
        patientName: String? = nil,
        bodyArea: String? = nil,
        laterality: String? = nil,
        context: WoundAnalysisContext? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.perimeter = perimeter
        self.area = area
        self.volume = volume
        self.severity = severity
        self.patientID = patientID
        self.patientName = patientName
        self.bodyArea = bodyArea
        self.laterality = laterality
        self.context = context
    }
}
