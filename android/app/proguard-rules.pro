# ── Brutus / R8 keep rules ───────────────────────────────────────────────

# ML Kit Text Recognition — we ONLY use the Latin script recognizer. The
# `google_mlkit_text_recognition` plugin references the Chinese / Devanagari /
# Japanese / Korean recognizer options classes via reflection in its bridge
# code, but those modules aren't on the classpath because we never depend on
# them. Tell R8 to stop warning about the missing references — the code
# paths that hit them are unreachable at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep ML Kit core API entry points so the recognizer class can be loaded
# reflectively from the Flutter plugin.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Flutter Play Store split / deferred components stubs — harmless missing
# references that R8 flags during release builds with shrinkResources.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Tink / crypto — googleapis_auth + flutter_secure_storage pull these in
# transitively. Some optional sub-modules reference each other reflectively.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Joda / threetenbp — pulled in transitively by googleapis. Usually safe to
# skip warnings on the Joda time classes that Tink references but aren't
# actually called from our code paths.
-dontwarn org.joda.time.**
-dontwarn org.threeten.bp.**

# OkHttp / Conscrypt — googleapis HTTP layer. Optional certificate pinning
# pieces produce noisy R8 warnings.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Hive — relies on Map / List runtime types via mirrors. Keep the public API.
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# Brutus native services — keep so AccessibilityService / NotificationListenerService
# can be instantiated by the Android framework via reflection.
-keep class com.adityapandey.brutus_app.BrutusAccessibilityService { *; }
-keep class com.adityapandey.brutus_app.BrutusNotificationListenerService { *; }
-keep class com.adityapandey.brutus_app.ScreenCaptureService { *; }
-keep class com.adityapandey.brutus_app.MainActivity { *; }

# Camera / record / permission_handler — Flutter plugin entry points.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.embedding.**
