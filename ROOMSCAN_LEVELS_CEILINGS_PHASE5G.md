# RoomScan Phase 5G — Floor Levels and Ceiling Zones

الإصدار: `0.16.0` — البناء: `20`

## ما تمت إضافته

- ملف تعريف منسوب لكل غرفة يشمل الطابق، منسوب الأرضية، ارتفاع السقف الإنشائي، وارتفاع التشطيب الافتراضي.
- الاستفادة من `CapturedRoom.floors` و`polygonCorners` من RoomPlan لتحديد بصمة الأرضية ومركزها واتجاهها.
- استنتاج بديل من الحوائط عند غياب أرضية RoomPlan.
- مناطق سقف مستقلة للجبس والكمـرات والسواقط والمناطق المرتفعة.
- عرض أرضيات RoomPlan ومناطق السقف داخل SwiftUI Canvas وApple SceneKit.
- تطبيق فرق منسوب الغرفة على الحوائط والأبواب في عرض SceneKit من دون تغيير البيانات الأصلية.
- فحص تلقائي لفروق المناسيب وتعارضات ارتفاع السقف.

## ملف الحفظ الجديد

```text
Review/room-levels.json
```

يحتوي الملف على:

```text
profiles[]
├── roomIndex
├── story
├── roomPlanFloorElevationMeters
├── floorElevationMeters
├── structuralCeilingHeightMeters
└── finishedCeilingHeightMeters

ceilingZones[]
├── roomIndex
├── kind
├── centerX / centerZ
├── widthMeters / depthMeters
├── rotationDegrees
└── heightAboveFloorMeters
```

## مبدأ عدم إتلاف المصدر

تبقى `CapturedRoom` و`CapturedStructure` وملفات JSON وUSDZ الأصلية كما هي. يطبق التطبيق المناسيب ومناطق السقف في طبقة العرض والتحرير الخاصة به فقط.

## حدود المرحلة

- مناطق السقف مستطيلة في هذه المرحلة، ولا يوجد محرر مضلع حر حتى الآن.
- السقف اليدوي يظهر كلوح معماري في SceneKit، ولا ينفذ عمليات Boolean مع الحوائط.
- فرق المنسوب بين غرفتين يظهر كتعارض للمراجعة؛ التطبيق لا يفترض تلقائيًا هل الفرق درجة حقيقية أم خطأ مسح.
