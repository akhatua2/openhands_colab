#!/bin/bash

# Run multiple OpenHands agents for collaborative puzzle solving
# Each agent gets partial information and must communicate to solve the complete puzzle
# Usage: ./run-multiple-agents.sh [number_of_agents]

NUM_AGENTS=${1:-2}  # Default to 2 agents

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY is not set. Export it before running."
    exit 1
fi

echo "Starting $NUM_AGENTS OpenHands agents for COLLABORATIVE PUZZLE SOLVING..."
echo ""
echo "🧩 PUZZLE SETUP:"
echo "  Agent 1 knows: First half of code ('ALPHA') + math operation (ADDITION) + first number (42)"
echo "  Agent 2 knows: Second half of code ('OMEGA') + second number (58)"
echo "  Expected solution: [ALPHAOMEGA][100] (42 + 58 = 100)"
echo ""

# Create shared directories
LOGS_DIR="$(pwd)/logs_colab"
DB_DIR="$(pwd)/shared_agent_db"
mkdir -p "$LOGS_DIR" "$DB_DIR"

export LLM_MODEL="gpt-5"

# Function to run a single agent
run_agent() {
    local agent_num=$1
    local agent_id="agent_${agent_num}"  # Simple, clean agent ID
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local trajectory_file="$LOGS_DIR/trajectory_${agent_id}_${timestamp}.json"
    local container_name="openhands-${agent_id}-${timestamp}"
    
    # Create isolated workspace for this agent
    local agent_workspace="$(pwd)/agent_${agent_num}_workspace"
    mkdir -p "$agent_workspace"
    
    # Write agent ID to agent's isolated workspace for MCP server to read
    echo "$agent_id" > "$agent_workspace/agent_id.txt"
    
    # Create agent-specific sandbox volumes (isolated workspace + shared MCP server + shared database)
    local agent_volumes="$agent_workspace:/workspace:rw,$(pwd)/mcp_communication_server.py:/app/mcp_communication_server.py:ro,$DB_DIR:/app/db:rw"
    
    echo "Starting Agent $agent_num (ID: $agent_id)"
    echo "  Workspace: $agent_workspace"
    
    # Collaborative puzzle-solving tasks for different agents
    local task
    case $agent_num in
           1)
               task="COLLABORATIVE PUZZLE - You are agent_1. 

MISSION: Work with agent_2 to solve this puzzle. You have PART 1 of the solution.

YOUR SECRET INFO (agent_1 only):
- The first half of a secret code is: 'ALPHA'
- The mathematical operation needed is: ADDITION
- The first number in the equation is: 42

TASK:
1) Send your secret info to agent_2 using openhands_comm_send with recipient_id='agent_2'
2) Messages from other agents will appear automatically as '[Inter-agent message]' in your conversation
3) Once you receive agent_2's info, solve the complete puzzle
4) The final answer should be in format: '[CODE][RESULT]' where CODE is both parts combined and RESULT is the math result

Work together to find the complete answer!"
               ;;
        2) 
            task="COLLABORATIVE PUZZLE - You are agent_2.

MISSION: Work with agent_1 to solve this puzzle. You have PART 2 of the solution.

YOUR SECRET INFO (agent_2 only):
- The second half of a secret code is: 'OMEGA'
- The second number in the equation is: 58
- The operation will be provided by agent_1

TASK:
1) Messages from other agents will appear automatically as '[Inter-agent message]' in your conversation
2) Send your secret info to agent_1 using openhands_comm_send with recipient_id='agent_1'
3) Help solve the complete puzzle together
4) Verify the solution is correct based on the combined information

The complete code should combine both parts, and the math should use both numbers with agent_1's operation.

Work together to find the complete answer!"
            ;;
        *)
            task="You are Agent $agent_num. Test MCP communication: 1) Use openhands_comm_get to check for messages, 2) Use openhands_comm_send to send 'Hello from Agent $agent_num at $(date)!' to broadcast"
            ;;
    esac
    
    docker run -d --rm \
        --pull=never \
        -e SANDBOX_RUNTIME_CONTAINER_IMAGE=colab/openhands_runtime_colab:latest \
        -e SANDBOX_USER_ID=$(id -u) \
        -e SANDBOX_VOLUMES="$agent_volumes" \
        -e LLM_API_KEY="$OPENAI_API_KEY" \
        -e LLM_MODEL="$LLM_MODEL" \
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
        python -m openhands.core.main --config-file /app/config.toml --log-level DEBUG -t "$task"
    
    echo "Agent $agent_num started in background (Container: $container_name)"
    echo "Trajectory: $trajectory_file"
    echo "---"
}

# Start all agents
for i in $(seq 1 $NUM_AGENTS); do
    run_agent $i
    sleep 2  # Small delay between starts
done

echo "All $NUM_AGENTS agents started!"
echo ""
echo "🔍 MONITORING THE PUZZLE SOLVING:"
echo "  docker ps  # List running containers"
echo "  docker logs -f openhands-agent_1_*  # Follow Agent 1 (has first puzzle piece)"
echo "  docker logs -f openhands-agent_2_*  # Follow Agent 2 (has second puzzle piece)"
echo ""
echo "📊 CHECK COMMUNICATION:"
echo "  sqlite3 $DB_DIR/openhands_messages.db \"SELECT sender_id, content, timestamp FROM messages ORDER BY timestamp;\""
echo ""
echo "🛑 TO STOP ALL AGENTS:"
echo "  docker stop \$(docker ps -q --filter name=openhands-agent)"
echo ""
echo "📁 RESULTS LOCATIONS:"
echo "  Messages: $DB_DIR/openhands_messages.db"
echo "  Trajectories: $LOGS_DIR/"
echo "  Agent 1 workspace: $(pwd)/agent_1_workspace/"
echo "  Agent 2 workspace: $(pwd)/agent_2_workspace/"
echo ""
echo "🔒 ISOLATION:"
echo "  ✅ Each agent has its own isolated workspace"
echo "  ✅ Agents share only the communication database"
echo "  ✅ No file contamination between agents"
echo ""
echo "🎯 SUCCESS CRITERIA:"
echo "  - Agent 1 sends: 'ALPHA', 'ADDITION', '42'"
echo "  - Agent 2 sends: 'OMEGA', '58'"
echo "  - Final answer: '[ALPHAOMEGA][100]'"
