pluginManagement {
    // خواندن مسیر Flutter SDK از local.properties
    val flutterSdkPath = {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        assert(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }()

    // معرفی پلاگین‌های داخلی فلاتر به Gradle
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // Mirrors
        maven { url = uri("https://maven.myket.ir") }
        maven { url = uri("https://maven.devneeds.ir") }
        maven { url = uri("https://gradle.devneeds.ir/mvn") }

        // Fallbacks
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}


dependencyResolutionManagement {
    repositories {
        // Mirrors
        maven { url = uri("https://maven.myket.ir") }
        maven { url = uri("https://maven.devneeds.ir") }
        
        // Fallbacks
        google()
        mavenCentral()
    }
}

rootProject.name = "bioflash"

include(":app")
