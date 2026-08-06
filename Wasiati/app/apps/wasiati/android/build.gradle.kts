allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    // camera_android_camerax (locked at the ceiling of camera ^0.11's constraint) ships
    // against camera-core 1.5.0-beta01, whose annotated API references
    // CallbackToFutureAdapter without declaring androidx.concurrent on its own compile
    // classpath. javac then fails the PLUGIN's compile task with "Cannot attach type
    // annotations @NonNull … class file for
    // androidx.concurrent.futures.CallbackToFutureAdapter not found" — so no Android
    // build assembles at all (found by the first real `flutter build apk`, 5 Aug 2026;
    // an :app-level dependency was tried first and does not reach the plugin's task).
    // Scoped to that one plugin; delete when the camera plugin moves off the beta
    // camerax. plugins.withId rather than afterEvaluate: the template's
    // evaluationDependsOn(":app") above forces :app's evaluation during root
    // configuration, and afterEvaluate throws on an already-evaluated project.
    if (name == "camera_android_camerax") {
        plugins.withId("com.android.library") {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
