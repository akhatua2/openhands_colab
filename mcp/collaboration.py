#!/usr/bin/env python3
"""
Minimal MCP stdio server exposing a single tool: send.
Writes messages to a SQLite database.

Methods implemented (JSON-RPC 2.0):
- initialize
- tools/list (declares the send tool)
- tools/call (send)

No external deps. Intended for local OpenHands via stdio MCP.
"""

import asyncio
import json
import logging
import os
import sqlite3
import sys
from typing import Any, Dict


# Configure logging: keep stderr quiet for stdio channel, verbose to file
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('mcp_collaboration.log'),
        logging.StreamHandler(sys.stderr),
    ],
)
logging.getLogger().handlers[1].setLevel(logging.ERROR)
logger = logging.getLogger(__name__)


def get_db_path() -> str:
    return os.getenv('COLLABORATION_DB_PATH', './shared/collaboration.db')


def init_db() -> None:
    db_path = get_db_path()
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute(
        '''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        '''
    )
    conn.commit()
    conn.close()
    logger.info(f"DB initialized at {db_path}")


def db_connect():
    return sqlite3.connect(get_db_path())


def error_response(code: int, message: str, id_value: Any) -> Dict[str, Any]:
    return {
        'jsonrpc': '2.0',
        'id': id_value,
        'error': {
            'code': code,
            'message': message,
        },
    }


async def handle_request(req: Dict[str, Any]) -> Dict[str, Any]:
    method = req.get('method', '')
    params = req.get('params', {})
    req_id = req.get('id')

    if method == 'initialize':
        return {
            'jsonrpc': '2.0',
            'id': req_id,
            'result': {
                'protocolVersion': '2024-11-05',
                'capabilities': {'tools': {}},
                'serverInfo': {'name': 'collaboration', 'version': '0.1.0'},
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
                        'description': 'Send a message stored in SQLite',
                        'inputSchema': {
                            'type': 'object',
                            'properties': {
                                'message': {
                                    'type': 'string',
                                    'description': 'Message text',
                                },
                                'agent_id': {
                                    'type': 'string',
                                    'description': 'Optional agent identifier',
                                },
                            },
                            'required': ['message'],
                        },
                    }
                ]
            },
        }

    if method == 'tools/call':
        tool = params.get('name')
        args = params.get('arguments', {})

        if tool != 'send':
            return error_response(-32601, f"Unknown tool: {tool}", req_id)

        message = args.get('message')
        if not isinstance(message, str) or message == '':
            return error_response(-32602, 'Invalid params: message is required', req_id)

        agent_id = args.get('agent_id') or 'unknown'

        try:
            conn = db_connect()
            cur = conn.cursor()
            cur.execute(
                'INSERT INTO messages (sender, message) VALUES (?, ?)',
                (agent_id, message),
            )
            conn.commit()
            conn.close()
        except Exception as e:
            logger.exception('DB insert failed')
            return error_response(-32603, f'Internal error: {str(e)}', req_id)

        return {
            'jsonrpc': '2.0',
            'id': req_id,
            'result': {
                'content': [
                    {'type': 'text', 'text': f'OK: message stored for {agent_id}'}
                ]
            },
        }

    return error_response(-32601, f'Method not found: {method}', req_id)


async def stdio_loop() -> None:
    logger.info('Starting MCP stdio server (collaboration)')
    while True:
        try:
            line = await asyncio.get_event_loop().run_in_executor(None, sys.stdin.readline)
            if not line:
                break
            try:
                req = json.loads(line.strip())
            except json.JSONDecodeError as e:
                print(json.dumps(error_response(-32700, f'Parse error: {str(e)}', None)), flush=True)
                continue

            resp = await handle_request(req)
            print(json.dumps(resp), flush=True)
        except Exception as e:
            logger.exception('Unhandled error in stdio_loop')
            print(json.dumps(error_response(-32603, f'Internal error: {str(e)}', None)), flush=True)


def main() -> None:
    init_db()
    asyncio.run(stdio_loop())


if __name__ == '__main__':
    main()


