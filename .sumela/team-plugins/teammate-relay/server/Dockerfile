# Teammate Relay server — hardened image.
# Runs as non-root, read-only root FS (enforced in compose), only the WSS port exposed.
FROM python:3.12-slim AS base

# Create an unprivileged user up front.
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin relay

WORKDIR /app

# Install only runtime deps (no build toolchain left in the final image).
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy the relay code (server + shared modules). Tests/docs are NOT shipped.
COPY relay_common /app/relay_common
COPY server /app/server

ENV PYTHONUNBUFFERED=1 \
    RELAY_HOST=0.0.0.0 \
    RELAY_PORT=8765 \
    RELAY_SERVER_KEY=/data/server-key.pem

EXPOSE 8765
USER relay

# Healthcheck: complete a TLS handshake (a bare TCP connect would report healthy even with
# a broken/expired/unreadable cert — review I4). Self-signed/hostname not verified here; this
# proves the listener is up AND TLS is wired.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import socket,ssl,os; ctx=ssl._create_unverified_context(); s=ctx.wrap_socket(socket.create_connection(('127.0.0.1', int(os.environ['RELAY_PORT'])), 3), server_hostname='localhost'); s.close()" || exit 1

ENTRYPOINT ["python", "-m", "server.main"]
CMD ["serve"]
