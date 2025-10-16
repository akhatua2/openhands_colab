#!/bin/bash

# Simple Cotomata Colab runner - hardcoded for react_hook_form_task task153 features 1,2
# Usage: ./run-cotomata-colab.shclear

set -e

PROJECT="react_hook_form_task"
TASK_ID="153"
FEATURE1_ID="1"
FEATURE2_ID="2"

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY is not set. Export it before running."
    exit 1
fi

BASE_DIR="/Users/arpan/Desktop/CodeConflictBenchmark"
DATASET_DIR="$BASE_DIR/dataset/${PROJECT}/task${TASK_ID}"

# Everything else goes in openhands_colab directory for testing (like run-multiple-agents.sh)
OPENHANDS_DIR="$BASE_DIR/experiments/execution/cotomata_colab/openhands_colab"
LOGS_DIR="$OPENHANDS_DIR/logs_colab"
DB_DIR="$OPENHANDS_DIR/shared_agent_db"

# Workspace paths (use the actual git worktrees created by the Python script)
WORKSPACE1="${DATASET_DIR}/agent_workspace/${PROJECT}_feature${FEATURE1_ID}_feature${FEATURE2_ID}_k1"
WORKSPACE2="${DATASET_DIR}/agent_workspace/${PROJECT}_feature${FEATURE2_ID}_feature${FEATURE1_ID}_k1"

mkdir -p "$DB_DIR" "$LOGS_DIR"

# Load feature descriptions
FEATURE1_DESC=$(cat "$DATASET_DIR/feature${FEATURE1_ID}/feature.md" 2>/dev/null || echo "Feature ${FEATURE1_ID}")
FEATURE2_DESC=$(cat "$DATASET_DIR/feature${FEATURE2_ID}/feature.md" 2>/dev/null || echo "Feature ${FEATURE2_ID}")

# Load plans from actual logs location
ACTUAL_LOGS="$BASE_DIR/logs/cotomata/${PROJECT}/task${TASK_ID}/feature${FEATURE1_ID}_feature${FEATURE2_ID}"
PLAN1=$(cat "$ACTUAL_LOGS/plan_gpt5_k1_feature${FEATURE1_ID}.md" 2>/dev/null || echo "No plan available")
PLAN2=$(cat "$ACTUAL_LOGS/plan_gpt5_k1_feature${FEATURE2_ID}.md" 2>/dev/null || echo "No plan available")

echo "=========================================="
echo "Cotomata Colab Execution"
echo "=========================================="
echo "Project:    $PROJECT"
echo "Task:       $TASK_ID"
echo "Features:   $FEATURE1_ID <-> $FEATURE2_ID"
echo "Workspace1: $WORKSPACE1"
echo "Workspace2: $WORKSPACE2"
echo "DB:         $DB_DIR"
echo "=========================================="

# Function to run a single agent
run_agent() {
    local agent_num=$1
    local workspace=$2
    local feature_desc=$3
    local plan=$4
    local agent_id="agent_${agent_num}"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local trajectory_file="$LOGS_DIR/trajectory_agent_${agent_num}_${timestamp}.json"
    local container_name="openhands-agent_${agent_num}-${timestamp}"
    
    # Create agent-specific sandbox volumes
    local agent_volumes="$workspace:/workspace:rw,$(pwd)/mcp_communication_server.py:/app/mcp_communication_server.py:ro,$DB_DIR:/app/db:rw"
    
    # Build the task prompt
    local task="You are ${agent_id} working on the following feature in parallel with another agent.

FEATURE DESCRIPTION:
$feature_desc

IMPLEMENTATION PLAN:
$plan

YOUR TASK:
1. Implement the feature according to the plan
2. You can communicate with the other agent using MCP tools:
   - openhands_comm_send: Send messages to the other agent
   - Messages from the other agent will appear automatically as '[Inter-agent message]'
3. Coordinate to avoid conflicts
4. Complete the implementation

Work directory: /workspace"

    echo "Starting Agent $agent_num (ID: $agent_id)..."
    
    # Run in background but capture logs
    docker run --rm \
        --pull=never \
        -e SANDBOX_RUNTIME_CONTAINER_IMAGE=colab/openhands_runtime_colab:latest \
        -e SANDBOX_USER_ID=$(id -u) \
        -e SANDBOX_VOLUMES="$agent_volumes" \
        -e LLM_API_KEY="$OPENAI_API_KEY" \
        -e LLM_MODEL="gpt-5" \
        -e LOG_ALL_EVENTS=true \
        -e DEBUG=true \
        -e SAVE_TRAJECTORY_PATH="/logs/$(basename "$trajectory_file")" \
        -e OPENHANDS_AGENT_ID="$agent_id" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v ~/.openhands:/.openhands \
        -v "$(pwd)/config.toml:/app/config.toml:ro" \
        -v "$LOGS_DIR:/logs:rw" \
        --add-host host.docker.internal:host-gateway \
        --name "$container_name" \
        colab/openhands_colab:latest \
        python -m openhands.core.main --config-file /app/config.toml --log-level DEBUG -t "$task" \
        > "$LOGS_DIR/agent_${agent_num}_output.log" 2>&1 &
    
    echo "  Container: $container_name"
    echo "  Trajectory: $trajectory_file"
    echo "  Logs: $LOGS_DIR/agent_${agent_num}_output.log"
}

# Start both agents
run_agent 1 "$WORKSPACE1" "$FEATURE1_DESC" "$PLAN1"
sleep 2
run_agent 2 "$WORKSPACE2" "$FEATURE2_DESC" "$PLAN2"

echo ""
echo "=========================================="
echo "Both agents started!"
echo "=========================================="
echo ""
echo "🔍 MONITOR:"
echo "  # Stream logs from both agents:"
echo "  tail -f $LOGS_DIR/agent_1_output.log"
echo "  tail -f $LOGS_DIR/agent_2_output.log"
echo "  # Or watch both simultaneously:"
echo "  tail -f $LOGS_DIR/agent_*_output.log"
echo ""
echo "📊 CHECK MESSAGES:"
echo "  sqlite3 $DB_DIR/openhands_messages.db 'SELECT * FROM messages ORDER BY timestamp;'"
echo ""
echo "🛑 STOP:"
echo "  pkill -f 'docker run.*openhands_colab'"
echo "  # Or find and kill specific containers:"
echo "  docker ps --filter name=openhands-agent"
echo "  docker stop \$(docker ps -q --filter name=openhands-agent)"
echo ""
echo "📁 OUTPUTS:"
echo "  Live Logs:     $LOGS_DIR/agent_*_output.log"
echo "  Trajectories: $LOGS_DIR/trajectory_agent_*.json"
echo "  Database:     $DB_DIR/openhands_messages.db"
echo "  Workspace 1:  $WORKSPACE1"
echo "  Workspace 2:  $WORKSPACE2"
echo ""

