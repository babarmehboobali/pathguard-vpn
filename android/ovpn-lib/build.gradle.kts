// Wrapper around the official ics-openvpn engine (GPL-2.0, https://github.com/schwabe/ics-openvpn).
// The engine itself is checked out into android/ovpn by tool/fetch_ovpn.sh (CI does this automatically).
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val ics = rootProject.file("ovpn/main")

android {
    namespace = "de.blinkt.openvpn"
    compileSdk = 37
    ndkVersion = "30.0.14904198"

    defaultConfig {
        minSdk = 24
        buildConfigField("boolean", "openvpn3", "false")
        ndk { abiFilters += listOf("arm64-v8a") }
    }
    buildFeatures {
        aidl = true
        buildConfig = true
    }
    sourceSets {
        getByName("main") {
            manifest.srcFile("$ics/src/skeleton/AndroidManifest.xml")
            java.srcDirs("$ics/src/main/java", "$ics/src/skeleton/java")
            aidl.srcDirs("$ics/src/main/aidl")
            res.srcDirs("$ics/src/main/res", "$ics/src/skeleton/res")
            assets.srcDirs("$ics/src/main/assets", "$ics/build/ovpnassets")
        }
    }
    externalNativeBuild {
        cmake { path = file("$ics/src/main/cpp/CMakeLists.txt") }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    lint { abortOnError = false }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.core:core-ktx:1.13.1")
}
