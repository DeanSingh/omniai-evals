# omniai-evals — the contract between the gem and its consumers

The gem and every consumer build against this file. The
gem ships sample files for every format below and tests that load them; a consumer that cannot
read the samples has found a contract break, not a bug to work around.

Contract version: **1**. Every file the gem reads or writes carries `"contract": 1`.

## 1. What lives where

The gem holds structure and grading, and knows nothing about any dataset, model, or product:
the nouns in §2, the file formats in §3, the interfaces in §4, assertions, the reducer, the
comparability check, the scorecard, calibration, and the adapters that reach a model. It also
holds one **demo bench** — a small synthetic, PHI-free dataset with keys — so the gem always
has a consumer of its own and a reproducible example.

Consumers hold the datasets, the criteria keys, the prompts under test, and the runners that
wire a target to a dataset. A dataset that holds PHI stays with the consumer.

Hard rule: the gem's core takes no dependency on any consumer, makes no HTTP call itself, and
never reads a file it was not handed a path to. Model access is only through adapters (§4.2).

## 2. Vocabulary (used verbatim in code, specs, and prose)

- **Dataset** — a frozen set of examples, identified by a content hash.
- **Example** — one unit under test: `id`, `input`, `target`, `metadata`.
- **Target** — the production code path being measured (a callable the consumer supplies).
- **Criterion** — one atomic, binary check on one example, with a `family` and provenance.
- **Scorer** — grades a criterion, returning `{key, score, comment}`. Three kinds:
  **assertion** (code, deterministic, free), **judge** (model, binary, calibrated, costs),
  **label** (human verdict; ground truth for calibration and the source of new criteria).
- **Run** — one target version × one dataset, with a manifest. **Epoch** — one repeat within a
  run. **Reducer** — how epochs combine into one verdict per criterion.
- **Comparability key** — `(dataset sha, criteria sha, prompt_version)`; runs compare only when it
  matches.
- **Calibration** — judge-vs-label agreement, per family, as precision and recall.
- **Scorecard** — the PHI-free aggregate: counts, all-pass on top, family rates beneath.

Scores are boolean. The gem has no 0–1 scores, thresholds, or weights, by design.

## 3. File formats

### 3.1 Dataset manifest — `manifest.json`

```json
{ "contract": 1,
  "name": "ocr_vision_eval",
  "examples": [
    { "id": "demo/p1",
      "input": { "kind": "image", "path": "pages/demo_p1.png", "dpi": 150 },
      "target": "criteria/demo_p1.json",
      "metadata": { "tier": "hard", "class": "handwriting,stamp,date" } } ] }
```

`input.kind` is `image`, `text`, or `messages`; `path` is relative to the manifest. The
**dataset sha** is SHA-256 over the manifest bytes plus every referenced input file, in manifest
order. A re-render is a different dataset.

### 3.2 Criteria file — one per example

```json
{ "contract": 1, "example_id": "demo/p1",
  "criteria": [
    { "id": "demo/p1#c1", "family": "date", "type": "presence", "scorer": "assertion",
      "target": { "date": "2019-03-14" },
      "provenance": { "author": "annotator", "verified_by": "reviewer", "region": "stamp, upper right" } },
    { "id": "demo/p1#c2", "family": "abstention", "type": "abstention", "scorer": "assertion",
      "target": { "region": "line 7 shorthand", "forbidden_terms_present": false } },
    { "id": "demo/p1#c3", "family": "handwriting", "type": "faithful", "scorer": "judge",
      "target": { "key_text": "…human-authored transcription of the region…" },
      "provenance": { "author": "annotator", "region": "handwritten narrative" } } ] }
```

`type` is one of `presence`, `absence`, `structure`, `abstention`, `identity`, `faithful`; the
gem defines an assertion for each of the first five and a judge prompt for `faithful`. `target`
shape is per type and documented in the gem. Dates are compared parsed, never as strings. The
**criteria sha** is SHA-256 over all criteria files for the dataset, in manifest order.

### 3.3 Result record — JSONL, one line per (example, criterion, epoch)

```json
{ "contract": 1, "run_id": "2026-09-02T18:04:11Z-ocr-a1b2c3", "example_id": "demo/p1",
  "key": "demo/p1#c1", "score": true, "comment": "date 2019-03-14 found via Dates.parse",
  "family": "date", "scorer": "assertion", "epoch": 1, "cost_usd": 0.0, "latency_ms": 3 }
```

`key`/`score`/`comment` are the LangSmith / Braintrust / openevals record and are the only
required fields; the rest are ours. The **results file is PHI-bearing** (a judge comment may quote
output) and the consumer stores it under its own protected path. The scorecard never carries
comments.

### 3.4 Run manifest — `manifest.json` next to the results

```json
{ "contract": 1, "run_id": "…", "tool": "run_bench", "argv_sanitized": ["--plan"],
  "toolkit_sha": "…", "ruby_version": "3.3.3", "ts": "2026-09-02T18:04:11Z",
  "dataset": { "name": "ocr_vision_eval", "sha256": "…" },
  "criteria": { "sha256": "…" },
  "target": { "name": "ExampleService", "prompt_version": "sha256:…", "commit": "1a2b3c4d" },
  "model": { "provider": "google", "id": "gemini-3.7-flash", "endpoint": "us-central1" },
  "params": { "thinking": "default", "temperature": null }, "seed": "none",
  "epochs": 5, "reducer": "all_epochs",
  "gems": { "omniai": "3.8.0", "omniai-google": "…", "omniai-evals": "0.1.0" },
  "judge": { "adapter": "claude_cli", "model": "sonnet", "prompt_sha256": "…", "billing": "subscription" },
  "comparability_key": "sha256:dataset|sha256:criteria|sha256:prompt" }
```

