# Validation Notes

## ما تم التحقق منه محليًا

- وجود جميع ملفات المشروع المشار إليها في `project.yml`.
- تحليل Syntax لجميع ملفات Swift باستخدام Swift frontend على Linux.
- صحة YAML لكل من `project.yml` وملف GitHub Actions.
- اكتمال App Icon asset catalog بالمقاسات الأساسية للـiPhone والـiPad.

## ما يحتاج GitHub Actions أو جهاز Apple

- Type-check وربط ARKit وRealityKit داخل Xcode.
- إنشاء ملف `.app` وملف unsigned IPA.
- اختبار Scene Depth وScene Mesh على جهاز LiDAR حقيقي.
- اختبار التوقيع التجريبي والتثبيت على iPhone.
