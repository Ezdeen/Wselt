# تطبيق Future Roots — الحزمة الكاملة (أندرويد + iOS)

اسم الحزمة المستخدم في كل مكان: **com.futureroots.webview**
(مضبوط جاهزاً في `android/app/build.gradle`. سجّله كما هو في Firebase.)

## الخطوات على FlutLab (للمبتدئ)

1. أنشئ مشروع Flutter **جديداً** في FlutLab.
2. احذف من المشروع الجديد: مجلد `lib` ومجلد `android` وملف `pubspec.yaml`.
3. ارفع **محتويات** هذه الحزمة بعد فك الضغط (وليس المجلد الخارجي): `pubspec.yaml` و`lib` و`android`.
   يجب أن ترى `pubspec.yaml` و`lib` و`android` مباشرة في جذر المشروع.
4. أنشئ مشروع Firebase: console.firebase.google.com ← Add project ← أيقونة Android.
   في **Android package name** اكتب: `com.futureroots.webview` ← Register app ← حمّل `google-services.json`.
5. ارفع `google-services.json` إلى **`android/app/`** (بجانب `build.gradle`).
6. افتح `pubspec.yaml` واضغط **Pub get**.
7. اضغط **Build APK** أو **Run**.

> بدون `google-services.json` سيفشل البناء. هذا مطلوب لإشعارات Firebase.

## تجربة إشعار
انسخ `FCM TOKEN` من نافذة Console ← Firebase ← Messaging ← New campaign ← Send test message ← الصق التوكن.
أو أرسل لكل المستخدمين عبر الـ Topic: `all`.

## فتح صفحة عند الضغط على الإشعار
أضف Custom data: المفتاح `url` والقيمة رابط من موقعك (داخل futureroots.site).

## ربط التوكن بموقعك
```js
window.onFcmToken = function (token) {
  fetch('/wa/api/save-token', {            // عدّل المسار حسب نظامك
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ token: token, platform: window.FCM_PLATFORM })
  });
};
window.addEventListener('fcmToken', e => console.log(e.detail));
if (window.FlutterApp) FlutterApp.postMessage('getToken');
```
الإرسال من السيرفر: `server/send_fcm.php` (يتطلب service-account.json من Firebase).

## iOS
راجع `README_IOS_AR.md` (يحتاج Mac وحساب Apple Developer).
في iOS اجعل الـ Bundle ID: `com.futureroots.webview`.

## أخطاء شائعة
| الخطأ | الحل |
|---|---|
| `google-services.json is missing` | الملف ليس في `android/app/` |
| `No matching client found for package name` | سجّلت اسماً غير `com.futureroots.webview` في Firebase |
| `flutter.sdk not set in local.properties` | اضغط Pub get أو شغّل Build مرة؛ FlutLab ينشئ الملف تلقائياً |
| خطأ إصدار Gradle/Kotlin/AGP | الصق لي الخطأ كاملاً وأعدّل الإصدارات (الحالي: AGP 8.9.1، Gradle 8.11.1، Kotlin 2.1.0) |
