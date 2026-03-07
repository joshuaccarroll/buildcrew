#!/usr/bin/env bats
# AC-03: stream_processor.bats timing test uses polling, not bare sleep

load '../setup.bash'

@test "AC-03: stream_processor.bats has polling loop" {
    # Should have a while loop with [ \$i -lt 50 ] or similar polling construct
    grep -q 'while.*\[.*-lt' tests/unit/stream_processor.bats
}

@test "AC-03: stream_processor.bats polling loop uses sleep 0.1" {
    # Polling loop should use short sleep intervals
    grep -q 'sleep 0.1' tests/unit/stream_processor.bats
}

@test "AC-03: stream_processor.bats no bare sleep before grep" {
    # The old bare 'sleep 1' before first grep should be replaced
    # Check that there's no pattern like "sleep 1" followed by grep
    ! grep -A1 'sleep 1$' tests/unit/stream_processor.bats | grep -q 'grep'
}

@test "AC-03: stream_processor.bats preserves sleep 2 in input pipe" {
    # The 'sleep 2' in the input pipe { echo '...'; sleep 2; } should still exist
    grep -q 'sleep 2;' tests/unit/stream_processor.bats
}
