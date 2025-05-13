package vision.salient

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path
import kotlin.io.path.absolutePathString
import kotlin.io.path.createDirectories
import kotlin.io.path.writeText
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class SummariseScriptTests {

    @TempDir
    lateinit var tempTestDir: Path // Used for temporary outputs of summarise.sh

    // Assumes summarise.sh and capture_test_case.sh are in the project root
    private val projectRoot = File(".").absoluteFile.parentFile 
    private val summariseScript = File(projectRoot, "summarise.sh").absolutePath
    // private val captureScript = File(projectRoot, "capture_test_case.sh").absolutePath // If needed for tests

    init {
        // Ensure scripts are executable (especially in CI or if cloned on Windows)
        File(summariseScript).setExecutable(true)
        // File(captureScript).setExecutable(true)
    }

    private fun runBashCommand(
        command: String,
        workDir: File? = null,
        envVars: Map<String, String> = emptyMap()
    ): ProcessResult {
        val processBuilder = ProcessBuilder("bash", "-c", command)
            .directory(workDir ?: projectRoot) // Default to project root if not specified
            .redirectErrorStream(false) // Keep stdout and stderr separate for better debugging

        val MergedEnvVars = System.getenv().toMutableMap()
        MergedEnvVars.putAll(envVars) // Add/override with specified envVars
        processBuilder.environment().clear()
        processBuilder.environment().putAll(MergedEnvVars)


        val process = processBuilder.start()
        val stdout = process.inputStream.bufferedReader().readText().trim()
        val stderr = process.errorStream.bufferedReader().readText().trim()
        val exitCode = process.waitFor()

        if (stderr.isNotEmpty() && exitCode != 0) {
            println("COMMAND STDERR for \"$command\":\n$stderr")
        }
         if (stdout.isNotEmpty() && exitCode != 0) {
            println("COMMAND STDOUT for \"$command\":\n$stdout")
        }


        return ProcessResult(stdout, stderr, exitCode)
    }

    data class ProcessResult(val stdout: String, val stderr: String, val exitCode: Int)

    private fun getFixtureDir(fixtureName: String): File {
        val fixtureDir = File(projectRoot, "src/test/resources/test_fixtures/$fixtureName")
        assertTrue(fixtureDir.exists() && fixtureDir.isDirectory, "Fixture directory '$fixtureName' not found at ${fixtureDir.absolutePath}")
        return fixtureDir
    }

    @Test
    fun `test list candidate files for custom_exclude fixture`() {
        val fixtureName = "custom_exclude"
        val fixtureDir = getFixtureDir(fixtureName)
        val projectFilesDir = File(fixtureDir, "project_files").absolutePath
        val customIgnoresFile = File(fixtureDir, "custom_ignores.txt").absolutePath

        // Enable VERBOSE logging from the script for this test
        val command = "VERBOSE=1 $summariseScript --test-list-files \"$projectFilesDir\" \"$customIgnoresFile\""
        
        println("Executing for test list: $command")
        val result = runBashCommand(command)

        if (result.exitCode != 0) {
            fail("Script execution failed with exit code ${result.exitCode}. STDERR:\n${result.stderr}\nSTDOUT:\n${result.stdout}")
        }
        
        println("--- Script STDOUT (Log output from summarise.sh) ---")
        println(result.stdout.lines().filter{ it.startsWith("LOG:")}.joinToString("\n"))
        println("--- End Script STDOUT ---")
        println("--- Script STDERR ---")
        if (result.stderr.isNotBlank()) println(result.stderr)
        println("--- End Script STDERR ---")


        val actualListedFiles = result.stdout.lines()
            .filterNot { it.startsWith("LOG:") } // Filter out log lines
            .filter { it.isNotBlank() } // Filter out any blank lines
            .sorted()
            .joinToString("\n")

        val expectedListedFiles = listOf(
            "file_to_include.txt",
            "subdir/another_to_include.md"
        ).sorted().joinToString("\n")
        
        assertEquals(expectedListedFiles, actualListedFiles, "List of candidate files did not match expected.")
    }

    @Test
    fun `test full summarisation for custom_exclude fixture`() {
        val fixtureName = "custom_exclude"
        val fixtureDir = getFixtureDir(fixtureName)
        val projectFilesDir = File(fixtureDir, "project_files").absolutePath
        val customIgnoresFile = File(fixtureDir, "custom_ignores.txt").absolutePath
        
        val tempOutputFile = tempTestDir.resolve("summary_output.txt").absolutePathString()

        // Enable VERBOSE logging from the script for this test
        val command = "VERBOSE=1 $summariseScript \"$projectFilesDir\" \"$tempOutputFile\" \"$customIgnoresFile\""
        println("Executing for full summary: $command")
        val result = runBashCommand(command)

        if (result.exitCode != 0) {
            fail("Script execution failed with exit code ${result.exitCode}. STDERR:\n${result.stderr}\nSTDOUT:\n${result.stdout}")
        }

        println("--- Script STDOUT (Log output from summarise.sh) ---")
        println(result.stdout.lines().filter{ it.startsWith("LOG:")}.joinToString("\n")) // Only log lines go to stdout due to redirection in script
        println("--- End Script STDOUT ---")
         println("--- Script STDERR (Log output from summarise.sh) ---")
        println(result.stderr.lines().filter{ it.startsWith("LOG:")}.joinToString("\n")) // Only log lines go to stdout due to redirection in script
        println("--- End Script STDERR ---")

        val summaryContent = File(tempOutputFile).readText()

        assertTrue(summaryContent.contains("=== FILE: file_to_include.txt ==="), "Output missing file_to_include.txt")
        assertTrue(summaryContent.contains("Content of file to include."), "Output missing content of file_to_include.txt")
        assertTrue(summaryContent.contains("=== FILE: subdir/another_to_include.md ==="), "Output missing subdir/another_to_include.md")
        assertTrue(summaryContent.contains("Markdown content."), "Output missing content of subdir/another_to_include.md")
        
        assertTrue(!summaryContent.contains("=== FILE: file_to_exclude.log ==="), "Output incorrectly included file_to_exclude.log")
    }
}
