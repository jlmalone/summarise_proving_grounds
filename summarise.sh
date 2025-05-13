#!/usr/bin/env bash

set -euo pipefail

VERBOSE=${VERBOSE:-0} # Set VERBOSE to 0 if not already set, allows override
BIN_CHECK="grep -Iq ." # Check for text files (grep -I exits 0 for text, non-0 for binary)
DEFAULT_EXTRA='.git/
*.log'

log(){ (( VERBOSE )) && echo "LOG: $*" >&2; }
usage(){ echo "Usage: $0 <dir> <out> [custom_ignore_file]" >&2; exit 1; }
usage_test_list(){ echo "Usage: $0 --test-list-files <dir> [custom_ignore_file]" >&2; exit 1; }


# --- Pattern Processing ---
EXTRA_PATTERNS=()
read_patterns() {
  local src="$1" source_name="$2"
  [[ ! -f "$src" ]] && { [[ -n "$source_name" ]] && log "Ignore source '$source_name' not found at '$src'"; return; }
  log "Reading ignore patterns from $source_name at '$src'"
  while IFS= read -r line; do
    line="${line%%#*}" # Strip inline comments
    [[ -z "${line//[[:space:]]/}" ]] && continue # Skip if blank after comment removal
    line="$(echo "$line" | sed 's/[[:space:]]*$//')" # Remove trailing spaces
    line="${line%$'\r'}" # Remove trailing CR
    line="$(echo "$line" | sed 's/^[[:space:]]*//')" # Remove leading spaces
    if [[ -n "$line" ]]; then
        log "Adding pattern: [$line]"
        EXTRA_PATTERNS+=("$line")
    fi
  done < "$src"
}

# --- Ignore Matching Logic ---
# Processed ignore patterns are stored in EXTRA_PATTERNS
# This function checks if 'rel_path' matches any of these patterns.
# Returns 0 if a match is found (should be ignored/skipped).
# Returns 1 if no match is found (should NOT be skipped).
matches_extra_ignore() {
  local rel_path="$1"
  local pattern
  local p_temp # temporary pattern for manipulation

  for pattern in "${EXTRA_PATTERNS[@]}"; do
    if [[ "$pattern" == /* ]]; then
      p_temp="${pattern#/}"
      if [[ "$p_temp" == */ ]]; then
        local dir_base="${p_temp%/}"
        if [[ "$rel_path" == "$dir_base" || "$rel_path" == "$p_temp"* ]]; then
          log "Ignore match (anchored dir): '$rel_path' vs '$pattern'"
          return 0
        fi
      else
        if [[ "$rel_path" == $p_temp ]]; then
          log "Ignore match (anchored file/glob): '$rel_path' vs '$pattern'"
          return 0
        fi
      fi
    elif [[ "$pattern" == */ ]]; then
      local dir_name="${pattern%/}"
      if [[ "$rel_path" == "$dir_name" || \
            "$rel_path" == "$dir_name/"* || \
            "$rel_path" == *"/${dir_name}/"* ]]; then
        log "Ignore match (unanchored dir): '$rel_path' vs '$pattern'"
        return 0
      fi
    elif [[ "$pattern" == *"/"* ]]; then
      if [[ "$rel_path" == $pattern ]]; then
        log "Ignore match (unanchored path-spec): '$rel_path' vs '$pattern'"
        return 0
      fi
    else
      if [[ "${rel_path##*/}" == $pattern ]]; then
        log "Ignore match (basename/glob): '$rel_path' vs '$pattern'"
        return 0
      fi
    fi
  done
  return 1 # No ignore patterns matched
}

# --- File Skipping Decision ---
skip_file() {
  local f_abs_path="$1" rel_path="$2"
  local filename="${rel_path##*/}"

  if [[ "$filename" == ".gitignore" ]]; then
    log "skip hardcoded: $rel_path (.gitignore)"
    return 0
  fi
  matches_extra_ignore "$rel_path" && { log "skip extra : $rel_path"; return 0; }
  # Check for binary files. grep -I returns 0 for text, non-zero for binary. We skip on non-zero.
  $BIN_CHECK "$f_abs_path"         || { log "skip binary: $rel_path"; return 0; }
  [[ -s "$f_abs_path" ]]           || { log "skip empty : $rel_path"; return 0; }
  return 1 # Do not skip
}

# --- File Appending and Redaction ---
append_file_to_output() {
  local f_abs_path="$1" rel_path="$2" output_target_file="$3"
  {
    printf '\n\n=== FILE: %s ===\n\n' "$rel_path"
    tr -d '\000' < "$f_abs_path" \
      | sed -E \
          -e 's/("(key|password|token|secret)"[[:space:]]*:[[:space:]]*")[^"]+"/\1REDACTED"/gi' \
          -e 's/((key|password|token|secret)[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1REDACTED/gi' \
          -e 's/((key|password|token|secret)[[:space:]]*:[[:space:]]*)[^[:space:]]+/\1REDACTED/gi'
  } >> "$output_target_file"
}

