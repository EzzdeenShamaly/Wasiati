pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    // 2.1.0, not the template's 1.8.22: flutter_tts 4.2.5 ships kotlin-stdlib 2.2.x,
    // whose metadata (2.2.0) a 1.8 compiler cannot read — :flutter_tts:compileDebugKotlin
    // fails and no Android build assembles (found by the first real `flutter build apk`,
    // 5 Aug 2026). 2.1.0 reads metadata up to 2.2 and is inside the Kotlin plugin's
    // tested compatibility range for AGP 8.7.
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
