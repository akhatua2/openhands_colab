#!/bin/bash

# Simple sequential multi-agent communication test
# Tests the shared MCP server and database

if [ -z "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY is not set. Export it before running."
    exit 1
fi

echo "=== Multi-Agent Communication Test ==="
echo ""

# Clean up any existing database
rm -f shared_agent_db/openhands_messages.db

echo "Step 1: Agent 1 sends a message..."
echo "Running: OPENHANDS_AGENT_ID=\"agent_1\" ./run-openhands.sh"
OPENHANDS_AGENT_ID="agent_1" ./run-openhands.sh

echo "Step 2: Checking database for Agent 1's message..."
if [ -f "shared_agent_db/openhands_messages.db" ]; then
    echo "✅ Database created successfully!"
    sqlite3 shared_agent_db/openhands_messages.db "SELECT sender_id, content, timestamp FROM messages ORDER BY timestamp;"
else
    echo "❌ Database not found"
    exit 1
fi

echo ""
echo "Step 3: Agent 2 checks for messages and replies..."
echo "Running: OPENHANDS_AGENT_ID=\"agent_2\" ./run-openhands.sh"
OPENHANDS_AGENT_ID="agent_2" ./run-openhands.sh

echo "Step 4: Final database state (should show both agents' messages):"
sqlite3 shared_agent_db/openhands_messages.db "SELECT sender_id, content, timestamp FROM messages ORDER BY timestamp;"

echo ""
echo "✅ Multi-agent communication test completed!"
echo "Check the trajectories in logs_colab/ for detailed logs"
