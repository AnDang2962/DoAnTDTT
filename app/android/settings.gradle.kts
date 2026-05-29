pluginManagement {
<<<<<<< HEAD
    val flutterSdkPath = "D:/DaiHoc/DoAn_TDTT/flutter"
=======
    val flutterSdkPath = "D:\\tl\\flutter"
>>>>>>> 670f9ff7c54bc5c3a841154cfcd1f3c42ee7fb2b

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
