// ./src/web/easis.rs
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse, Redirect},
    routing::{get, post},
    Form, Router,
};
use axum_login::AuthUser;
use axum_messages::{Message, Messages};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use sqlx::SqlitePool;
use time::OffsetDateTime;

use crate::users::AuthSession;



// Form struct
#[derive(Deserialize)]
struct CorrectionTesterForm {
    xml_input: String,
}

// Template struct
#[derive(Template)]
#[template(path = "correction_tester.html")]
struct CorrectionTesterTemplate {
    xml_input: String,
    formatted_output: String,
    has_output: bool,
}


// Models for database entities
#[derive(Clone, Debug, Serialize, sqlx::FromRow)]
struct EssayPrompt {
    id: i64,
    topic: String,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
struct EssaySubmission {
    id: i64,
    user_id: i64,
    prompt_id: i64,
    original_text: String,
    corrected_text: Option<String>,
    annotated_text: Option<String>, // Add this line
    score: Option<i64>,
    error_count: Option<i64>,
    submitted_at: OffsetDateTime,
}

#[derive(Debug, Serialize)]
struct SubmissionWithPrompt {
    id: i64,
    user_id: i64,
    prompt_id: i64,
    topic: String,
    original_text: String,
    corrected_text: Option<String>,
    annotated_text: Option<String>, // Add this line
    score: Option<i64>,
    error_count: Option<i64>,
    submitted_at: String,
}

// Templates
#[derive(Template)]
#[template(path = "easis.html")]
struct EasisTemplate {
    messages: Vec<Message>,
    prompt: EssayPrompt,
}

#[derive(Template)]
#[template(path = "easis_history.html")]
struct EasisHistoryTemplate {
    submissions: Vec<SubmissionWithPrompt>,
}

#[derive(Template)]
#[template(path = "easis_view.html")]
struct EasisViewTemplate {
    submission: SubmissionWithPrompt,
}

use crate::filters;

// Form for submission
#[derive(Deserialize)]
struct EssaySubmitForm {
    prompt_id: i64,
    essay: String,
    time_spent: u32,
}

pub fn router() -> Router<SqlitePool> {
    Router::new()
        .route("/easis", get(self::get::writing_page))
        .route("/easis/submit", post(self::post::submit_essay))
        .route("/easis/history", get(self::get::history))
        .route("/easis/view/{id}", get(self::get::view_submission))
        .route(
            "/tools/correction-tester",
            get(self::get::correction_tester),
        )
        .route(
            "/tools/correction-tester",
            post(self::post::process_corrections),
        )
}

mod get {
    use super::*;
    use rand::rng;
    use rand::seq::IndexedRandom; // Add this import correctly // Import thread_rng directly

// In your get module
pub async fn correction_tester() -> impl IntoResponse {
    Html(
        CorrectionTesterTemplate {
            xml_input: String::new(),
            formatted_output: String::new(),
            has_output: false,
        }
        .render()
        .unwrap_or_else(|_| String::from("Error rendering template")),
    )
    .into_response()
}

