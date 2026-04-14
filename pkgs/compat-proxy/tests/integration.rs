//! Integration tests: mock upstream + real proxy, end-to-end.
//!
//! These tests spin up a mock upstream server, configure the proxy
//! to point at it, and verify end-to-end request/response translation.

// TODO: Implement integration tests once the core is verified.
//
// Test plan:
// 1. Start a mock Axum server that captures requests and returns
//    canned responses (both JSON and SSE).
// 2. Start the compat-proxy pointing at the mock upstream.
// 3. Send requests in the client format.
// 4. Assert the mock received canonically-formatted requests.
// 5. Assert the proxy returned client-formatted responses.
//
// Key scenarios:
// - Basic tool rename round-trip (JSON response)
// - Tool drop (tool removed from request, no tool_use in response)
// - System prompt replacement
// - SSE streaming with tool_use blocks (reverse rename)
// - SSE with thinking blocks (passthrough)
// - Property rename in tool_use.input (both directions)
// - Unmapped tool with error policy → 400
// - Missing credentials → 503
// - Upstream error → forwarded status code

#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn test_placeholder() {
        // Placeholder — verifies the test harness runs
        assert!(true);
    }
}
