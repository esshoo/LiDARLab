# RoomScan Phase 7 — Rigid Rooms & True Openings

Version: **0.19.0**  
Build: **24**

## Added

- Move and rotate any captured room as one rigid block.
- Lock room position to protect it from automatic alignment.
- Suggest alignment using the strongest shared-wall match.
- Persist room transforms in `Review/room-transforms.json`.
- Apply room transforms to 2D, SceneKit 3D, floors, ceilings, manual openings, correction scans, review issues, and every reviewed export format.
- Build real wall voids in SceneKit by decomposing a wall into solid cells around door/window/opening rectangles.
- Split 2D wall geometry at openings in the live review and in PDF/PNG/DXF exports.
- Export room translation, rotation, and lock state in JSON and `rooms.csv`.

## Non-destructive rule

`CapturedRoom`, `room.json`, and RoomPlan USDZ files are unchanged. All edits remain app-owned review layers.

## Device test

1. Scan two connected rooms and confirm the shared wall.
2. Open Review → 2D → select room 2 → Position.
3. Unlock room 2 and use shared-wall alignment.
4. Save and verify that the entire room, floor, ceiling zones, doors, and correction layers move together.
5. Add a manual door and verify that SceneKit displays a real empty wall opening.
6. Export and confirm that PDF/PNG/DXF contain a wall gap at the opening.
7. Close and reopen the app and confirm that `room-transforms.json` restores the same position.