    pub async fn writing_page(
        State(db): State<SqlitePool>,
        auth_session: AuthSession,
        messages: Messages,
    ) -> impl IntoResponse {
        // Get the current user
        let user = match auth_session.user {
            Some(user) => user,
            None => return Redirect::to("/login").into_response(),
        };

        // First, get all prompts
        let all_prompts = match sqlx::query_as::<_, EssayPrompt>("SELECT * FROM essay_prompts")
            .fetch_all(&db)
            .await
        {
            Ok(prompts) => prompts,
            Err(_) => {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
        };

        if all_prompts.is_empty() {
            // If no prompts exist at all, create a default one
            let default_prompt = EssayPrompt {
                id: 0,
                topic: "Write about anything that comes to mind".to_string(),
            };

            return Html(
                EasisTemplate {
                    messages: messages.into_iter().collect(),
                    prompt: default_prompt,
                }
                .render()
                .unwrap(),
            )
            .into_response();
        }

        // Get prompts the user has already answered
        let answered_prompts = match sqlx::query(
            r#"
        SELECT
            prompt_id, MAX(submitted_at) as last_submitted
        FROM
            essay_submissions
        WHERE
            user_id = ?
        GROUP BY
            prompt_id
        ORDER BY
            last_submitted ASC
        "#,
        )
        .bind(user.id())
        .fetch_all(&db)
        .await
        {
            Ok(rows) => {
                let mut answered = Vec::new();
                for row in rows {
                    answered.push((
                        row.get::<i64, _>("prompt_id"),
                        row.get::<OffsetDateTime, _>("last_submitted"),
                    ));
                }
                answered
            }
            Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        };

        // Find prompts the user hasn't answered yet
        let answered_ids: Vec<i64> = answered_prompts.iter().map(|(id, _)| *id).collect();
        let unseen_prompts: Vec<&EssayPrompt> = all_prompts
            .iter()
            .filter(|p| !answered_ids.contains(&p.id))
            .collect();

        let prompt = if !unseen_prompts.is_empty() {
            // If there are unseen prompts, randomly select one
            let mut rng = rng();
            match unseen_prompts.choose(&mut rng) {
                Some(prompt) => (*prompt).clone(),
                None => all_prompts[0].clone(), // Fallback (shouldn't happen)
            }
        } else if !answered_prompts.is_empty() {
            // If all prompts have been seen, select the one answered longest ago
            let oldest_prompt_id = answered_prompts[0].0;
            match all_prompts.iter().find(|p| p.id == oldest_prompt_id) {
                Some(prompt) => prompt.clone(),
                None => all_prompts[0].clone(), // Fallback
            }
        } else {
            // Fallback to a random prompt if something went wrong
            let mut rng = rng();
            match all_prompts.choose(&mut rng) {
                Some(prompt) => prompt.clone(),
                None => all_prompts[0].clone(), // Fallback (shouldn't happen)
            }
        };

        Html(
            EasisTemplate {
                messages: messages.into_iter().collect(),
                prompt,
            }
            .render()
            .unwrap(),
        )
        .into_response()
    }

    pub async fn history(
        State(db): State<SqlitePool>,
        auth_session: AuthSession,
    ) -> impl IntoResponse {
        // Get the current user
        let user = match auth_session.user {
            Some(user) => user,
            None => return Redirect::to("/login").into_response(),
        };

        // Get all submissions for this user
        let submissions = match sqlx::query(
            r#"
            SELECT
                s.id, s.user_id, s.prompt_id, s.original_text, s.corrected_text, s.annotated_text,
                s.score, s.error_count, s.submitted_at, p.topic
            FROM
                essay_submissions s
            JOIN
                essay_prompts p ON s.prompt_id = p.id
            WHERE
                s.user_id = ?
            ORDER BY
                s.submitted_at DESC
            "#,
        )
        .bind(user.id())
        .fetch_all(&db)
        .await
        {
            Ok(rows) => {
                let mut submissions = Vec::new();
                for row in rows {
                    let submission = SubmissionWithPrompt {
                        id: row.get("id"),
                        user_id: row.get("user_id"),
                        prompt_id: row.get("prompt_id"),
                        topic: row.get("topic"),
                        original_text: row.get("original_text"),
                        corrected_text: row.get("corrected_text"),
                        annotated_text: row.get("annotated_text"), // Add this line
                        score: row.get("score"),
                        error_count: row.get("error_count"),
                        submitted_at: row
                            .get::<OffsetDateTime, _>("submitted_at")
                            .format(&time::format_description::well_known::Rfc3339)
                            .unwrap(),
                    };
                    submissions.push(submission);
                }
                submissions
            }
            Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        };

        Html(EasisHistoryTemplate { submissions }.render().unwrap()).into_response()
    }

    pub async fn view_submission(
        State(db): State<SqlitePool>,
        auth_session: AuthSession,
        Path(submission_id): Path<i64>,
    ) -> impl IntoResponse {
        // Get the current user
        let user = match auth_session.user {
            Some(user) => user,
            None => return Redirect::to("/login").into_response(),
        };

        // Get the submission
        let submission = match sqlx::query(
            r#"
            SELECT
                s.id, s.user_id, s.prompt_id, s.original_text, s.corrected_text, s.annotated_text,
                s.score, s.error_count, s.submitted_at, p.topic
            FROM
                essay_submissions s
            JOIN
                essay_prompts p ON s.prompt_id = p.id
            WHERE
                s.id = ? AND s.user_id = ?
            "#,
        )
        .bind(submission_id)
        .bind(user.id())
        .fetch_optional(&db)
        .await
        {
            Ok(Some(row)) => SubmissionWithPrompt {
                id: row.get("id"),
                user_id: row.get("user_id"),
                prompt_id: row.get("prompt_id"),
                topic: row.get("topic"),
                original_text: row.get("original_text"),
                corrected_text: row.get("corrected_text"),
                annotated_text: row.get("annotated_text"), // Add this line
                score: row.get("score"),
                error_count: row.get("error_count"),
                submitted_at: row
                    .get::<OffsetDateTime, _>("submitted_at")
                    .format(&time::format_description::well_known::Rfc3339)
                    .unwrap(),
            },
            Ok(None) => return Redirect::to("/easis/history").into_response(),
            Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        };

        Html(EasisViewTemplate { submission }.render().unwrap()).into_response()
    }
}

mod post {
    use super::*;
    use axum_login::tracing::{error, info}; // Import tracing macros
    // In your post module
pub async fn process_corrections(
    Form(form): Form<CorrectionTesterForm>,
) -> impl IntoResponse {
    let xml_input = form.xml_input;

    // Use your existing format_corrections filter directly
    let (formatted_output, has_output) = match crate::filters::format_corrections(&xml_input) {
        Ok(output) => (output, true),
        Err(_) => (String::from("<div class=\"text-red-500\">Error processing XML</div>"), true),
    };

    Html(
        CorrectionTesterTemplate {
            xml_input,
            formatted_output,
            has_output,
        }
        .render()
        .unwrap_or_else(|_| String::from("Error rendering template")),
    )
    .into_response()
}

    pub async fn submit_essay(
        State(db): State<SqlitePool>,
        auth_session: AuthSession,
        messages: Messages,
        Form(form): Form<EssaySubmitForm>,
    ) -> impl IntoResponse {
        // Get the current user
        let user = match auth_session.user {
            Some(user) => user,
            None => return Redirect::to("/login").into_response(),
        };

        info!("Attempting to submit essay for user ID: {}", user.id());

        // Validate the essay
        if form.essay.trim().is_empty() {
            messages.error("Your essay cannot be empty");
            return Redirect::to("/easis").into_response();
        }

        // Save the submission
        let result = sqlx::query(
            r#"
            INSERT INTO essay_submissions
                (user_id, prompt_id, original_text, submitted_at)
            VALUES
                (?, ?, ?, CURRENT_TIMESTAMP)
            "#,
        )
        .bind(user.id())
        .bind(form.prompt_id)
        .bind(&form.essay)
        .execute(&db)
        .await;

        match result {
            Ok(_) => {
                info!("Essay submitted successfully for user {}", user.id()); // Log success
                messages.success("Your essay has been submitted successfully!");
                Redirect::to("/easis/history").into_response()
            }
            Err(e) => {
                error!("Failed to submit essay for user {}: {}", user.id(), e); // Log the error
                messages.error(format!("Failed to submit essay: {}", e));
                Redirect::to("/easis").into_response()
            }
        }
    }
}
