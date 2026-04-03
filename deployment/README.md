# Quadlet Deployment

This directory contains a Podman Quadlet deployment path for
`nkl-stack-playground` on Fedora with:

- a locally built static `nkl-stack-playground` binary
- a minimal `scratch` image
- Quadlet-managed image build, container, and network units
- `nginx` on the host as the reverse proxy

Layout:

- `deployment/artifacts/`
  staged binary input for the container build
- `deployment/quadlet/`
  the actual files to install with `podman quadlet install`

The default topology is:

- `nginx` listens on `80` and `443`
- the `nkl-stack-playground` container publishes `127.0.0.1:2888`
- `nginx` proxies to `http://127.0.0.1:2888`

## Static Build

Build the binary locally as a static Linux musl release:

```bash
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast
```

Verify it:

```bash
file zig-out/bin/nkl-stack-playground
ldd zig-out/bin/nkl-stack-playground
```

Expected shape:

- `file` reports `statically linked, stripped`
- `ldd` reports `not a dynamic executable`

## Stage The Artifact

The container build expects the binary at:

```text
deployment/artifacts/nkl-stack-playground
```

Stage it after building:

```bash
install -Dm0755 zig-out/bin/nkl-stack-playground deployment/artifacts/nkl-stack-playground
```

Or use the helper:

```bash
./deployment/prepare-quadlet-release.sh
```

When using Quadlet installation on the VPS, the build context becomes
`/etc/containers/systemd`, so the staged binary also needs to exist there as:

```text
/etc/containers/systemd/artifacts/nkl-stack-playground
```

## Files

- `quadlet/Containerfile`
  Minimal `scratch` image that contains only `nkl-stack-playground`
- `quadlet/.containerignore`
  Keeps the Quadlet build context small
- `quadlet/nkl-stack-playground.build`
  Builds `localhost/nkl-stack-playground:latest` from the local `Containerfile`
- `quadlet/nkl-stack-playground.container`
  Runs the container through Quadlet
- `quadlet/nkl-stack-playground.network`
  Creates a dedicated bridge network used by the container
- `quadlet/nkl-stack-playground.env`
  Runtime environment template for the container

## Runtime Defaults

The shipped defaults are conservative:

- bind inside container: `0.0.0.0:2888`
- published host port: `127.0.0.1:2888`
- short HTTP timeouts suitable for a demo app
- no persistent writable volume because the playground serves embedded assets
  and stateless demo routes only

Edit `deployment/quadlet/nkl-stack-playground.env` before installation if you
want different host or timeout values.

## Install On The VPS

Install the required packages:

```bash
sudo dnf install -y podman podman-quadlet nginx
```

## Copy The Deployment Bundle To The VPS

The deployment bundle is a directory, not a single file.

Use `scp -r`:

```bash
scp -r deployment lag@your-vps:/tmp/nkl-stack-playground-deployment
```

Or use `rsync` for repeated updates:

```bash
rsync -av --delete deployment/ lag@your-vps:/tmp/nkl-stack-playground-deployment/
```

The `rsync` form is usually better after the first copy because it updates the
directory contents in place.

One practical layout on the VPS is:

```text
/tmp/nkl-stack-playground-deployment/
```

where that directory contains:

- `artifacts/nkl-stack-playground`
- the files in `quadlet/`

Then install the Quadlet application:

```bash
sudo podman quadlet install /tmp/nkl-stack-playground-deployment/quadlet
sudo install -Dm0755 /tmp/nkl-stack-playground-deployment/artifacts/nkl-stack-playground /etc/containers/systemd/artifacts/nkl-stack-playground
sudo systemctl daemon-reload
sudo systemctl enable --now nkl-stack-playground.service
```

Check the generated service:

```bash
sudo systemctl status nkl-stack-playground.service
sudo journalctl -u nkl-stack-playground.service -f
```

The `.build` and `.network` units are pulled in automatically by the container
unit because it references:

- `Image=nkl-stack-playground.build`
- `Network=nkl-stack-playground.network`

## nginx

Keep `nkl-stack-playground` bound to localhost and proxy through `nginx`.

Example server block:

```nginx
server {
    server_name playground.example.com;

    location / {
        proxy_pass http://127.0.0.1:2888;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Reload `nginx` after updating the site config:

```bash
sudo nginx -t
sudo systemctl reload nginx
```
