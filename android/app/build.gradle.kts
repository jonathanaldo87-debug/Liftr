import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details, read from android/key.properties.
//
// That file and the keystore it points at are both in android/.gitignore, so the
// signing key never travels with the source. CI writes them from repository
// secrets before building; see .github/workflows/release.yml.
//
// Its absence is normal and not an error -- a fresh clone has no keystore, and
// the build below falls back to debug keys so the project still compiles.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.liftr.liftr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications 22 calls java.time APIs that don't exist
        // below Android 8; desugaring back-fills them so the run notification
        // builds against the app's minSdk instead of forcing it up to 26.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.liftr.liftr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only declared when the keystore is actually present -- referencing a
        // config whose storeFile doesn't exist fails the build at configuration
        // time, which would break every clone that isn't set up to sign.
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // Resolved against android/, so `storeFile=upload-keystore.jks`
                // in key.properties means android/upload-keystore.jks. An
                // absolute path works too and is passed through unchanged.
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No keystore on this machine. Debug keys keep `flutter build`
                // and `flutter run --release` working locally -- but a build
                // signed this way must NEVER be distributed: the debug key is a
                // well-known shared one (password "android"), so anyone could
                // sign a forged update, and it differs per machine, which would
                // leave real users unable to update.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The runtime library the desugaring above rewrites java.time calls onto.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
