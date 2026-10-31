# flutter_local_notifications (يستخدم Gson داخلياً؛ بدون هذه القواعد قد تتعطل الإشعارات في نسخة release)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*
