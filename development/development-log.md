# Development Log

## 2026-04-03 - initial stack playground

- Created `nkl-stack-playground` as a small manual playground for the current
  `nkl` substrate:
  - `nkl-http`
  - `nkl-html`
  - `nkl-wasm`
- Chose to make it a fresh project instead of reusing the older
  `nkl-playground-site`, because the older project still carried pre-extraction
  custom server/runtime and vendored browser bridge code.
- Kept the goal deliberately narrow:
  - not a `nkl-filebrowser` rewrite
  - not a framework starter
  - not a product codebase
  - just a small place to manually exercise the current dependency stack

## 2026-04-03 - first vertical slice

- Added a first combined fullstack slice with:
  - `nkl-http` runtime
  - `nkl-html` SSR page
  - `nkl-wasm` browser enhancement
- Built the first page as an SSR-first counter/fetch demo:
  - server-rendered initial state
  - hidden-input handoff to Wasm
  - DOM updates owned by Wasm
  - small fetch endpoint
  - local storage usage
  - browser history updates
- Added embedded asset serving for:
  - app JS
  - browser bridge JS from `nkl-wasm`
  - generated Wasm
  - local CSS
- Verified the initial scaffold with:
  - `zig build`
  - `zig build test`

## 2026-04-03 - explicit SSR and CSR split

- Expanded the playground into three explicit modes instead of leaving it as a
  single mixed demo:
  - `/` for plain SSR landing
  - `/ssr` for SSR plus Wasm enhancement
  - `/lab/svg` for CSR/SPA-style interactive SVG
- Chose to keep the distinction explicit instead of blending everything into one
  page shape. The playground should help compare app modes, not hide them.
- Added a second Wasm target for the SVG lab so the SSR-enhanced route and the
  CSR/SPA route can evolve independently.
- Added a small API endpoint for the SVG lab point data:
  - `GET /api/svg-points`
- Kept the SVG lab intentionally small and explicit:
  - Wasm fetches point data
  - Wasm renders SVG markup
  - Wasm owns the current view mode
  - Wasm updates browser history and title
  - JS stays a thin event/bootstrap bridge
- Re-verified after the route split with:
  - `zig build`
  - `zig build test`

## 2026-04-03 - helper surface mismatch cleanup

- Hit several compile-time mismatches while authoring the playground page
  against the current `nkl-html.helpers` surface.
- The initial page draft assumed helper coverage for some tags that are not
  exposed as named helpers in the current package, including:
  - `title`
  - `strong`
  - `pre`
- Resolved those by switching to explicit low-level calls:
  - `builder.element(.title, ...)`
  - `builder.element(.strong, ...)`
  - `builder.element(.pre, ...)`
- Decision recorded:
  - the playground should follow the current `nkl-html` helper reality instead
    of pretending the helper surface is broader than it is
  - when a helper is not present, use the lower-level builder path directly
- This is not a package bug; it is the intended low-level fallback path.

## 2026-04-03 - runtime crash on `/`

### Symptom

- Running:

  ```bash
  zig build run -- --host 127.0.0.1 --port 2888
  ```

  then requesting `/` caused a worker-thread abort with:

  - `thread ... panic: switch on corrupt value`
  - crash path inside `nkl-html/src/builder_tree.zig`
  - empty reply to the HTTP client

### Root Cause

- The crash was caused by invalid node-lifetime handling in
  `src/page.zig`.
- `commonHeadWithScript(...)` returned a slice created from a temporary
  runtime `&.{ ... }` array of `Node` values.
- That temporary slice did not have a safe lifetime by the time
  `builder.document(...)` deep-cloned the document input.
- The result was corrupted `Node` tag data and the panic inside
  `builder_tree.cloneNode(...)`.

### Fix

- Replaced the temporary runtime `&.{ ... }` node array with an explicit
  builder-owned node list:
  - `var head = builder.nodeList();`
  - append head nodes one by one
  - `return head.freeze();`
- This makes the head node slice stable for the duration of document cloning.

### Result

- Re-verified after the fix with:
  - `zig build`
  - `zig build test`
- Re-ran:

  ```bash
  zig build run -- --host 127.0.0.1 --port 2888
  ```

  and the server no longer crashed immediately on startup plus first-request
  handling.

