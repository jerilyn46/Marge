plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jerilyn.marge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jerilyn.marge"
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

        // AdMob is OFF for the Flip 7 hotfix unless -PADMOB_ENABLED=true.
        // tools:node=remove drops APPLICATION_ID so MobileAdsInitProvider
        // (also stripped) cannot start GMA before Flutter. Pair with
        // --dart-define=ADMOB_ENABLED=true when turning ads back on.
        val admobEnabled = (project.findProperty("ADMOB_ENABLED") as String?)
            ?.equals("true", ignoreCase = true) == true
        val admobAppId = (project.findProperty("ADMOB_APP_ID") as String?)
            ?.takeIf { it.isNotBlank() }
            ?: "ca-app-pub-3940256099942544~3347511713"
        manifestPlaceholders["admobAppId"] = if (admobEnabled) admobAppId else "unused"
        manifestPlaceholders["admobAppIdNode"] = if (admobEnabled) "merge" else "remove"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
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
