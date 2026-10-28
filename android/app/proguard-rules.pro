# Marge release R8 rules (Flutter's own rules come from the Flutter Gradle plugin).

# Flutter embedding + plugins registered by reflection.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
# Flutter references Play Core (deferred components) we do not ship.
-dontwarn com.google.android.play.core.**

# Google Mobile Ads / UMP (google_mobile_ads plugin, ads-on builds).
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-keep class io.flutter.plugins.googlemobileads.** { *; }
-dontwarn com.google.android.gms.**

# Play Billing (in_app_purchase).
-keep class com.android.billingclient.** { *; }
-keep class io.flutter.plugins.inapppurchase.** { *; }

# flutter_local_notifications: scheduled notifications are Gson-serialized.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# App code (MainActivity etc.).
-keep class com.jerilynroberts.marge.** { *; }

# kotlinx.coroutines: ServiceLoader looks up these by name via
# META-INF/services; R8 must not rename/strip them (Dispatchers.Main).
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keep class * implements kotlinx.coroutines.internal.MainDispatcherFactory { <init>(); }
-keep class * implements kotlinx.coroutines.CoroutineExceptionHandler { <init>(); }
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-keep class kotlinx.coroutines.android.AndroidExceptionPreHandler { *; }
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**
