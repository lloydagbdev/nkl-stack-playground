# nkl-stack-playground

`nkl-stack-playground` is a small manual playground for the current `nkl`
substrate:

- `nkl-http`
- `nkl-html`
- `nkl-wasm`

It is intentionally not a `nkl-filebrowser` rewrite and not a framework
starter. It is just a small place to poke the current libraries together in one
app shape.

## What It Demonstrates

- `nkl-http` runtime and route handling
- `nkl-html` server-rendered page generation
- `nkl-wasm` browser bridge, DOM mutation, fetch callbacks, storage, and
  history updates
- SSR-to-Wasm handoff through hidden inputs
- explicit contrast between SSR pages and a CSR/SPA-style page

## Routes

- `GET /`
- `GET /ssr`
- `GET /form`
- `POST /form`
- `GET /lab/svg`
- `GET /api/message`
- `GET /api/svg-points`
- `GET /assets/app.js`
- `GET /assets/svg_app.js`
- `GET /assets/browser_bridge.js`
- `GET /assets/site.css`
- `GET /assets/app.wasm`
- `GET /assets/svg_app.wasm`

## Run

```bash
cd nkl-stack-playground
zig build run
```

Pass args through:

```bash
zig build run -- --host 127.0.0.1 --port 2888
```

Then open:

```text
http://127.0.0.1:8088/
```

## Notes

- `/` is a plain SSR landing page.
- `/ssr` is SSR first, then Wasm-enhanced.
- `/form` is a document-heavy SSR page with a real form POST handled through
  `nkl-http` body helpers.
- `/lab/svg` is CSR/SPA-style and lets Wasm own the interactive SVG view.

If you want a larger playground later, add more routes or replace the page
without treating this directory as a product codebase.
