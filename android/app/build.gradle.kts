import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.murekkep.notebook"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.murekkep.notebook"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        // BuildConfig.DEBUG opens the Pro themes in debug builds (ui/AppTheme.kt).
        buildConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.06.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.1")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.input:input-motionprediction:1.0.0-beta05")
    // A shared imported PDF keeps its own pages, the ink laid over them (export/PdfOverlay.kt).
    // BouncyCastle only serves certificate-encrypted PDFs, which PdfRenderer does not open either.
    implementation("com.tom-roush:pdfbox-android:2.0.27.0") {
        exclude(group = "org.bouncycastle")
    }
    testImplementation("junit:junit:4.13.2")
}
