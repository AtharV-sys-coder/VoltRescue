# Always-on host for VoltRescue. The laptop is not in this path.
# Build:  flyctl deploy
# Public: https://<app>.fly.dev  (HTTPS forced)

FROM mcr.microsoft.com/powershell:7.4-ubuntu-24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends sqlite3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY api ./api
COPY public ./public
COPY server.ps1 ./
COPY .env.example ./
RUN mkdir -p data uploads

ENV PORT=8080
ENV APP_PORT=8080
ENV APP_ENV=poc
EXPOSE 8080

CMD ["pwsh", "-NoProfile", "-File", "/app/server.ps1"]
