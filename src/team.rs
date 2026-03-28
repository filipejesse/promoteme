use crate::models::{MemberStats, ProcessedPr};

pub fn compute_member_stats(
    username: &str,
    processed_prs: &[ProcessedPr],
    reviews_count: usize,
) -> MemberStats {
    let mut prs_merged = 0u32;
    let mut prs_open = 0u32;
    let mut total_additions = 0i64;
    let mut total_deletions = 0i64;
    let mut prs_with_tests = 0u32;
    let mut small_prs = 0u32;
    let mut large_prs = 0u32;

    for pr in processed_prs {
        match pr.state.to_uppercase().as_str() {
            "MERGED" => prs_merged += 1,
            "OPEN" => prs_open += 1,
            _ => {}
        }
        total_additions += pr.additions;
        total_deletions += pr.deletions;
        if !pr.test_files.is_empty() {
            prs_with_tests += 1;
        }
        if pr.total_changes <= 200 {
            small_prs += 1;
        }
        if pr.total_changes > 500 {
            large_prs += 1;
        }
    }

    let reviews_given = reviews_count as u32;
    let score = prs_merged as i64 * 10
        + prs_open as i64 * 3
        + reviews_given as i64 * 8
        + prs_with_tests as i64 * 3
        + small_prs as i64 * 2
        - large_prs as i64;

    MemberStats {
        username: username.to_string(),
        prs_merged,
        prs_open,
        total_additions,
        total_deletions,
        reviews_given,
        prs_with_tests,
        small_prs,
        large_prs,
        score,
    }
}

pub fn generate_member_report(stats: &MemberStats, prs: &[ProcessedPr]) -> String {
    let mut report = format!("# Contributions: {}\n\n", stats.username);

    for pr in prs {
        report.push_str(&pr.to_markdown());
        report.push('\n');
    }

    report.push_str("## Stats\n\n");
    report.push_str(&format!("- **PRs Merged:** {}\n", stats.prs_merged));
    report.push_str(&format!("- **PRs Open:** {}\n", stats.prs_open));
    report.push_str(&format!("- **Reviews Given:** {}\n", stats.reviews_given));
    report.push_str(&format!("- **PRs with Tests:** {}\n", stats.prs_with_tests));
    report.push_str(&format!("- **Small PRs (<= 200 lines):** {}\n", stats.small_prs));
    report.push_str(&format!("- **Large PRs (> 500 lines):** {}\n", stats.large_prs));
    report.push_str(&format!("- **Score:** {}\n", stats.score));

    report
}

pub fn generate_scores_table(all_stats: &[MemberStats]) -> String {
    let mut sorted: Vec<&MemberStats> = all_stats.iter().collect();
    sorted.sort_by(|a, b| b.score.cmp(&a.score));

    let mut table = "# Team Scores\n\n".to_string();
    table.push_str("| Rank | Member | Score | Merged | Reviews | With Tests | Avg Size |\n");
    table.push_str("|------|--------|-------|--------|---------|------------|----------|\n");

    for (i, stats) in sorted.iter().enumerate() {
        let total_prs = stats.prs_merged + stats.prs_open;
        let avg_size = if total_prs > 0 {
            (stats.total_additions + stats.total_deletions) / total_prs as i64
        } else {
            0
        };
        table.push_str(&format!(
            "| {} | {} | {} | {} | {} | {} | {} |\n",
            i + 1,
            stats.username,
            stats.score,
            stats.prs_merged,
            stats.reviews_given,
            stats.prs_with_tests,
            avg_size,
        ));
    }

    table
}
