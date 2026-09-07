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
    id("com.android.application") version "9.2.0" apply false
    // Declared but not applied: this only pins the Kotlin Gradle Plugin on the build
    // classpath, which is where AGP's built-in Kotlin picks its compiler up. AGP 9.2.0
    // would otherwise bring Kotlin 2.2.10, below the 2.2.20 the Flutter Gradle plugin
    // requires.
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
}

include(":app")
