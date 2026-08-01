# اختبار ربط 3ELiDAR مع مجموعة 3E

## 1. اختبار اختيار المجلد

1. ثبّت النسخة الجديدة وافتح **3ELiDAR**.
2. من بطاقة **تخزين مجموعة 3E** اضغط **اختيار مجلد 3E**.
3. اختر مجلد `3E` نفسه المستخدم في التطبيقات الأخرى، وليس `Apps` أو `LiDARLab` داخله.
4. يجب أن تتحول الحالة إلى **مجلد 3E في Files**.

تحقق من إنشاء البنية التالية دون حذف أي ملفات موجودة:

```text
3E/Apps/LiDARLab/Captures
3E/Apps/LiDARLab/Rooms
3E/Apps/LiDARLab/Recordings
3E/Apps/LiDARLab/Exports
3E/Apps/LiDARLab/Projects
3E/Shared/Inbox
3E/Shared/Outbox
3E/Shared/Projects
3E/Shared/Media
3E/System/registry.json
```

## 2. اختبار registry.json

افتح `3E/System/registry.json` وتأكد من وجود سجل التطبيق:

```json
{
  "appKey": "lidar",
  "displayName": "3ELiDAR",
  "bundleIdentifier": "com.essam.3E.LiDARLab",
  "urlScheme": "lidar",
  "folder": "Apps/LiDARLab"
}
```

يجب أن تبقى سجلات `RoomElectrical` و`LocalWeb` وأي تطبيقات أخرى كما هي.

## 3. اختبار استعادة الصلاحية

1. أغلق التطبيق بالكامل من App Switcher.
2. افتحه مرة أخرى.
3. يجب أن تظهر حالة **تمت استعادة صلاحية مجلد 3E تلقائيًا** دون فتح منتقي الملفات.
4. لاختبار الفشل، انقل مجلد 3E أو ألغِ صلاحية مزود الملفات ثم افتح التطبيق؛ يجب أن يطلب اختيار المجلد من جديد.

## 4. اختبار وظائف LiDAR بعد الربط

- التقط صورة عمق، ثم تحقق من ظهورها داخل `3E/Apps/LiDARLab/Captures`.
- صدّر مسح غرفة، ثم تحقق من `3E/Apps/LiDARLab/Rooms`.
- سجّل جلسة، ثم تحقق من `3E/Apps/LiDARLab/Recordings`.
- أنشئ فهرسًا من مركز التصدير، ثم تحقق من `3E/Apps/LiDARLab/Exports`.

يجب أن تبقى أسماء الملفات وصيغها كما كانت في النسخ السابقة.

## 5. اختبار URL Scheme

يمكن كتابة الروابط في Safari أو Notes والضغط عليها، أو استخدام تطبيق Shortcuts بإجراء **Open URLs**.

### فتح التطبيق والعودة للرئيسية

```text
lidar://open
```

### فتح ملف مشترك موجود

```text
lidar://open?path=Shared/Projects/FileName
```

### فتح ملف تابع للتطبيق

```text
lidar://open?path=Apps/LiDARLab/Projects/FileName
```

الملف يجب أن يكون موجودًا. الملفات تظهر عبر Quick Look، والمجلدات تعرض محتوياتها داخل التطبيق.

### اختبارات الرفض

يجب أن يعرض التطبيق رسالة رفض لهذه الأمثلة:

```text
lidar://open?path=/Shared/Projects/FileName
lidar://open?path=../Shared/Projects/FileName
lidar://open?path=Shared/../System/registry.json
lidar://open?path=file://outside
```

## 6. App Group

لا تختبر App Group في هذه النسخة؛ المعرف `group.com.essam.3e` موجود في الكود للمستقبل فقط، ولا يوجد ملف Entitlements أو اعتماد عليه في التشغيل الحالي.

## 7. اختبار سماكات الحوائط المشتركة — 0.10.0

1. افتح **مسح متعدد الغرف** واضغط **بدء مسح المبنى**.
2. اختر 25 سم، ثم ابدأ الغرفة الأولى.
3. ثبت الغرفة الأولى، وافتح **مراجعة سماكات حوائط الغرفة الأخيرة**.
4. تأكد أن الحوائط غير المشتركة تعرض مصدر **افتراضي المبنى** وقيمة 25 سم.
5. ابدأ الغرفة الثانية من الجهة المقابلة لحائط واضح، واختر 15 سم كافتراضي الغرفة.
6. ثبت الغرفة الثانية.
7. يجب أن تعرض الحوائط الجديدة 15 سم، بينما الحائط المطابق للغرفة الأولى يعرض **مشترك** ويرث 25 سم.
8. غيّر سماكة الحائط المشترك إلى 35 سم.
9. راجع ملفي:

```text
FrozenRooms/Room-01/wall-properties.json
FrozenRooms/Room-02/wall-properties.json
```

يجب أن يشيرا إلى نفس `buildingWallID` وقيمة 0.35 متر.

10. افتح `wall-metadata.json` وتأكد من وجود:

- `buildingDefaultThicknessMeters`
- `wallRecords`
- `assignments`
- `matchConfidence`
- `faceSeparationMeters`

11. اختبر حائطين متوازيين لكن غير متداخلين؛ يجب ألا يعتبرهما التطبيق حائطًا مشتركًا.
12. اختبر غرفتين بارتفاعي سقف مختلفين؛ يجب أن تستمر المطابقة إذا كان هناك تداخل رأسي كافٍ، دون تغيير ارتفاع أي غرفة.
