import Foundation
import SwiftUI

enum Color3DScanQualityLevel: String, Codable, Equatable {
    case waiting
    case poor
    case fair
    case good
    case excellent

    var title: String {
        switch self {
        case .waiting: "بانتظار بيانات"
        case .poor: "ضعيف"
        case .fair: "مقبول"
        case .good: "جيد"
        case .excellent: "ممتاز"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: "hourglass"
        case .poor: "exclamationmark.triangle.fill"
        case .fair: "exclamationmark.circle.fill"
        case .good: "checkmark.circle.fill"
        case .excellent: "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: .secondary
        case .poor: .red
        case .fair: .orange
        case .good: .green
        case .excellent: .cyan
        }
    }
}

struct Color3DScanQualityAssessment: Codable, Equatable {
    let score: Int
    let level: Color3DScanQualityLevel
    let headline: String
    let detail: String
    let issues: [String]

    static let waiting = Color3DScanQualityAssessment(
        score: 0,
        level: .waiting,
        headline: "بانتظار بدء الالتقاط",
        detail: "سيظهر تقييم جودة الإدخال عندما تبدأ جلسة المسح.",
        issues: []
    )
}

struct Color3DScanQualityReport: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let scanType: String
    let score: Int
    let level: Color3DScanQualityLevel
    let headline: String
    let detail: String
    let issues: [String]
    let imageCount: Int
    let invalidSampleCount: Int
    let skippedSampleCount: Int
    let metadata: [String: String]

    static func write(
        scanType: String,
        assessment: Color3DScanQualityAssessment,
        imageCount: Int,
        invalidSampleCount: Int,
        skippedSampleCount: Int,
        metadata: [String: String] = [:],
        to folder: URL
    ) {
        let report = Color3DScanQualityReport(
            schemaVersion: 1,
            createdAt: Date(),
            scanType: scanType,
            score: assessment.score,
            level: assessment.level,
            headline: assessment.headline,
            detail: assessment.detail,
            issues: assessment.issues,
            imageCount: imageCount,
            invalidSampleCount: invalidSampleCount,
            skippedSampleCount: skippedSampleCount,
            metadata: metadata
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(
                to: folder.appendingPathComponent("quality-report.json"),
                options: .atomic
            )
        } catch {
            // A diagnostics report must never invalidate a completed scan.
        }
    }
}

enum Color3DScanQualityEngine {
    static func objectCapture(
        trackingText: String,
        feedback: String?,
        shotCount: Int,
        minimumImages: Int,
        completedPasses: Int,
        recommendedPasses: Int,
        scanPassComplete: Bool,
        invalidSampleCount: Int,
        skippedSampleCount: Int,
        isActive: Bool,
        isCompleted: Bool
    ) -> Color3DScanQualityAssessment {
        guard isActive || isCompleted || shotCount > 0 else { return .waiting }

        var score = 58
        var issues: [String] = []

        let normalizedTracking = trackingText.lowercased()
        if normalizedTracking.contains("ممتاز") || normalizedTracking.contains("طبيعي") {
            score += 12
        } else if normalizedTracking.contains("سريعة") {
            score -= 24
            issues.append("الحركة سريعة؛ تحرك أبطأ حتى يثبت تتبع الكاميرا.")
        } else if normalizedTracking.contains("تفاصيل") {
            score -= 20
            issues.append("المشهد يحتوي تفاصيل مرئية قليلة؛ حسّن الإضاءة أو الخلفية.")
        } else if normalizedTracking.contains("غير جاهز") || normalizedTracking.contains("غير متاح") {
            score -= 22
            issues.append("تتبع الكاميرا غير مستقر بعد؛ انتظر قبل متابعة الالتقاط.")
        }

        if let feedback, !feedback.isEmpty {
            score -= 18
            issues.append(feedback)
        } else {
            score += 6
        }

        if minimumImages > 0 {
            let imageProgress = min(Double(shotCount) / Double(minimumImages), 1)
            score += Int(imageProgress * 10)
            if shotCount < minimumImages {
                issues.append("عدد الصور ما زال أقل من الحد الأدنى المحدد للإنهاء.")
            }
        }

        if recommendedPasses > 0 {
            let passProgress = min(Double(completedPasses) / Double(recommendedPasses), 1)
            score += Int(passProgress * 15)
            if completedPasses < recommendedPasses {
                issues.append("أكمل جولات إضافية من ارتفاعات مختلفة لتحسين التغطية.")
            }
        }

        if scanPassComplete {
            score += 5
        }

        applyReconstructionDiagnostics(
            invalidSampleCount: invalidSampleCount,
            skippedSampleCount: skippedSampleCount,
            totalImages: max(shotCount, 1),
            score: &score,
            issues: &issues
        )

        let clamped = clamp(score)
        return assessment(
            score: clamped,
            issues: deduplicated(issues),
            goodDetail: "التتبع والتغطية الحالية مناسبين للاستمرار. راجع Point Cloud قبل الإنهاء.",
            neutralDetail: "هذا تقييم لجودة الالتقاط، وليس نسبة اكتمال هندسي للنموذج النهائي."
        )
    }

