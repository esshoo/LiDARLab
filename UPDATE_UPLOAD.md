# رفع تحديث 3ELiDAR 0.13.0

## الطريقة الأسرع

1. فك ضغط ملف المشروع الكامل.
2. انسخ مجلد `3ELiDAR` إلى مستودع المشروع أو استبدل محتوى المستودع بمحتوياته.
3. ارفع التغييرات إلى GitHub.
4. شغّل Workflow: **Build LiDAR Lab Unsigned IPA**.
5. نزّل ملف IPA وثبّته بالطريقة التجريبية المعتادة.

## أهم ملفات مرحلة مركز المراجعة

- `project.yml`
- `LiDARLab/Features/RoomScan/RoomScanView.swift`
- `LiDARLab/Features/RoomScan/RoomScanViewModel.swift`
- `LiDARLab/Features/RoomScan/RoomScanReviewModels.swift`
- `LiDARLab/Features/RoomScan/RoomScanProjectReviewView.swift`
- `LiDARLab/Shared/QuickLookPreview.swift`
- `ROOMSCAN_REVIEW_PHASE5.md`

يمكن استخدام `ROOMSCAN_REVIEW_PHASE5.patch` بدل استبدال المشروع الكامل عند العمل داخل Git.

لا تضف ملف Entitlements ولا تفعّل App Groups في Signing & Capabilities عند استخدام التوقيع المجاني.
