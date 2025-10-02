#!/usr/bin/env python3
"""
Local test for the minimal MCP server without stdio.
Calls handle_request directly and verifies DB insert.
"""

import asyncio
import os
import sqlite3
from typing import Dict, Any

# Set test DB path before importing server module (absolute path under this folder)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEST_DB = os.path.join(BASE_DIR, 'shared', 'collaboration_test.db')
os.makedirs(os.path.dirname(TEST_DB), exist_ok=True)
os.environ['COLLABORATION_DB_PATH'] = TEST_DB

from collaboration import init_db, handle_request, get_db_path


def call(req: Dict[str, Any]) -> Dict[str, Any]:
    return asyncio.get_event_loop().run_until_complete(handle_request(req))


def main() -> None:
    init_db()

    # 1) initialize
    resp1 = call({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}})
    assert 'result' in resp1 and resp1['result']['serverInfo']['name'] == 'collaboration'

    # 2) tools/list → must include send
    resp2 = call({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}})
    tool_names = [t['name'] for t in resp2['result']['tools']]
    assert 'send' in tool_names

    # 3) tools/call send → insert row
    resp3 = call({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
            'name': 'send',
            'arguments': {'message': 'hello from test', 'agent_id': 'tester'},
        },
    })
    assert 'result' in resp3

    # 4) Verify DB row
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute('SELECT sender, message FROM messages ORDER BY id DESC LIMIT 1')
    row = cur.fetchone()
    conn.close()
    assert row is not None and row[0] == 'tester' and row[1] == 'hello from test'

    print('OK: test passed')


if __name__ == '__main__':
    main()


