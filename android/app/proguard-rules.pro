# Keep SeiReminds native Android components (Activity, Receivers, Foreground Service).
-keep class com.seireminds.seireminds.** { *; }

# Keep Flutter embedding & plugin registrants intact under R8 minification.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# Optional non-Latin ML Kit text recognizer modules not bundled (SeiReminds uses Latin only).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
