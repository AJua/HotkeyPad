pluginManagement {
    val flutterSdkPath =
        run {
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
    id("com.android.application") version "9.0.1" apply false
    // Not applied directly anywhere (AGP 9's built-in Kotlin support,
    // configured via the `kotlin { compilerOptions {} }` block in
    // app/build.gradle.kts, replaces the separate kotlin-android plugin) —
    // declared here with "apply false" purely to pin the Kotlin Gradle
    // Plugin version AGP resolves internally above its own default (2.2.10).
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
}

include(":app")
