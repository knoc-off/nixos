use chrono::NaiveDateTime;
use regex::Regex;
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

#[derive(Debug, Serialize, Deserialize, Clone, sqlx::FromRow)]
pub struct Analysis {
    pub id: i64,
    pub uuid: String,
    pub original_text: String,
    pub annotated_text: String, // contains inline markup
    pub score: f64,
    #[serde(skip)]
    pub created_at: NaiveDateTime,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NewAnalysis {
    pub uuid: String,
    pub original_text: String,
    pub annotated_text: String,
    pub score: f64,
}

impl NewAnalysis {
    pub async fn save(&self, pool: &SqlitePool) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO text_checks (uuid, original_text, annotated_text, score)
            VALUES (?, ?, ?, ?)
            "#,
        )
        .bind(&self.uuid)
        .bind(&self.original_text)
        .bind(&self.annotated_text)
        .bind(self.score)
        .execute(pool)
        .await?;
        Ok(())
    }
}

impl Analysis {
    /// Converts inline markup into corresponding HTML.
    ///
    /// Markup formats supported:
    /// - Typo markup: <<incorrect|correct>>
    /// - Suggestion markup: {{original|suggestion}}
    /// - Grammar markup: [[error|correction]]
    ///
    /// For example, the annotated text:
    ///   "I saw teh cat"
    /// might become (after conversion):
    ///   "I saw <span class="typo"><span class="original">teh</span><span class="correction">the</span></span> cat"
    pub fn to_html(&self) -> String {
        let mut html = self.annotated_text.clone();
        // Replace typo markup: <<incorrect|correct>>
        let typo_re = Regex::new(r"<<(.*?)\|(.*?)>>").unwrap();
        html = typo_re
            .replace_all(&html, r#"<span class="typo"><span class="original">$1</span><span class="correction">$2</span></span>"#)
            .to_string();
        // Replace suggestion markup: {{original|suggestion}}
        let suggestion_re = Regex::new(r"\{\{(.*?)\|(.*?)\}\}").unwrap();
        html = suggestion_re
            .replace_all(&html, r#"<span class="suggestion">$1<div class="suggestion-popup">$2</div></span>"#)
            .to_string();
        // Replace grammar markup: [[error|correction]]
        let grammar_re = Regex::new(r"\[\[(.*?)\|(.*?)\]\]").unwrap();
        html = grammar_re
            .replace_all(&html, r#"<span class="grammar">$1<span class="grammar-correction">$2</span></span>"#)
            .to_string();
        html
    }
}





