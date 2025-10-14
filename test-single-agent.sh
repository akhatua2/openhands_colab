#!/bin/bash

# Simple test script to debug workspace detection with actual task data

# Use the actual workspace that was already created
WORKSPACE_DIR="/Users/arpan/Desktop/CodeConflictBenchmark/dataset/dspy_task/task8394/agent_workspace/dspy_task_feature1_feature2_k1"

# Create logs directory
LOGS_DIR="$(pwd)/logs_test"
mkdir -p "$LOGS_DIR"

# Create MCP database directory
DB_DIR="$(pwd)/test_db"
mkdir -p "$DB_DIR"

# Require API key
if [ -z "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY is not set. Export it before running."; exit 1
fi

# Write agent ID
echo "agent_1" > "$WORKSPACE_DIR/agent_id.txt"
echo "agent_1" > "$DB_DIR/agent_id.txt"

# Set up SANDBOX_VOLUMES with workspace + MCP files
export SANDBOX_VOLUMES="$WORKSPACE_DIR:/workspace:rw,$(pwd)/mcp_communication_server.py:/app/mcp_communication_server.py:ro,$DB_DIR:/app/db:rw"

echo "Workspace: $WORKSPACE_DIR"
echo "SANDBOX_VOLUMES: $SANDBOX_VOLUMES"
echo ""

# Simple task prompt
TASK="Implement the feature described in the plan. Work in the /workspace directory which contains the dspy codebase."

docker run -it --rm \
    --pull=never \
    -e SANDBOX_RUNTIME_CONTAINER_IMAGE=colab/openhands_runtime_colab:latest \
    -e SANDBOX_USER_ID=$(id -u) \
    -e SANDBOX_VOLUMES="$SANDBOX_VOLUMES" \
    -e LLM_API_KEY="$OPENAI_API_KEY" \
    -e LLM_MODEL="gpt-5" \
    -e LOG_ALL_EVENTS=true \
    -e DEBUG=true \
    -e SAVE_TRAJECTORY_PATH="/logs/test_trajectory.json" \
    -e OPENHANDS_AGENT_ID="agent_1" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ~/.openhands:/.openhands \
    -v "$(pwd)/config.toml:/app/config.toml:ro" \
    -v "$LOGS_DIR:/logs:rw" \
    -v "$WORKSPACE_DIR:/opt/workspace_base:rw" \
    --add-host host.docker.internal:host-gateway \
    --name openhands-test-$(date +%Y%m%d%H%M%S) \
    colab/openhands_colab:latest \
    python -m openhands.core.main \
        --config-file /app/config.toml \
        --log-level DEBUG \
        -i 100 \
        -t "$TASK"

