#!/usr/bin/env bash
#
# test-tts.sh - Test suite for tts CLI tool
#
# Usage:
#   ./test-tts.sh           # Run unit tests only
#   ./test-tts.sh unit      # Run unit tests only
#   TTS_LIVE_TESTS=1 ./test-tts.sh live  # Run integration tests (requires API key)
#   ./test-tts.sh all       # Run all tests (requires TTS_LIVE_TESTS=1 for live)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TTS_CMD="${SCRIPT_DIR}/tts"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temporary directory for test outputs
TEST_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Test Framework ---

setup() {
    TEST_DIR=$(mktemp -d)
    export HOME="${TEST_DIR}/home"
    mkdir -p "${HOME}/.claude/output/audio"
}

teardown() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

trap teardown EXIT

pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then
        echo "      $2"
    fi
}

skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
}

run_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    if "$test_name"; then
        pass "$test_name"
    else
        fail "$test_name"
    fi
}

# --- Assertion Helpers ---

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "Expected: $expected"
        echo "Actual: $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo "Expected to contain: $needle"
        echo "Actual: $haystack"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        return 0
    else
        echo "File does not exist: $file"
        return 1
    fi
}

assert_valid_wav() {
    local file="$1"
    [[ -f "$file" ]] || { echo "File not created"; return 1; }
    [[ $(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null) -gt 1024 ]] || { echo "File too small"; return 1; }
    file "$file" | grep -qi "WAVE\|RIFF" || { echo "Invalid WAV format"; return 1; }
    return 0
}

assert_valid_mp3() {
    local file="$1"
    [[ -f "$file" ]] || { echo "File not created"; return 1; }
    [[ $(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null) -gt 512 ]] || { echo "File too small"; return 1; }
    file "$file" | grep -qi "audio\|MPEG\|MP3" || { echo "Invalid MP3 format"; return 1; }
    return 0
}

# --- Unit Tests (No API calls) ---

test_help_flag() {
    local output
    output=$("$TTS_CMD" --help 2>&1) || true
    assert_contains "$output" "Usage:"
    assert_contains "$output" "Options:"
    assert_contains "$output" "--voice"
}

test_list_voices() {
    local output
    output=$("$TTS_CMD" --list-voices 2>&1)
    assert_contains "$output" "en-GB-SoniaNeural"
    assert_contains "$output" "en-GB-RyanNeural"
    assert_contains "$output" "Female"
    assert_contains "$output" "Male"
}

test_dry_run_default_voice() {
    local output
    output=$("$TTS_CMD" --dry-run "Hello world" 2>&1)
    assert_contains "$output" "Voice: en-GB-SoniaNeural"
    assert_contains "$output" "Format: wav"
    assert_contains "$output" "en-GB-SoniaNeural"
}

test_dry_run_custom_voice() {
    local output
    output=$("$TTS_CMD" --dry-run -v en-GB-RyanNeural "Hello world" 2>&1)
    assert_contains "$output" "Voice: en-GB-RyanNeural"
}

test_dry_run_mp3_format() {
    local output
    output=$("$TTS_CMD" --dry-run -f mp3 "Hello world" 2>&1)
    assert_contains "$output" "Format: mp3"
    assert_contains "$output" "audio-24khz-160kbitrate-mono-mp3"
}

test_dry_run_prosody() {
    local output
    output=$("$TTS_CMD" --dry-run -r fast -p high "Hello" 2>&1)
    assert_contains "$output" "Rate: fast"
    assert_contains "$output" "Pitch: high"
    assert_contains "$output" "prosody"
}

test_ssml_xml_escaping() {
    local output
    output=$("$TTS_CMD" --dry-run "5 > 3 & 2 < 4" 2>&1)
    assert_contains "$output" "&gt;"
    assert_contains "$output" "&lt;"
    assert_contains "$output" "&amp;"
}

test_ssml_quote_escaping() {
    local output
    output=$("$TTS_CMD" --dry-run 'He said "hello" and '"'"'goodbye'"'" 2>&1)
    assert_contains "$output" "&quot;"
    assert_contains "$output" "&apos;"
}

test_filename_generation() {
    local output
    output=$("$TTS_CMD" --dry-run "Test" 2>&1)
    # Should contain timestamp pattern
    assert_contains "$output" "Output:"
    assert_contains "$output" "tts_"
    assert_contains "$output" ".wav"
}

# --- Input Validation Tests ---

test_empty_input() {
    local output
    if output=$("$TTS_CMD" "" 2>&1); then
        echo "Should have failed on empty input"
        return 1
    fi
    assert_contains "$output" "No text provided"
}

test_invalid_voice() {
    local output
    if output=$("$TTS_CMD" -v invalid-voice "Hello" 2>&1); then
        echo "Should have failed on invalid voice"
        return 1
    fi
    assert_contains "$output" "Unknown voice"
}

test_invalid_format() {
    local output
    if output=$("$TTS_CMD" -f xyz "Hello" 2>&1); then
        echo "Should have failed on invalid format"
        return 1
    fi
    assert_contains "$output" "Unknown format"
}

