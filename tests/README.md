# Tests

## Directory Structure

- `tests/unit/` — unit tests run by `./test.sh`
- `tests/integration/` — integration tests run by `./test.sh`
- `tests/e2e/` — end-to-end tests run by `./test.sh --e2e`
- `tests/tdd/` — **TDD scaffold tests**: written before implementation as pre-implementation failing tests
  that define expected behavior. These are intentionally excluded from `./test.sh` because the features
  they test may not yet be implemented; running them would produce misleading failure noise. Run them
  individually with `bats tests/tdd/<file>.bats` after implementing the relevant feature to verify
  acceptance criteria.