    static func areaCapture(
        feedback: String?,
        shotCount: Int,
        minimumImages: Int,
        invalidSampleCount: Int,
        skippedSampleCount: Int,
        automaticDownsamplingOccurred: Bool,
        isActive: Bool,
        isCompleted: Bool
    ) -> Color3DScanQualityAssessment {
        guard isActive || isCompleted || shotCount > 0 else { return .waiting }

        var score = 58
        var issues: [String] = []

        if let feedback, !feedback.isEmpty {
            score -= 22
            issues.append(feedback)
        } else {
            score += 10
        }

        if minimumImages > 0 {
            let imageProgress = min(Double(shotCount) / Double(minimumImages), 1)
            score += Int(imageProgress * 18)
            if shotCount < minimumImages {
                issues.append("استمر في المسح؛ صور الإدخال ما زالت أقل من الحد الأدنى المحدد.")
            }
        }

        if automaticDownsamplingOccurred {
            score -= 8
            issues.append("الجهاز خفّض جزءًا من بيانات الإدخال تلقائيًا أثناء إعادة البناء.")
        }

        applyReconstructionDiagnostics(
            invalidSampleCount: invalidSampleCount,
            skippedSampleCount: skippedSampleCount,
            totalImages: max(shotCount, 1),
            score: &score,
            issues: &issues
        )

        let clamped = clamp(score)
        return assessment(
            score: clamped,
            issues: deduplicated(issues),
            goodDetail: "جودة صور الإدخال الحالية جيدة. حافظ على حركة بطيئة وتداخل واضح بين المسارات.",
            neutralDetail: "المؤشر يقيم جودة الإدخال فقط؛ لا يعني أن كل أسطح المكان تم بناؤها هندسيًا."
        )
    }

    static func turntable(
        isSmartAutomatic: Bool,
        cameraLocked: Bool,
        smartCaptureState: String,
        visualChangeScore: Float,
        motionScore: Float,
        stabilityThreshold: Float,
        averageLuminance: Float,
        passImageCount: Int,
        targetImagesPerPass: Int,
        capturedImageCount: Int,
        minimumImages: Int,
        skippedDuplicateCount: Int,
        invalidSampleCount: Int,
        skippedSampleCount: Int,
        isActive: Bool,
        isCompleted: Bool
    ) -> Color3DScanQualityAssessment {
        guard isActive || isCompleted || capturedImageCount > 0 else { return .waiting }

        var score = 55
        var issues: [String] = []

        if cameraLocked {
            score += 10
        } else if isActive {
            score -= 10
            issues.append("انتظر حتى تُقفل إعدادات التركيز والتعريض وتوازن الأبيض.")
        }

        if targetImagesPerPass > 0 {
            let progress = min(Double(passImageCount) / Double(targetImagesPerPass), 1)
            score += Int(progress * 12)
        }

        if minimumImages > 0 {
            let totalProgress = min(Double(capturedImageCount) / Double(minimumImages), 1)
            score += Int(totalProgress * 8)
            if capturedImageCount < minimumImages {
                issues.append("عدد الصور المقبولة ما زال أقل من الحد الأدنى المحدد للبناء.")
            }
        }

        if averageLuminance > 0 {
            if averageLuminance < 0.12 {
                score -= 20
                issues.append("الإضاءة ضعيفة جدًا؛ زد الإضاءة أو شغّل الكشاف إذا لم يسبب انعكاسات.")
            } else if averageLuminance < 0.20 {
                score -= 10
                issues.append("الإضاءة منخفضة؛ ارفع الإضاءة قليلًا لتقليل الضوضاء وفقدان التفاصيل.")
            } else if averageLuminance > 0.92 {
                score -= 15
                issues.append("الإضاءة شديدة وقد تحرق التفاصيل؛ خفّض الكشاف أو الإضاءة المباشرة.")
            } else {
                score += 5
            }
        }

        if motionScore > stabilityThreshold {
            score -= 15
            issues.append("الحركة الحالية أعلى من حد الثبات؛ توقف لحظة قبل التقاط الصورة.")
        }

        if isSmartAutomatic {
            if smartCaptureState.contains("يتحرك") {
                score -= 18
                issues.append("المجسم يتحرك الآن؛ ثبته لحظة قبل التقاط الزاوية التالية.")
            } else if smartCaptureState.contains("منظر قريب") {
                score -= 5
                issues.append("الزاوية الحالية قريبة من لقطة سابقة؛ لف المجسم أكثر.")
            } else if smartCaptureState.contains("زاوية جديدة") || smartCaptureState.contains("تم التقاط منظر جديد") {
                score += 10
            }

            if visualChangeScore > 0.01 {
                score += min(Int(visualChangeScore.rounded()), 5)
            }

            if skippedDuplicateCount > 0 {
                score += min(skippedDuplicateCount, 4)
            }
        }

        applyReconstructionDiagnostics(
            invalidSampleCount: invalidSampleCount,
            skippedSampleCount: skippedSampleCount,
            totalImages: max(capturedImageCount, 1),
            score: &score,
            issues: &issues
        )

        let clamped = clamp(score)
        return assessment(
            score: clamped,
            issues: deduplicated(issues),
            goodDetail: isSmartAutomatic
                ? "الالتقاط الذكي يجد مناظر جديدة مستقرة. واصل تدوير المجسم تدريجيًا."
                : "ثبات الكاميرا جيد. التقط صورة لكل زاوية جديدة مع تداخل واضح.",
            neutralDetail: "هذا تقييم لجودة وتسلسل الصور، وليس قياسًا مباشرًا لتغطية 360° بدون مرجع زاوية خارجي."
        )
    }

