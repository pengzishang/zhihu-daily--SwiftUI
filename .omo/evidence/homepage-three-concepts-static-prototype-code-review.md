# Homepage Three-Concept Static Prototype Code Review

Scope:
- `outputs/首页三套方案-互动设计稿.html`
- `outputs/首页三套方案-tokens.css`
- Consistency reference: `docs/design/design-system.md`

Verdict: FAIL

## Skill-Perspective Check

- `omo:remove-ai-slops`: SKILL.md loaded and applied to production code and evidence. The diff violates this lens because `outputs/首页三套方案-tokens.css:1` contains broad unverifiable "pass" claims with no artifact paths, and one claim is contradicted by the tokenization findings below.
- `omo:programming`: SKILL.md loaded and applied as a maintainability/test-shape lens. Per-language references were not loaded because the scoped files are HTML/CSS/vanilla JS, not `.py`, `.rs`, `.ts`, `.tsx`, or `.go`, and this review made no code edits. The diff violates the shared boundary rule: persisted `localStorage` values are untrusted inputs but are applied without parsing to known layout/theme values.
- `omo:frontend`: SKILL.md plus `references/design/README.md` and `references/perfection/README.md` loaded for frontend accessibility/design-system review. The prototype meets the local-only dependency requirement, but not the tokenization and defensive state requirements.

## Findings By Severity

### CRITICAL

None.

### HIGH

1. `outputs/首页三套方案-互动设计稿.html:352-363` applies the saved layout directly from `localStorage`. If `dailyreader-prototype-layout` contains any stale or tampered value, all layout buttons become `aria-pressed="false"`, all preview panels lose `.is-active`, and all notes become hidden. Existing evidence confirms this in `.omo/evidence/homepage-prototype-qa/invalid-localstorage-state.json:13-16`, and an independent JS simulation reproduced the same state. Parse the saved layout against the three known values (`directory`, `frontpage`, `sections`) before calling `setLayout`; fall back to `directory`.

2. The explicit "all color/font values tokenized" requirement is not met. `outputs/首页三套方案-互动设计稿.html:6` hard-codes `#f9f6ef` outside the token layer, while `outputs/首页三套方案-互动设计稿.html:226` hard-codes a hero `font-size: clamp(1.65rem, 5vw, 2.4rem)`. The heading also uses raw negative letter spacing at `outputs/首页三套方案-互动设计稿.html:55`. Move these typography/color decisions into `outputs/首页三套方案-tokens.css` tokens and reference them consistently; if `theme-color` must remain a meta value, keep it synchronized from the theme tokens.

3. `outputs/首页三套方案-tokens.css:1` includes a large generated audit banner claiming `contrast: pass`, `tokens: pass`, `responsive: pass`, and `mobile: pass` without evidence paths. This is false-confidence slop and is contradicted by the tokenization violation above. Remove the comment or replace it with a neutral provenance note that links to concrete evidence artifacts.

### MEDIUM

1. `outputs/首页三套方案-互动设计稿.html:273` labels a non-interactive `<span>` as `AI 搜索`. Screen-reader users can encounter it as a search affordance with no button semantics or action. If it represents a control, make it a `<button type="button">`; if it is just the app mark, expose it as plain text or mark it decorative.

2. `outputs/首页三套方案-互动设计稿.html:266-268` and `outputs/首页三套方案-互动设计稿.html:280-326` do not expose control-to-panel relationships. The buttons are semantic buttons and `aria-pressed` is valid, but adding stable panel IDs plus `aria-controls` would make the three switchable concepts clearer to assistive tech and easier to test.

### LOW

1. `outputs/首页三套方案-互动设计稿.html:344-350` and `outputs/首页三套方案-互动设计稿.html:352-357` call `localStorage` directly. The page mostly degrades because DOM updates happen before writes, but blocked storage can still throw unhandled errors during startup or interaction. Wrap preference reads/writes behind a tiny safe storage helper.

## Evidence Reviewed

- `git status --short`: scoped prototype files are untracked; no normal `git diff` exists for them, so I reviewed full file contents.
- `nl -ba` read all scoped files and `docs/design/design-system.md`.
- `rg` confirmed no external `http(s)` URLs, imports, media, form, fetch, WebSocket, or unsafe DOM sinks in the scoped files.
- Inline script syntax parsed successfully with `new Function`.
- Existing Playwright evidence under `.omo/evidence/homepage-prototype-qa` was inspected but not trusted blindly. `run-output.json` is FAIL. The invalid-storage failure is valid; the keyboard failure is not used as a blocker because the QA script clears `localStorage` after page load, which makes that specific expectation unreliable.
- Existing security/privacy review `.omo/evidence/static-dailyreader-html-prototype-security-review-code-review.md` is narrower than this assignment and does not cover the blockers above.

## Return Fields

- codeQualityStatus: BLOCK
- recommendation: REQUEST_CHANGES
- reportPath: `.omo/evidence/homepage-three-concepts-static-prototype-code-review.md`
- blockers:
  - Validate persisted layout/theme values before applying them; invalid layout must restore exactly one default active button, panel, and note.
  - Tokenize the remaining raw color/typography values and keep meta theme color synchronized with theme tokens.
  - Remove or evidence-link the generated "pass" audit banner in the token CSS.
