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

// Compatibilité AGP 8 : le plugin `tdlib` (pub.dev 1.6.0) a été publié
// avant l'obligation de déclarer un namespace. On l'injecte ici, au niveau
// du projet, pour que la compilation reste possible en local comme dans
// un futur workflow GitHub Actions (aucune modification du pub-cache).
subprojects {
    if (project.name == "tdlib") {
        val configureTdlib: (Project) -> Unit = { target ->
            target.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                namespace = "org.naji.td.tdlib"
                // Le plugin déclare compileSdk 31 : trop ancien pour les
                // dépendances AndroidX actuelles (au moins 34 requis).
                @Suppress("DEPRECATION")
                compileSdkVersion(35)
            }
        }
        if (project.state.executed) {
            configureTdlib(project)
        } else {
            project.afterEvaluate { configureTdlib(project) }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
