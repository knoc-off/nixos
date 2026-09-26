//! `marki mcp`: the card-authoring tools over MCP streamable HTTP.
//!
//! The Lua engine is `!Send`, so one worker thread owns the [`Handler`] and
//! every tool call is a closure shipped to it. That also serializes all
//! collection access, which SQLite wants anyway.

use anyhow::Result;
use base64::Engine as _;
use rmcp::handler::server::router::prompt::PromptRouter;
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{
    CallToolResult, ContentBlock, GetPromptResult, ListResourcesResult, PaginatedRequestParams,
    PromptMessage, ReadResourceRequestParams, ReadResourceResult, Resource, ResourceContents,
    Role, ServerCapabilities, ServerConfig,
};
use rmcp::service::RequestContext;
use rmcp::transport::streamable_http_server::session::local::LocalSessionManager;
use rmcp::transport::streamable_http_server::{StreamableHttpServerConfig, StreamableHttpService};
use rmcp::{ErrorData as McpError, RoleServer, ServerHandler, prompt, prompt_handler, prompt_router, tool, tool_handler, tool_router};
use schemars::JsonSchema;
use serde::Deserialize;
use std::sync::mpsc;
use tokio::sync::oneshot;

use crate::config::Config;
use crate::mcp_tools::Handler;
use crate::project::Project;

const INSTRUCTIONS: &str = "\
marki keeps Anki flashcards as markdown files in a git repo and pushes them \
into the user's Anki collection.

Workflow: call marki_context first (models, decks, media dirs). Draft a card, \
check it with marki_preview (pass `source` to preview without saving), then \
marki_write_card. When done, marki_push without confirm simulates and returns \
a plan_hash; show the user the planned changes, and only after they agree \
call marki_push with confirm=true and that plan_hash. Check `ok` and `steps` \
of the result; never report success when a step says error. marki_status \
shows anything still pending.

Cards: one .md file = one note; the directory is the deck (a/b/x.md -> a::b), \
or #deck(a::b). `---` splits front from back. Tags are #words anywhere; \
#cloze with **bold**/*italic* answers makes cloze cards (never write {{c1::}}); \
#model(name) uses a custom model. Never invent #id(...): new cards get one on \
write; when editing, keep the existing #id and pass it as expected_id.

Good cards test one fact, have a short unambiguous front, and put context on \
the back. Prefer several small cards over one big one.

Media: marki_add_media saves a file, then reference it in a ```media block \
(`src = \"dir/name\"`). Models: marki_read_model / marki_write_model \
(Lua; must define card_names, generate, describe). Renaming or dropping a \
card type loses review history unless M.renames maps old->new; dropping needs \
M.allow_card_removal and the user's consent.

marki_flagged finds cards the user flagged in Anki (1 red .. 7 purple), \
usually meaning 'fix this card'. marki_query runs read-only SQL on a snapshot \
of the collection (tables notes, cards, revlog, decks, notetypes).";

type Job = Box<dyn FnOnce(&mut Handler) + Send>;

#[derive(Clone)]
pub struct Marki {
    jobs: mpsc::Sender<Job>,
    tool_router: ToolRouter<Self>,
    prompt_router: PromptRouter<Self>,
}

impl Marki {
    /// Start the worker thread that owns the project.
    pub fn spawn(cfg: Config) -> Self {
        let (tx, rx) = mpsc::channel::<Job>();
        std::thread::spawn(move || {
            let mut h = Handler::new(Project::new(cfg));
            for job in rx {
                job(&mut h);
            }
        });
        Self { jobs: tx, tool_router: Self::tool_router(), prompt_router: Self::prompt_router() }
    }

    async fn run<R: Send + 'static>(
        &self,
        f: impl FnOnce(&mut Handler) -> Result<R> + Send + 'static,
    ) -> Result<R, String> {
        let (tx, rx) = oneshot::channel();
        self.jobs
            .send(Box::new(move |h| {
                // A panicking tool must not take the worker down with it.
                let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| f(h)));
                let _ = tx.send(match r {
                    Ok(r) => r.map_err(|e| format!("{e:#}")),
                    Err(_) => Err("internal error (panic); see server log".into()),
                });
            }))
            .map_err(|_| "worker stopped".to_string())?;
        rx.await.map_err(|_| "worker dropped the request".to_string())?
    }

    /// Run a tool and render its result as JSON text (or a tool error, which
    /// the model sees and can react to, rather than a protocol error).
    async fn tool<R: serde::Serialize + Send + 'static>(
        &self,
        f: impl FnOnce(&mut Handler) -> Result<R> + Send + 'static,
    ) -> Result<CallToolResult, McpError> {
        Ok(match self.run(f).await {
            Ok(v) => CallToolResult::success(vec![ContentBlock::text(
                serde_json::to_string_pretty(&v).unwrap_or_default(),
            )]),
            Err(e) => CallToolResult::error(vec![ContentBlock::text(e)]),
        })
    }
}

#[derive(Deserialize, JsonSchema)]
pub struct Empty {}

#[derive(Deserialize, JsonSchema)]
pub struct SearchArgs {
    /// Case-insensitive substring of path or content; empty lists all.
    #[serde(default)]
    pub query: String,
    /// Max results (default 50).
    pub limit: Option<usize>,
}

