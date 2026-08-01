# رفع تحديث 3ELiDAR 0.12.0

## الطريقة الأسرع

1. فك ضغط ملف المشروع الكامل.
2. انسخ مجلد `3ELiDAR` إلى مستودع المشروع أو استبدل محتوى المستودع بمحتوياته.
3. ارفع التغييرات إلى GitHub.
4. شغّل Workflow: **Build LiDAR Lab Unsigned IPA**.
5. نزّل ملف IPA وثبّته بالطريقة التجريبية المعتادة.

## أهم ملفات مرحلة الاستعادة الدائمة

- `project.yml`
- `LiDARLab/Features/RoomScan/RoomScanView.swift`
- `LiDARLab/Features/RoomScan/RoomScanViewModel.swift`
- `LiDARLab/Features/RoomScan/RoomScanFragmentModels.swift`
- `LiDARLab/Features/RoomScan/RoomCaptureViewContainer.swift`
- `ROOMSCAN_WORLD_MAP_PHASE4.md`

يمكن استخدام `WORLD_MAP_RECOVERY_PHASE4.patch` بدل استبدال المشروع الكامل عند العمل داخل Git.

لا تضف ملف Entitlements ولا تفعّل App Groups في Signing & Capabilities عند استخدام التوقيع المجاني.
