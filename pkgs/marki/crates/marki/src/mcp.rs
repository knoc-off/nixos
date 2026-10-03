//! `marki mcp`: the card-authoring tools over MCP streamable HTTP.
//!
//! The Lua engine is `!Send`, so one worker thread owns the [`Handler`] and
//! every tool call is a closure shipped to it. That also serializes all
//! collection access, which SQLite wants anyway.

use anyhow::Result;
use std::path::PathBuf;
use base64::Engine as _;
use rmcp::handler::server::router::prompt::PromptRouter;
use rmcp::handler::server::router::tool::{ToolRoute, ToolRouter};
use rmcp::handler::server::tool::ToolCallContext;
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

Docs first: marki has built-in features for what cards usually need (cloze, \
maps that highlight countries/regions, images and audio, typeset math and \
diagrams, custom card types). Before writing cards read marki_docs(\"cards\"); \
before using a ```map, ```media or ```typst block read marki_docs(<that \
block>). Use these features instead of hand-written HTML, external images of \
maps, {{c1::}} syntax or other workarounds; if something seems unsupported, \
check the docs before inventing a solution, and ask the user if it still is. \
Blocks bring lookup tools (marki_map_units, marki_map_find, \
marki_media_list...; marki_context lists them per block): look up valid \
region names, OSM refs and media files with them instead of guessing. For a \
map feature no single ref covers (a wall made of many OSM segments, a route, \
a historic border), build it once with marki_map_define and use its geo/<name> \
ref; marki_context lists existing ones under custom_geometry.

Workflow: call marki_context first (models, decks, media dirs, available \
blocks and doc topics). Draft a card, \
check it with marki_preview (pass `source` to preview without saving), then \
marki_write_card (marki_write_cards for more than a few). When done, \
marki_push without confirm simulates and returns \
a plan_hash; show the user the planned changes, and only after they agree \
call marki_push with confirm=true and that plan_hash. Check `ok` and `steps` \
of the result; never report success when a step says error. marki_status \
shows anything still pending.

Deleting: marki_delete_card removes the file; the next push lists the note \
as an orphan and suspends its cards. Only with the user's explicit consent \
pass delete_orphans=true (to both the simulation and the confirm) to delete \
the note and its review history instead. To change a card's deck, \
marki_move_card it; the push moves the note and keeps its reviews. \
`media_orphans: N` counts rendered media files (maps, typst, media blocks) \
no card uses any more; delete_orphans=true also deletes those.

Cards: one .md file = one note; the directory is the deck (a/b/x.md -> a::b), \
or #deck(a::b). `---` splits front from back. Tags are #words anywhere; \
#cloze with **bold**/*italic* answers makes cloze cards (never write {{c1::}}); \
#model(name) uses a custom model. Never invent #id(...): new cards get one on \
write; when editing, keep the existing #id and pass it as expected_id.

Good cards test one fact, have a short unambiguous front, and put context on \
the back. Prefer several small cards over one big one.

Media: marki_add_media saves a file, then reference it in a ```media block \
(marki_docs(\"media\")). Maps: a ```map block renders the map itself \
(marki_docs(\"map\")); never download a map image. marki_preview returns a \
PNG of each map, and marki_map_render renders a bare map block: look at them \
to check the frame, gaps and overlaps. Math: $inline$ and \
$$display$$.

Models: read marki_docs(\"models\") before writing one; \
marki_read_model(\"basic\"|\"cloze\") shows the built-ins as Lua examples. \
M.card_names lists card types; generate(note, ctx) returns keys \
<Card>Front / <Card>Back only (other keys are an error); render output with \
ctx:section_html(note, n), not block:html(), or media blocks show as text. \
Renaming or dropping a card type loses review history unless M.renames maps \
old->new; dropping needs M.allow_card_removal and the user's consent.

marki_query runs read-only SQL on a snapshot of the collection (tables \
notes, cards, revlog, decks, notetypes); select n.guid to get each card's \
file path. Flags (cards.flags & 7: 1 red .. 7 purple) usually mean 'fix this \
card': select distinct n.guid from cards c join notes n on n.id=c.nid where \
c.flags & 7 = 1. A push that changes a flagged note clears its flags \
(`unflag` in the change detail).";

type Job = Box<dyn FnOnce(&mut Handler) + Send>;
pub type Reload = Box<dyn Fn() -> Result<Config> + Send>;

#[derive(Clone)]
pub struct Marki {
    jobs: mpsc::Sender<Job>,
    tool_router: ToolRouter<Self>,
    prompt_router: PromptRouter<Self>,
}

impl Marki {
    /// Start the worker thread that owns the project. Before each job it
    /// reloads the project if `config_path` changed on disk, so edits to
    /// `.marki/config.toml` apply without a restart. A config that no longer
    /// parses keeps the old project and fails that job with the error.
    pub fn spawn(cfg: Config, config_path: Option<PathBuf>, reload: Reload) -> Self {
        // Block modules' lookup tools, fixed at startup: a client caches the
        // tool list, so enabling a module (e.g. typst_binary) needs a restart.
        let block_tools = crate::project::build_registry(&cfg).tools();
        let (tx, rx) = mpsc::channel::<Job>();
        std::thread::spawn(move || {
            let mtime = || config_path.as_ref().and_then(|p| std::fs::metadata(p).and_then(|m| m.modified()).ok());
            let mut seen = mtime();
            let mut h = Handler::new(Project::new(cfg));
            for job in rx {
                let now = mtime();
                if now != seen {
                    match reload() {
                        Ok(cfg) => {
                            tracing::info!("config changed; reloaded");
                            h = Handler::new(Project::new(cfg));
                            seen = now;
                        }
                        Err(e) => {
                            let e = format!("{e:#}");
                            tracing::warn!("config reload failed: {e}");
                            h.config_error = Some(e);
                        }
                    }
                }
                job(&mut h);
            }
        });
        let mut tool_router = Self::tool_router();
        for (lang, t) in block_tools {
            let schema = match t.schema {
                serde_json::Value::Object(o) => o,
                _ => Default::default(),
            };
            let attr = rmcp::model::Tool::new(format!("marki_{lang}_{}", t.name), t.description, schema);
            tool_router.add_route(ToolRoute::new_dyn(attr, move |c: ToolCallContext<'_, Self>| {
                let args = serde_json::Value::Object(c.arguments.clone().unwrap_or_default());
                let service = c.service.clone();
                Box::pin(async move {
                    service.tool(move |h| h.block_tool(lang, t.name, args)).await.map(Into::into)
                })
            }));
        }
        Self { jobs: tx, tool_router, prompt_router: Self::prompt_router() }
    }

    async fn run<R: Send + 'static>(
        &self,
        f: impl FnOnce(&mut Handler) -> Result<R> + Send + 'static,
    ) -> Result<R, String> {
        let (tx, rx) = oneshot::channel();
        self.jobs
            .send(Box::new(move |h| {
                if let Some(e) = &h.config_error {
                    let _ = tx.send(Err(format!(".marki/config.toml no longer loads, fix it first: {e}")));
                    return;
                }
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
    /// Attach PNG snapshots of maps/typst figures (default true).
    pub images: Option<bool>,
}

/// JSON text first, then one label + image pair per PNG.
fn with_pngs(json: &serde_json::Value, pngs: Vec<(String, Vec<u8>)>) -> Vec<ContentBlock> {
    let b64 = base64::engine::general_purpose::STANDARD;
    let mut out = vec![ContentBlock::text(serde_json::to_string_pretty(json).unwrap_or_default())];
    for (label, png) in pngs {
        out.push(ContentBlock::text(label));
        out.push(ContentBlock::image(b64.encode(png), "image/png"));
    }
    out
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
pub struct WriteCardsArgs {
    /// Up to 500 cards; each like marki_write_card's arguments.
    pub cards: Vec<WriteCardArgs>,
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
    /// Delete notes whose card file is gone (with their review history)
    /// instead of suspending them, and rendered media files no card uses
    /// (`media_orphans`). Must match between simulate and confirm.
    #[serde(default)]
    pub delete_orphans: bool,
    /// List every change line, including one per media file. Default: counts
    /// (`summary`, `by_dir`) and at most 50 non-media lines.
    #[serde(default)]
    pub detail: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct StatusArgs {
    /// As for marki_push.
    #[serde(default)]
    pub detail: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct DeleteCardArgs {
    pub path: String,
    /// The card's current #id, as a guard against deleting the wrong file.
    pub expected_id: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct MoveCardArgs {
    pub path: String,
    /// New path; its directory becomes the deck (created if missing).
    pub new_path: String,
    /// The card's current #id.
    pub expected_id: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct QueryArgs {
    /// One read-only SQLite statement. Max 200 rows returned.
    pub sql: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct DocsArgs {
    /// cards | map | media | typst | models
    pub topic: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct MapRenderArgs {
    /// The map block's TOML, without the ```map fences.
    pub source: String,
    /// Optional card path whose [map.rules] defaults should apply.
    pub path: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct MakeCardsArgs {
    /// What to make cards about.
    pub topic: String,
}

#[tool_router]
impl Marki {
    #[tool(description = "Overview: models (with card types and descriptions), decks with card counts, media dirs, the special blocks this server renders and the doc topics. Call first.")]
    async fn marki_context(&self, _: Parameters<Empty>) -> Result<CallToolResult, McpError> {
        self.tool(|h| h.context()).await
    }

    #[tool(description = "Authoring reference. Topics: cards (file format, tags, cloze, decks, code blocks, math), map (```map blocks: highlight countries/regions/OSM features), media (```media images/audio), typst (```typst diagrams/formulas), models (Lua card types). Read `cards` before writing cards and the block's topic before using a block; prefer these built-in features over inventing HTML or workarounds.")]
    async fn marki_docs(&self, Parameters(a): Parameters<DocsArgs>) -> Result<CallToolResult, McpError> {
        // Plain markdown, not JSON.
        Ok(match self.run(move |h| crate::docs::doc(&h.project.registry, &a.topic)).await {
            Ok(t) => CallToolResult::success(vec![ContentBlock::text(t)]),
            Err(e) => CallToolResult::error(vec![ContentBlock::text(e)]),
        })
    }

    #[tool(description = "Render a ```map block's TOML (without the fences, no card needed) to PNGs of its front (reveal layers hidden) and back (all layers), max 512 px. Use it to iterate on a map's frame, styling and geometry. `path` (a card path) only selects which [map.rules] defaults apply.")]
    async fn marki_map_render(&self, Parameters(a): Parameters<MapRenderArgs>) -> Result<CallToolResult, McpError> {
        let r = self.run(move |h| h.map_render(&a.source, a.path.as_deref())).await;
        Ok(match r {
            Ok(pngs) => CallToolResult::success(with_pngs(&serde_json::json!({"images": pngs.iter().map(|(l, _)| l).collect::<Vec<_>>()}), pngs)),
            Err(e) => CallToolResult::error(vec![ContentBlock::text(e)]),
        })
    }

    #[tool(description = "Search card files by path or content.")]
    async fn marki_search_cards(&self, Parameters(a): Parameters<SearchArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.search_cards(&a.query, a.limit.unwrap_or(50))).await
    }

    #[tool(description = "Read a card's markdown source.")]
    async fn marki_read_card(&self, Parameters(a): Parameters<PathArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.read_card(&a.path)).await
    }

    #[tool(description = "Render a card (saved or draft source, optionally with a draft model) to the HTML of every card front/back it generates, plus render errors, plus a PNG (max 512 px) of each map/typst figure per card side so you can check what it looks like (`images` lists their labels; images=false skips them). Writes nothing.")]
    async fn marki_preview(&self, Parameters(a): Parameters<PreviewArgs>) -> Result<CallToolResult, McpError> {
        let images = a.images.unwrap_or(true);
        let r = self
            .run(move |h| {
                h.preview(&a.path, a.source.as_deref(), a.model_lua.as_deref(), a.model_css.as_deref(), images)
            })
            .await;
        Ok(match r {
            Ok((json, pngs)) => CallToolResult::success(with_pngs(&json, pngs)),
            Err(e) => CallToolResult::error(vec![ContentBlock::text(e)]),
        })
    }

    #[tool(description = "Format, validate and save a card file. New cards get an #id; overwriting needs expected_id. Does not push.")]
    async fn marki_write_card(&self, Parameters(a): Parameters<WriteCardArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.write_card(&a.path, &a.source, a.expected_id.as_deref())).await
    }

    #[tool(description = "Write many cards at once (e.g. a whole deck from one model): every card is formatted and checked like marki_write_card, then all are written, or none if any fails (the error lists each failing card). Does not push.")]
    async fn marki_write_cards(&self, Parameters(a): Parameters<WriteCardsArgs>) -> Result<CallToolResult, McpError> {
        let cards: Vec<_> = a.cards.into_iter().map(|c| (c.path, c.source, c.expected_id)).collect();
        self.tool(move |h| h.write_cards(&cards)).await
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

    #[tool(description = "Read a custom model's Lua and CSS, with per-card-type card and review counts from the collection.")]
    async fn marki_read_model(&self, Parameters(a): Parameters<ModelArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.read_model(&a.name)).await
    }

    #[tool(description = "Validate (compiles, has describe(), renders every note using it) and save a custom model. Follow with marki_push to see the effect on the collection.")]
    async fn marki_write_model(&self, Parameters(a): Parameters<WriteModelArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.write_model(&a.name, &a.lua, a.css.as_deref())).await
    }

    #[tool(description = "Everything that is out of sync, read-only and fast: pending model/note/media changes, cards that fail to render (errors), and card files not yet committed (uncommitted). ok=true only when all agree. Does not pause the sync server.")]
    async fn marki_status(&self, Parameters(a): Parameters<StatusArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| Ok(h.status()?.compact(a.detail))).await
    }

    #[tool(description = "Without confirm: simulate the push on copies of the collection and media db, check what the real push needs (server pause, media dir, git), and return a summary (counts per kind and per deck dir), changes, problems and plan_hash. With confirm=true and that plan_hash (after the user agreed): pause the sync server, write media then the collection (stopping at the first failure), restart the server and commit the repo; `steps` reports each part. After a failed step, fix it and push again: pushes are idempotent. detail=true lists every change incl. media files.")]
    async fn marki_push(&self, Parameters(a): Parameters<PushArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| Ok(h.push(a.confirm, a.plan_hash.as_deref(), a.delete_orphans)?.compact(a.detail))).await
    }

    #[tool(description = "Delete a card file (needs its current #id). Does not push: the next marki_push suspends the note's cards in Anki (tagged marki::orphan), or deletes the note and its review history with delete_orphans=true -- ask the user which.")]
    async fn marki_delete_card(&self, Parameters(a): Parameters<DeleteCardArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.delete_card(&a.path, &a.expected_id)).await
    }

    #[tool(description = "Move/rename a card file (needs its current #id). The directory is the deck, so this changes deck; the next marki_push moves the note and keeps its review history. Returns render_errors if relative media broke.")]
    async fn marki_move_card(&self, Parameters(a): Parameters<MoveCardArgs>) -> Result<CallToolResult, McpError> {
        self.tool(move |h| h.move_card(&a.path, &a.new_path, &a.expected_id)).await
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
                 1. Call marki_context and marki_search_cards to see existing decks, models, \
                 blocks and overlapping cards, and read marki_docs(\"cards\").\n\
                 2. Propose a short list of cards (one fact each, deck = directory) and wait for my OK. \
                 If a card would benefit from a map, image, audio or diagram, read that block's \
                 marki_docs topic and use the block.\n\
                 3. For each: marki_preview with the draft source, fix any errors, then marki_write_card.\n\
                 4. marki_push (simulate), show me the plan, and push with confirm only after I agree.",
                a.topic
            ),
        )])
        .with_description("Card-making workflow")
    }
}

// The routers are fields, not rebuilt per request (the macro default), so
// the block modules' tools added in `spawn` are listed and callable.
#[tool_handler(router = self.tool_router)]
#[prompt_handler(router = self.prompt_router)]
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
                Ok((cards, ctx, crate::docs::topics(&h.project.registry)))
            })
            .await
            .map_err(|e| McpError::internal_error(e, None))?;
        let (cards, ctx, topics) = listed;
        let mut resources: Vec<_> = topics
            .into_iter()
            .map(|(t, what)| {
                Resource::new(format!("marki://docs/{t}"), format!("docs: {what}")).with_mime_type("text/markdown")
            })
            .collect();
        resources.extend(cards
            .into_iter()
            .map(|c| {
                Resource::new(format!("marki://card/{}", c.path), c.path)
                    .with_mime_type("text/markdown")
            }));
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
                if let Some(t) = uri.strip_prefix("marki://docs/") {
                    crate::docs::doc(&h.project.registry, t)
                } else if let Some(p) = uri.strip_prefix("marki://card/") {
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
pub fn serve(cfg: Config, config_path: Option<PathBuf>, reload: Reload, listen: &str) -> Result<()> {
    let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build()?;
    rt.block_on(async move {
        let marki = Marki::spawn(cfg, config_path, reload);
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
