# رفع تحديث 3ELiDAR 0.8.0

## الطريقة الأسرع

1. فك ضغط `3ELiDAR-v0.8.0-update-only.zip`.
2. انسخ محتوياته إلى جذر مستودع `esshoo/LiDARLab`.
3. وافق على استبدال الملفات الموجودة.
4. ارفع التغييرات إلى GitHub.
5. شغّل Workflow: **Build LiDAR Lab Unsigned IPA**.

## أهم الملفات المعدلة

- `project.yml`
- `LiDARLab/Info.plist`
- `LiDARLab/App/LiDARLabApp.swift`
- `LiDARLab/Core/Storage/LiDARLabStorage.swift`
- `LiDARLab/Core/Storage/ThreeEStorageConstants.swift`
- `LiDARLab/Core/Storage/ThreeEFolderPicker.swift`
- `LiDARLab/Core/Storage/ThreeERegistry.swift`
- `LiDARLab/Core/Storage/ThreeEURLRouter.swift`
- `LiDARLab/Features/Home/HomeView.swift`
- `LiDARLab/Features/Home/ThreeEStorageStatusView.swift`
- `LiDARLab/Features/DepthPhoto/DepthPhotoViewModel.swift`
- `LiDARLab/Features/RoomScan/RoomScanViewModel.swift`
- `LiDARLab/Features/Export/ExportCenterView.swift`
- `LiDARLab/Features/Export/ExportCenterViewModel.swift`

لا تضف ملف entitlements ولا تفعّل App Groups في Signing & Capabilities عند استخدام التوقيع المجاني.
