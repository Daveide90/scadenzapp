# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# SQLCipher (sqflite_sqlcipher usa net.zetetic; net.sqlcipher resta innocuo)
-keep class net.zetetic.** { *; }
-dontwarn net.zetetic.**
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**

# flutter_local_notifications: usa GSON (TypeToken) per (de)serializzare le notifiche
# schedulate. Senza queste keep-rule, in RELEASE R8 rompe le notifiche programmate
# (falliscono alla consegna e spariscono dopo il reboot).
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-keepclassmembers,allowobfuscation class * { @com.google.gson.annotations.SerializedName <fields>; }
-dontwarn com.google.gson.**

# Play Core (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
