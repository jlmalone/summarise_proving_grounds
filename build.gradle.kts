plugins {
    kotlin("jvm") version "1.9.23" // Or the latest stable Kotlin version
}

group = "com.example"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter-api:5.10.2")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:5.10.2")
}

tasks.test {
    useJUnitPlatform()
    testLogging {
        events("passed", "skipped", "failed")
    }
}

// Optional: Task to make shell scripts executable if needed,
// especially if checked out on Windows and then used on Linux/macOS.
tasks.register("makeScriptsExecutable") {
    doLast {
        file("summarise.sh").setExecutable(true)
        file("capture_test_case.sh").setExecutable(true)
        println("Made summarise.sh and capture_test_case.sh executable.")
    }
}
