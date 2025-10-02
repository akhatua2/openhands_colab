#!/bin/bash

# OpenHands headless runner with custom images (hardcoded, no args)

# Create/use local tmp workspace folder in this repo
TMP_WS_DIR="$(pwd)/tmp_workspace"
mkdir -p "$TMP_WS_DIR"

# Create logs directory for trajectories
LOGS_DIR="$(pwd)/logs_colab"
mkdir -p "$LOGS_DIR"

# Create shared database directory for agent communication
DB_DIR="$(pwd)/shared_agent_db"
mkdir -p "$DB_DIR"

# Hardcoded environment - mount workspace, MCP server, and shared database
export SANDBOX_VOLUMES="$TMP_WS_DIR:/workspace:rw,$(pwd)/mcp_communication_server.py:/app/mcp_communication_server.py:ro,$DB_DIR:/app/db:rw"
export LLM_MODEL="gpt-5"

# Require API key from environment (do not hardcode secrets in repo)
if [ -z "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY is not set. Export it before running."; exit 1
fi

# Generate unique trajectory filename and agent ID
TRAJECTORY_FILE="$LOGS_DIR/trajectory_$(date +%Y%m%d_%H%M%S).json"
AGENT_ID="agent_$(date +%Y%m%d_%H%M%S)"

# Write agent ID to file for MCP server to read
echo "$AGENT_ID" > "$DB_DIR/agent_id.txt"

echo "Saving trajectory to: $TRAJECTORY_FILE"
echo "Agent ID: $AGENT_ID"

# MCP server will be started by OpenHands as stdio server
echo "MCP Communication Server will be started by OpenHands as stdio server"

docker run -it --rm \
    --pull=never \
    -e SANDBOX_RUNTIME_CONTAINER_IMAGE=colab/openhands_runtime_colab:latest \
    -e SANDBOX_USER_ID=$(id -u) \
    -e SANDBOX_VOLUMES="$SANDBOX_VOLUMES" \
    -e LLM_API_KEY="$OPENAI_API_KEY" \
    -e LLM_MODEL="$LLM_MODEL" \
    -e LOG_ALL_EVENTS=true \
    -e DEBUG=true \
    -e SAVE_TRAJECTORY_PATH="/logs/$(basename "$TRAJECTORY_FILE")" \
    -e OPENHANDS_AGENT_ID="$AGENT_ID" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ~/.openhands:/.openhands \
    -v "$(pwd)/config.toml:/app/config.toml:ro" \
    -v "$LOGS_DIR:/logs:rw" \
    --add-host host.docker.internal:host-gateway \
    --name openhands-app-$(date +%Y%m%d%H%M%S) \
    colab/openhands_colab:latest \
    python -m openhands.core.main --config-file /app/config.toml --log-level DEBUG -t "Please test the MCP communication tools. First, check what MCP tools are available to you (there should be 'send' and 'get' tools), then test them by sending a message and retrieving it."