# تقرير دمج القياس المتعدد — 0.17.0

## المصدران

- قاعدة المشروع: `3ELiDAR 0.16.1` وتشمل جميع تعديلات RoomScan.
- تحديث المستخدم: `3ELiDAR-v0.9.0-update-only` لوظيفة القياس المتعدد.

## سياسة الدمج

- لم يتم نسخ أي ملف RoomScan من تحديث القياس.
- الملفات المشتركة دُمجت على مستوى التغيير بدل استبدالها عندما كان ذلك قد يعيد أوصاف RoomScan القديمة.
- تم الاحتفاظ بنسخ الملفات السابقة في `_backup/Measurement_pre_merge_0.16.1`.

## الملفات الجديدة

- `LiDARLab/Features/Measure/MeasurementARViewContainer.swift`
- `LiDARLab/Features/Measure/MeasurementModels.swift`
- `LiDARLab/Features/Measure/MeasurementViewModel.swift`
- `TEST_MEASUREMENTS.md`

## الملفات المعدلة

- `LiDARLab/Features/Measure/DistanceMeasureView.swift`
- `LiDARLab/Core/Models/LiDARFeature.swift`
- `LiDARLab/Core/Storage/LiDARLabStorage.swift`
- `LiDARLab/Core/Storage/ThreeEStorageConstants.swift`
- `LiDARLab/Features/Export/ExportCenterView.swift`
- `LiDARLab/Features/Export/ExportCenterViewModel.swift`
- `project.yml`

## ملفات RoomScan

لم يتم تعديل أي ملف داخل `LiDARLab/Features/RoomScan`.
