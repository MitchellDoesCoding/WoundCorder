import Foundation

/// A frozen wound-plane grid. Coverage counts exactly the cells inside its polygon.
struct WoundCoverageGrid {
    struct Cell: Hashable { let u: Int32; let v: Int32 }
    let cellSizeM: Float
    let cells: Set<Cell>

    static func suggestedCellSize(areaM2: Float, depthPixelM: Float) -> Float {
        let nominal = min(Float(0.004), sqrt(max(0, areaM2) / 40))
        let sensor = depthPixelM.isFinite && depthPixelM > 0 ? depthPixelM * 1.5 : 0
        return min(0.006, max(0.0025, nominal, sensor))
    }

    init?(polygon: [SIMD2<Float>], cellSizeM: Float) {
        guard polygon.count >= 3, cellSizeM.isFinite, cellSizeM > 0,
              polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let minU = floor(polygon.map(\.x).min()! / cellSizeM)
        let maxU = ceil(polygon.map(\.x).max()! / cellSizeM)
        let minV = floor(polygon.map(\.y).min()! / cellSizeM)
        let maxV = ceil(polygon.map(\.y).max()! / cellSizeM)
        guard [minU, maxU, minV, maxV].allSatisfy({ abs($0) < 100_000 }),
              (maxU - minU + 1) * (maxV - minV + 1) <= 100_000 else { return nil }
        func contains(_ point: SIMD2<Float>) -> Bool {
            var inside = false
            var previous = polygon.count - 1
            for i in polygon.indices {
                let a = polygon[i], b = polygon[previous]
                if (a.y > point.y) != (b.y > point.y),
                   point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                previous = i
            }
            return inside
        }
        var result = Set<Cell>()
        for u in Int(minU)...Int(maxU) {
            for v in Int(minV)...Int(maxV) {
                if contains(SIMD2(Float(u) * cellSizeM, Float(v) * cellSizeM)) {
                    result.insert(Cell(u: Int32(u), v: Int32(v)))
                }
            }
        }
        guard !result.isEmpty else { return nil }
        self.cellSizeM = cellSizeM
        self.cells = result
    }

    func cell(u: Float, v: Float) -> Cell? {
        guard u.isFinite, v.isFinite, abs(u / cellSizeM) < 100_000, abs(v / cellSizeM) < 100_000 else { return nil }
        let key = Cell(u: Int32((u / cellSizeM).rounded()), v: Int32((v / cellSizeM).rounded()))
        return cells.contains(key) ? key : nil
    }
}
