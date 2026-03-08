#!/usr/bin/env bats

load '../setup.bash'

SP="$BATS_TEST_DIRNAME/../../lib/stream_processor.py"

teardown() {
    rm -f /tmp/sp_test_*
}

@test "assistant/text event: stdout contains text" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo '{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hello world\"}]}}' | python3 \"$SP\" --activity-file /tmp/sp_test_text --max-turns 10"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "assistant/tool_use event: activity file written with correct fields" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    { echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"src/auth/login.py"}}]}}'; sleep 2; } \
      | python3 "$SP" --activity-file /tmp/sp_test_tool --max-turns 10 &
    local PID=$!
    # Poll up to 5 seconds (50 × 100 ms) for the activity file to contain expected data
    local i=0
    while [ $i -lt 50 ]; do
        [ -f /tmp/sp_test_tool ] && grep -qx 'TOOL=Read' /tmp/sp_test_tool 2>/dev/null && break
        sleep 0.1
        i=$((i + 1))
    done
    [ -f /tmp/sp_test_tool ] || { echo "Activity file never written within 5s"; return 1; }
    local content
    content=$(<"/tmp/sp_test_tool")
    grep -qx 'TOOL=Read' <<<"$content"
    grep -q 'TOOL_INPUT={"file_path' <<<"$content"
    grep -qx 'TURN=1' <<<"$content"
    grep -qx 'MAX_TURNS=10' <<<"$content"
    grep -qx 'STATUS=tool_use' <<<"$content"
    wait $PID
    [ $? -eq 0 ]
}

@test "result/max_turns event: stdout contains 'Max turns limit reached'" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo '{\"type\":\"result\",\"stop_reason\":\"max_turns\"}' | python3 \"$SP\" --activity-file /tmp/sp_test_result --max-turns 10"
    [ "$status" -eq 0 ]
    [ "$output" = "Max turns limit reached" ]
}

@test "invalid JSON: passed through unchanged to stdout" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo 'not json here' | python3 \"$SP\" --activity-file /tmp/sp_test_invalid --max-turns 10"
    [ "$status" -eq 0 ]
    [ "$output" = "not json here" ]
}

@test "EOF after tool_use: activity file deleted and exit code 0" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo '{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"ls\"}}]}}' | python3 \"$SP\" --activity-file /tmp/sp_test_eof --max-turns 10"
    [ "$status" -eq 0 ]
    [ ! -f /tmp/sp_test_eof ]
}

@test "clean EOF on empty input: exit code 0 and no output" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo -n '' | python3 \"$SP\" --activity-file /tmp/sp_test_empty --max-turns 10"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "rate_limit_event: stdout contains 'Rate limit reached'" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo '{\"type\":\"rate_limit_event\"}' | python3 \"$SP\" --activity-file /tmp/sp_test_rate_limit --max-turns 10"
    [ "$status" -eq 0 ]
    [ "$output" = "Rate limit reached" ]
}

@test "error event with rate_limit_error: stdout contains 'Rate limit reached'" {
    if ! command -v python3 &>/dev/null; then skip "python3 not available"; fi
    run bash -c "echo '{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\"}}' | python3 \"$SP\" --activity-file /tmp/sp_test_rate_error --max-turns 10"
    [ "$status" -eq 0 ]
    [ "$output" = "Rate limit reached" ]
}
