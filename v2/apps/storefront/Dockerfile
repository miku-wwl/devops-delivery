# syntax=docker/dockerfile:1
# One image for all six storefront services; the Deployment's command picks the service:
#   uvicorn storefront.<service>.main:app ...      (see the Helm chart in v2/gitops/charts)
# Stages: deps -> test (lint + unit tests, also used by CI) -> runtime.

# python:3.13-slim, multi-arch index digest (same base as volume 1, chapter 5)
ARG PYTHON_IMAGE=python:3.13-slim@sha256:09a17cad02668ae61ece136b4fd36ac3849e14f670ebedb637ea3e15580525bc

FROM ${PYTHON_IMAGE} AS deps
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check --prefix=/install -r requirements.txt

FROM ${PYTHON_IMAGE} AS test
WORKDIR /src
COPY requirements-dev.txt requirements.txt ./
RUN pip install --no-cache-dir --disable-pip-version-check -r requirements-dev.txt
COPY pyproject.toml ./
COPY src/ ./src/
COPY tests/ ./tests/
ENV PYTHONPATH=/src/src PYTHONDONTWRITEBYTECODE=1
RUN ruff check src tests && ruff format --check src tests
CMD ["pytest", "-q", "--cov=storefront", "--cov-report=term"]

FROM ${PYTHON_IMAGE} AS runtime
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="storefront" \
      org.opencontainers.image.description="Multi-service workload of volume 2 of the devops-delivery handbook" \
      org.opencontainers.image.source="https://github.com/miku-wwl/devops-delivery" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app/src \
    APP_VERSION=${APP_VERSION} GIT_SHA=${GIT_SHA}
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app \
 && python -m pip uninstall --yes --quiet pip \
 && rm -rf /usr/local/lib/python3.13/ensurepip
COPY --from=deps /install /usr/local
WORKDIR /app
COPY src/ ./src/
USER 10001
EXPOSE 8080
# No default service: the command names it, e.g.
#   ["uvicorn", "storefront.gateway.main:app", "--host", "0.0.0.0", "--port", "8080",
#    "--loop", "uvloop", "--http", "httptools", "--no-access-log"]
CMD ["python", "-c", "print('choose a service: uvicorn storefront.<service>.main:app'); raise SystemExit(64)"]
