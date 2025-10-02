#!/usr/bin/env python3

"""
Minimal MCP Server for OpenHands (Python version)
Provides basic tools: echo, file_list, current_time
"""

import asyncio
import json
import sys
import os
from datetime import datetime
from typing import Any, Dict, List


class MinimalMCPServer:
    def __init__(self):
        self.tools = {
            "echo": {
                "name": "echo",
                "description": "Echo back the provided text",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "text": {
                            "type": "string",
                            "description": "Text to echo back"
                        }
                    },
                    "required": ["text"]
                }
            },
            "file_list": {
                "name": "file_list",
                "description": "List files in the current directory",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "directory": {
                            "type": "string",
                            "description": "Directory to list (defaults to current)",
                            "default": "."
                        }
                    }
                }
            },
            "current_time": {
                "name": "current_time",
                "description": "Get the current time",
                "inputSchema": {
                    "type": "object",
                    "properties": {}
                }
            }
        }

    async def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle incoming MCP requests"""
        method = request.get("method", "")
        params = request.get("params", {})
        
        if method == "tools/list":
            return {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "result": {
                    "tools": list(self.tools.values())
                }
            }
        
        elif method == "tools/call":
            tool_name = params.get("name", "")
            arguments = params.get("arguments", {})
            
            try:
                result = await self.call_tool(tool_name, arguments)
                return {
                    "jsonrpc": "2.0",
                    "id": request.get("id"),
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": result
                            }
                        ]
                    }
                }
            except Exception as e:
                return {
                    "jsonrpc": "2.0",
                    "id": request.get("id"),
                    "error": {
                        "code": -32000,
                        "message": str(e)
                    }
                }
        
        elif method == "initialize":
            return {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {}
                    },
                    "serverInfo": {
                        "name": "minimal-mcp-server",
                        "version": "1.0.0"
                    }
                }
            }
        
        else:
            return {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }

    async def call_tool(self, name: str, arguments: Dict[str, Any]) -> str:
        """Execute a tool and return the result"""
        if name == "echo":
            text = arguments.get("text", "")
            return f"Echo: {text}"
        
        elif name == "file_list":
            directory = arguments.get("directory", ".")
            try:
                files = os.listdir(directory)
                return f"Files in {directory}:\n" + "\n".join(files)
            except Exception as e:
                return f"Error listing files: {e}"
        
        elif name == "current_time":
            return f"Current time: {datetime.now().isoformat()}"
        
        else:
            raise Exception(f"Unknown tool: {name}")

    async def run(self):
        """Run the MCP server on stdio"""
        server = MinimalMCPServer()
        
        # Send server info to stderr for debugging
        print("Minimal MCP Server running on stdio", file=sys.stderr)
        
        # Read from stdin and write to stdout
        while True:
            try:
                line = await asyncio.get_event_loop().run_in_executor(
                    None, sys.stdin.readline
                )
                
                if not line:
                    break
                
                # Parse JSON-RPC request
                try:
                    request = json.loads(line.strip())
                except json.JSONDecodeError:
                    continue
                
                # Handle request
                response = await self.handle_request(request)
                
                # Send response
                print(json.dumps(response), flush=True)
                
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)
                break


if __name__ == "__main__":
    server = MinimalMCPServer()
    asyncio.run(server.run())
