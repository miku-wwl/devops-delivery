# syntax=docker/dockerfile:1
# Multi-stage build: dependencies are installed in a throwaway "build" stage, the
# runtime stage only receives the installed packages and the source code.

# Base image pinned by digest (multi-arch index of python:3.13-slim, 2026-11-06).
# Update the tag and digest together, e.g. via Dependabot/Renovate.
ARG PYTHON_IMAGE=python:3.13-slim@sha256:09a17cad02668ae61ece136b4fd36ac3849e14f670ebedb637ea3e15580525bc

FROM ${PYTHON_IMAGE} AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check --prefix=/install -r requirements.txt

FROM ${PYTHON_IMAGE} AS runtime
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="demo-api" \
      org.opencontainers.image.description="Reference workload for the devops-delivery training repository" \
      org.opencontainers.image.source="https://github.com/miku-wwl/devops-delivery" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}
# Debian security update newer than the pinned base image (2026-11-13): zlib1g CVE-2026-76844 and
# CVE-2026-85091 (HIGH, fixed in 1:1.3.dfsg+really1.3.1-1+deb13u1). The image gate blocks fixable
# HIGH findings; drop this step once the pinned python:3.13-slim digest ships the fixed package.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends --only-upgrade zlib1g \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app \
 # pip is only needed at build time. Its vendored copies of urllib3, msgpack and
 # setuptools were flagged by Trivy (HIGH, fix available); removing pip from the
 # runtime image removes them and means nobody can "pip install" inside a container.
 && python -m pip uninstall --yes --quiet pip \
 && rm -rf /usr/local/lib/python3.13/ensurepip
COPY --from=build /install /usr/local
WORKDIR /app
COPY src/ ./src/
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]
CMD ["uvicorn", "demo_api.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
