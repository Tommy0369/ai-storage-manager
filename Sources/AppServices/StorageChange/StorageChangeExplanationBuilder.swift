import Foundation

public enum StorageChangeExplanationBuilder {
    public static func firstRun() -> StorageChangeExplanation {
        StorageChangeExplanation(
            headline: "No previous scan yet.",
            bodyLines: [
                "Storage history starts after your first scan.",
                "Run another scan later to see what changed.",
                "No trend is claimed from a single observation."
            ],
            usesLowerBoundLanguage: false,
            firstRun: true
        )
    }

    public static func build(
        quality: StorageComparisonQuality,
        diskUsedDelta: Int64?,
        identifiedGrowth: Int64,
        unexplained: Int64?,
        topGrowing: [StorageChangeItem],
        usesLowerBound: Bool
    ) -> StorageChangeExplanation {
        if quality == .noComparisonYet {
            return firstRun()
        }
        if quality == .notComparable {
            return StorageChangeExplanation(
                headline: "These scans are not comparable.",
                bodyLines: ["Volume, schema, or scope differs."],
                usesLowerBoundLanguage: false,
                firstRun: false
            )
        }

        var lines: [String] = []
        let headline: String
        if let delta = diskUsedDelta {
            let absLabel = byteLabel(abs(delta))
            if delta > 0 {
                headline = usesLowerBound
                    ? "Used storage increased. At least \(byteLabel(identifiedGrowth)) of growth was identified."
                    : "Used storage increased by \(absLabel) since your previous scan."
            } else if delta < 0 {
                headline = "Used storage decreased by \(absLabel) since your previous scan."
            } else {
                headline = "Used storage is unchanged since your previous scan."
            }
        } else {
            headline = "Storage change report is available for matched items."
        }

        if !topGrowing.isEmpty {
            lines.append("We identified these major changes:")
            for item in topGrowing.prefix(5) {
                let delta = item.deltaBytes ?? 0
                let sign = delta >= 0 ? "+" : ""
                lines.append("\(item.displayName)  \(sign)\(byteLabel(delta))")
            }
        }

        if let unexplained, unexplained > 0 {
            if usesLowerBound {
                lines.append(
                    "About \(byteLabel(unexplained)) of the disk increase is outside the currently comparable mapped scope."
                )
            } else {
                lines.append(
                    "About \(byteLabel(unexplained)) of the disk increase is not explained by currently comparable mapped items."
                )
            }
        }

        // Growth never implies actionable cleanup.
        lines.append("Growth alone does not mean items are safe to clean.")

        return StorageChangeExplanation(
            headline: headline,
            bodyLines: lines,
            usesLowerBoundLanguage: usesLowerBound,
            firstRun: false
        )
    }

    private static func byteLabel(_ bytes: Int64) -> String {
        UICandidateMapper.byteLabel(bytes)
    }
}
