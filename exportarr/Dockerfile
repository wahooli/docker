ARG EXPORTARR_VERSION=2.3.0
ARG ALPINE_IMAGE=3.24

FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder
ARG EXPORTARR_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN apk add --no-cache git
RUN git clone --depth 1 --branch v$EXPORTARR_VERSION https://github.com/onedr0p/exportarr /build
WORKDIR /build
COPY queue-counts.patch /tmp/
RUN git apply /tmp/queue-counts.patch \
    && go test ./internal/arr/collector/ -run TestQueue
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w" -o /exportarr ./cmd/exportarr

FROM alpine:$ALPINE_IMAGE
ARG EXPORTARR_VERSION
ENV EXPORTARR_VERSION=$EXPORTARR_VERSION \
    PORT=9707
RUN apk add --no-cache tini
COPY --from=builder /exportarr /exportarr
# Same uid and entrypoint as the upstream distroless image
USER 65532:65532
ENTRYPOINT ["/sbin/tini", "--", "/exportarr"]
