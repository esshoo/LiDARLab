# RoomScan Phase 6 - Final Reviewed Project Export

Version: **0.18.0**  
Build: **23**

## Output folder

`Exports/RoomScan-Reviewed-<timestamp>/`

## Generated files

- `floor-plan.pdf` - scaled plan plus paginated room/wall/issue report.
- `floor-plan.png` - high-resolution 2D plan.
- `project-model.json` - reviewed non-destructive building model.
- `floor-plan.dxf` - meter-based CAD plan with separate layers.
- `rooms.csv`
- `walls.csv`
- `openings.csv`
- `ceiling-zones.csv`
- `issues.csv`
- `export-manifest.json`

## Data rules

- RoomPlan source JSON and USDZ files are never rewritten.
- Physical walls are grouped by `buildingWallID`.
- Shared wall faces are combined into one exported physical wall.
- Confirmed thickness and wall-geometry overrides control the exported wall rectangle.
- Suppressed RoomPlan openings remain in JSON/CSV with `suppressed=true` but are excluded from the drawing.
- Manual openings, room levels, ceiling zones, accepted correction scans and review issues are included.
- CSV files include a UTF-8 BOM for Arabic-compatible spreadsheet import.
- DXF uses meters and English layer names for CAD compatibility.

## Device test

1. Finish a multi-room project.
2. Open Review Center > Export.
3. Create the final package.
4. Preview the PDF.
5. Share all files.
6. Open the DXF in a CAD viewer and verify units/layers.
7. Reopen JSON and CSV files from Files or Export Center.
