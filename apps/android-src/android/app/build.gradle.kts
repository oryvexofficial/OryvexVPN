import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: put a key.properties next to this folder's parent (gui/android/key.properties)
// or let CI write one from secrets. Without it, release APKs are signed with the debug key so
// they still install.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.oryvex.oryvexcore"
    compileSdk = flutter.compileSdkVersion
    // shared_preferences_android (and newer plugins) need NDK 27; NDKs are backward compatible.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.oryvex.oryvexcore"
        // Android 5.0+: the oldest phones still in use. The core is built for API 21 too.
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Fixed fallback key (committed on purpose). CI runners generate a NEW random debug key on
        // every build, so each APK had a different signature and Android refused to update an older
        // install ("App not installed"). Signing every build with this same key fixes that. Set the
        // ANDROID_KEYSTORE_* secrets in CI to use your own private release key instead.
        create("stable") {
            storeFile = file("oryvex-stable.jks")
            storePassword = "oryvexstable"
            keyAlias = "oryvex"
            keyPassword = "oryvexstable"
            enableV1Signing = true // Android 5 to 6
            enableV2Signing = true // Android 7+
            enableV3Signing = true // Android 9+ (Samsung One UI)
        }
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("stable")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        getByName("main") {
            // Kotlin sources plus the hev-socks5-tunnel Java binding (src/main/java/hev/htproxy).
            java.srcDirs("src/main/java", "src/main/kotlin")
        }
    }

    packaging {
        jniLibs {
            // The core ships as an executable named liboryvexcore_cli.so. Android only lets an
            // app exec files from its extracted native library dir, so keep them extracted.
            useLegacyPackaging = true
            // Never strip or drop ABIs: arm64 (Galaxy A52/A53 and most phones), arm32 (old/low-end), x86_64.
            pickFirsts.add("**/libc++_shared.so")
            keepDebugSymbols.add("**/liboryvexcore_cli.so")
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
