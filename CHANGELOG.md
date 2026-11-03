# Changelog

## 0.2.0

- `Adapters::ClaudeCLI` retries a rate limit: a process whose envelope has `api_error_status` 429 or 529 runs again, up to 5 processes, waiting 30s doubling each try plus up to 30s of jitter. `attempts` in the call's one record counts processes.
- Out of attempts, the adapter's limit is spent: the call raises `ClaudeCLI::RateLimitSpent` (a `JudgeError`), no new call starts, and calls still waiting stop. The gem never exits; the caller decides, using the error or `adapter.rate_limit.spent?`.

## 0.1.0

Initial release.

- Datasets, criteria, boolean results, the `all_epochs` reducer, run manifests, scorecards, comparability, and `Plan`.
- Assertions: `presence`, `absence`, `structure`, `identity`, `abstention`.
- Judge adapters: `Adapters::OmniAI` and `Adapters::ClaudeCLI`. Both accept a `calls:` collector that records each call's finish reason and latency.
