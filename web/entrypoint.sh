#!/bin/sh
# Start the Rust fetch sidecar in the background, then run the Node helper as
# the foreground process. Killing the container or the Node process terminates
# the sidecar via SIGTERM.

set -e

# Sidecar listens on 127.0.0.1:9876 by default, only reachable from inside the
# container. Override port via VENERA_FETCH_PORT if it conflicts.
VENERA_FETCH_PORT="${VENERA_FETCH_PORT:-9876}"
export VENERA_FETCH_PORT

# Launch sidecar
/usr/local/bin/venera-fetch &
SIDECAR_PID=$!

# Forward signals so the sidecar dies cleanly on container stop.
trap 'kill -TERM "$SIDECAR_PID" 2>/dev/null || true' INT TERM

# Run Node helper as PID 1's child. Replace shell once Node is ready so its
# signals/lifecycle remain the container's primary process.
node server.js &
NODE_PID=$!

# Wait for Node to exit, then clean up the sidecar.
wait "$NODE_PID"
NODE_EXIT=$?

kill -TERM "$SIDECAR_PID" 2>/dev/null || true
wait "$SIDECAR_PID" 2>/dev/null || true

exit "$NODE_EXIT"
