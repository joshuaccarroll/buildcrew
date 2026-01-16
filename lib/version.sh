#!/bin/bash
# BuildCrew Version Management

# Get the installed version
get_version() {
    local version_file="$BUILDCREW_HOME/VERSION"
    if [ -f "$version_file" ]; then
        cat "$version_file"
    else
        echo "unknown"
    fi
}

# Compare versions (returns 0 if $1 < $2)
version_lt() {
    [ "$1" = "$2" ] && return 1
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [ -z "${ver2[i]}" ]; then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
    done
    return 1
}
