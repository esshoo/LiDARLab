import Foundation
import SwiftUI

struct StableResultView: View {
    let result: StableProcessingResult
    let onClose: () -> Void
    @State private var showPath = true
    @State private var showEvidence = true

    var body: some View {
        ZStack {
            StableMapView(
                pathSegments: showPath ? result.pathSegments : [],
                breakPoints: showPath ? result.breakPoints : [],
                coverageCells: [],
                processedCells: showEvidence ? result.cells : [],
                currentPose: nil,
                previewCellSize: 0.18,
                showCoverage: false,
                showProcessed: showEvidence
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Button(action: onClose) {
                        Label("إغلاق النتيجة", systemImage: "xmark")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Text("معالجة محلية بعد انتهاء الجلسة")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Toggle("المسار", isOn: $showPath)
                        Toggle("الدليل الرأسي", isOn: $showEvidence)
                    }
                    .toggleStyle(.button)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { summaryItems }
                        VStack(spacing: 8) { summaryItems }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(12)
        }
        .background(.black)
    }

    @ViewBuilder
    private var summaryItems: some View {
        Text("Pose \(result.summary.posePackets)")
        Text("Depth \(result.summary.scanPackets)")
        Text("خلايا \(result.summary.structuralCells)")
        Text(String(format: "%.2f ث", result.summary.processingDurationMilliseconds / 1_000))
    }
}
