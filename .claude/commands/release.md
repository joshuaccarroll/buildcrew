---
name: release
description: Bump version, commit, tag, push, and create a GitHub release
arguments:
  - name: type
    description: "Version bump type: major, minor, or patch (default: minor)"
    required: false
---

# Release BuildCrew

Create a new release with version bump, git tag, and GitHub release.

## Instructions

1. **Determine bump type** from `$ARGUMENTS` (default: `minor`). Valid values: `major`, `minor`, `patch`.

2. **Read `VERSION`** to get the current version (format: `MAJOR.MINOR.PATCH`).

3. **Calculate new version** by incrementing the appropriate segment:
   - `major`: increment MAJOR, reset MINOR and PATCH to 0
   - `minor`: increment MINOR, reset PATCH to 0
   - `patch`: increment PATCH

4. **Check for uncommitted changes**. Run `git status --porcelain`. If there are uncommitted changes:
   - Show the user what's uncommitted (`git status --short`)
   - Ask if they want to commit everything first or abort
   - If committing: stage all changes, ask for a commit message (suggest one based on `git diff --stat`), commit
   - If aborting: stop

5. **Write the new version** to `VERSION`.

6. **Commit the version bump**:
   ```
   git add VERSION
   git commit -m "chore: Bump version to X.Y.Z"
   ```

7. **Tag the release**:
   ```
   git tag vX.Y.Z
   ```

8. **Push to origin**:
   ```
   git push origin main --tags
   ```

9. **Generate release notes** by reading `git log --oneline` from the previous tag to HEAD. Group commits by prefix:
   - `feat:` → "What's New"
   - `fix:` → "Bug Fixes"
   - `chore:`, `docs:`, `refactor:`, `test:` → "Other Changes"
   - Omit "chore: Bump version" commits from the notes

10. **Create a GitHub release**:
    ```
    gh release create vX.Y.Z --title "vX.Y.Z" --notes "<generated notes>"
    ```

11. **Confirm** by printing the release URL and new version number.