test_invalid_rate() {
    local output
    if output=$("$TTS_CMD" -r invalid "Hello" 2>&1); then
        echo "Should have failed on invalid rate"
        return 1
    fi
    assert_contains "$output" "Unknown rate"
}

test_invalid_pitch() {
    local output
    if output=$("$TTS_CMD" -p invalid "Hello" 2>&1); then
        echo "Should have failed on invalid pitch"
        return 1
    fi
    assert_contains "$output" "Unknown pitch"
}

test_unknown_option() {
    local output
    if output=$("$TTS_CMD" --unknown-flag "Hello" 2>&1); then
        echo "Should have failed on unknown option"
        return 1
    fi
    assert_contains "$output" "Unknown option"
}

test_unwritable_output_dir() {
    # Create unwritable directory
    local unwritable_dir="${TEST_DIR}/unwritable"
    mkdir -p "$unwritable_dir"
    chmod 000 "$unwritable_dir"

    local output
    if output=$("$TTS_CMD" --dry-run "Hello" "${unwritable_dir}/test.wav" 2>&1); then
        chmod 755 "$unwritable_dir"  # Restore for cleanup
        echo "Should have failed on unwritable directory"
        return 1
    fi
    chmod 755 "$unwritable_dir"  # Restore for cleanup
    return 0
}

# --- Integration Tests (Live API, gated) ---

test_live_wav_synthesis() {
    if [[ "${TTS_LIVE_TESTS:-}" != "1" ]]; then
        skip "TTS_LIVE_TESTS not set"
        return 0
    fi

    local output_file="${TEST_DIR}/test_$$.wav"
    local result
    result=$("$TTS_CMD" "Hello, this is a test." "$output_file" 2>&1) || {
        echo "Command failed: $result"
        return 1
    }

    assert_valid_wav "$output_file"
}

test_live_mp3_synthesis() {
    if [[ "${TTS_LIVE_TESTS:-}" != "1" ]]; then
        skip "TTS_LIVE_TESTS not set"
        return 0
    fi

    local output_file="${TEST_DIR}/test_$$.mp3"
    local result
    result=$("$TTS_CMD" -f mp3 "Hello, this is an MP3 test." "$output_file" 2>&1) || {
        echo "Command failed: $result"
        return 1
    }

    assert_valid_mp3 "$output_file"
}

test_live_male_voice() {
    if [[ "${TTS_LIVE_TESTS:-}" != "1" ]]; then
        skip "TTS_LIVE_TESTS not set"
        return 0
    fi

    local output_file="${TEST_DIR}/test_ryan_$$.wav"
    local result
    result=$("$TTS_CMD" -v en-GB-RyanNeural "Hello from Ryan." "$output_file" 2>&1) || {
        echo "Command failed: $result"
        return 1
    }

    assert_valid_wav "$output_file"
}

test_live_prosody() {
    if [[ "${TTS_LIVE_TESTS:-}" != "1" ]]; then
        skip "TTS_LIVE_TESTS not set"
        return 0
    fi

    local output_file="${TEST_DIR}/test_prosody_$$.wav"
    local result
    result=$("$TTS_CMD" -r fast -p high "Speaking quickly with high pitch." "$output_file" 2>&1) || {
        echo "Command failed: $result"
        return 1
    }

    assert_valid_wav "$output_file"
}

# --- Test Runner ---

run_unit_tests() {
    echo "=== Running Unit Tests ==="
    run_test test_help_flag
    run_test test_list_voices
    run_test test_dry_run_default_voice
    run_test test_dry_run_custom_voice
    run_test test_dry_run_mp3_format
    run_test test_dry_run_prosody
    run_test test_ssml_xml_escaping
    run_test test_ssml_quote_escaping
    run_test test_filename_generation
    echo ""
    echo "=== Running Input Validation Tests ==="
    run_test test_empty_input
    run_test test_invalid_voice
    run_test test_invalid_format
    run_test test_invalid_rate
    run_test test_invalid_pitch
    run_test test_unknown_option
    run_test test_unwritable_output_dir
}

run_live_tests() {
    echo ""
    echo "=== Running Integration Tests (Live API) ==="
    if [[ "${TTS_LIVE_TESTS:-}" != "1" ]]; then
        echo "Set TTS_LIVE_TESTS=1 to run live API tests"
        return 0
    fi
    run_test test_live_wav_synthesis
    run_test test_live_mp3_synthesis
    run_test test_live_male_voice
    run_test test_live_prosody
}

print_summary() {
    echo ""
    echo "=== Test Summary ==="
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# --- Main ---

main() {
    setup

    local mode="${1:-unit}"

    case "$mode" in
        unit)
            run_unit_tests
            ;;
        live)
            run_live_tests
            ;;
        all)
            run_unit_tests
            run_live_tests
            ;;
        *)
            echo "Usage: $0 [unit|live|all]"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
