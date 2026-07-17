# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) for georinex — a PURE-Python package fuzzed with atheris.
# Builds ON TOP of the org base image (ghcr.io/mayhemheroes/base), which provides debian + clang +
# python3.13 + the non-root `mayhem` identity + the build-contract ENV. The base ships no atheris,
# so this image bakes a pip wheelhouse (atheris + georinex + its full dep closure: numpy, xarray,
# netcdf4, hatanaka, ncompress, python-dateutil, …) under /opt/toolchains; build.sh then installs
# from it OFFLINE and compiles a tiny ELF libFuzzer launcher for the .py harness.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t georinex-commit:test .
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Declared for parity with the build contract; georinex is pure Python (no native objects to sanitize).
ARG SANITIZER_FLAGS

# Pin atheris (prebuilt cp313 wheel) so the wheelhouse is reproducible.
ARG ATHERIS_VERSION=3.1.0
ENV ATHERIS_VERSION=${ATHERIS_VERSION} \
    PIP_WHEELHOUSE=/opt/toolchains/pip/wheelhouse \
    PY_VENV=/opt/toolchains/python/venv \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Wheelhouse and venv under /opt/toolchains ($HOME-independent); owned by the non-root mayhem user (2000) so
# build.sh — run as mayhem — populates it on the first online build and reads it on the offline re-run.
USER root
RUN install -d -o 2000 -g 2000 /opt/toolchains/pip/wheelhouse /opt/toolchains/python
USER mayhem

# The FULL repo (incl. .git history) enters from the CI checkout and is built in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run the functional known-answer oracle at build time; a failing suite fails the image build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