#[derive(Deserialize, JsonSchema)]
pub struct PathArgs {
    /// Card path relative to the repo root, e.g. `geography/europe/france.md`.
    pub path: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct PreviewArgs {
    /// Card path (decides the deck, and where relative media resolve).
    pub path: String,
    /// Unsaved card markdown; omit to preview the saved file.
    pub source: Option<String>,
    /// Draft Lua for the card's model, previewed without saving.
    pub model_lua: Option<String>,
    /// Draft CSS for the card's model.
    pub model_css: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct WriteCardArgs {
    pub path: String,
    /// Full card markdown. Formatted on write (tags moved to the last line).
    pub source: String,
    /// Required to overwrite an existing card: its current #id.
    pub expected_id: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct MediaArgs {
    /// Directory under .marki/media/, e.g. `flags` or `diagrams/cell`.
    pub dir: String,
    /// File name with extension (svg png webp jpg gif mp3 ogg m4a wav).
    pub name: String,
    /// http(s) URL to download.
    pub url: Option<String>,
    /// Or the file content, base64.
    pub base64: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct FindArgs {
    /// A card id, media name, tag or any literal text.
    pub needle: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct ModelArgs {
    pub name: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct WriteModelArgs {
    pub name: String,
    pub lua: String,
    pub css: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct PushArgs {
    /// false/omitted: simulate only. true: apply (needs plan_hash).
    #[serde(default)]
    pub confirm: bool,
    pub plan_hash: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct FlagArgs {
    /// 1 red, 2 orange, 3 green, 4 blue, 5 pink, 6 turquoise, 7 purple.
    pub flag: u8,
}

#[derive(Deserialize, JsonSchema)]
pub struct QueryArgs {
    /// One read-only SQLite statement. Max 200 rows returned.
    pub sql: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct MakeCardsArgs {
    /// What to make cards about.
    pub topic: String,
}

#[tool_router]
impl Marki {
    #[tool(description = "Overview: models (with card types and descriptions), decks with card counts, media dirs. Call first.")]
    async fn marki_context(&self, _: Parameters<Empty>) -> Result<CallToolResult, McpError> {
        self.tool(|h| h.context()).await
    }

    #[tool(description = "Search card files by path or content.")]
    async fn marki_search_cards(&self, Parameters(a): Parameters<SearchArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.search_cards(&a.query, a.limit.unwrap_or(50))).await
    }

    #[tool(description = "Read a card's markdown source.")]
    async fn marki_read_card(&self, Parameters(a): Parameters<PathArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.read_card(&a.path)).await
    }

    #[tool(description = "Render a card (saved or draft source, optionally with a draft model) to the HTML of every card front/back it generates, plus render errors. Writes nothing.")]
    async fn marki_preview(&self, Parameters(a): Parameters<PreviewArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| {
            h.preview(&a.path, a.source.as_deref(), a.model_lua.as_deref(), a.model_css.as_deref())
        })
        .await
    }

    #[tool(description = "Format, validate and save a card file. New cards get an #id; overwriting needs expected_id. Does not push.")]
    async fn marki_write_card(&self, Parameters(a): Parameters<WriteCardArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.write_card(&a.path, &a.source, a.expected_id.as_deref())).await
    }

    #[tool(description = "Save a media file (from a URL or base64) under .marki/media/<dir>/. Returns the `src` line for a ```media block.")]
    async fn marki_add_media(&self, Parameters(a): Parameters<MediaArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| {
            let bytes = match (a.url, a.base64) {
                (Some(url), None) => {
                    anyhow::ensure!(url.starts_with("https://") || url.starts_with("http://"), "url must be http(s)");
                    let resp = reqwest::blocking::Client::builder()
                        .timeout(std::time::Duration::from_secs(30))
                        .build()?
                        .get(&url)
                        .send()?
                        .error_for_status()?;
                    resp.bytes()?.to_vec()
                }
                (None, Some(b)) => base64::engine::general_purpose::STANDARD.decode(b.trim())?,
                _ => anyhow::bail!("pass exactly one of url or base64"),
            };
            h.add_media(&a.dir, &a.name, &bytes)
        })
        .await
    }

    #[tool(description = "Card files containing a literal (card id, media name, tag...).")]
    async fn marki_find(&self, Parameters(a): Parameters<FindArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.find(&a.needle)).await
    }

    #[tool(description = "Read a custom model's Lua and CSS, with per-card-type card and review counts from the collection.")]
    async fn marki_read_model(&self, Parameters(a): Parameters<ModelArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.read_model(&a.name)).await
    }

    #[tool(description = "Validate (compiles, has describe(), renders every note using it) and save a custom model. Follow with marki_push to see the effect on the collection.")]
    async fn marki_write_model(&self, Parameters(a): Parameters<WriteModelArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.write_model(&a.name, &a.lua, a.css.as_deref())).await
    }

    #[tool(description = "Everything that is out of sync, read-only and fast: pending model/note/media changes, cards that fail to render (errors), and card files not yet committed (uncommitted). ok=true only when all agree. Does not pause the sync server.")]
    async fn marki_status(&self, _: Parameters<Empty>) -> Result<CallToolResult, McpError> {
        self.tool(|h| h.status()).await
    }

    #[tool(description = "Without confirm: simulate the push on copies of the collection and media db, check what the real push needs (server pause, media dir, git), and return changes, problems and plan_hash. With confirm=true and that plan_hash (after the user agreed): pause the sync server, write media then the collection (stopping at the first failure), restart the server and commit the repo; `steps` reports each part. After a failed step, fix it and push again: pushes are idempotent.")]
    async fn marki_push(&self, Parameters(a): Parameters<PushArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.push(a.confirm, a.plan_hash.as_deref())).await
    }

