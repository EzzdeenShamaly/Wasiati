import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-key signing is wired through android/key.properties, which is GITIGNORED
// (android/.gitignore) — the keystore and its passwords must never enter git. Locally
// Raed writes the file by hand (docs/MOBILE_RELEASE.md, one-time); in CI
// .github/workflows/mobile.yml materializes it from repository secrets. Everywhere
// else the file simply doesn't exist and the debug fallback below applies.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKeystore = keystorePropertiesFile.exists()
if (hasUploadKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// The fallback below must never be SILENT: CI prints its own ::notice, but a local
// `flutter build appbundle --release` without key.properties would otherwise produce
// a debug-signed artifact indistinguishable, by filename, from a shippable one.
// Scoped to the task graph so debug builds stay quiet; logger.quiet because the
// flutter tool drives Gradle at quiet verbosity, where warn-level lines are dropped.
gradle.taskGraph.whenReady {
    if (!hasUploadKeystore && allTasks.any { it.name.contains("Release") }) {
        logger.quiet(
            "WARNING: android/key.properties not found — this release build is DEBUG-SIGNED " +
                "(build proof only; Play will reject it). Wiring: docs/MOBILE_RELEASE.md."
        )
    }
}

android {
    namespace = "com.wasiati.wasiati"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.wasiati.wasiati"
        // 24, not Flutter's default (21): flutter_tts declares minSdk 24, so with 21 the
        // manifest merger fails and NO Android build — debug or release — assembles at
        // all (found by running the first real `flutter build apk`, 5 Aug 2026). Android
        // 7.0+ is effectively the whole market; below it Ameen's spoken replies couldn't
        // work anyway.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // A relative storeFile resolves against this module (android/app/);
                // CI writes an absolute $RUNNER_TEMP path, which file() passes through.
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // With key.properties present this is the Play upload key. Without it the
            // release DELIBERATELY falls back to debug signing instead of failing:
            // `flutter run --release`, a fresh clone, and secretless CI all keep
            // working, and the fallback cannot reach users by accident — Play rejects
            // a debug-signed bundle at upload. mobile.yml prints a notice whenever it
            // builds on this fallback so an unsigned artifact is never mistaken for a
            // shippable one.
            signingConfig = if (hasUploadKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
