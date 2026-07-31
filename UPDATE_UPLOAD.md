# رفع تحديث LiDAR Lab 0.3.0

## باستخدام الحزمة الكاملة

1. فك ضغط `LiDARLab-v0.3.0.zip`.
2. ارفع **محتويات** مجلد `LiDARLab_v0.3.0` إلى جذر المستودع `esshoo/LiDARLab`.
3. وافق على استبدال الملفات القديمة.
4. افتح GitHub Actions وشغّل `Build LiDAR Lab Unsigned IPA`.

## باستخدام حزمة التحديث فقط

1. فك ضغط `LiDARLab-v0.3.0-update-only.zip` داخل نسخة المستودع على جهازك.
2. وافق على دمج مجلد `LiDARLab` واستبدال الملفات.
3. ارفع الملفات الجديدة والمعدلة إلى الفرع `main` أو إلى فرع اختبار.
4. شغّل GitHub Actions.

## الملفات الجديدة أو المعدلة

- `LiDARLab/Features/Measure/DistanceMeasureView.swift`
- `LiDARLab/Features/Level/LevelToolView.swift`
- `LiDARLab/Features/Level/LevelToolViewModel.swift`
- `LiDARLab/Features/Planes/PlaneDetectionView.swift`
- `LiDARLab/Core/Models/LiDARFeature.swift`
- `LiDARLab/Features/Home/FeatureRouterView.swift`
- `project.yml`
- `README.md`
- `CHANGELOG.md`
- `VALIDATION.md`

يفضل الاحتفاظ بالـcommit الناجح السابق `035a06f3f9ff389cf1a6c741d1d4ca8d18387fee` كنقطة رجوع قبل رفع التحديث.
