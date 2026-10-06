import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Codemagic injects these values from its private signing identity. Local builds
// use the ignored android/key.properties file. Never fall back to the debug key.
val signingEnvironment = listOf(
    "CM_KEYSTORE_PATH", "CM_KEYSTORE_PASSWORD", "CM_KEY_ALIAS", "CM_KEY_PASSWORD",
).associateWith { providers.environmentVariable(it).orNull }
val hasSigningEnvironment = signingEnvironment.values.any { it != null }
val localSigningProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (!hasSigningEnvironment && propertiesFile.isFile) {
        propertiesFile.inputStream().use { load(it) }
    }
}
fun signingValue(environmentName: String, propertyName: String): String? =
    if (hasSigningEnvironment) signingEnvironment[environmentName]
    else localSigningProperties.getProperty(propertyName)

val releaseStorePath = signingValue("CM_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("CM_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("CM_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("CM_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.example.pharmacyms"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pharmacyms"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isDebuggable = false
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        check(hasReleaseSigning) {
            "Release signing is missing. Configure the pharmacy_release keystore " +
                "in Codemagic or android/key.properties locally. See docs/ANDROID_RELEASE.md."
        }
        check(file(releaseStorePath!!).isFile) { "The release keystore file does not exist." }
    }
}
tasks.matching { it.name == "preReleaseBuild" || it.name == "validateSigningRelease" }
    .configureEach { dependsOn(verifyReleaseSigning) }

flutter {
    source = "../.."
}
