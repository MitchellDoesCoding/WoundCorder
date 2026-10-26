import Foundation

/// Temporal consistency of paired observations from the same tracked wound.
enum WoundMeasurementConsistency {
    struct VolumetricMetricSample {
        let perimeter: Float
        let area: Float
        let volume: Float
        let qualityRank: Int
    }
    struct RobustCentralEstimate {
        let value: Float
        let inlierCount: Int
        let relativeMAD: Float
        let center: Float
        let tolerance: Float
    }
    struct StabilizedVolumetricEstimate {
        let perimeter: Float
        let area: Float
        let volume: Float
        let hasConsensus: Bool
        let qualityRank: Int
        let sampleCount: Int
        let positiveVolumeSampleCount: Int
    }
    static func stabilizedVolumetricMetrics(_ volumetricMetricSamples: [VolumetricMetricSample], minimumVolumetricMetricSamples: Int = 2) -> StabilizedVolumetricEstimate? {
        let volumetricMetricSamples = volumetricMetricSamples.filter {
            $0.area.isFinite && $0.area > 0 && $0.perimeter.isFinite && $0.perimeter >= 0
                && $0.volume.isFinite && $0.volume >= 0
        }
        guard !volumetricMetricSamples.isEmpty else { return nil }
        let mediumOrBetter = volumetricMetricSamples.filter { $0.qualityRank >= 1 }
        let candidates = mediumOrBetter.count >= minimumVolumetricMetricSamples
            ? mediumOrBetter
            : volumetricMetricSamples

        guard let area = robustCentralEstimate(candidates.map(\.area)), area.value > 0 else { return nil }
        let perimeter = robustCentralEstimate(candidates.map(\.perimeter).filter { $0 > 0 })
        let positiveVolumes = candidates.map(\.volume).filter { $0 > 0 }
        let volume = robustCentralEstimate(positiveVolumes)
        // Three agreeing observations remain preferred. On slower devices, two
        // medium-quality observations may also finalize only when both area and
        // volume agree tightly; a single segmentation frame is never sufficient.
        // A robust majority is enough; one drifting inference must not veto an
        // otherwise repeatable scan, while two-sample scans still require both.
        let consensusSampleCount = max(
            minimumVolumetricMetricSamples,
            candidates.count / 2 + 1
        )
        // With two readings, relative MAD is half their pairwise difference around
        // the mean. Halving these limits enforces the intended 12% area and 20%
        // volume maximum differences for the slow-device fallback.
        let areaMADLimit: Float = candidates.count == 2 ? 0.06 : 0.12
        let volumeMADLimit: Float = candidates.count == 2 ? 0.10 : 0.20
        let volumeHasConsensus = positiveVolumes.isEmpty
            || (volume?.inlierCount ?? 0) >= consensusSampleCount
                && (volume?.relativeMAD ?? 1) <= volumeMADLimit
        // Area and volume must agree in the SAME observations. Independent
        // majorities could otherwise manufacture a pair supported by one frame.
        let jointInlierCount = candidates.filter { sample in
            guard abs(sample.area - area.center) <= area.tolerance else { return false }
            guard let volume else { return sample.volume == 0 }
            return sample.volume > 0 && abs(sample.volume - volume.center) <= volume.tolerance
        }.count
        let hasConsensus = jointInlierCount >= consensusSampleCount
            && candidates.count >= minimumVolumetricMetricSamples
            && mediumOrBetter.count >= consensusSampleCount
            && area.inlierCount >= consensusSampleCount
            && area.relativeMAD <= areaMADLimit
            && volumeHasConsensus
        let sortedQuality = candidates.map(\.qualityRank).sorted()
        let qualityRank = sortedQuality[sortedQuality.count / 2]

        return StabilizedVolumetricEstimate(
            perimeter: perimeter?.value ?? 0,
            area: area.value,
            volume: volume?.value ?? 0,
            hasConsensus: hasConsensus,
            qualityRank: qualityRank,
            sampleCount: candidates.count,
            positiveVolumeSampleCount: positiveVolumes.count
        )
    }
    static func robustCentralEstimate(_ values: [Float]) -> RobustCentralEstimate? {
        let finite = values.filter(\.isFinite).sorted()
        guard let center = medianValue(finite) else { return nil }
        let deviations = finite.map { abs($0 - center) }.sorted()
        let mad = medianValue(deviations) ?? 0
        let tolerance = max(0.001, max(abs(center) * 0.08, mad * 3.0))
        let inliers = finite.filter { abs($0 - center) <= tolerance }
        let value = medianValue(inliers) ?? center
        let relativeMAD = mad / max(abs(center), 0.001)
        return RobustCentralEstimate(
            value: value,
            inlierCount: inliers.count,
            relativeMAD: relativeMAD,
            center: center,
            tolerance: tolerance
        )
    }
    static func medianValue(_ sortedValues: [Float]) -> Float? {
        guard !sortedValues.isEmpty else { return nil }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) * 0.5
        }
        return sortedValues[middle]
    }
}
