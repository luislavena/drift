# syntax=docker/dockerfile:1

# ---
# Development image: hydrofoil-crystal plus project-specific tools
ARG CRYSTAL_VERSION=1.16
FROM ghcr.io/luislavena/hydrofoil-crystal:${CRYSTAL_VERSION}

# install development utilities
RUN --mount=type=tmpfs,target=/tmp \
    set -eux; \
    cd /tmp; \
    # Ameba
    { \
        export AMEBA_VERSION=1.7.0; \
        case "$(arch)" in \
        x86_64) \
            export \
                AMEBA_ARCH=x86_64 \
                AMEBA_SHA256=7ed747711e76579902c5a4165a78a41b1e5acf0681ffcc538197bab435b4318f \
            ; \
            ;; \
        aarch64) \
            export \
                AMEBA_ARCH=aarch64 \
                AMEBA_SHA256=6467cdf69cae19ab3c52be93d2a1604e9b50e67fc20c7c1cb257117bd970837c \
            ; \
            ;; \
        esac; \
        curl --fail -Lo ameba.tar.gz https://github.com/crystal-ameba/ameba/releases/download/v${AMEBA_VERSION}/ameba-${AMEBA_VERSION}-linux-musl-${AMEBA_ARCH}.tar.gz; \
        echo "${AMEBA_SHA256} *ameba.tar.gz" | sha256sum -c - >/dev/null 2>&1; \
        tar -xf ameba.tar.gz; \
        mv ameba /usr/local/bin/; \
        rm -f ameba.tar.gz; \
    }; \
    # smoke tests
    [ "$(command -v ameba)" = '/usr/local/bin/ameba' ]; \
    ameba --version
