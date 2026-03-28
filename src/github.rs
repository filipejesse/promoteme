use anyhow::{bail, Context, Result};
use std::process::Command;

use crate::models::{PrDetails, SearchResult};

/// Check if gh CLI is installed
pub fn check_gh_installed() -> Result<()> {
    let output = Command::new("which").arg("gh").output()?;

    if !output.status.success() {
        bail!("GitHub CLI ('gh') is not installed.");
    }
    Ok(())
}

/// Check if user is authenticated with gh
pub fn check_gh_auth() -> Result<()> {
    let status = Command::new("gh")
        .args(["auth", "status"])
        .output()?
        .status;

    if !status.success() {
        bail!("You are not logged into GitHub CLI. Run 'gh auth login' first.");
    }
    Ok(())
}

/// Get current authenticated GitHub user
pub fn get_current_user() -> Result<String> {
    let output = Command::new("gh")
        .args(["api", "user", "--jq", ".login"])
        .output()
        .context("Failed to get current user")?;

    if !output.status.success() {
        bail!("Could not retrieve current GitHub user.");
    }

    let user = String::from_utf8(output.stdout)?
        .trim()
        .to_string();

    if user.is_empty() {
        bail!("Could not retrieve current GitHub user.");
    }

    Ok(user)
}

/// Fetch PRs for a user with optional filters
pub fn fetch_prs(
    user: &str,
    date_filter: Option<&str>,
    org_filter: Option<&str>,
    repo_filter: Option<&str>,
) -> Result<Vec<SearchResult>> {
    let mut query = format!("author:{} type:pr", user);

    if let Some(date) = date_filter {
        query.push(' ');
        query.push_str(date);
    }

    if let Some(orgs) = org_filter {
        for org in orgs.split(',') {
            query.push_str(&format!(" org:{}", org.trim()));
        }
    }

    if let Some(repos) = repo_filter {
        for repo in repos.split(',') {
            query.push_str(&format!(" repo:{}", repo.trim()));
        }
    }

    let output = Command::new("gh")
        .args([
            "api",
            "-X",
            "GET",
            "search/issues",
            "-f",
            &format!("q={}", query),
            "--paginate",
            "-f",
            "per_page=30",
            "--jq",
            r#".items[] | {title: .title, url: .html_url, repo: (.repository_url | sub("https://api.github.com/repos/"; "")), created_at: .created_at, state: (if .pull_request.merged_at != null then "merged" else .state end), author: .user.login}"#,
        ])
        .output()
        .context("Failed to fetch PRs")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("Failed to fetch PRs: {}", stderr);
    }

    let stdout = String::from_utf8(output.stdout)?;
    let mut results = Vec::new();

    for line in stdout.lines() {
        if line.trim().is_empty() {
            continue;
        }
        match serde_json::from_str::<SearchResult>(line) {
            Ok(pr) => results.push(pr),
            Err(e) => eprintln!("Warning: Failed to parse PR: {}", e),
        }
    }

    Ok(results)
}

/// Fetch count of PRs reviewed by a user
pub fn fetch_reviews_by_user(
    user: &str,
    date_filter: Option<&str>,
    org_filter: Option<&str>,
    repo_filter: Option<&str>,
) -> Result<usize> {
    let mut query = format!("reviewed-by:{} type:pr", user);

    if let Some(date) = date_filter {
        query.push(' ');
        query.push_str(date);
    }

    if let Some(orgs) = org_filter {
        for org in orgs.split(',') {
            query.push_str(&format!(" org:{}", org.trim()));
        }
    }

    if let Some(repos) = repo_filter {
        for repo in repos.split(',') {
            query.push_str(&format!(" repo:{}", repo.trim()));
        }
    }

    let output = Command::new("gh")
        .args([
            "api",
            "-X",
            "GET",
            "search/issues",
            "-f",
            &format!("q={}", query),
            "--jq",
            ".total_count",
        ])
        .output()
        .context("Failed to fetch review count")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("Failed to fetch reviews for {}: {}", user, stderr);
    }

    let stdout = String::from_utf8(output.stdout)?;
    let count: usize = stdout.trim().parse().unwrap_or(0);
    Ok(count)
}

/// Fetch all members of a GitHub organization
pub fn fetch_org_members(org: &str) -> Result<Vec<String>> {
    let output = Command::new("gh")
        .args([
            "api",
            &format!("orgs/{}/members", org),
            "--paginate",
            "--jq",
            ".[].login",
        ])
        .output()
        .context("Failed to fetch org members")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("Failed to fetch members for org {}: {}", org, stderr);
    }

    let stdout = String::from_utf8(output.stdout)?;
    let members: Vec<String> = stdout
        .lines()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    Ok(members)
}

/// Fetch detailed PR information
pub fn fetch_pr_details(url: &str) -> Result<PrDetails> {
    let output = Command::new("gh")
        .args(["pr", "view", url, "--json", "body,files,additions,deletions"])
        .output()
        .context("Failed to fetch PR details")?;

    if !output.status.success() {
        bail!("Failed to fetch details for PR: {}", url);
    }

    let stdout = String::from_utf8(output.stdout)?;
    let details: PrDetails = serde_json::from_str(&stdout)
        .context("Failed to parse PR details")?;

    Ok(details)
}
