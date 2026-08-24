FROM golang:1.25.8-alpine AS downloader

ARG TERM_LLM_VERSION=v0.0.403
ARG TERM_LLM_SOURCE_COMMIT=
ARG TERM_LLM_SHA256_AMD64
ARG TERM_LLM_SHA256_ARM64
ARG TARGETARCH

RUN apk add --no-cache ca-certificates curl tar
RUN set -eux; \
    mkdir -p /out; \
    if [ -n "$TERM_LLM_SOURCE_COMMIT" ]; then \
      printf '%s\n' "$TERM_LLM_SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; \
      mkdir -p /tmp/source; \
      curl -fsSL "https://github.com/samsaffron/term-llm/archive/${TERM_LLM_SOURCE_COMMIT}.tar.gz" \
        | tar -xz -C /tmp/source --strip-components=1; \
      cd /tmp/source; \
      short_commit=$(printf '%.12s' "$TERM_LLM_SOURCE_COMMIT"); \
      CGO_ENABLED=0 GOOS=linux GOARCH="$TARGETARCH" go build -buildvcs=false -trimpath \
        -ldflags "-s -w -X github.com/samsaffron/term-llm/cmd.Version=main-${short_commit} -X github.com/samsaffron/term-llm/cmd.Commit=${TERM_LLM_SOURCE_COMMIT}" \
        -o /out/term-llm ./main.go; \
    else \
      version="${TERM_LLM_VERSION#v}"; \
      asset="term-llm_${version}_linux_${TARGETARCH}.tar.gz"; \
      base="https://github.com/samsaffron/term-llm/releases/download/v${version}"; \
      case "$TARGETARCH" in \
        amd64) expected="$TERM_LLM_SHA256_AMD64" ;; \
        arm64) expected="$TERM_LLM_SHA256_ARM64" ;; \
        *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
      esac; \
      test -n "$expected"; \
      curl -fsSLo "/tmp/${asset}" "${base}/${asset}"; \
      printf '%s  %s\n' "$expected" "/tmp/${asset}" | sha256sum -c -; \
      cd /tmp; \
      tar -xzf "${asset}"; \
      install -m 0755 term-llm /out/term-llm; \
    fi

FROM debian:bookworm-20260803-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates gosu wget \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --home-dir /home/termllm --uid 10001 termllm \
    && install -d -m 0700 -o termllm -g termllm /data /run/term-llm \
    && chown -R termllm:termllm /home/termllm

COPY --from=downloader /out/term-llm /usr/local/bin/term-llm
COPY entrypoint.sh /usr/local/bin/hub-entrypoint
RUN chmod 0755 /usr/local/bin/hub-entrypoint

ENV HOME=/home/termllm
EXPOSE 8090
ENTRYPOINT ["/usr/local/bin/hub-entrypoint"]
