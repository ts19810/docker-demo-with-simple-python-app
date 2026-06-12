# syntax=docker/dockerfile:1

# Multi-stage Docker image for moole-sast-fact-extractor-golang.
#
# The runtime image intentionally includes the Go toolchain. The extractor is
# built with the `gopackages` tag, and golang.org/x/tools/go/packages invokes
# `go list` while scanning repositories. Without /usr/local/go/bin/go in the
# final image, deployments can start but typed extraction can fail at scan time.
ARG GO_VERSION=1.25

FROM golang:${GO_VERSION}-bookworm AS builder

WORKDIR /src

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -tags "kafka gopackages" \
    -trimpath \
    -ldflags "-s -w" \
    -o /out/go-facts-extractor ./cmd/go-facts-extractor

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/configs /tmp/repos-cloned /tmp/tools /tmp/logs /tmp/go/pkg/mod /tmp/go-build-cache

WORKDIR /app

# Required by the gopackages runtime loader for `go list` during repository scans.
COPY --from=builder /usr/local/go /usr/local/go
COPY --from=builder /out/go-facts-extractor /app/go-facts-extractor

# Keep default config files in the image for direct docker runs. Kubernetes
# deployments override the active profile file via a ConfigMap subPath mount.
COPY configs/ /app/configs/

ENV PATH="/usr/local/go/bin:${PATH}" \
    GOROOT=/usr/local/go \
    GOPATH=/tmp/go \
    GOMODCACHE=/tmp/go/pkg/mod \
    GOCACHE=/tmp/go-build-cache \
    GOENV=off \
    GOTOOLCHAIN=local \
    GO_FACTS_PROFILE=dev \
    GO_FACT_LOG_PATH=/tmp/logs/go-facts-extractor.log

EXPOSE 8080

ENTRYPOINT ["/app/go-facts-extractor"]

# Default for direct docker runs. Kubernetes deployments override this with
# environment-specific args so DEV uses application-dev.json and PROD uses
# application-prod.json from the mounted ConfigMap.
CMD ["-config", "/app/configs/application-dev.json"]