    private static func applyReconstructionDiagnostics(
        invalidSampleCount: Int,
        skippedSampleCount: Int,
        totalImages: Int,
        score: inout Int,
        issues: inout [String]
    ) {
        guard invalidSampleCount > 0 || skippedSampleCount > 0 else { return }
        let rejected = invalidSampleCount + skippedSampleCount
        let ratio = min(Double(rejected) / Double(max(totalImages, 1)), 1)
        score -= Int((ratio * 35).rounded())
        if invalidSampleCount > 0 {
            issues.append("RealityKit اعتبر \(invalidSampleCount) صورة غير صالحة لإعادة البناء.")
        }
        if skippedSampleCount > 0 {
            issues.append("RealityKit تخطى \(skippedSampleCount) صورة أثناء المعالجة.")
        }
    }

    private static func assessment(
        score: Int,
        issues: [String],
        goodDetail: String,
        neutralDetail: String
    ) -> Color3DScanQualityAssessment {
        let level = level(for: score)
        let headline: String
        let detail: String

        if let firstIssue = issues.first, score < 80 {
            headline = firstIssue
            detail = neutralDetail
        } else {
            headline = level == .excellent ? "الالتقاط مستقر جدًا" : "جودة الالتقاط مناسبة"
            detail = goodDetail
        }

        return Color3DScanQualityAssessment(
            score: score,
            level: level,
            headline: headline,
            detail: detail,
            issues: issues
        )
    }

    private static func level(for score: Int) -> Color3DScanQualityLevel {
        switch score {
        case 0..<45: .poor
        case 45..<65: .fair
        case 65..<85: .good
        default: .excellent
        }
    }

    private static func clamp(_ score: Int) -> Int {
        min(max(score, 0), 100)
    }

    private static func deduplicated(_ issues: [String]) -> [String] {
        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }
}

struct Color3DScanQualityCard: View {
    let assessment: Color3DScanQualityAssessment
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 8) {
                Label(assessment.level.title, systemImage: assessment.level.systemImage)
                    .font(compact ? .caption.bold() : .subheadline.bold())
                    .foregroundStyle(assessment.level.tint)

                Spacer()

                if assessment.level != .waiting {
                    Text("\(assessment.score)%")
                        .font((compact ? Font.caption : Font.subheadline).bold().monospacedDigit())
                }
            }

            if assessment.level != .waiting {
                ProgressView(value: Double(assessment.score), total: 100)
                    .tint(assessment.level.tint)
            }

            Text(assessment.headline)
                .font(compact ? .caption2 : .caption)
                .fixedSize(horizontal: false, vertical: true)

            if !compact {
                Text(assessment.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 8 : 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: compact ? 12 : 14))
    }
}
