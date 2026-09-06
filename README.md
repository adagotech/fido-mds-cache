# FIDO MDS Cache

A tiny, self-refreshing cache for the [FIDO Alliance Metadata Service (MDS)][mds]
blob, packaged as an nginx Docker image.

## Why

The FIDO Alliance publishes its metadata as a single signed JWT at
<https://mds.fidoalliance.org>. WebAuthn/FIDO2 relying parties download this blob
to validate authenticator attestations. 

This project caches the blob and serves it from your own infrastructure:

- A daily GitHub Actions job checks the upstream blob and, when a new version is
  published, rebuilds and pushes a Docker image containing the latest blob. A
  new version means either a new `nextUpdate` date or a new serial number
  (`no`) — FIDO republishes the blob within a single validity window, so the
  serial is what catches those in-window updates.
- The image is a minimal nginx server that serves the blob at `/blob.jwt`.
- Your relying parties point at **your** cached image instead of hammering the
  FIDO endpoint, so you only fetch upstream once per release (in CI) rather than
  on every request or deploy.

The MDS blob is fully signed by the FIDO Alliance, so caching and re-serving it
does not weaken its trust guarantees — clients still verify the JWT signature
chain against the FIDO root. As of the 2026-08-31 MDS update that chain roots to
**GlobalSign Root R46** (cross-signed by the older GlobalSign Root CA – R3, so
the `x5c` header now carries three certificates). Relying parties must have R46
in their trust store before the cross-certificate expires on 2029-03-18.

## Usage

Run the image and serve the blob on port 8080:

```bash
docker run -d --name fido-mds-cache -p 8080:80 adagotechnologies/fido-mds-cache:latest
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
| `/blob-no.txt`     | The blob's serial number (`no`), e.g. `279`.               |
| `/healthz`         | Returns `200 ok` — use for container/load-balancer probes. |
| `/`                | Redirects to `/blob.jwt`.                                  |

### Tags

- `latest` — always the most recently published blob.
- `YYYY-MM-DD` — the UTC date the image was built (e.g. `2026-07-01`), if you
  want to pin to a specific release. The blob's own `nextUpdate` date is
  available from `/next-update.txt` and the `fido.mds.next-update` image label,
  and its serial number from `/blob-no.txt` and the `fido.mds.blob-no` label.

### Docker Compose

```yaml
services:
  fido-mds-cache:
    image: adagotechnologies/fido-mds-cache:latest
    ports:
      - "8080:80"
    restart: unless-stopped
```

You can also trigger a run manually from the Actions tab (wit

## Repository layout

| File                            | Purpose                                                        |
| ------------------------------- | ------------------------------------------------------------- |
| `Dockerfile`                    | Copies the pre-downloaded blob into a minimal nginx image.    |
| `nginx/default.conf`            | nginx config serving the blob, `next-update.txt`, `/healthz`. |
| `next-update.txt`               | The `nextUpdate` date of the currently-cached blob.           |
| `blob-no.txt`                   | The serial number (`no`) of the currently-cached blob.        |
| `scripts/refresh.sh`            | Downloads the blob (to `blob.jwt`) and detects whether it changed. |
| `.github/workflows/refresh.yml` | Daily check + build/push pipeline.                            |