# --- Core Logic Functions ---
process_repository_files() {
    local root_dir="$1" output_file_path="$2"
    
    if [[ -d "$root_dir/.git" ]] && command -v git >/dev/null; then
      log "Git repo detected, using 'git ls-files' in '$root_dir'..."
      git -C "$root_dir" ls-files -co --exclude-standard -z \
        | while IFS= read -r -d '' rel; do
            local f_abs="$root_dir/$rel"
            if [[ -f "$f_abs" ]] && [[ -r "$f_abs" ]]; then
                if ! skip_file "$f_abs" "$rel"; then
                    log "add git: $rel"
                    append_file_to_output "$f_abs" "$rel" "$output_file_path"
                fi
            else
                 log "skip non-file/unreadable (git): $rel"
            fi
          done
    else
      log "No .git directory or git command not found in '$root_dir' — using 'find'..."
      find "$root_dir" -type f -print0 |
        while IFS= read -r -d '' f_abs; do
          local rel="${f_abs#$root_dir/}"
          # Ensure rel path doesn't start with / if root_dir was '.'
          rel="${rel#./}"
          if [[ -r "$f_abs" ]]; then
             if ! skip_file "$f_abs" "$rel"; then
                 log "add find: $rel"
                 append_file_to_output "$f_abs" "$rel" "$output_file_path"
             fi
          else
              log "skip unreadable (find): $rel"
          fi
        done
    fi
}

list_candidate_files_for_test() {
    local root_dir="$1"
    local custom_ignore_file="${2:-}" # Optional
    EXTRA_PATTERNS=() # Reset for this specific run

    [[ ! -d "$root_dir" ]] && { echo "ERROR (test-list-files): Directory '$root_dir' not found." >&2; exit 1; }
    root_dir="$(cd "$root_dir" && pwd -P)" # Ensure absolute path

    log "TEST_LIST_FILES: Root dir: $root_dir"
    log "TEST_LIST_FILES: Custom ignore file: ${custom_ignore_file:-None}"

    local tmp_default_ignores
    tmp_default_ignores=$(mktemp)
    printf '%s\n' "$DEFAULT_EXTRA" > "$tmp_default_ignores"
    read_patterns "$tmp_default_ignores" "Defaults (for test-list)"
    rm -f "$tmp_default_ignores"

    if [[ -n "$custom_ignore_file" ]]; then
        if [[ -f "$custom_ignore_file" ]]; then
            read_patterns "$custom_ignore_file" "Custom file (for test-list)"
        else
            log "TEST_LIST_FILES: Custom ignore file '$custom_ignore_file' not found."
        fi
    fi
    
    log "TEST_LIST_FILES: Compiled ${#EXTRA_PATTERNS[@]} extra ignore patterns."

    if [[ -d "$root_dir/.git" ]] && command -v git >/dev/null; then
      log "TEST_LIST_FILES: Using 'git ls-files' in '$root_dir'..."
      git -C "$root_dir" ls-files -co --exclude-standard -z \
        | while IFS= read -r -d '' rel; do
            local f_abs="$root_dir/$rel"
            if [[ -f "$f_abs" ]] && [[ -r "$f_abs" ]]; then
                if ! skip_file "$f_abs" "$rel"; then
                    echo "$rel" # Output relative path if not skipped
                fi
            fi
          done
    else
      log "TEST_LIST_FILES: No .git directory or git command not found — using 'find' in '$root_dir'..."
      find "$root_dir" -type f -print0 |
        while IFS= read -r -d '' f_abs; do
          local rel="${f_abs#$root_dir/}"
          rel="${rel#./}" # Ensure rel path doesn't start with / if root_dir was '.'
          if [[ -r "$f_abs" ]]; then
             if ! skip_file "$f_abs" "$rel"; then
                 echo "$rel" # Output relative path if not skipped
             fi
          fi
        done
    fi
}

# --- Main Execution Logic ---
main_summarise() {
    (( $# < 2 )) && usage
    local root_input_dir="$1"
    local output_target_file="$2"
    local custom_ignore_file_path="${3:-}"

    root_input_dir="$(cd "$root_input_dir" && pwd -P)"
    # Ensure output_target_file is absolute or correctly relative to PWD
    if [[ "$output_target_file" != /* ]]; then
        output_target_file="$(pwd -P)/$output_target_file"
    else
        output_target_file="$(cd "$(dirname "$output_target_file")" && pwd -P)/$(basename "$output_target_file")"
    fi
    
    [[ ! -d "$root_input_dir" ]] && { echo "ERROR: Input directory '$root_input_dir' not found." >&2; exit 1; }
    
    # Ensure output file's directory exists
    mkdir -p "$(dirname "$output_target_file")"
    # Ensure output file exists and is empty for appending
    > "$output_target_file"
    
    EXTRA_PATTERNS=() # Clear/initialize for the run

    local tmp_default_ignores
    tmp_default_ignores=$(mktemp)
    printf '%s\n' "$DEFAULT_EXTRA" > "$tmp_default_ignores"
    read_patterns "$tmp_default_ignores" "Defaults"
    rm -f "$tmp_default_ignores"

    if [[ -n "$custom_ignore_file_path" ]]; then
        if [[ -f "$custom_ignore_file_path" ]]; then
            read_patterns "$custom_ignore_file_path" "Custom file"
        else
            log "Custom ignore file '$custom_ignore_file_path' not found. Proceeding without it."
        fi
    fi
    
    log "Compiled ${#EXTRA_PATTERNS[@]} extra ignore patterns for summarisation."

    process_repository_files "$root_input_dir" "$output_target_file"

    log "DONE → $(wc -c <"$output_target_file") bytes written to '$output_target_file'."
    # head -4 "$output_target_file" >&2 # Potentially noisy for tests, can be enabled if needed
}


# --- Script Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${1:-}" == "--test-list-files" ]]; then
    shift # remove --test-list-files
    (( $# < 1 || $# > 2 )) && usage_test_list # Expects <dir> [custom_ignore_file]
    target_dir="$1"
    custom_ignores_for_test_list="${2:-}"
    list_candidate_files_for_test "$target_dir" "$custom_ignores_for_test_list"
  else
    main_summarise "$@"
  fi
fi
