#!/usr/bin/env python3
"""Stream processor: converts claude --output-format stream-json --verbose to
human-readable text (stdout) and a real-time .buildcrew/.agent-activity file."""
import sys
import json
import os
import signal
import argparse
import tempfile
import time


def write_activity(activity_file, tool, tool_input, turn, max_turns):
    content = (
        f"TOOL={tool}\n"
        f"TOOL_INPUT={tool_input}\n"
        f"TURN={turn}\n"
        f"MAX_TURNS={max_turns}\n"
        f"STATUS=tool_use\n"
        f"TIMESTAMP={int(time.time())}\n"
    )
    activity_dir = os.path.dirname(activity_file) or '.'
    os.makedirs(activity_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=activity_dir)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(content)
        os.rename(tmp, activity_file)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def cleanup(activity_file):
    try:
        os.unlink(activity_file)
    except FileNotFoundError:
        pass


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.stdout.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(description='Stream processor for claude stream-json output')
    parser.add_argument('--activity-file', required=True, help='Path to write agent activity key=value file')
    parser.add_argument('--max-turns', type=int, required=True, help='Max turns passed to claude')
    args = parser.parse_args()

    turn = 0

    def handle_sigterm(sig, frame):
        cleanup(args.activity_file)
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_sigterm)

    try:
        for line in sys.stdin:
            line = line.rstrip('\n')
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                print(line)
                continue

            etype = event.get('type')
            if etype == 'assistant':
                turn += 1
                for block in event.get('message', {}).get('content', []):
                    btype = block.get('type')
                    if btype == 'text':
                        print(block.get('text', ''))
                    elif btype == 'tool_use':
                        tool = block.get('name', '')
                        raw = json.dumps(block.get('input', {}), separators=(',', ':'))
                        tool_input = raw[:80]
                        write_activity(args.activity_file, tool, tool_input, turn, args.max_turns)
            elif etype == 'result':
                if event.get('stop_reason') == 'max_turns':
                    print('Max turns limit reached')
            # system, user, rate_limit_event: ignore silently
    except BrokenPipeError:
        pass

    cleanup(args.activity_file)


if __name__ == '__main__':
    main()
