# ============================================================================
# Flutter Play Store deferred-components — R8 keep rules
# ============================================================================
# Flutter's Android embedding (io.flutter.embedding.android.FlutterPlayStore
# SplitApplication and io.flutter.embedding.engine.deferredcomponents.
# PlayStoreDeferredComponentManager) references several classes from
# com.google.android.play.core.* for dynamic/deferred Play Feature Delivery.
#
# Those classes are only on the classpath if you actually ship as an Android
# App Bundle (.aab) with on-demand feature modules. STORAQ ships as a single
# APK, so the references are dead code — but R8 still verifies them, and
# without explicit -dontwarn it fails the whole build with "Missing class"
# errors during :app:minifyReleaseWithR8.
#
# Telling R8 to ignore these specific packages is the recommended fix in the
# Flutter docs (https://docs.flutter.dev/deployment/android#shrinking-your-code-with-r8).
# It does NOT keep the classes in the APK (they don't exist to keep) — it
# just suppresses the verification error.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ============================================================================
# Common Flutter plugin keep rules
# ============================================================================
# Some Flutter plugins use reflection to look up their native bridge classes.
# These rules are conservative — they keep symbol names so the bridges don't
# get renamed to a$, b$, etc. and silently break at runtime in release builds.

# Flutter engine itself
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# image_picker / mobile_scanner / camera plugins use CameraX reflection
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# sqflite uses JNI
-keep class com.tekartik.sqflite.** { *; }

# pdf / printing — use reflection for font loading
-keep class com.itextpdf.** { *; }
-dontwarn com.itextpdf.**

# Kotlin coroutines internals (referenced by some plugins)
-dontwarn kotlinx.coroutines.**
-keep class kotlinx.coroutines.** { *; }
