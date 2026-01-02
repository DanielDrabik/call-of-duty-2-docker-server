# Available build arguments and default configuration
ARG COD2_VERSION="1_3"
ARG COD2_LNXDED_TYPE="_nodelay_va_loc"
# Options: "voron" or "ibuddieat"
ARG LIBCOD_TYPE="ddrabik"
# Options: [0 = mysql disables (default); 1 = default mysql; 2 = VoroN mysql]
ARG LIBCOD_MYSQL_TYPE=0
ARG LIBCOD_SPEEX_ENABLE=0
ARG LIBCOD_DDRABIK_VERSION="8b092e8a1228c4a1790780a62973e765f87b3967"
ARG LIBCOD_IBUDDIEAT_VERSION="v14.0"
ARG SPEEX_VERSION="Speex-1.2.1"

# ==================================================================
# Base builder with common dependencies
# ==================================================================
# Force linux/amd64 platform for build stage to support i386 architecture
# hadolint ignore=DL3029
FROM --platform=linux/amd64 debian:bookworm-20251020-slim AS build-base
ARG COD2_VERSION
ARG COD2_LNXDED_TYPE
# Define temporary directory for build artifacts
ARG TMPDIR=/tmp

# Copy server binary and make it runnable
COPY bin/cod2_lnxded_${COD2_VERSION}${COD2_LNXDED_TYPE} /bin/cod2_lnxded
RUN chmod +x /bin/cod2_lnxded

# Add i386 architecture support and install dependencies
# hadolint ignore=DL3008
RUN dpkg --add-architecture i386 \
  && apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  git \
  # Install 32 bits c++ libraries needed by cod2_lnxded and cross-compilation libs
  libstdc++5:i386 \
  libstdc++6:i386 \
  g++-multilib \
  # Install mysql & sqlite 32bit libs required if using libcod mysql options
  default-libmysqlclient-dev:i386 \
  libsqlite3-dev:i386 \
  # Install speex requirements
  libtool \
  build-essential \
  automake \
  libogg-dev \
  libogg-dev:i386 \
  ffmpeg \
  && rm -rf /var/lib/apt/lists/*

# ==================================================================
# Builder for "ddrabik" libcod
# ==================================================================
FROM build-base AS build-ddrabik
ARG COD2_VERSION
ARG LIBCOD_MYSQL_TYPE
ARG LIBCOD_DDRABIK_VERSION
ARG TMPDIR=/tmp

RUN git clone https://github.com/DanielDrabik/libcod "${TMPDIR}/libcod2"
WORKDIR ${TMPDIR}/libcod2
RUN git checkout ${LIBCOD_DDRABIK_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Configure MySQL/SQLite support (0=disable via config.hpp modification)
# Voron custom mysql support dropped with this commit: https://github.com/DanielDrabik/libcod/commit/ced0aa4cd1880be6180d8132a9495b3009d06fcb
RUN if [ "${LIBCOD_MYSQL_TYPE}" = "0" ]; then \
  sed -i "/#define COMPILE_MYSQL 1/c\\#define COMPILE_MYSQL 0" config.hpp && \
  sed -i "/#define COMPILE_SQLITE 1/c\\#define COMPILE_SQLITE 0" config.hpp; \
  fi
# Build libcod for specified COD2 version (doit.sh expects cod2_1_0, cod2_1_2, or cod2_1_3)
RUN ./doit.sh cod2_${COD2_VERSION} && \
  mv bin/libcod2_${COD2_VERSION}.so /lib/libcod2_${COD2_VERSION}.so

# ==================================================================
# Dynamic build source selector alias
# ==================================================================
# hadolint ignore=DL3006
FROM build-${LIBCOD_TYPE} AS build

# ==================================================================
# Runtime image
# ==================================================================
FROM alpine:3.22
ARG COD2_VERSION

# Create non-root user for running the server
ENV SERVER_USER="cod2"
RUN addgroup -g 1000 ${SERVER_USER} && \
  adduser -D -u 1000 -G ${SERVER_USER} ${SERVER_USER}

# Copy needed libraries and binaries from the selected build stage
COPY --from=build /usr/lib/i386-linux-gnu/ /usr/lib/i386-linux-gnu/
COPY --from=build /lib/i386-linux-gnu/ /lib/i386-linux-gnu/
COPY --from=build /lib/ld-linux.so.2 /lib/ld-linux.so.2
COPY --from=build /lib/libcod2_${COD2_VERSION}.so /lib/libcod2_${COD2_VERSION}.so
COPY --chown=${SERVER_USER}:${SERVER_USER} --from=build /bin/cod2_lnxded /home/${SERVER_USER}/cod2_lnxded
COPY --chown=${SERVER_USER}:${SERVER_USER} lib/pb/v1.760_A1383_C2.208/ /home/${SERVER_USER}/pb/

# Exposed server ports
EXPOSE 20500/udp 20510/udp 28960/tcp 28960/udp

# Server "main" folder volume
VOLUME [ "/home/${SERVER_USER}/main" ]

# Set the server dir
WORKDIR /home/${SERVER_USER}

# Redirect server multiplayer logs to container stdout
RUN mkdir -p /home/${SERVER_USER}/.callofduty2/main/ \
  && ln -sf /dev/stdout /home/${SERVER_USER}/.callofduty2/main/games_mp.log \
  && chown -R ${SERVER_USER}:${SERVER_USER} /home/${SERVER_USER}/.callofduty2

# Health checks :
# - check server process is running and responsive
# - check games log are written to file (Uses -e to check symlink/file exists)
HEALTHCHECK --interval=5s --timeout=1s --start-period=5s --retries=3 \
  CMD pgrep -x cod2_lnxded > /dev/null && \
  test -e /home/${SERVER_USER}/.callofduty2/main/games_mp.log || exit 1

# Switch to non-root user
USER ${SERVER_USER}

# Launch server at container startup using libcod library
ENV LD_PRELOAD="/lib/libcod2_${COD2_VERSION}.so"
ENTRYPOINT [ "./cod2_lnxded" ]
