# Validation Notes — 0.8.1

تم تنفيذ الفحوص التالية:

- تحليل Syntax لجميع ملفات Swift وعددها 48 باستخدام Swift 6.2 في وضع parser.
- التحقق من صحة `project.yml` كملف YAML.
- التحقق من صحة `LiDARLab/Info.plist` كملف Property List.
- التحقق من Display Name: `3ELiDAR`.
- التحقق من Bundle Identifier: `com.essam.3E.LiDARLab`.
- التحقق من URL Scheme: `lidar`.
- التحقق من عدم وجود App Group entitlement أو اعتماد إجباري عليه.
- التحقق من وجود القيمة المستقبلية `group.com.essam.3e` داخل طبقة التخزين فقط.
- التحقق من إزالة مسارات Documents المباشرة من وظائف صورة العمق ومسح الغرفة.
- التحقق من بقاء Sandbox الحالي `Documents/LiDARLab` كحل مؤقت، دون إنشاء مجلد 3E مزيف داخله.
- التحقق من إنشاء بنية Apps وShared وSystem دون أي عمليات حذف.
- التحقق من دمج سجل `lidar` داخل registry وعدم استبدال سجلات التطبيقات الأخرى.
- التحقق من استخدام الكتابة الذرية لملف `registry.json`.
- التحقق من رفض المسارات المطلقة و`.` و`..` وbackslash وcolon، وفحص بقاء المسار داخل جذر 3E.
- التحقق من أن ملفات نتائج LiDAR الحالية ما زالت تحمل الأسماء والصيغ نفسها.
- فحص سلامة ملفات ZIP بعد إنشائها.

يتبقى تشغيل GitHub Actions باستخدام Xcode 16.4 وiOS SDK 18.5 للتأكد من Type-check والربط الكامل، ثم اختبار Security-Scoped Bookmark وفتح URL Scheme على جهاز iPhone أو iPad فعلي.

## إصلاح Bookmark على iOS

- أزيل `BookmarkCreationOptions.withSecurityScope` لأنه غير متاح في iOS SDK 18.5.
- أزيل `BookmarkResolutionOptions.withSecurityScope` للسبب نفسه.
- يستخدم الإنشاء `minimalBookmark` والاستعادة `withoutUI`.
- يبقى `startAccessingSecurityScopedResource()` مطلوبًا بعد الاختيار وبعد الاستعادة.
- لا توجد App Group Entitlements في المشروع.
