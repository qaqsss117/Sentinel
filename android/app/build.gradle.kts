import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingDirectory = rootProject.file("../signing/android")
val signingPropertiesFile = File(signingDirectory, "signing.properties")
val signingProperties = Properties().apply {
    if (signingPropertiesFile.exists()) {
        signingPropertiesFile.inputStream().use { load(it) }
    }
}
val mStoreFile: File? = signingProperties.getProperty("storeFile")
    ?.let { File(signingDirectory, it) }
val mStorePassword: String? = signingProperties.getProperty("storePassword")
val mKeyAlias: String? = signingProperties.getProperty("keyAlias")
val mKeyPassword: String? = signingProperties.getProperty("keyPassword")
val isReleaseSigningConfigured = mStoreFile?.exists() == true
        && mStorePassword != null
        && mKeyAlias != null
        && mKeyPassword != null
val isReleaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

if (isReleaseBuildRequested && !isReleaseSigningConfigured) {
    throw GradleException(
        "Android release signing is not configured. " +
            "Run: dart run tool/generate_android_signing.dart"
    )
}

android {
    namespace = "com.follow.clash"
    compileSdk = 36
    ndkVersion = "28.0.13004108"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.follow.clash"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (isReleaseSigningConfigured) {
            create("release") {
                storeFile = mStoreFile
                storePassword = mStorePassword
                keyAlias = mKeyAlias
                keyPassword = mKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".debug"
        }

        release {
            isMinifyEnabled = true
            isDebuggable = false

            if (isReleaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":core"))
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("com.android.tools.smali:smali-dexlib2:3.0.9") {
        exclude(group = "com.google.guava", module = "guava")
    }
}