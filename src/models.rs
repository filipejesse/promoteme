use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct SearchResult {
    pub title: String,
    pub url: String,
    pub repo: String,
    pub created_at: String,
    pub state: String,
    #[serde(default)]
    #[allow(dead_code)]
    pub author: String,
}

pub struct MemberStats {
    pub username: String,
    pub prs_merged: u32,
    pub prs_open: u32,
    pub total_additions: i64,
    pub total_deletions: i64,
    pub reviews_given: u32,
    pub prs_with_tests: u32,
    pub small_prs: u32,
    pub large_prs: u32,
    pub score: i64,
}

#[derive(Debug, Deserialize)]
pub struct PrDetails {
    #[allow(dead_code)]
    pub body: Option<String>,
    pub files: Vec<PrFile>,
    pub additions: i64,
    pub deletions: i64,
}

#[derive(Debug, Deserialize)]
pub struct PrFile {
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct ProcessedPr {
    pub title: String,
    pub url: String,
    pub repo: String,
    pub created_at: String,
    pub state: String,
    pub additions: i64,
    pub deletions: i64,
    pub total_changes: i64,
    pub risk: String,
    pub action: String,
    pub test_files: Vec<String>,
}

impl ProcessedPr {
    pub fn to_markdown(&self) -> String {
        let tests_text = if self.test_files.is_empty() {
            "No explicit test files detected.".to_string()
        } else {
            let files: String = self.test_files.iter().take(3).cloned().collect::<Vec<_>>().join(" ");
            format!("Verified. (Found: {}...)", files)
        };

        format!(
            "- **Scope:** {}\n- **Impact:** {} lines changed (+{} / -{}).\n- **Risk:** {}\n- **Action:** {}\n- **Tests:** {}\n  ([View PR]({}))\n",
            self.title,
            self.total_changes,
            self.additions,
            self.deletions,
            self.risk,
            self.action,
            tests_text,
            self.url
        )
    }
}
