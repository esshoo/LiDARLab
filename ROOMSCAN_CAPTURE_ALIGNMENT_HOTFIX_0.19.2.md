# RoomScan Capture & Alignment Hotfix — 0.19.2 (Build 26)

هذا التحديث مخصص للإصلاح فقط، ولا يضيف وظيفة عامة خارج المسح المكاني.

## الإصلاحات

1. أثناء المسح النشط تختفي لوحة ملخص المبنى والإحصائيات والتصدير والمراجعة، وتظهر الكاميرا بملء الشاشة مع شريط حالة صغير وأزرار الإيقاف/الإنهاء فقط.
2. نموذج SceneKit التفاعلي يحسب تحويلًا صلبًا من كل غرفة مجمدة إلى الغرفة المقابلة داخل `CapturedStructure.rooms`، ثم يطبق تعديل المستخدم بعده مرة واحدة فقط.
3. معاينة Apple Quick Look الأصلية تحتوي على شريط علوي وزر **تم** واضح للعودة إلى مركز المراجعة.

## ملفات الكود المعدلة

- `LiDARLab/Features/RoomScan/RoomScanView.swift`
- `LiDARLab/Features/RoomScan/RoomScanProject3DView.swift`
- `LiDARLab/Features/RoomScan/RoomScanProjectReviewView.swift`
- `LiDARLab/Features/RoomScan/RoomRigidTransformModels.swift`
- `project.yml`

## اختبار الجهاز المطلوب

- ابدأ الغرفة الثانية وتأكد أن الكاميرا تشغل الشاشة وأن الإحصائيات لا تظهر أثناء الالتقاط.
- أنهِ مبنى من غرفتين وافتح 3D، ثم قارن تركيب الغرف مع ملف RoomPlan الأصلي.
- افتح ملف RoomPlan الأصلي واضغط **تم** للعودة دون إغلاق التطبيق.
