# OmniAI::Evals

Structure and grading for LLM evals: datasets, boolean criteria, assertions, judges,
epoch reduction, comparability, and PHI-free scorecards. A companion to the
[omniai](https://github.com/ksylvest/omniai) gem family.

The gem holds the *structure*. It knows nothing about any dataset, model, or product —
consumers hold the datasets, the criteria keys, the prompts under test, and the runners
that wire a target to a dataset.

`docs/contract.md` is the authority. It fixes the vocabulary, the five file formats, the
Ruby interfaces, and six invariants the gem tests for itself. Every file the gem reads or
writes carries `"contract": 1`; changing a format without bumping that number fails the
suite.

## Install

```ruby
gem "omniai-evals"
```

## Load

The core loads with stdlib and `json` only. **Adapters reach a model, so none of them is
required for you** — require the one you want:

```ruby
require "omniai/evals"                      # core: no network, no gems
require "omniai/evals/adapters/omniai"      # judge via the omniai gem (API-billed)
require "omniai/evals/adapters/claude_cli"  # judge via `claude -p` (subscription or API)
```

## Scores are boolean

There are no 0–1 scores, thresholds, or weights anywhere, by design. A criterion either
held or it did not, and `Result` raises on anything that is not `true` or `false`. Across
epochs, `Reducer.all_epochs` returns `:pass`, `:fail`, or `:flaky` — a criterion that
passes 3 runs in 5 is not "60% correct", it is unreliable, and the reader needs to see
that rather than a rounded number.

## The five deterministic criterion types

Each is free, offline, and returns `{key, score, comment}`.

| type | `target` | passes when |
|---|---|---|
| `presence` | `{"date": "2019-03-14"}` / `{"text": "signed by"}` | the date (parsed, any format) or the text (case- and whitespace-normalized) appears |
| `absence` | `{"text": "DO NOT COPY"}` | the text does **not** appear |
| `structure` | `{"table_rows": 12}` | the markdown table has that many body rows (header and separator excluded) |
| `structure` | `{"circled": "Option B"}` | that option is marked circled / selected |
| `structure` | `{"path": ["exam","date"], "type": "string"}` | the output is a Hash, the path resolves, the value has that JSON type |
| `identity` | `{"text": "Patient: JANE Q."}` | the output contains it **exactly**, case-sensitive, after whitespace collapse |
| `identity` | `{"field": "claim_number", "value": "ABC-123"}` | that field of a Hash output equals that value |
| `abstention` | `{"region": "line 7", "forbidden_terms": ["approved"]}` | the output abstains on the region rather than asserting content it cannot read |

`structure` and `identity` each take a **text-mode** target and a **structured** target,
selected by which key is present — the shape a target emits (markdown vs JSON) is the
consumer's business, not the criterion's.

`identity` in text mode is the one assertion that is **case-sensitive** and normalizes
nothing but whitespace. That is deliberate: a banded table whose header names a different
patient must be transcribed as-is, and an OCR pass that quietly "fixes" the case has
produced exactly the failure the criterion exists to detect.

`abstention` recognises the non-lexical marker `~~~~` (any run of 3+ tildes) that
production models actually emit, plus lexical markers like `[illegible]`. Override the
list per criterion with `target["markers"]`.

`faithful` is a judge, not an assertion, and `Assertions.for("faithful")` raises rather
than quietly falling back to a string compare.

**Dates are compared parsed, never as strings.** `2019-03-14`, `03/14/2019`,
`03-14-2019`, `14 March 2019`, `Mar. 14, 2019`, `March 14 2019`, `2019/03/14` and
`3/14/19` are all the same day.

Numeric slash and dash dates are read **US month-first**. Ruby's `Date.parse` reads them
day-first, so it returns `nil` for `03/14/2019` and — worse — silently returns *February
4th* for `04/02/2019`, marking a correct transcription wrong with nothing raised anywhere.
A non-US dataset needs a per-dataset locale field; the format cannot be inferred from the
text. See `Dates::US_NUMERIC`.

## PHI

- **Result records (JSONL) are PHI-bearing** — a judge comment may quote model output.
  Store them under your own protected path.
- **Scorecards and run manifests are not.** They carry counts and provenance, never text.
  The scorecard is built as a fresh Hash of integers rather than by filtering fields out
  of records, so there is no route by which a comment reaches it.
- **The judge receives the key text and the model output, never the example input.**
  `Judge.packet` takes only those two, so there is no parameter to leak the input through.

## Runs, configs, and the results file

A **run is one target version**. `Plan` takes `configs:` so you can price "default vs
`effort: low`" in one go *before* committing the spend, but each config is its own run with
its own manifest and its own results file. `Results.write` refuses to append records from a
second `run_id` into a file that already holds one — otherwise a re-run silently doubles
every epoch and the reducer returns a PASS assembled from two runs nobody asked to combine.

`--plan` prices **target calls as well as judge calls**, from `prices["target"]` and
`prices["judge"]`. For a vision bench the target calls are the metered spend, and a plan
reporting `$0.00` for a paid run is worse than no plan.

## The demo bench

The gem ships one synthetic, PHI-free bench so it always has a consumer of its own:

```bash
ruby bench/demo/run.rb --plan   # estimates calls and cost, makes zero model calls
ruby bench/demo/run.rb          # grades a deliberately imperfect target, prints a scorecard
```

## Development

```bash
bundle install
bundle exec rake        # rspec + rubocop
```

## Releasing

Bump `VERSION` and `CHANGELOG.md`, merge, then push a `vX.Y.Z` tag on that commit. The Release workflow checks the tag matches `VERSION`, runs the suite, and pushes the gem via RubyGems trusted publishing.

The six contract invariants have their own spec file, `spec/omniai/evals/invariants_spec.rb`.

## License

MIT. See `LICENSE`.
