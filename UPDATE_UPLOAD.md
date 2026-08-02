# رفع نسخة 3ELiDAR 0.19.0 — الغرف الثابتة والفتحات الحقيقية

1. فك ضغط ملف المشروع الكامل.
2. استبدل محتوى مستودع 3ELiDAR بالمجلد الجديد.
3. ارفع الملفات إلى GitHub.
4. شغّل Workflow: **Build LiDAR Lab Unsigned IPA**.
5. بعد نجاح البناء اختبر تحريك غرفة ككتلة واحدة، محاذاتها بالحائط المشترك، ثم إضافة باب وتصدير PDF/DXF.

أهم الملفات الجديدة:

- `LiDARLab/Features/RoomScan/RoomRigidTransformModels.swift`
- `LiDARLab/Features/RoomScan/RoomRigidTransformEditorView.swift`
- `LiDARLab/Features/RoomScan/RoomScanProject3DView.swift`
- `LiDARLab/Features/RoomScan/RoomScanProjectExport.swift`

لا تضف Entitlements ولا تفعّل App Groups عند استخدام التوقيع المجاني.

---

# رفع نسخة 3ELiDAR 0.17.0 المدمجة

هذه النسخة تحتوي على جميع مراحل RoomScan حتى 0.16.1، بالإضافة إلى وظيفة القياس المتعدد المرسلة في تحديث 0.9.0.

## الطريقة الأسرع

1. فك ضغط ملف المشروع الكامل.
2. استبدل محتوى مستودع 3ELiDAR بمحتويات المجلد.
3. ارفع التغييرات إلى GitHub.
4. شغّل Workflow: **Build LiDAR Lab Unsigned IPA**.
5. نزّل ملف IPA وثبّته بالطريقة التجريبية المعتادة.

## أهم ملفات الدمج الجديدة

- `LiDARLab/Features/Measure/DistanceMeasureView.swift`
- `LiDARLab/Features/Measure/MeasurementARViewContainer.swift`
- `LiDARLab/Features/Measure/MeasurementModels.swift`
- `LiDARLab/Features/Measure/MeasurementViewModel.swift`
- `LiDARLab/Core/Storage/LiDARLabStorage.swift`
- `LiDARLab/Core/Storage/ThreeEStorageConstants.swift`
- `LiDARLab/Features/Export/ExportCenterView.swift`
- `LiDARLab/Features/Export/ExportCenterViewModel.swift`
- `LiDARLab/Core/Models/LiDARFeature.swift`

لا تضف ملف Entitlements ولا تفعّل App Groups عند استخدام التوقيع المجاني.

---

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
