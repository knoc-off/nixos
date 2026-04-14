# Golden test fixtures

This directory holds captured request/response payloads for golden tests.

## Naming convention

```
<client>_<scenario>_<direction>.json
```

Examples:
- `claude-code_basic_request.json` — a basic request from Claude Code
- `claude-code_basic_translated.json` — the same request after forward translation
- `claude-code_tool_use_response.json` — an upstream response with tool_use
- `claude-code_tool_use_client.json` — the same response after reverse translation

## Adding fixtures

1. Enable `--dump-requests` on the proxy to capture live requests.
2. Copy the dumped files here and rename to match the convention.
3. Create the expected translated version manually or by running the
   translation functions in a test.
4. Add a test in the relevant `apply_*.rs` file that loads both files
   and asserts equality.

## SSE fixtures

SSE fixtures use `.sse` extension with standard SSE framing:

```
event: message_start
data: {"type":"message_start","message":{...}}

event: content_block_start
data: {"type":"content_block_start","index":0,...}

```
