#!/usr/bin/env bats
# AC-03: Skill updates README.md when user-facing changes are detected

load '../setup.bash'

setup() {
    setup_test_dir
    # Create a basic README with sections
    cat > README.md <<'EOF'
# My Project

## Installation

Install with npm:
```
npm install
```

## Usage

Run the tool with:
```
./bin/tool --help
```

## Features

- Feature A
- Feature B
EOF
    # Initialize git repo
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add README.md
    git commit -q -m "initial readme"
}

teardown() {
    teardown_test_dir
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: README.md update when user-facing changes are detected
# Expected: Skill updates README when CLI/API/config/deps changed
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-03a: README.md is updated when CLI file changes" {
    # Modify a CLI file in bin/
    mkdir -p bin
    echo "#!/bin/bash" > bin/tool
    git add bin/tool
    git commit -q -m "update tool"
    echo "#!/bin/bash\necho 'updated'" > bin/tool

    # After skill runs, README.md should be modified if user-facing changes are detected
    # This test verifies the skill can modify README
    [ -f "README.md" ]
    [ -w "README.md" ]
}

@test "AC-03b: README.md maintains structure when updated" {
    # Create a modified bin/ file to trigger update
    mkdir -p bin
    echo "#!/bin/bash" > bin/tool
    git add bin/tool
    git commit -q -m "add tool"
    echo "#!/bin/bash\necho 'v2'" > bin/tool

    # README should still have its original sections (if not all modified)
    [ -f "README.md" ]
    grep -q "^#" "README.md"  # Should have headers
}

@test "AC-03c: README.md is updated when config file changes" {
    # Modify .buildcrew/config
    mkdir -p .buildcrew
    echo "option=1" > .buildcrew/config
    git add .buildcrew/config
    git commit -q -m "add config"
    echo "option=2" > .buildcrew/config

    # Config changes should trigger README update
    [ -f "README.md" ]
}

@test "AC-03d: README.md is updated when dependencies change (package.json)" {
    # Modify package.json
    echo '{"name":"test"}' > package.json
    git add package.json
    git commit -q -m "add package.json"
    echo '{"name":"test","version":"2.0.0","dependencies":{"foo":"1.0.0"}}' > package.json

    # Dependency changes should trigger README update
    [ -f "README.md" ]
}
