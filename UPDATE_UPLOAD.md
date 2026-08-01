# رفع تحديث 3ELiDAR 0.11.0

## الطريقة الأسرع

1. فك ضغط ملف المشروع الكامل.
2. انسخ مجلد `3ELiDAR` إلى مستودع المشروع أو استبدل محتوى المستودع بمحتوياته.
3. ارفع التغييرات إلى GitHub.
4. شغّل Workflow: **Build LiDAR Lab Unsigned IPA**.
5. نزّل ملف IPA وثبّته بالطريقة التجريبية المعتادة.

## أهم ملفات مرحلة التوقف المؤقت

- `project.yml`
- `LiDARLab/Features/RoomScan/RoomScanView.swift`
- `LiDARLab/Features/RoomScan/RoomScanViewModel.swift`
- `LiDARLab/Features/RoomScan/RoomWallMetadata.swift`
- `LiDARLab/Features/RoomScan/RoomScanFragmentModels.swift`
- `ROOMSCAN_PAUSE_RESUME_PHASE3.md`

يمكن استخدام `PAUSE_RESUME_PHASE3.patch` بدل استبدال المشروع الكامل عند العمل داخل Git.

لا تضف ملف Entitlements ولا تفعّل App Groups في Signing & Capabilities عند استخدام التوقيع المجاني.
