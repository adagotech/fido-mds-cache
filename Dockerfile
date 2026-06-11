# syntax=docker/dockerfile:1

# --- download stage ---------------------------------------------------------
# Fetch the FIDO Alliance MDS blob and sanity-check that it is a three-part JWT.
FROM alpine:3.20 AS downloader

ARG BLOB_URL="https://mds.fidoalliance.org"
# Changing NEXT_UPDATE busts the download layer cache so a new release is fetched.
ARG NEXT_UPDATE="unknown"

RUN apk add --no-cache curl
RUN echo "Fetching FIDO MDS blob for nextUpdate=${NEXT_UPDATE}" \
 && curl -fsSL --retry 5 --retry-delay 10 "$BLOB_URL" -o /blob.jwt \
 && test -s /blob.jwt \
 && [ "$(tr -cd '.' < /blob.jwt | wc -c)" -eq 2 ]

# --- runtime stage ----------------------------------------------------------
FROM nginx:1.27-alpine

COPY --from=downloader /blob.jwt /usr/share/nginx/html/blob.jwt
COPY next-update.txt /usr/share/nginx/html/next-update.txt
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

ARG NEXT_UPDATE="unknown"
LABEL org.opencontainers.image.title="FIDO MDS Cache" \
      org.opencontainers.image.description="Caches and serves the FIDO Alliance Metadata Service (MDS) blob via nginx" \
      org.opencontainers.image.source="https://mds.fidoalliance.org" \
      org.opencontainers.image.url="https://mds.fidoalliance.org" \
      fido.mds.next-update="${NEXT_UPDATE}"

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz >/dev/null 2>&1 || exit 1
