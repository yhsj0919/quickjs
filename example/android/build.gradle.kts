import com.android.build.gradle.LibraryExtension
import org.gradle.api.tasks.compile.JavaCompile

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

// video_player_android 2.7.1 pins Java 8 and passes -Werror, which fails on newer JDKs.
subprojects {
    if (name != "video_player_android") {
        return@subprojects
    }
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<JavaCompile>().configureEach {
            options.compilerArgs.removeAll(listOf("-Werror"))
            if (!options.compilerArgs.contains("-Xlint:-options")) {
                options.compilerArgs.add("-Xlint:-options")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
