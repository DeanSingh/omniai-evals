# Changelog

## 0.1.0

Initial release.

- Datasets, criteria, boolean results, the `all_epochs` reducer, run manifests, scorecards, comparability, and `Plan`.
- Assertions: `presence`, `absence`, `structure`, `identity`, `abstention`.
- Judge adapters: `Adapters::OmniAI` and `Adapters::ClaudeCLI`. Both accept a `calls:` collector that records each call's finish reason and latency.
