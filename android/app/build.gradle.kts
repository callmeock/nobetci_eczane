import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 🔐 Keystore bilgilerini key.properties'ten oku
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ock.nobetcieczane"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications için gerekli:
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Kendi paket adını Google Play'de ne kullandıysan ona göre düzenle
        applicationId = "com.ock.nobetci_eczane"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 🔐 Release imza ayarları
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
    getByName("release") {
        // 🔐 Release imzan burada kalsın
        signingConfig = signingConfigs.getByName("release")

        // 🔽 ÖNEMLİ: Kod küçültmeyi açıyoruz
        isMinifyEnabled = true

        // Eğer plugin shrinkResources açıyorsa sorun çıkmasın diye biz de açık tanımlayalım:
        isShrinkResources = true
    }
}

}

flutter {
    source = "../.."
}

dependencies {
    // Desugaring (flutter_local_notifications için)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
