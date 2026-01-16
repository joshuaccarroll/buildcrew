#!/bin/bash
# BuildCrew Update Checker

CACHE_FILE="$HOME/.buildcrew/.update-cache"
CACHE_TTL=3600  # 1 hour in seconds

# Fetch latest version from GitHub
fetch_latest_version() {
    local latest
    latest=$(curl -s --max-time 5 "https://api.github.com/repos/joshuacarroll/buildcrew/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    echo "$latest"
}

# Check for updates (with caching)
check_for_updates() {
    local current_version=$(get_version)

    # Skip if version unknown
    if [ "$current_version" = "unknown" ]; then
        return
    fi

    # Ensure cache directory exists
    mkdir -p "$(dirname "$CACHE_FILE")"

    # Check if cache is fresh
    if [ -f "$CACHE_FILE" ]; then
        local cache_time
        if [[ "$OSTYPE" == "darwin"* ]]; then
            cache_time=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
        else
            cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        fi
        local now=$(date +%s)
        local age=$((now - cache_time))

        if [ $age -lt $CACHE_TTL ]; then
            # Use cached result
            local cached_version=$(cat "$CACHE_FILE")
            if [ -n "$cached_version" ] && [ "$cached_version" != "$current_version" ]; then
                print_update_notice "$current_version" "$cached_version"
            fi
            return
        fi
    fi

    # Fetch latest version
    local latest_version=$(fetch_latest_version)

    # Cache the result
    if [ -n "$latest_version" ]; then
        echo "$latest_version" > "$CACHE_FILE"

        # Check if update available
        if [ "$latest_version" != "$current_version" ] && version_lt "$current_version" "$latest_version"; then
            print_update_notice "$current_version" "$latest_version"
        fi
    fi
}

# Print update notice
print_update_notice() {
    local current="$1"
    local latest="$2"
    echo -e "\033[33m⬆ Update available: v$current → v$latest\033[0m"
    echo "  Run 'buildcrew update' to upgrade"
    echo ""
}
