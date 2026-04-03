# nkl-stack-playground

`nkl-stack-playground` is a small manual proving ground for how the current
`nkl` substrate fits together in one application shape.

It is intentionally not:

- a `nkl-filebrowser` rewrite
- a framework starter
- a reusable package
- a product codebase

## Core Constraints

- use `nkl-http` directly instead of preserving old custom runtime code
- use `nkl-html` directly for SSR pages
- use `nkl-wasm` directly for browser-host and Wasm interaction
- keep the project small enough to stay understandable in one sitting
- make route and rendering modes explicit instead of blending them into one
  hidden architecture

## Current Role

The playground exists to manually compare and exercise three page/application
shapes over the same substrate:

- pure SSR
- SSR plus Wasm enhancement
- CSR / SPA-style interaction-heavy view

## Near-Term Goal

Keep the playground good at manual experimentation without letting it become a
second product.

That means it should prioritize:

- small vertical slices
- explicit route design
- a few realistic examples of the current libraries working together
- durable notes when a mistake or integration mismatch is discovered

## Current Route Set

- `/`
- `/ssr`
- `/form`
- `/lab/svg`
- `/api/message`
- `/api/svg-points`

## What It Should Prove

- `nkl-http` is enough for the app shell and small API routes
- `nkl-html` is enough for document-heavy SSR routes
- `nkl-wasm` is enough for both enhancement and client-owned interaction
- the current `nkl` substrate supports multiple app modes without needing a
  framework layer
