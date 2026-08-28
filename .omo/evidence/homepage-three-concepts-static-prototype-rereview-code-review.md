# Homepage Three-Concept Static Prototype Rereview

Scope:
- `outputs/首页三套方案-互动设计稿.html`
- `outputs/首页三套方案-tokens.css`
- Consistency reference: `docs/design/design-system.md`

Verdict: FAIL

## Skill-Perspective Check

- `omo:remove-ai-slops`: SKILL.md loaded and applied to current production code and QA evidence. No deletion-only tests or tautological production tests were added in scope. The remaining concern is evidence hygiene: the required Hallmark provenance stamp is acceptable in principle, but its aggregate evidence references are inconsistent, noted below.
- `omo:programming`: SKILL.md loaded and applied as a maintainability/test-shape lens. Per-language references were not loaded because the scoped files are HTML/CSS/vanilla JS, not `.py`, `.rs`, `.ts`, `.tsx`, or `.go`, and this review made no code edits. The previous untrusted-layout boundary issue is resolved by parsing saved layout to a known value.
- `omo:frontend`: SKILL.md plus `references/design/README.md` and `references/perfection/README.md` loaded for frontend accessibility/design-system review. The switcher semantics and local-only behavior improved, but strict typography tokenization still fails.

## Findings By Severity

### CRITICAL

None.

### HIGH

1. `outputs/首页三套方案-互动设计稿.html:54` still hard-codes `letter-spacing: -0.05em` on the main heading. This was part of the previous tokenization blocker and also violates the frontend rule that letter spacing must be `0`, not negative. Because the success criteria require all color/font values to be tokenized, move this typographic decision into `outputs/首页三套方案-tokens.css` only if it is allowed by the design rules; otherwise set it to `0`. While doing that, decide whether raw `font-weight` and `line-height` values in the same CSS block are also part of the strict typography token contract and tokenize them consistently.

### MEDIUM

1. `outputs/首页三套方案-tokens.css:1` keeps the Hallmark provenance stamp, which I am not treating as a violation because the user explicitly invoked Hallmark. The evidence references still need cleanup: `.omo/evidence/homepage-prototype-qa/run-output.json:1-20` is stale and reports `FAIL`, and `.omo/evidence/homepage-prototype-qa/manualQa.json:278-284` contains a failing accessibility-basics row from an obsolete assertion that still expects an `AI 搜索` label after the mark was made decorative. Regenerate the aggregate result or narrow the stamp to specific passing artifacts so future reviewers do not see contradictory pass/fail evidence.

### LOW

1. `outputs/首页三套方案-互动设计稿.html:350-370` still calls `localStorage` directly. The claimed layout fallback now works, and DOM updates happen before writes, so this is not a blocker. A small safe storage wrapper would prevent blocked-storage environments from producing unhandled startup or interaction errors.

## Verified Fixes

- Invalid saved layout now falls back to `directory`: current code at `outputs/首页三套方案-互动设计稿.html:358-364`, current artifact `.omo/evidence/homepage-prototype-qa/invalid-localstorage-state.json:13-22`, and an independent non-mutating JS simulation all show one active layout, one active button, and one visible note.
- Hero color and hero font size moved to tokens: `outputs/首页三套方案-tokens.css:13-17`, `outputs/首页三套方案-tokens.css:34`, and `outputs/首页三套方案-互动设计稿.html:216-225`.
- The three view buttons now expose `aria-controls` for their panels/notes at `outputs/首页三套方案-互动设计稿.html:264-266`, and target IDs exist at `outputs/首页三套方案-互动设计稿.html:278`, `outputs/首页三套方案-互动设计稿.html:295`, `outputs/首页三套方案-互动设计稿.html:314`, and `outputs/首页三套方案-互动设计稿.html:337-339`.
- The previous static `AI 搜索` affordance issue is resolved by making the visual mark decorative: `outputs/首页三套方案-互动设计稿.html:271`.
- The prototype remains local-only: static scan found only the local stylesheet link and inline script, with no external network dependencies or unsafe DOM sinks.
- Inline script syntax parsed successfully.

## Return Fields

- codeQualityStatus: BLOCK
- recommendation: REQUEST_CHANGES
- reportPath: `.omo/evidence/homepage-three-concepts-static-prototype-rereview-code-review.md`
- blockers:
  - Remove or properly tokenize the remaining raw negative heading letter-spacing at `outputs/首页三套方案-互动设计稿.html:54`; do not leave negative letter spacing in the shipped prototype.