### Regression Note

- This was a real runtime regression introduced during the playground page
  refactor when the explicit SSR/CSR split was added.
- It is a useful reminder for `nkl-html` app code:
  - temporary runtime `&.{ ... }` node slices are dangerous when they are
    passed around as document-input slices
  - use stable slices or builder-owned lists when the slice must survive until
    a later clone/build step

## Current Shape

- The playground now exists primarily as a comparison and experimentation
  surface for:
  - pure SSR
  - SSR plus Wasm enhancement
  - CSR/SPA-style interactive page
- Current route set:
  - `/`
  - `/ssr`
  - `/form`
  - `/lab/svg`
  - `/api/message`
  - `/api/svg-points`
- Current verification status:
  - `zig build`
  - `zig build test`

## 2026-04-03 - form page slice

- Added a document-heavy SSR form route to better contrast with the Wasm-heavy
  routes:
  - `GET /form`
  - `POST /form`
- Chose to keep the form route mostly server-owned rather than adding more Wasm
  to it.
- The main goal is to exercise:
  - `nkl-http.body.readAllAlloc(...)`
  - `nkl-http.body.formValue(...)`
  - redirect-based form flow
  - `nkl-html` for document-heavy page rendering
- The form route now uses a simple redirect-back flow:
  - POST reads and decodes form data
  - the handler redirects to `GET /form?...`
  - the result panel renders from the query state
- This keeps the form example explicit and low-level without adding a larger
  framework-shaped form abstraction.

## 2026-04-03 - project metadata

- Added `development/project-info.md` so the playground follows the same basic
  documentation shape as the rest of the current `nkl` ecosystem.

## 2026-04-03 - SVG lab rendering correction

- The first SVG lab implementation rendered SVG markup through manual string
  concatenation inside `src/frontend/svg_app_wasm.zig`.
- That worked mechanically, but it underused the current substrate and made the
  CSR/SPA example less representative than it should be.
- `nkl-html` already supports SVG tags directly, including the tags used by the
  lab page:
  - `svg`
  - `rect`
  - `polyline`
  - `circle`
  - `text`
- Corrected the SVG lab so the Wasm-side renderer now uses `nkl-html`
  directly:
  - `builder_tree.Builder`
  - `helpers.bind(...)`
  - `render.node(...)`
- Also updated `build.zig` so the SVG Wasm target imports `nkl_html`
  explicitly instead of using only `nkl_wasm`.

### Decision

- SSR routes should use `nkl-html` on the server.
- CSR/SPA routes that generate markup in Zig should also use `nkl-html` rather
  than dropping to manual HTML/SVG string assembly by default.
- Manual string building is still acceptable as a narrow fallback, but it should
  not be the default path when `nkl-html` already covers the tag surface.

### Result

- The playground now demonstrates `nkl-html` in both server-rendered and
  Wasm-rendered markup paths.
- Re-verified after the change with:
  - `zig build`
  - `zig build test`

## 2026-04-03 - UI alignment and canonical repo

- Adjusted the playground UI styling to match the current `nkl-filebrowser`
  visual language more closely.
- Replaced the warmer custom playground styling with a flatter, GitHub-like,
  filebrowser-aligned surface:
  - same neutral panel and border language
  - same accent and text hierarchy direction
  - same small-radius control styling
  - same system-font posture
  - same light/dark variable model
- Kept the playground-specific layout classes, but moved them into the same
  style family as `nkl-filebrowser` so the playground now reads more like a
  sibling project than a separate design system experiment.

### Canonical Repository

- Initialized the playground as its own local Git repository.
- Added the canonical remote:

  - `git@github.com:lloydagbdev/nkl-stack-playground.git`

- Remote name:
  - `origin`

### Verification

- Re-verified after the CSS and repo changes with:
  - `zig build`
  - `zig build test`

## Follow-On Ideas

- Add a small form-oriented page to compare document-heavy SSR with more
  interaction-heavy routes.
- Add lightweight integration checks later if the playground stabilizes enough
  to justify them.
- Keep the playground small and manual-first; avoid letting it drift into a
  second product codebase.
