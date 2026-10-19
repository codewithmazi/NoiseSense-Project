allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Aligns each plugin's Kotlin bytecode target with its own Java target.
//
// tflite_flutter 0.12.1 compiles its Java for JVM 11 but leaves Kotlin at the
// default, which is the version of the JDK running Gradle (25 here, from
// Android Studio's bundled runtime). Gradle rejects that mismatch outright:
// "Inconsistent JVM-target compatibility ... (11) and ... (25)". Reading each
// plugin's declared Java target and applying it to Kotlin fixes the cause.
// Setting kotlin.jvm.target.validation.mode=warning would only hide it, and
// leave classes compiled for a newer JVM than the module declares.
//
// Configured lazily (configureEach runs when the task is configured, after
// the project has been evaluated), because evaluationDependsOn above means a
// project can already be evaluated when this block runs, so afterEvaluate
// cannot be used.
subprojects {
    val module = this
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val android = module.extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension ?: return@configureEach
        val javaTarget = android.compileOptions.targetCompatibility.majorVersion
        compilerOptions.jvmTarget.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(
                if (javaTarget.toInt() <= 8) "1.8" else javaTarget,
            ),
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
