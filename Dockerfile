# syntax=docker/dockerfile:1

# The FIDO Alliance MDS blob is downloaded by scripts/refresh.sh *before* the
# build and passed in via the build context as blob.jwt. Copying it here (rather
# than downloading a second time) avoids a redundant request to the upstream MDS
# endpoint, which can trip the 429 rate limit this cache exists to work around.
FROM nginx:1.27-alpine

ARG NEXT_UPDATE="unknown"

COPY blob.jwt /usr/share/nginx/html/blob.jwt
COPY next-update.txt /usr/share/nginx/html/next-update.txt
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Sanity-check that the blob is a non-empty three-part JWT.
RUN test -s /usr/share/nginx/html/blob.jwt \
 && [ "$(tr -cd '.' < /usr/share/nginx/html/blob.jwt | wc -c)" -eq 2 ]

LABEL org.opencontainers.image.title="FIDO MDS Cache" \
      org.opencontainers.image.description="Caches and serves the FIDO Alliance Metadata Service (MDS) blob via nginx" \
      org.opencontainers.image.source="https://mds.fidoalliance.org" \
      org.opencontainers.image.url="https://mds.fidoalliance.org" \
      fido.mds.next-update="${NEXT_UPDATE}"

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz >/dev/null 2>&1 || exit 1
