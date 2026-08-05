# Validation v0.5.0

- Swift syntax parse: 83/83 succeeded.
- RoomScan changed/added/deleted: 0/0/0.
- Original v0.3.1 ComputerBridge changed: 0.
- `senderBusy` in Stable Core: no.
- `sendInProgress` in Stable Core: no.
- Pose policy: record every ARFrame before Depth, network, and UI.
- Processing policy: manual after finish only.
- Raw policy: append-only without silent deletion.

`xcodebuild` cannot run in the current Linux container; GitHub Actions/Xcode 16.4 remains the final compile test.