    #[tool(description = "Card files whose Anki cards carry a flag (1 red .. 7 purple).")]
    async fn marki_flagged(&self, Parameters(a): Parameters<FlagArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.flagged(a.flag)).await
    }

    #[tool(description = "Read-only SQL on a snapshot of the Anki collection. A `guid` column gets a `path` column with the card file.")]
    async fn marki_query(&self, Parameters(a): Parameters<QueryArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.query(&a.sql)).await
    }
}

#[prompt_router]
impl Marki {
    #[prompt(name = "make-cards", description = "Create well-formed flashcards about a topic.")]
    async fn make_cards(&self, Parameters(a): Parameters<MakeCardsArgs>) -> GetPromptResult {
        GetPromptResult::new(vec![PromptMessage::new_text(
            Role::User,
            format!(
                "Make Anki flashcards about: {}\n\n\
                 1. Call marki_context and marki_search_cards to see existing decks, models and \
                 overlapping cards.\n\
                 2. Propose a short list of cards (one fact each, deck = directory) and wait for my OK.\n\
                 3. For each: marki_preview with the draft source, fix any errors, then marki_write_card.\n\
                 4. marki_push (simulate), show me the plan, and push with confirm only after I agree.",
                a.topic
            ),
        )])
        .with_description("Card-making workflow")
    }
}

#[tool_handler]
#[prompt_handler]
impl ServerHandler for Marki {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(
            ServerCapabilities::builder().enable_tools().enable_resources().enable_prompts().build(),
        )
        .with_instructions(INSTRUCTIONS)
    }

    async fn list_resources(
        &self,
        _: Option<PaginatedRequestParams>,
        _: RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, McpError> {
        let listed = self
            .run(|h| {
                let cards = h.search_cards("", usize::MAX)?;
                let ctx = h.context()?;
                Ok((cards, ctx))
            })
            .await
            .map_err(|e| McpError::internal_error(e, None))?;
        let (cards, ctx) = listed;
        let mut resources: Vec<Resource> = cards
            .into_iter()
            .map(|c| {
                Resource::new(format!("marki://card/{}", c.path), c.path)
                    .with_mime_type("text/markdown")
            })
            .collect();
        for m in ctx["models"].as_array().into_iter().flatten() {
            if m.get("builtin").is_none() {
                let name = m["name"].as_str().unwrap_or_default();
                resources.push(
                    Resource::new(format!("marki://model/{name}"), format!("model {name}"))
                        .with_mime_type("text/x-lua"),
                );
            }
        }
        Ok(ListResourcesResult { resources, ..Default::default() })
    }

    async fn read_resource(
        &self,
        req: ReadResourceRequestParams,
        _: RequestContext<RoleServer>,
    ) -> Result<rmcp::model::ReadResourceResponse, McpError> {
        let uri = req.uri.clone();
        let text = self
            .run(move |h| {
                if let Some(p) = uri.strip_prefix("marki://card/") {
                    h.read_card(p)
                } else if let Some(n) = uri.strip_prefix("marki://model/") {
                    Ok(h.read_model(n)?["lua"].as_str().unwrap_or_default().to_string())
                } else {
                    anyhow::bail!("unknown resource {uri}")
                }
            })
            .await
            .map_err(|e| McpError::resource_not_found(e, None))?;
        Ok(ReadResourceResult::new(vec![ResourceContents::text(text, req.uri)]).into())
    }
}

/// Serve on `listen` (e.g. `127.0.0.1:3047`) at `/mcp`. rmcp only accepts
/// loopback `Host` headers, which is what an auth proxy on the same host
/// sends (it rewrites Host to its backend URL).
pub fn serve(cfg: Config, listen: &str) -> Result<()> {
    let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build()?;
    rt.block_on(async move {
        let marki = Marki::spawn(cfg);
        let config = StreamableHttpServerConfig::default();
        let service: StreamableHttpService<Marki, LocalSessionManager> =
            StreamableHttpService::new(move || Ok(marki.clone()), Default::default(), config);
        let app = axum::Router::new().nest_service("/mcp", service);
        let listener = tokio::net::TcpListener::bind(listen).await?;
        tracing::info!("marki mcp listening on http://{listen}/mcp");
        axum::serve(listener, app)
            .with_graceful_shutdown(async {
                let _ = tokio::signal::ctrl_c().await;
            })
            .await?;
        Ok(())
    })
}
