import Foundation
import RoomPlan
import simd

struct RoomScanProjectReviewEngine {
    let rooms: [CapturedRoom]
    let wallRecords: [BuildingWallRecord]
    let assignments: [RoomWallAssignment]
    let geometryOverrides: [WallGeometryOverrideRecord]
    let manualOpenings: [ManualOpeningRecord]
    let suppressedSurfaceIdentifiers: Set<UUID>
    let levelProfiles: [RoomLevelProfileRecord]
    let ceilingZones: [CeilingZoneRecord]

    func makeIssues() -> [ProjectReviewIssue] {
        var issues: [ProjectReviewIssue] = []
        var keys = Set<String>()
        let recordByID = Dictionary(uniqueKeysWithValues: wallRecords.map { ($0.id, $0) })
        let overrideByAssignment = Dictionary(uniqueKeysWithValues: geometryOverrides.map { ($0.assignmentID, $0) })
        let assignmentsByWall = Dictionary(grouping: assignments, by: \.buildingWallID)

        func append(
            key: String,
            kind: ProjectReviewIssueKind,
            severity: ProjectReviewIssueSeverity,
            title: String,
            details: String,
            action: String,
            assignment: RoomWallAssignment? = nil,
            roomIndex: Int? = nil,
            buildingWallID: UUID? = nil
        ) {
            guard keys.insert(key).inserted else { return }
            issues.append(
                ProjectReviewIssue(
                    id: UUID(),
                    kind: kind,
                    severity: severity,
                    title: title,
                    details: details,
                    suggestedAction: action,
                    roomIndex: roomIndex ?? assignment?.roomIndex,
                    assignmentID: assignment?.id,
                    wallIdentifier: assignment?.wallIdentifier,
                    buildingWallID: buildingWallID ?? assignment?.buildingWallID
                )
            )
        }

        for assignment in assignments {
            let geometry = EffectiveWallGeometry(
                base: assignment.geometry,
                adjustment: overrideByAssignment[assignment.id]
            )
            if !geometry.centerX.isFinite || !geometry.centerZ.isFinite || !geometry.widthMeters.isFinite || !geometry.heightMeters.isFinite {
                append(
                    key: "malformed-nan-\(assignment.id)",
                    kind: .malformedWall,
                    severity: .critical,
                    title: "بيانات حائط غير صالحة",
                    details: "الحائط رقم \(assignment.wallNumber) في الغرفة \(assignment.roomIndex) يحتوي قيمة هندسية غير قابلة للعرض.",
                    action: "أعد مسح الحائط أو أعده إلى هندسة RoomPlan الأصلية.",
                    assignment: assignment
                )
            } else if geometry.widthMeters < 0.25 || geometry.heightMeters < 1.50 {
                append(
                    key: "malformed-small-\(assignment.id)",
                    kind: .malformedWall,
                    severity: .warning,
                    title: "حائط قصير أو منخفض بصورة غير معتادة",
                    details: "الحائط رقم \(assignment.wallNumber): طول \(Self.centimeters(geometry.widthMeters)) سم وارتفاع \(Self.centimeters(geometry.heightMeters)) سم.",
                    action: "راجع الحائط في المخطط أو استخدم إعادة المسح الجزئي.",
                    assignment: assignment
                )
            }

            if let adjustment = overrideByAssignment[assignment.id],
               (abs(adjustment.centerOffsetAlongMeters) > 1
                    || abs(adjustment.centerOffsetNormalMeters) > 1
                    || abs(adjustment.rotationDegrees) > 45) {
                append(
                    key: "extreme-\(assignment.id)",
                    kind: .extremeManualCorrection,
                    severity: .warning,
                    title: "تصحيح هندسي كبير",
                    details: "تم تحريك أو تدوير الحائط رقم \(assignment.wallNumber) بقيمة كبيرة مقارنة بالمسح الأصلي.",
                    action: "تأكد أن التصحيح مقصود، أو أعد الحائط إلى الأصل ثم أعد مسح المنطقة.",
                    assignment: assignment
                )
            }
        }

        for (buildingWallID, group) in assignmentsByWall {
            let roomIndices = Set(group.map(\.roomIndex))
            if roomIndices.count > 2 {
                append(
                    key: "too-many-rooms-\(buildingWallID)",
                    kind: .sharedByTooManyRooms,
                    severity: .critical,
                    title: "حائط واحد مرتبط بأكثر من غرفتين",
                    details: "الحائط الفيزيائي مرتبط بالغرف: \(roomIndices.sorted().map(String.init).joined(separator: "، ")).",
                    action: "افصل الوجه المطابق خطأ أو أعد مسح إحدى الغرف المتعارضة.",
                    assignment: group.first,
                    buildingWallID: buildingWallID
                )
            }

            if roomIndices.count > 1 {
                if let record = recordByID[buildingWallID], record.source != .userConfirmed {
                    append(
                        key: "unconfirmed-thickness-\(buildingWallID)",
                        kind: .unconfirmedSharedThickness,
                        severity: .information,
                        title: "سماكة حائط مشترك غير مؤكدة يدويًا",
                        details: "السماكة الحالية \(Int((record.thicknessMeters * 100).rounded())) سم ومصدرها \(record.source.arabicTitle).",
                        action: "افتح محرر السماكات وأكد القيمة عند توفر قياس فعلي.",
                        assignment: group.first,
                        buildingWallID: buildingWallID
                    )
                }

                let confidenceValues = group.compactMap(\.matchConfidence)
                if let minimumConfidence = confidenceValues.min(), minimumConfidence < 0.55 {
                    append(
                        key: "low-confidence-\(buildingWallID)",
                        kind: .lowSharedWallConfidence,
                        severity: .warning,
                        title: "مطابقة حائط مشترك منخفضة الثقة",
                        details: "أقل درجة مطابقة \(Int((minimumConfidence * 100).rounded()))٪ بين وجهي الحائط.",
                        action: "راجع موضع الحائط والسماكة أو افصل المطابقة إذا كانت غير صحيحة.",
                        assignment: group.first,
                        buildingWallID: buildingWallID
                    )
                }

                let separations = group.compactMap(\.faceSeparationMeters)
                if let record = recordByID[buildingWallID], let measured = Self.median(separations) {
                    let difference = abs(measured - record.thicknessMeters)
                    if difference > 0.08 {
                        append(
                            key: "thickness-mismatch-\(buildingWallID)",
                            kind: .wallThicknessMismatch,
                            severity: difference > 0.15 ? .critical : .warning,
                            title: "السماكة لا تتفق مع المسافة بين الوجهين",
                            details: "السماكة المسجلة \(Int((record.thicknessMeters * 100).rounded())) سم، والمسافة المقاسة تقريبًا \(Int((measured * 100).rounded())) سم.",
                            action: "أكد السماكة الصحيحة أو عدّل محاذاة الحائط قبل التصدير.",
                            assignment: group.first,
                            buildingWallID: buildingWallID
                        )
                    }
                }
            }
        }

        let assignmentsByRoom = Dictionary(grouping: assignments, by: \.roomIndex)
        for (roomIndex, roomAssignments) in assignmentsByRoom {
            for firstIndex in roomAssignments.indices {
                for secondIndex in roomAssignments.indices where secondIndex > firstIndex {
                    let first = roomAssignments[firstIndex]
                    let second = roomAssignments[secondIndex]
                    guard first.buildingWallID != second.buildingWallID else { continue }
                    let firstGeometry = EffectiveWallGeometry(base: first.geometry, adjustment: overrideByAssignment[first.id])
                    let secondGeometry = EffectiveWallGeometry(base: second.geometry, adjustment: overrideByAssignment[second.id])
                    guard Self.areNearParallel(firstGeometry.tangent2D, secondGeometry.tangent2D) else { continue }
                    let normalDistance = abs(simd_dot(secondGeometry.center2D - firstGeometry.center2D, firstGeometry.normal2D))
                    guard normalDistance < 0.12 else { continue }
                    let overlap = Self.overlapRatio(firstGeometry, secondGeometry)
                    guard overlap > 0.65 else { continue }
                    append(
                        key: "duplicate-\(roomIndex)-\([first.id.uuidString, second.id.uuidString].sorted().joined(separator: "-"))",
                        kind: .duplicatedWall,
                        severity: .warning,
                        title: "حائطان متراكبان داخل الغرفة",
                        details: "الحائطان \(first.wallNumber) و\(second.wallNumber) متوازيان ومتداخلان بنسبة \(Int((overlap * 100).rounded()))٪.",
                        action: "راجع موضع الحائطين، صحح أحدهما هندسيًا، أو أعد مسح الجزء المتعارض.",
                        assignment: first,
                        roomIndex: roomIndex
                    )
                }
            }
        }

        for opening in manualOpenings {
            guard let assignment = assignments.first(where: {
                $0.wallIdentifier == opening.sourceWallIdentifier
                    && $0.roomIndex == opening.sourceRoomIndex
            }) ?? assignments.first(where: {
                $0.buildingWallID == opening.buildingWallID && $0.roomIndex == opening.sourceRoomIndex
            }) ?? assignments.first(where: { $0.buildingWallID == opening.buildingWallID }) else {
                append(
                    key: "opening-missing-wall-\(opening.id)",
                    kind: .openingOutsideWall,
                    severity: .critical,
                    title: "عنصر يدوي بلا حائط",
                    details: "\(opening.kind.arabicTitle) اليدوي لم يعد مرتبطًا بحائط موجود في المشروع.",
                    action: "احذف العنصر وأعد إضافته على الحائط الصحيح.",
                    roomIndex: opening.sourceRoomIndex,
                    buildingWallID: opening.buildingWallID
                )
                continue
            }
            let geometry = EffectiveWallGeometry(base: assignment.geometry, adjustment: overrideByAssignment[assignment.id])
            let centerOffset = (opening.positionRatio - 0.5) * Double(geometry.widthMeters)
            let left = centerOffset - opening.widthMeters / 2
            let right = centerOffset + opening.widthMeters / 2
            let halfWall = Double(geometry.widthMeters) / 2
            if left < -halfWall - 0.01 || right > halfWall + 0.01 {
                append(
                    key: "opening-outside-\(opening.id)",
                    kind: .openingOutsideWall,
                    severity: .critical,
                    title: "باب أو فتحة خارج حدود الحائط",
                    details: "عرض أو موضع \(opening.kind.arabicTitle) يتجاوز طول الحائط رقم \(assignment.wallNumber).",
                    action: "عدّل موضع العنصر أو عرضه من مدير الأبواب والفتحات.",
                    assignment: assignment
                )
            }
            if opening.sillHeightMeters + opening.heightMeters > Double(geometry.heightMeters) + 0.01 {
                append(
                    key: "opening-height-\(opening.id)",
                    kind: .openingHeightConflict,
                    severity: .critical,
                    title: "ارتفاع فتحة يتجاوز الحائط",
                    details: "الارتفاع الكلي للعنصر أكبر من ارتفاع وجه الحائط في الغرفة.",
                    action: "صحح ارتفاع العنصر أو ارتفاع الحائط.",
                    assignment: assignment
                )
            }
            if let connected = opening.connectsRoomIndex,
               connected == opening.sourceRoomIndex || connected < 1 || connected > rooms.count {
                append(
                    key: "opening-connection-\(opening.id)",
                    kind: .invalidRoomConnection,
                    severity: .warning,
                    title: "ربط باب بين غرف غير صالح",
                    details: "الغرفة الأخرى المحددة للعنصر غير موجودة أو هي نفس الغرفة.",
                    action: "اختر الغرفة المقابلة الصحيحة أو اترك الربط غير محدد.",
                    assignment: assignment
                )
            }
        }

        for (offset, room) in rooms.enumerated() {
            let roomIndex = offset + 1
            let wallIDs = Set(room.walls.map(\.identifier))
            func inspect(_ surfaces: [CapturedRoom.Surface], name: String) {
                for surface in surfaces where !suppressedSurfaceIdentifiers.contains(surface.identifier) {
                    guard let parent = surface.parentIdentifier, wallIDs.contains(parent) else {
                        append(
                            key: "orphan-\(surface.identifier)",
                            kind: .orphanDetectedOpening,
                            severity: .warning,
                            title: "\(name) غير مرتبط بحائط واضح",
                            details: "العنصر المكتشف في الغرفة \(roomIndex) لا يملك Parent Wall صالحًا في نتيجة RoomPlan الحالية.",
                            action: "اخفِ العنصر المكتشف وأضف عنصرًا يدويًا عند الحاجة.",
                            roomIndex: roomIndex
                        )
                        continue
                    }
                }
            }
            inspect(room.doors, name: "باب مكتشف")
            inspect(room.openings, name: "فتحة مكتشفة")
            inspect(room.windows, name: "نافذة مكتشفة")
        }

        if rooms.count > 1 {
            var graph: [Int: Set<Int>] = Dictionary(uniqueKeysWithValues: (1...rooms.count).map { ($0, []) })
            for group in assignmentsByWall.values {
                let roomIndices = Array(Set(group.map(\.roomIndex))).sorted()
                guard roomIndices.count > 1 else { continue }
                for first in roomIndices {
                    for second in roomIndices where second != first { graph[first, default: []].insert(second) }
                }
            }
            for opening in manualOpenings {
                guard let other = opening.connectsRoomIndex,
                      other >= 1, other <= rooms.count, other != opening.sourceRoomIndex else { continue }
                graph[opening.sourceRoomIndex, default: []].insert(other)
                graph[other, default: []].insert(opening.sourceRoomIndex)
            }
            var visited: Set<Int> = [1]
            var queue = [1]
            while let current = queue.first {
                queue.removeFirst()
                for neighbor in graph[current, default: []] where visited.insert(neighbor).inserted {
                    queue.append(neighbor)
                }
            }
            for roomIndex in 1...rooms.count where !visited.contains(roomIndex) {
                append(
                    key: "disconnected-room-\(roomIndex)",
                    kind: .disconnectedRoom,
                    severity: .warning,
                    title: "غرفة غير مرتبطة بباقي المشروع",
                    details: "لم يُعثر على حائط مشترك أو باب يدوي يربط الغرفة \(roomIndex) بالشبكة التي تبدأ من الغرفة 1.",
                    action: "راجع الحائط المشترك أو اربط بابًا بالغرفة المقابلة.",
                    roomIndex: roomIndex
                )
            }
        }

        let profileByRoom = Dictionary(uniqueKeysWithValues: levelProfiles.map { ($0.roomIndex, $0) })
        for (offset, room) in rooms.enumerated() {
            let roomIndex = offset + 1
            if room.floors.isEmpty {
                append(
                    key: "missing-floor-\(roomIndex)",
                    kind: .missingFloorSurface,
                    severity: .information,
                    title: "أرضية RoomPlan غير متوفرة",
                    details: "لم يسجل RoomPlan سطح أرضية صريحًا للغرفة \(roomIndex)، لذلك استُنتج المنسوب من أسفل الحوائط.",
                    action: "راجع منسوب الأرضية يدويًا من محرر الأرضية والسقف.",
                    roomIndex: roomIndex
                )
            }

            guard let profile = profileByRoom[roomIndex] else { continue }
            if profile.finishedCeilingHeightMeters > profile.structuralCeilingHeightMeters + 0.01 {
                append(
                    key: "ceiling-profile-\(roomIndex)",
                    kind: .ceilingHeightConflict,
                    severity: .critical,
                    title: "سقف التشطيب أعلى من السقف الإنشائي",
                    details: "ارتفاع التشطيب \(Self.centimeters(Float(profile.finishedCeilingHeightMeters))) سم بينما الإنشائي \(Self.centimeters(Float(profile.structuralCeilingHeightMeters))) سم.",
                    action: "صحح ارتفاع التشطيب أو الارتفاع الإنشائي للغرفة.",
                    roomIndex: roomIndex
                )
            }

            let seed = RoomLevelGeometrySeed.make(room: room)
            for zone in ceilingZones where zone.roomIndex == roomIndex {
                if zone.heightAboveFloorMeters > profile.structuralCeilingHeightMeters + 0.01 {
                    append(
                        key: "ceiling-zone-height-\(zone.id)",
                        kind: .ceilingHeightConflict,
                        severity: .critical,
                        title: "منطقة سقف تتجاوز الارتفاع الإنشائي",
                        details: "منطقة \(zone.name.isEmpty ? zone.kind.arabicTitle : zone.name) أعلى من السقف الإنشائي للغرفة.",
                        action: "خفّض ارتفاع المنطقة أو صحح الارتفاع الإنشائي.",
                        roomIndex: roomIndex
                    )
                }
                let centerDistance = hypot(zone.centerX - seed.centerX, zone.centerZ - seed.centerZ)
                let roomRadius = hypot(seed.widthMeters, seed.depthMeters) / 2
                let zoneRadius = hypot(zone.widthMeters, zone.depthMeters) / 2
                if centerDistance + zoneRadius > roomRadius * 1.35 {
                    append(
                        key: "ceiling-zone-outside-\(zone.id)",
                        kind: .ceilingZoneOutsideRoom,
                        severity: .warning,
                        title: "منطقة سقف خارج حدود الغرفة تقريبًا",
                        details: "مركز أو أبعاد منطقة \(zone.name.isEmpty ? zone.kind.arabicTitle : zone.name) تتجاوز بصمة أرضية الغرفة المتاحة.",
                        action: "راجع المركز X وZ والأبعاد من محرر الأرضية والسقف.",
                        roomIndex: roomIndex
                    )
                }
            }
        }

        for group in assignmentsByWall.values {
            let roomIndices = Array(Set(group.map(\.roomIndex))).sorted()
            guard roomIndices.count == 2,
                  let first = profileByRoom[roomIndices[0]],
                  let second = profileByRoom[roomIndices[1]] else { continue }
            let difference = abs(first.floorElevationMeters - second.floorElevationMeters)
            if difference > 0.08 {
                append(
                    key: "floor-level-\(group[0].buildingWallID)",
                    kind: .floorLevelMismatch,
                    severity: .warning,
                    title: "فرق منسوب بين غرفتين متجاورتين",
                    details: "فرق منسوب الأرضية بين الغرفتين \(roomIndices[0]) و\(roomIndices[1]) يساوي \(Int((difference * 100).rounded())) سم.",
                    action: "أكد وجود درجة فعلية أو صحح منسوب إحدى الغرف.",
                    assignment: group.first
                )
            }
        }

        return issues.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return ($0.roomIndex ?? Int.max, $0.title) < ($1.roomIndex ?? Int.max, $1.title)
        }
    }

    private static func centimeters(_ value: Float) -> Int { Int((value * 100).rounded()) }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func areNearParallel(_ first: SIMD2<Float>, _ second: SIMD2<Float>) -> Bool {
        abs(simd_dot(first, second)) > cos(Float.pi / 60) // 3 degrees
    }

    private static func overlapRatio(_ first: EffectiveWallGeometry, _ second: EffectiveWallGeometry) -> Double {
        let tangent = first.tangent2D
        let firstCenter = simd_dot(first.center2D, tangent)
        let secondCenter = simd_dot(second.center2D, tangent)
        let firstRange = (Double(firstCenter) - Double(first.widthMeters) / 2)...(Double(firstCenter) + Double(first.widthMeters) / 2)
        let secondRange = (Double(secondCenter) - Double(second.widthMeters) / 2)...(Double(secondCenter) + Double(second.widthMeters) / 2)
        let overlap = max(0, min(firstRange.upperBound, secondRange.upperBound) - max(firstRange.lowerBound, secondRange.lowerBound))
        return overlap / max(min(Double(first.widthMeters), Double(second.widthMeters)), 0.01)
    }
}
