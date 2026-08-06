# التحقق من v0.5.2

- Swift Parse: نجح لكل ملفات Swift وعددها 86.
- Xcode Build الفعلي: لم يُشغّل في بيئة Linux؛ يلزم GitHub Actions / Xcode 16.4.
- Info.plist: سليم.
- صورة الكاميرا المخفية 1×1: غير موجودة في Stable Core.
- `senderBusy` أو `sendInProgress` داخل Stable Core: صفر.
- `resetTracking` داخل Stable Core: مرة واحدة فقط عند إنشاء Generation جديدة صراحةً.
- RoomScan: الملف الوحيد المعدّل هو `RoomScanView.swift` لإضافة زر الكشاف وإطفائه عند الخروج/الخلفية.
- منطق RoomScan وRoomPlan والحوائط والحفظ: لم يتغير.
- ComputerBridge الأصلي: لم تتغير ملفاته.
- Receiver Python Tests: 17/17.
- Receiver Integration: نجح Hello Ack وSession Start Ack وPose Ack ورسم Segments منفصلة.
- JavaScript Syntax: سليم.
- Python Compile: سليم.

## ملاحظة
طبقة الألوان فوق الكاميرا تعرض عينات LiDAR للـFrame الحالية. التغطية السابقة تبقى ظاهرة في الخريطة المصغرة؛ لم تتم إضافة Point Cloud تاريخية ثقيلة فوق الكاميرا في هذه النسخة حتى لا نعيد مشكلة الحرارة والتوقف.
