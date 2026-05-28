# Runtime stage. The Linux64 FFCompanion binary is built externally via the
# delphi-build MCP server (Windows-hosted Delphi cross-compiler) and consumed
# from bin/Linux64/Release/.
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      libsqlite3-0 ca-certificates curl tzdata \
 && rm -rf /var/lib/apt/lists/*

# Non-root runtime user
RUN groupadd -r ff && useradd -r -g ff -d /app -s /usr/sbin/nologin ff \
 && mkdir -p /app /app/data && chown -R ff:ff /app

WORKDIR /app

# Copy compiled binary + runtime assets
COPY --chown=ff:ff bin/Linux64/Release/FFCompanion /app/FFCompanion
COPY --chown=ff:ff templates /app/templates
COPY --chown=ff:ff static    /app/static
COPY --chown=ff:ff l10n      /app/l10n
COPY --chown=ff:ff data/books_seed.yaml /app/seed/books_seed.yaml

RUN chmod +x /app/FFCompanion

USER ff

ENV TZ=Europe/Berlin \
    HTTP_PORT=8080 \
    DEFAULT_LANGUAGE=de \
    DATABASE_PATH=/app/data/ffcompanion.db \
    SEED_YAML_PATH=/app/seed/books_seed.yaml

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/login || exit 1

CMD ["/app/FFCompanion"]
