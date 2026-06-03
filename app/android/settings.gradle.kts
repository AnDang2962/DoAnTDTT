pluginManagement {
    val localProperties = java.util.Properties()
    val localPropertiesFile = java.io.File(settingsDir, "local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { localProperties.load(it) }
    }
    val flutterSdkPath = localProperties.getProperty("flutter.sdk") ?: "C:/development/flutter_windows_3.41.9-stable/flutter"

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
