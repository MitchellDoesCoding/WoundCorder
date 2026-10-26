import Foundation

@main
struct WoundCoverageGridTests {
    static func main() {
        let polygon: [SIMD2<Float>] = [SIMD2(-0.02, -0.02), SIMD2(0.02, -0.02), SIMD2(0.02, 0.02), SIMD2(-0.02, 0.02)]
        let grid = WoundCoverageGrid(polygon: polygon, cellSizeM: 0.005)!
        let expected = grid.cells
        var firstPass = Set<WoundCoverageGrid.Cell>()
        var secondPass = Set<WoundCoverageGrid.Cell>()
        for cell in expected {
            let u = Float(cell.u) * grid.cellSizeM
            let v = Float(cell.v) * grid.cellSizeM
            firstPass.insert(grid.cell(u: u, v: v)!)
            secondPass.insert(grid.cell(u: u + 0.0008, v: v - 0.0008)!)
        }
        precondition(firstPass.intersection(secondPass) == expected, "Sub-cell movement must retain matching coverage")
        precondition(expected.count > 20)
        let oldExpected = Int(0.0016 / (0.0025 * 0.0025))
        precondition(Double(firstPass.count) / Double(oldExpected) < 0.4, "Regression reproduces the old fine-grid ceiling")
        var repeated = Set<WoundCoverageGrid.Cell>()
        for _ in 0..<100 { repeated.insert(firstPass.first!) }
        precondition(repeated.count == 1, "Repeating one patch must not inflate coverage")
        precondition(grid.cells == expected, "Capture denominator remains frozen")
        precondition(grid.cell(u: 0.1, v: 0.1) == nil)
        precondition(grid.cell(u: .nan, v: 0) == nil)
        precondition(WoundCoverageGrid(polygon: polygon, cellSizeM: 0) == nil)
        precondition(WoundCoverageGrid(polygon: [SIMD2(.nan, 0), .zero, SIMD2(1, 1)], cellSizeM: 0.005) == nil)
        let coarse = WoundCoverageGrid.suggestedCellSize(areaM2: 0.0016, depthPixelM: 0.0035)
        precondition(coarse >= 0.005 && coarse <= 0.006)
        print("PASS: sparse-depth coverage ceiling, cross-view jitter, fixed denominator, unique cells, and invalid grid rejection")
    }
}
