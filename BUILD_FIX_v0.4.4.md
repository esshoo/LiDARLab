# إصلاح بناء v0.4.4

يعالج هذا الإصدار أخطاء عزل `MainActor` التي ظهرت في Xcode 16.4 عند إنشاء نسخ ثابتة من إعدادات وإحصائيات `UnifiedScanViewModel`.

## السبب

`UnifiedScanViewModel` معزول على `MainActor`، بينما مُهيئات:

- `UnifiedScanSettingsDraft`
- `UnifiedScanStatsSnapshot`

كانت غير معزولة، لذلك منع Swift الوصول إلى خصائص الـViewModel من داخلها.

## الإصلاح

تمت إضافة `@MainActor` إلى مُهيئي النسختين الثابتتين. لا يتغير سلوك التسجيل أو الإرسال أو حفظ البيانات.

## النسخة

- Version: 0.40.4
- Build: 44
