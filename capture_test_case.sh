#!/usr/bin/env bash

set -euo pipefail

# --- Usage ---
usage() {
  echo "Usage: $0 <project_root_dir> <custom_ignore_file_path> <fixture_name> [test_fixtures_base_dir]"
  echo ""
  echo "  project_root_dir:         The root of the codebase to capture."
  echo "  custom_ignore_file_path:  Path to the custom_ignore.txt file used."
  echo "  fixture_name:             A descriptive name for this test case (e.g., 'projectX_specific_scenario')."
  echo "  test_fixtures_base_dir:   Optional. Base directory to store fixtures."
  echo "                            Defaults to './src/test/resources/test_fixtures/' relative to this script's CWD."
  exit 1
}

# --- Argument Parsing ---
if (( $# < 3 || $# > 4 )); then
  usage
fi

PROJECT_ROOT_DIR="$1"
CUSTOM_IGNORE_FILE_PATH="$2"
FIXTURE_NAME="$3"
TEST_FIXTURES_BASE_DIR="${4:-./src/test/resources/test_fixtures}" # Default value

# --- Validate Inputs ---
if [[ ! -d "$PROJECT_ROOT_DIR" ]]; then
  echo "ERROR: Project root directory '$PROJECT_ROOT_DIR' not found." >&2
  exit 1
fi
if [[ ! -f "$CUSTOM_IGNORE_FILE_PATH" ]]; then
  echo "ERROR: Custom ignore file '$CUSTOM_IGNORE_FILE_PATH' not found." >&2
  exit 1
fi
if [[ -z "$FIXTURE_NAME" ]]; then
  echo "ERROR: Fixture name cannot be empty." >&2
  exit 1
fi

# --- Prepare Paths ---
PROJECT_ROOT_DIR_ABS="$(cd "$PROJECT_ROOT_DIR" && pwd -P)"
CUSTOM_IGNORE_FILE_PATH_ABS="$(cd "$(dirname "$CUSTOM_IGNORE_FILE_PATH")" && pwd -P)/$(basename "$CUSTOM_IGNORE_FILE_PATH")"

FIXTURE_PATH_ABS="$(pwd -P)/$TEST_FIXTURES_BASE_DIR/$FIXTURE_NAME" # Assume relative to CWD for base dir
FIXTURE_PROJECT_FILES_DIR="$FIXTURE_PATH_ABS/project_files"
FIXTURE_CUSTOM_IGNORES_FILE="$FIXTURE_PATH_ABS/custom_ignores.txt"
FIXTURE_MANIFEST_FILE="$FIXTURE_PATH_ABS/manifest.txt"

echo "--- Capture Details ---"
echo "Project Root:         $PROJECT_ROOT_DIR_ABS"
echo "Custom Ignores:       $CUSTOM_IGNORE_FILE_PATH_ABS"
echo "Fixture Name:         $FIXTURE_NAME"
echo "Fixture Base Dir:     $(dirname "$FIXTURE_PATH_ABS")"
echo "Full Fixture Path:    $FIXTURE_PATH_ABS"
echo "-----------------------"

# --- Create Fixture Directory ---
if [[ -d "$FIXTURE_PATH_ABS" ]]; then
  echo "WARNING: Fixture directory '$FIXTURE_PATH_ABS' already exists. Overwriting."
  rm -rf "$FIXTURE_PATH_ABS"
fi
mkdir -p "$FIXTURE_PROJECT_FILES_DIR"
echo "Created fixture directory: $FIXTURE_PATH_ABS"

# --- Copy Custom Ignore File ---
cp "$CUSTOM_IGNORE_FILE_PATH_ABS" "$FIXTURE_CUSTOM_IGNORES_FILE"
echo "Copied custom ignores to: $FIXTURE_CUSTOM_IGNORES_FILE"

# --- Copy Project Files ---
# Using rsync for more control, especially if we want to exclude .git of the source project later.
# For now, a simple copy. Add --exclude='.git' if you don't want to copy the .git dir from the source.
echo "Copying project files from '$PROJECT_ROOT_DIR_ABS' to '$FIXTURE_PROJECT_FILES_DIR'..."
if command -v rsync &> /dev/null; then
    rsync -a --exclude='.git' "$PROJECT_ROOT_DIR_ABS/" "$FIXTURE_PROJECT_FILES_DIR/"
else
    echo "rsync not found, using cp -R. Consider installing rsync for better copy capabilities."
    # cp -R can be problematic with symlinks or specific permissions, rsync is generally better.
    # Ensure source path ends with / to copy contents, not the directory itself into project_files
    cp -R "$PROJECT_ROOT_DIR_ABS/." "$FIXTURE_PROJECT_FILES_DIR/"
fi
echo "Project files copied."

# --- Generate Manifest File ---
echo "Generating manifest file: $FIXTURE_MANIFEST_FILE"
(
  cd "$FIXTURE_PROJECT_FILES_DIR" || exit 1
  find . -type f -print0 | while IFS= read -r -d $'\0' file_path; do
    # Strip leading ./
    echo "${file_path#./}"
  done | sort > "$FIXTURE_MANIFEST_FILE"
)
echo "Manifest generated."

echo "--- Capture Complete ---"
echo "Fixture '$FIXTURE_NAME' created successfully at '$FIXTURE_PATH_ABS'"
echo "You can now write a Kotlin test targeting this fixture."
