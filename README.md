# Community Crossword

[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/apps/new?repo=https://github.com/pollend/community-crossword/tree/main&refcode=32d44e634533)


A multiplayer game that is played on one large crossword board.

## Server Configuration

The Zig backend server can be configured using environment variables. Here are all available options:

### Core Server Settings

| Environment Variable | Default Value | Description |
|---------------------|---------------|-------------|
| `PORT` | `3010` | Port number for the HTTP/WebSocket server |
| `THREADS` | `1` | Number of worker threads for the server |
| `DOMAIN` | `localhost` | Domain name for cookie and CORS settings |
| `ALLOW_ORIGINS` | `http://localhost:8080` | Comma-separated list of allowed origins for CORS |
| `SESSION_KEY` | `bad_hash` | Secret key for session cookie encryption (⚠️ **Change in production!**) |
| `CROSSWORD_LOAD` | `crossword` | S3 key/filename for the crossword map to load |


### other datasets 
- https://huggingface.co/datasets/albertxu/CrosswordQA
