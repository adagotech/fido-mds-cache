# FIDO MDS Cache

A tiny, self-refreshing cache for the [FIDO Alliance Metadata Service (MDS)][mds]
blob, packaged as an nginx Docker image.

## Why

The FIDO Alliance publishes its metadata as a single signed JWT at
<https://mds.fidoalliance.org>. WebAuthn/FIDO2 relying parties download this blob
to validate authenticator attestations. 

This project caches the blob and serves it from your own infrastructure:

- A daily GitHub Actions job checks the upstream blob and, when a new version is
  published, rebuilds and pushes a Docker image containing the latest blob.
- The image is a minimal nginx server that serves the blob at `/blob.jwt`.
- Your relying parties point at **your** cached image instead of hammering the
  FIDO endpoint, so you only fetch upstream once per release (in CI) rather than
  on every request or deploy.

The MDS blob is fully signed by the FIDO Alliance, so caching and re-serving it
does not weaken its trust guarantees — clients still verify the JWT signature
chain against the FIDO root.

## Usage

Run the image and serve the blob on port 8080:

```bash
docker run -d --name fido-mds-cache -p 8080:80 adagotech/fido-mds-cache:latest
```

Then fetch the blob from your cache instead of from FIDO:

```bash
curl http://localhost:8080/blob.jwt
```

Point your WebAuthn/FIDO library's metadata URL at `http://<host>:8080/blob.jwt`.

### Endpoints

| Path               | Description                                                |
| ------------------ | --------------------------------------------------------- |
| `/blob.jwt`        | The cached FIDO MDS blob (a signed JWT).                   |
| `/next-update.txt` | The blob's `nextUpdate` date, e.g. `2026-07-01`.          |
| `/healthz`         | Returns `200 ok` — use for container/load-balancer probes. |
| `/`                | Redirects to `/blob.jwt`.                                  |

### Tags

- `latest` — always the most recently published blob.
- `YYYY-MM-DD` — pinned to the blob whose `nextUpdate` is that date (e.g.
  `2026-07-01`), if you want to pin to a specific release.

### Docker Compose

```yaml
services:
  fido-mds-cache:
    image: adagotech/fido-mds-cache:latest
    ports:
      - "8080:80"
    restart: unless-stopped
```

You can also trigger a run manually from the Actions tab (wit

## Repository layout

| File                            | Purpose                                                        |
| ------------------------------- | ------------------------------------------------------------- |
| `Dockerfile`                    | Downloads & verifies the blob, builds the nginx image.        |
| `nginx/default.conf`            | nginx config serving the blob, `next-update.txt`, `/healthz`. |
| `next-update.txt`               | The `nextUpdate` date of the currently-cached blob.           |
| `scripts/refresh.sh`            | Downloads the blob and detects whether it changed.            |
| `.github/workflows/refresh.yml` | Daily check + build/push pipeline.                            |

### Build locally

```bash
docker build -t fido-mds-cache .
docker run --rm -p 8080:80 fido-mds-cache
```

The build downloads the current blob from FIDO directly.

[mds]: https://fidoalliance.org/metadata/
