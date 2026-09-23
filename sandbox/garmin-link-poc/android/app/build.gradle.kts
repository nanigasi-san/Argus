plugins { id("com.android.application") }

android {
    namespace = "com.argus.garminpoc"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.argus.garminpoc"
        minSdk = 27
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.4.0@aar")
    // SDK 2.4.0 contains Kotlin message-conversion code, but its published POM
    // does not declare the Kotlin runtime as a transitive dependency.
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
    testImplementation("junit:junit:4.13.2")
}