`seed` is recorded as the
string `"none"` when the provider exposes none.

### 3.5 Scorecard — `scorecard.json`, PHI-free, publishable

```json
{ "contract": 1, "run_id": "…", "comparability_key": "…",
  "examples": { "total": 11, "all_pass": 9, "flaky": 1, "failed": 1 },
  "families": { "date": { "criteria": 14, "pass": 13, "flaky": 1, "fail": 0 },
                "abstention": { "criteria": 6, "pass": 4, "flaky": 0, "fail": 2 } },
  "cost_usd": 4.62, "calls": 110 }
```

Counts, not percentages: small datasets make rates misleading, and the reader can divide.

## 4. Interfaces (Ruby)

### 4.1 Scorers

```ruby
# An assertion is any callable with this shape. The gem ships one per criterion type.
Assertion = ->(example:, output:, criterion:) { Result.new(key:, score:, comment:) }
```

### 4.2 Judge adapter

A judge adapter is anything responding to:

```ruby
call(system:, packet:, model:, schema:, timeout:) # => Hash matching `schema`
```

Billing is fixed at construction, not threaded through. The gem ships `Adapters::OmniAI` (default; API-billed, structured output via
`OmniAI::Schema.format`) and `Adapters::ClaudeCLI` (`claude -p`,
packet on stdin, env allowlist, `--json-schema`). A judge criterion's schema is one boolean field
plus a short `reason`; the judge receives the key text and the output, never the example input.

### 4.3 Target

```ruby
Target = ->(example:, params:) { output_string_or_hash }
```

The consumer supplies it and it MUST be the production path, not a copy.

### 4.4 Reducer and comparability

`Reducer.all_epochs` yields `PASS` only if every epoch passed, `FAIL` if every epoch failed, else
`FLAKY`. It is the default and the only reducer in v1. `Compare.check!(a, b)` raises unless the
comparability keys match; `--force-compare` downgrades it to a loud warning in the report.

### 4.5 Plan

Every runner exposes `--plan`: prints examples × configs × epochs, estimated calls and cost, and
makes **zero** model calls. Estimates come from a per-adapter price table the consumer supplies.

## 5. Invariants the gem enforces (and tests)

1. Scores are booleans. No float ever reaches a result record.
2. Scorecards and run manifests contain no field that can carry input or output text.
3. The core loads with only stdlib and `json`; adapters are required explicitly.
4. A run with a mismatched comparability key is never silently compared.
5. `--plan` performs no network I/O (tested by stubbing the adapter to raise).
6. Sample files under `spec/fixtures/contract/` load for every format in §3; changing a format
   without bumping `contract` fails the suite.

## Amendments recorded by the gem (pending contract v2)

These are decisions made while implementing contract v1. They do not change any format,
so `"contract": 1` still holds. Fold them into the contract proper when it is next revised.

- **Numeric dates are read US month-first.** `MM/DD/YYYY` and `MM-DD-YYYY` are parsed
  month-first rather than by `Date.parse`, which reads them day-first and therefore returns
  `nil` for `03/14/2019` and *February 4th* for `04/02/2019`. Year-first (`2019-03-14`,
  `2019/03/14`) and textual months (`14 March 2019`, `Mar. 14, 2019`) are unambiguous and
  are parsed as written. **A non-US dataset needs a per-dataset locale field** — the format
  cannot be inferred from the text, because `04/02/2019` is valid under both readings and
  guessing reintroduces the silent error. Write unambiguous keys ISO. See
  `OmniAI::Evals::Dates::US_NUMERIC`.

- **§3.2 `structure` and `identity` each take a text-mode target as well as a structured
  one**, selected by which key is present, because the first consumer's target emits
  markdown rather than JSON. `identity: {"text": …}` is exact and **case-sensitive** (a
  wrong-patient header must be transcribed as-is; case-folding would hide the failure the
  type exists to detect). `structure: {"table_rows": N}` counts markdown table body rows;
  `structure: {"circled": …}` grades which option was marked. A mark counts only when it
  belongs to that option and that field: emphasis must be the option itself (not merely
  present on the line), a lexical marker is attributed to the option it follows, and both
  are looked for in the contiguous run of lines carrying the field's options rather than
  page-wide — option words repeat across a form, so page scope both invents rivals and
  accepts marks from elsewhere. It takes two optional companions: `"among": [...]` lists the sibling options so the check can refuse a page
  that emphasises all of them (emphasis only means "circled" when it singles one out, and
  the options cannot be inferred — the field label is emphasised too), and `"markers": [...]`
  replaces the built-in lexical markers for a target with its own convention. The Hash/path and field
  shapes are unchanged.

- **`abstention` recognises the non-lexical marker `~~~~`** (any run of 3+ tildes), which
  is what the production model actually emits, alongside the lexical markers. A criterion
  may replace the list via `target["markers"]`.

- **`--plan` prices target calls as well as judge calls**, from `prices["target"]`. For a
  vision bench the target calls are the metered spend, and a plan reporting `$0.00` for a
  paid run defeats the gate.

- **`Plan`'s `configs:` is a planning dimension only.** A run is one target version, so
  each config is its own run with its own manifest and results file. `Results.write`
  refuses to append records from a second `run_id` into an existing file, which is what
  prevents two configs merging by key.

- **Both judge adapters take `call(system:, packet:, model:, schema:, timeout:)`** and put
  the judge prompt in a real system turn, so a runner can swap them and calibration
  measured on one transfers to the other.
