# 3ELiDAR Unified v0.4.1 — Build Fix

تم إصلاح خطأ Xcode:

`Multiple commands produce LiDARLab.app/README_AR.md`

السبب كان وجود ملفين باسم `README_AR.md` داخل ميزتين مختلفتين، وكان XcodeGen يضيفهما كموارد وينسخهما إلى المسار نفسه داخل التطبيق.

الإصلاح:

- إعادة تسمية ملفي التوثيق بأسماء فريدة.
- استبعاد ملفات Markdown من موارد التطبيق في `project.yml`.
- رفع رقم النسخة إلى `0.40.1 (41)`.

لا توجد تغييرات في ملفات `RoomScan`.
