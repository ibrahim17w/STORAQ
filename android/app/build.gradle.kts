plugins {
    id("com.android.application")
    // id("kotlin-android")  // REMOVED - Flutter uses Built-in Kotlin now
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.example.storaq"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.storaq"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // NOTE: debug signing is used so `flutter build apk` produces an
            // installable APK without requiring a release keystore. Replace
            // this with a real keystore before uploading to Google Play
            // (a Play upload signed with the debug key will be rejected).
            signingConfig = signingConfigs.getByName("debug")

            // Code shrinking + resource shrinking. R8 is on by default for
            // release builds in modern Flutter/AGP; the explicit flags here
            // make the behavior visible and consistent.
            //   isMinifyEnabled    - removes unused classes/methods/fields
            //                        and renames the rest (smaller APK +
            //                        slight perf win from inlining)
            //   isShrinkResources  - removes unused PNG/XML/etc. assets
            //                        that minified code no longer references
            //
            // proguardFiles loads:
            //   * proguard-android-optimize.txt - AGP's tuned defaults
            //   * proguard-rules.pro            - this project's overrides
            //     (including the -dontwarn rules for Flutter's unused
            //     Play Core / deferred-components references — without
            //     these, R8 fails the build with "Missing class" errors)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
