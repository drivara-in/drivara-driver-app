plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

android {
    namespace = "com.drivara.drivara_driver_android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.drivara.drivara_driver_android"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Read .env for Secrets
        val possibleEnvFiles = listOf(
            rootProject.file("../.env"),        // From android/app
            rootProject.file("../../.env"),     // From android/app/src/main
            File("/Users/rishi/Documents/drivara-driver-app/.env"), // Absolute path (fallback)
            File(System.getProperty("user.dir"), ".env") 
        )
        
        var mapsApiKey = ""
        for (f in possibleEnvFiles) {
             println("Checking environment file: ${f.absolutePath} (Exists: ${f.exists()})")
             if (f.exists()) {
                 val props = Properties()
                 props.load(FileInputStream(f))
                 val rawKey = props.getProperty("GOOGLE_MAPS_API_KEY")
                 if (rawKey != null && rawKey.isNotBlank()) {
                     mapsApiKey = rawKey.trim()
                     println("SUCCESS: Loaded GOOGLE_MAPS_API_KEY from ${f.absolutePath}")
                     break
                 }
             }
        }
        
        if (mapsApiKey.isEmpty()) {
            throw GradleException("CRITICAL: GOOGLE_MAPS_API_KEY not found in any .env file. Checked locations: ${possibleEnvFiles.map { it.absolutePath }}")
        }

        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            val keyPropertiesFile = rootProject.file("key.properties")
            if (keyPropertiesFile.exists()) {
                val keyProperties = Properties()
                keyProperties.load(FileInputStream(keyPropertiesFile))
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
