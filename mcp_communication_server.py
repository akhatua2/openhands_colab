#!/usr/bin/env python3

"""
Multi-OpenHands Communication MCP Server
Implements proper MCP protocol using stdio transport
"""

import json
import sqlite3
import sys
import os
from datetime import datetime
from typing import Any, Dict
import uuid


# Database setup
def init_database(db_path: str):
    """Initialize SQLite database"""
    conn = sqlite3.connect(db_path)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            content TEXT NOT NULL,
            message_type TEXT DEFAULT 'info',
            timestamp TEXT NOT NULL,
            is_read BOOLEAN DEFAULT FALSE
        )
    """)
    conn.commit()
    conn.close()


def error_response(code: int, message: str, req_id: Any) -> Dict[str, Any]:
    """Create a JSON-RPC error response"""
    return {
        'jsonrpc': '2.0',
        'id': req_id,
        'error': {'code': code, 'message': message}
    }


# Global agent ID - will be set when the script starts
AGENT_ID = "unknown_agent"

def handle_request(request: Dict[str, Any]) -> Dict[str, Any]:
    """Handle MCP JSON-RPC request"""
    global AGENT_ID
    
    # Try to read agent ID from file if not set via command line
    if AGENT_ID == "unknown_agent":
        # Try workspace first (for multi-agent), then shared db (for single agent)
        agent_id_paths = ["/workspace/agent_id.txt", "/app/db/agent_id.txt"]
        
        for agent_id_file in agent_id_paths:
            if os.path.exists(agent_id_file):
                try:
                    with open(agent_id_file, 'r') as f:
                        AGENT_ID = f.read().strip()
                    break
                except Exception:
                    pass  # Silently try next path
    
    agent_id = AGENT_ID
    db_dir = "/app/db" if os.path.exists("/app/db") else "."
    db_path = os.path.join(db_dir, "openhands_messages.db")
    
    # Initialize database if needed
    init_database(db_path)
    
    method = request.get('method')
    params = request.get('params', {})
    req_id = request.get('id')

    if method == 'initialize':
        return {
            'jsonrpc': '2.0',
            'id': req_id,
            'result': {
                'protocolVersion': '2024-11-05',
                'capabilities': {'tools': {}},
                'serverInfo': {'name': 'openhands_communication', 'version': '1.0.0'},
            },
        }

    if method == 'tools/list':
        return {
            'jsonrpc': '2.0',
            'id': req_id,
            'result': {
                'tools': [
                    {
                        'name': 'send',
                        'description': 'Send a message to another OpenHands agent',
                        'inputSchema': {
                            'type': 'object',
                            'properties': {
                                'content': {
                                    'type': 'string',
                                    'description': 'Message content',
                                },
                                'recipient_id': {
                                    'type': 'string',
                                    'description': 'Target agent ID or "broadcast"',
                                    'default': 'broadcast'
                                },
                            },
                            'required': ['content'],
                        },
                    },
                    {
                        'name': 'get',
                        'description': 'Get messages from other agents',
                        'inputSchema': {
                            'type': 'object',
                            'properties': {
                                'limit': {
                                    'type': 'integer',
                                    'description': 'Maximum number of messages to retrieve',
                                    'default': 10
                                },
                            },
                        },
                    }
                ]
            },
        }

    if method == 'tools/call':
        tool = params.get('name')
        args = params.get('arguments', {})

        if tool == 'send':
            content = args.get('content')
            if not isinstance(content, str) or content == '':
                return error_response(-32602, 'Invalid params: content is required', req_id)

            recipient_id = args.get('recipient_id', 'broadcast')

            try:
                conn = sqlite3.connect(db_path)
                cursor = conn.execute(
                    "INSERT INTO messages (sender_id, recipient_id, content, timestamp) VALUES (?, ?, ?, ?)",
                    (agent_id, recipient_id, content, datetime.now().isoformat())
                )
                conn.commit()
                message_id = cursor.lastrowid
                conn.close()

                return {
                    'jsonrpc': '2.0',
                    'id': req_id,
                    'result': {
                        'content': [{'type': 'text', 'text': f'Message sent successfully (ID: {message_id})'}]
                    }
                }
            except Exception as e:
                return error_response(-32603, f'Database error: {str(e)}', req_id)

        elif tool == 'get':
            limit = args.get('limit', 10)
            
            try:
                conn = sqlite3.connect(db_path)
                # Only get UNREAD messages from OTHER agents (not self)
                cursor = conn.execute(
                    "SELECT id, sender_id, content, timestamp FROM messages WHERE (recipient_id = ? OR recipient_id = 'broadcast') AND sender_id != ? AND is_read = FALSE ORDER BY timestamp ASC LIMIT ?",
                    (agent_id, agent_id, limit)
                )
                messages = cursor.fetchall()
                
                if messages:
                    # Mark them as read
                    message_ids = [msg[0] for msg in messages]
                    placeholders = ','.join('?' * len(message_ids))
                    conn.execute(f"UPDATE messages SET is_read = TRUE WHERE id IN ({placeholders})", message_ids)
                    conn.commit()
                    
                    # Format result (skip the id field)
                    result = "\n".join([f"From {msg[1]} at {msg[3]}: {msg[2]}" for msg in messages])
                else:
                    result = "No new messages"
                
                conn.close()

                return {
                    'jsonrpc': '2.0',
                    'id': req_id,
                    'result': {
                        'content': [{'type': 'text', 'text': result}]
                    }
                }
            except Exception as e:
                return error_response(-32603, f'Database error: {str(e)}', req_id)

        else:
            return error_response(-32601, f"Unknown tool: {tool}", req_id)

    return error_response(-32601, f"Unknown method: {method}", req_id)


def main():
    """Main stdio MCP server loop"""
    # Minimize stderr output during startup for FastMCP compatibility
    
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
            
        try:
            request = json.loads(line)
            response = handle_request(request)
            print(json.dumps(response), flush=True)
        except json.JSONDecodeError as e:
            error_resp = error_response(-32700, f"Parse error: {str(e)}", None)
            print(json.dumps(error_resp), flush=True)
        except Exception as e:
            error_resp = error_response(-32603, f"Internal error: {str(e)}", None)
            print(json.dumps(error_resp), flush=True)


if __name__ == "__main__":
    import sys
    
    # Parse command line arguments for agent ID
    if len(sys.argv) > 1:
        AGENT_ID = sys.argv[1]
    else:
        # Try environment variable as fallback
        AGENT_ID = os.environ.get('OPENHANDS_AGENT_ID', 'unknown_agent')
    
    # Start main loop (minimal stderr output for FastMCP compatibility)
    main()