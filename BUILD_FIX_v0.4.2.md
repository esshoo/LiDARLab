# 3ELiDAR Unified v0.4.2 — Swift Build Fix

تم إصلاح أخطاء Xcode 16.4 التالية:

- تعارض الاسم الداخلي `Section` مع `SwiftUI.Section` داخل `UnifiedScanSettingsView.swift`.
- الوصول إلى `settingsLocked` المعزولة بـ `@MainActor` من `UnifiedARViewContainer.Coordinator`.
- تحذير تعديل متغير ملتقط من Closure متزامنة في `UnifiedAppleDirectNetworking.swift`.

الإصلاحات:

- إعادة تسمية enum إلى `SettingsTab` واستخدام `SwiftUI.Section` صراحةً.
- عزل Coordinator على `@MainActor` مع إبقاء callbacks الخاصة بـ ARSession `nonisolated` ثم العودة إلى MainActor عبر Task.
- استبدال متغير `resumed` ببوابة thread-safe تعمل مرة واحدة.
- رفع رقم النسخة إلى `0.40.2 (42)`.

لا توجد تغييرات في ملفات `RoomScan`.
