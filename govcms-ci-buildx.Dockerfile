ARG DOCKER_VERSION="20.10.10"
ARG BUILDKIT_VERSION="0.9.1"
ARG BUILDX_VERSION="0.6.3"
ARG COMPOSE_VERSION="2.0.1"

FROM moby/buildkit:v${BUILDKIT_VERSION} as buildkit
FROM docker/buildx-bin:${BUILDX_VERSION} as buildx

FROM alpine:3.14 AS base

FROM base AS docker-static
ARG TARGETPLATFORM
ARG DOCKER_VERSION
WORKDIR /opt/docker
RUN DOCKER_ARCH=$(case ${TARGETPLATFORM:-linux/amd64} in \
    "linux/amd64")   echo "x86_64"  ;; \
    "linux/arm/v7")  echo "armhf"   ;; \
    "linux/arm64")   echo "aarch64" ;; \
    *)               echo ""        ;; esac) \
  && echo "DOCKER_ARCH=$DOCKER_ARCH" \
  && wget -qO- "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" | tar xvz --strip 1

FROM base AS compose
ARG TARGETPLATFORM
ARG COMPOSE_VERSION
WORKDIR /opt
RUN COMPOSE_ARCH=$(case ${TARGETPLATFORM:-linux/amd64} in \
    "linux/amd64")   echo "linux-x86_64"  ;; \
    "linux/arm/v7")  echo "linux-armv7"  ;; \
    "linux/arm64")   echo "linux-aarch64"  ;; \
    *)               echo ""        ;; esac) \
  && echo "COMPOSE_ARCH=$COMPOSE_ARCH" \
  && wget -q "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-${COMPOSE_ARCH}" -qO "/opt/docker-compose" \
  && chmod +x /opt/docker-compose

FROM alpine:3.14

RUN apk --update --no-cache add \
    bash \
    ca-certificates \
    docker-compose \
    openssh-client \
  && rm -rf /tmp/* /var/cache/apk/*

COPY --from=docker-static /opt/docker/ /usr/local/bin/
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
COPY --from=buildkit /usr/bin/buildkit* /usr/local/bin/
COPY --from=buildx /buildx /usr/libexec/docker/cli-plugins/docker-buildx
COPY --from=compose /opt/docker-compose /usr/libexec/docker/cli-plugins/docker-compose

# https://github.com/docker-library/docker/pull/166
#   dockerd-entrypoint.sh uses DOCKER_TLS_CERTDIR for auto-generating TLS certificates
#   docker-entrypoint.sh uses DOCKER_TLS_CERTDIR for auto-setting DOCKER_TLS_VERIFY and DOCKER_CERT_PATH
# (For this to work, at least the "client" subdirectory of this path needs to be shared between the client and server containers via a volume, "docker cp", or other means of data sharing.)
ENV DOCKER_TLS_CERTDIR=/certs
ENV DOCKER_CLI_EXPERIMENTAL=enabled

RUN docker --version \
  && buildkitd --version \
  && buildctl --version \
  && docker buildx version \
  && docker compose version \
  && docker-compose --version \
  && mkdir /certs /certs/client \
  && chmod 1777 /certs /certs/client

COPY rootfs/modprobe.sh /usr/local/bin/modprobe
COPY rootfs/docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["sh"]

