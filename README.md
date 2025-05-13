# Summarise Script Proving Grounds

This repository serves as the development and testing environment for the `summarise.sh` Bash script. The primary goal is to robustly test the script's ability to flatten a code repository into a single text file, respecting various ignore patterns and redacting sensitive information.

The finalised `summarise.sh` script is typically exported/updated to the Gist found at:
[https://gist.github.com/jlmalone/1858084a3a15b98e3758355e0a38bc28](https://gist.github.com/jlmalone/1858084a3a15b98e3758355e0a38bc28)

## Core Components

1.  **`summarise.sh`**: The Bash script kernel. It takes a directory, an output file path, and an optional custom ignore file path. It traverses the directory, concatenates text files, and applies redaction rules.
2.  **`capture_test_case.sh`**: A utility script to create test fixtures. When `summarise.sh` behaves unexpectedly on a project, this script can capture the relevant project state (files, custom ignores) into a new test fixture directory.
3.  **Kotlin Test Harness (Gradle Project)**:
    *   Located in `src/test/kotlin/`.
    *   Uses JUnit 5 to execute tests against `summarise.sh`.
    *   Tests are designed around "fixtures" stored in `src/test/resources/test_fixtures/`. Each fixture represents a specific scenario with a captured file structure and ignore rules.
    *   Two main testing approaches:
        *   **File Inclusion/Exclusion Tests**: Verifies that `summarise.sh` correctly identifies which files to include or exclude based on `.gitignore` files, default ignores, and custom ignore patterns. This uses a special `--test-list-files` mode of `summarise.sh`.
        *   **Full Summarisation Tests**: Runs the complete `summarise.sh` script and checks the content of the generated summary file for correct file inclusion, content integrity, and redaction.

## Project Structure

```
.
├── summarise.sh             # The main script being developed/tested
├── capture_test_case.sh     # Utility to create test fixtures
├── build.gradle.kts         # Gradle build file for the Kotlin test harness
├── settings.gradle.kts      # Gradle settings
├── gradlew                  # Gradle wrapper executable (Linux/macOS)
├── gradlew.bat              # Gradle wrapper executable (Windows)
├── gradle/                  # Gradle wrapper files
└── src/
    ├── main/                # Main source (currently unused, could hold future library code)
    └── test/
        ├── kotlin/          # Kotlin test sources
        │   └── vision/salient/SummariseScriptTests.kt
        └── resources/       # Test resources
            └── test_fixtures/ # Directory for test fixtures
                └── <fixture_name>/
                    ├── project_files/    # Copied file structure for the test case
                    ├── custom_ignores.txt # Custom ignore file for this test case
                    └── manifest.txt       # List of all files in project_files/
```

## Getting Started

### Prerequisites

*   Bash (for running the scripts)
*   Java JDK (version 17 or later recommended for Gradle)
*   Git (optional, but `summarise.sh` can leverage it if a `.git` directory is present)
*   (Optional) `rsync` for faster/better file copying in `capture_test_case.sh`.

### Setup

1.  Clone the repository.
2.  The Gradle wrapper (`gradlew`) is included. No separate Gradle installation is required.
3.  Ensure `summarise.sh` and `capture_test_case.sh` are executable:
    ```bash
    chmod +x summarise.sh capture_test_case.sh
    ```
    Alternatively, you can run the Gradle task:
    ```bash
RAW_gradlew: makeScriptsExecutable
```

### Running Tests

To run the Kotlin test suite:

```bash
./gradlew test
```

Test reports can be found in `build/reports/tests/test/index.html`.

### Creating a New Test Fixture

If you encounter a scenario where `summarise.sh` doesn't behave as expected on a particular project:

1.  Use the `capture_test_case.sh` script:
    ```bash
    ./capture_test_case.sh /path/to/your/project /path/to/your/custom_ignore.txt new_fixture_name
    ```
    This will create a new fixture directory under `src/test/resources/test_fixtures/new_fixture_name/` containing the project files and your custom ignore file.

2.  Add new test methods in `SummariseScriptTests.kt` that target this `new_fixture_name`.
    *   Define the expected included files.
    *   Assert against the output of `summarise.sh --test-list-files ...` for inclusion/exclusion.
    *   Optionally, write assertions for the full summary output, checking for specific file headers and content redaction.

## Development Workflow

1.  Modify `summarise.sh` with new features or bug fixes.
2.  Run `./gradlew test` to ensure existing tests pass.
3.  If a test fails or new behavior needs to be verified, create a new test fixture using `capture_test_case.sh`.
4.  Add corresponding tests in `SummariseScriptTests.kt`.
5.  Iterate until all tests pass and the script behaves as desired.
6.  Once satisfied, the updated `summarise.sh` can be copied/pushed to its Gist or other distribution points.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.