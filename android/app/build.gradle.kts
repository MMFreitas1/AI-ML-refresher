import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

/*
 * Official releases are built with a private brand kit cloned next to this repository, at
 * ../brand-kit (not public; see BRAND.md). Its brand.properties lists the Kotlin and resource
 * folders that supply BrandKit, the app name and the icon. Without it, src/neutral is used: a
 * neutral look and the name "AI-ML Refresher".
 */
val brandDir = rootDir.resolve("../../brand-kit/products/ai-ml-refresher/android")
val brandProps = Properties().apply {
    brandDir.resolve("brand.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
}
fun brandDirs(key: String) =
    brandProps.getProperty(key, "").split(',').map(String::trim).filter(String::isNotEmpty).map { brandDir.resolve(it).path }

/* Release signing reads android/keystore.properties (not in git):
 *   storeFile=/path/to/release.jks  storePassword=…  keyAlias=…  keyPassword=… */
val keystoreProps = Properties().apply {
    rootDir.resolve("keystore.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
}

android {
    namespace = "com.mmfreitas.aibrief"
    compileSdk = 37

    defaultConfig {
        // Never change: installed data and the widget are tied to it.
        applicationId = "com.mmfreitas.aibrief"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "1.1"
    }

    signingConfigs {
        if (keystoreProps.isNotEmpty()) create("release") {
            storeFile = file(keystoreProps.getProperty("storeFile"))
            storePassword = keystoreProps.getProperty("storePassword")
            keyAlias = keystoreProps.getProperty("keyAlias")
            keyPassword = keystoreProps.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }

    sourceSets["main"].apply {
        if (brandProps.isNotEmpty()) {
            brandDirs("kotlinDirs").forEach { kotlin.directories.add(it) }
            brandDirs("resDirs").forEach { res.directories.add(it) }
        } else {
            kotlin.directories.add("src/neutral/kotlin")
            res.directories.add("src/neutral/res")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures { compose = true }
}

dependencies {
    implementation(project(":core"))

    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")

    implementation("androidx.work:work-runtime-ktx:2.12.0")
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")
    implementation("androidx.glance:glance-appwidget:1.2.0")
    implementation("androidx.glance:glance-material3:1.2.0")
}
