import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.testing.Test

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

/** Reads a release-signing value from -P/gradle.properties first, then the environment. */
fun signingValue(name: String): String? =
    providers.gradleProperty(name).orNull ?: System.getenv(name)

android {
    namespace = "com.simonkaring.voltlink"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.simonkaring.voltlink"
        minSdk = 29
        targetSdk = 36
        versionCode = 2
        versionName = "1.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // Release signing is injected by CI (or a local gradle.properties); it never lives in the
    // repository. Without these values a release build stays unsigned instead of failing.
    val keystorePath = signingValue("VOLTLINK_KEYSTORE")
    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = signingValue("VOLTLINK_KEYSTORE_PASSWORD")
                keyAlias = signingValue("VOLTLINK_KEY_ALIAS")
                keyPassword = signingValue("VOLTLINK_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

// The OKF bundle generator lives in the unit-test source set (src/test/.../okf) so it can read
// the live profiles; these properties tell it where the repository and the asset seeds are.
// Regenerate with `-Pokf.export=true`, validate with a plain `testDebugUnitTest`.
tasks.withType<Test>().configureEach {
    systemProperty("okf.root", rootProject.projectDir.absolutePath)
    systemProperty("okf.assets", project.file("src/main/assets").absolutePath)
    systemProperty("okf.export", providers.gradleProperty("okf.export").getOrElse("false"))
    // The bundle is read (and on export, rewritten) by the tests, so it is an input: a hand-edited
    // or stale concept has to re-run the check instead of being skipped as UP-TO-DATE.
    inputs.dir(rootProject.file("knowledge"))
        .withPropertyName("androidKnowledgeBundle")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.09.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    // 1.18+ carries NotificationCompat.ProgressStyle / promoted ongoing (Android 16 Live Updates).
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.1")
    implementation("androidx.datastore:datastore-preferences:1.1.7")

    // Android Auto templates are compiled into the debug build only: the release manifest
    // registers no car service, and the old phone-app `car` package was removed.
    debugImplementation("androidx.car.app:app:1.7.0")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

/**
 * Runs the screenshot tests and copies the PNGs into `app/build/screenshots`.
 *
 * `adb` must be on PATH (it is while the emulator/device is attached). Filter to the screenshot
 * class with `-Pandroid.testInstrumentationRunnerArguments.class=com.simonkaring.voltlink.ScreenshotTest`
 * when the rest of the instrumentation suite does not need to run again.
 */
tasks.register<Exec>("recordScreenshots") {
    group = "verification"
    description = "Captures every app screen from the connected device."
    dependsOn("connectedDebugAndroidTest")

    val remote = "/sdcard/Download/voltlink-screenshots"
    val output = layout.buildDirectory.dir("screenshots")
    doFirst { output.get().asFile.mkdirs() }
    commandLine("adb", "pull", "$remote/.", output.get().asFile.absolutePath)
}
