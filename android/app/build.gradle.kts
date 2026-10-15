import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (created by scripts/create_keystore.ps1).
// Without it, release builds fall back to the debug key so `flutter run --release` still works.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.nxsaves.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nxsaves.app"
        // youtubedl-android (yt-dlp + Python + ffmpeg) requires API 24+.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Flutter supports these three ABIs; drop the library's 32-bit x86 binaries from the
        // universal APK. (`--split-per-abi` builds already limit ABIs, and AGP rejects both at once.)
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
            }
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            // yt-dlp's Python interpreter and ffmpeg ship as executables inside jniLibs; they must be
            // extracted to nativeLibraryDir to be runnable, so legacy (extracted) packaging is required.
            useLegacyPackaging = true
            // These are zip archives named *.so (Python stdlib, ffmpeg libs); don't try to strip them.
            keepDebugSymbols += listOf("**/libpython.zip.so", "**/libffmpeg.zip.so")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val ytdlpVersion = "0.18.1"
    implementation("io.github.junkfood02.youtubedl-android:library:$ytdlpVersion")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$ytdlpVersion")
    implementation("androidx.core:core-ktx:1.16.0")
}

flutter {
    source = "../.."
}
