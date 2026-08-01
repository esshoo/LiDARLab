# RoomScan Multi-Room — Phase 1

This test changes only the existing `LiDARLab/Features/RoomScan` feature.

## Goal

Prevent a later room scan from continuously reshaping walls and ceiling heights that were already accepted in an earlier room.

## Implemented workflow

1. One shared `ARSession` is created for the whole building workflow.
2. Each room is scanned as a separate RoomPlan session.
3. The user must finish the current room before crossing its door.
4. `stop(pauseARSession: false)` keeps world tracking alive between rooms.
5. Every processed `CapturedRoom` is appended to a frozen array and automatically saved as JSON.
6. At the end, `StructureBuilder` creates a merged comparison model, but it does not replace the frozen room results.

## Automatic files

`Rooms/MultiRoom-<timestamp>/`

- `manifest.json`
- `FrozenRooms/Room-01/room.json`
- `FrozenRooms/Room-02/room.json`
- `structure.json` after a successful merge

## Not implemented yet

- Manual door/portal anchors from both sides.
- Wall thickness estimation from two opposite wall faces.
- Independent ceiling zones and gypsum detection.
- Rigid-room alignment solver outside StructureBuilder.
- ARKit mesh evidence and confidence scoring.

Those belong to the next test after confirming that separate frozen room scans improve stability.
