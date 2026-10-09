plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Ads-on path (fail closed): OFF unless -PADMOB_ENABLED=true.
// AGP cannot use a Gradle placeholder for tools:node, so ads-on builds
// swap in AndroidManifest.ads-on.xml (APPLICATION_ID + ${admobAppId}).
val admobEnabled = (project.findProperty("ADMOB_ENABLED") as String?)
    ?.equals("true", ignoreCase = true) == true
val admobSampleAppId = "ca-app-pub-3940256099942544~3347511713"
val admobInjectedAppId = (project.findProperty("ADMOB_APP_ID") as String?)
    ?.takeIf { it.isNotBlank() }
// Debug ads-on builds may use Google's sample App ID. Release ads-on builds
// must inject a real one (-PADMOB_APP_ID) — checked below, fail closed.
val admobAppId = admobInjectedAppId ?: admobSampleAppId
val admobAllowTestIds = (project.findProperty("ADMOB_ALLOW_TEST_IDS") as String?)
    ?.equals("true", ignoreCase = true) == true

// Terms of Use effective date (fail closed for release). The Dart side reads
// String.fromEnvironment('TERMS_EFFECTIVE_DATE'), so the one mechanism that
// fills the app AND satisfies this check is the dart-define:
//   flutter build appbundle --release --dart-define=TERMS_EFFECTIVE_DATE=...
// Flutter hands dart-defines to Gradle as -Pdart-defines=<base64,base64,...>.
// A bare -PTERMS_EFFECTIVE_DATE would not reach the app, so it is not accepted.
fun dartDefine(name: String): String? {
    val raw = project.findProperty("dart-defines") as String? ?: return null
    return raw.split(",")
        .mapNotNull { encoded ->
            try {
                String(Base64.getDecoder().decode(encoded.trim()), Charsets.UTF_8)
            } catch (e: IllegalArgumentException) {
                null
            }
        }
        .firstOrNull { it.startsWith("$name=") }
        ?.substringAfter("=")
}
val termsEffectiveDate = dartDefine("TERMS_EFFECTIVE_DATE")?.trim()?.takeIf { it.isNotEmpty() }

android {
    namespace = "com.jerilynroberts.marge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jerilynroberts.marge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Pair with --dart-define=ADMOB_ENABLED=true. See docs/ads.md.
        // MobileAdsInitProvider is always stripped; Dart bootstraps after first frame.
        manifestPlaceholders["admobAppId"] = if (admobEnabled) admobAppId else "unused"
    }

    sourceSets {
        getByName("main") {
            if (admobEnabled) {
                manifest.srcFile("src/main/AndroidManifest.ads-on.xml")
            }
        }
    }

    signingConfigs {
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
            // Always the upload key. No debug-keystore fallback: a release
            // build without android/key.properties fails (see check below).
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// Release builds must be upload-key signed. Fail fast instead of silently
// producing a debug-signed APK/AAB when key.properties is missing.
gradle.taskGraph.whenReady {
    val releaseTaskPrefixes = listOf("assemble", "bundle", "package", "sign")
    val wantsRelease = allTasks.any { task ->
        task.project == project &&
            task.name.contains("Release") &&
            releaseTaskPrefixes.any { task.name.startsWith(it) }
    }
    // Terms §9 refers to "the effective date above": release must carry it.
    if (wantsRelease && termsEffectiveDate == null) {
        throw GradleException(
            "Release build needs the Terms of Use effective date: pass " +
                "--dart-define=TERMS_EFFECTIVE_DATE=\"<Month D, YYYY>\" to " +
                "flutter build (see docs/store/README.md).",
        )
    }
    if (wantsRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Release build needs android/key.properties (upload key). " +
                "Refusing to fall back to the debug keystore.",
        )
    }
    // Ads-on release: never ship Google's sample App ID by accident.
    val sampleAppId = admobInjectedAppId == null ||
        admobInjectedAppId.startsWith("ca-app-pub-3940256099942544")
    if (wantsRelease && admobEnabled && sampleAppId && !admobAllowTestIds) {
        throw GradleException(
            "Ads-on release needs -PADMOB_APP_ID (real App ID, injected at " +
                "build time). Pass -PADMOB_ALLOW_TEST_IDS=true only for Tester " +
                "builds that intentionally use Google sample IDs.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
