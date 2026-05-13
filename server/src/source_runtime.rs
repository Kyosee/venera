use std::{path::Path, time::Duration};

use serde::Deserialize;
use tokio::{process::Command, time::timeout};

use crate::{
    config::AppConfig,
    error::{ApiError, ApiResult},
    models::RuntimeSearchResult,
};

#[derive(Deserialize)]
struct RuntimeEnvelope<T> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

pub async fn search(
    config: &AppConfig,
    source_path: &Path,
    keyword: &str,
    page: u32,
) -> ApiResult<RuntimeSearchResult> {
    let runtime_path = config.source_runtime_path();
    if !runtime_path.is_file() {
        return Err(ApiError::State(format!(
            "source runtime not found: {}",
            runtime_path.display()
        )));
    }

    let mut command = Command::new(&config.node_bin);
    command
        .arg(runtime_path)
        .arg("search")
        .arg(source_path)
        .arg(keyword)
        .arg(page.to_string());

    let output = timeout(Duration::from_secs(20), command.output())
        .await
        .map_err(|_| ApiError::SourceRuntime("source runtime timed out".to_string()))?
        .map_err(|err| ApiError::SourceRuntime(err.to_string()))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        return Err(ApiError::SourceRuntime(runtime_error(&stdout, &stderr)));
    }

    let envelope: RuntimeEnvelope<RuntimeSearchResult> = serde_json::from_str(stdout.trim())
        .map_err(|err| ApiError::SourceRuntime(format!("invalid runtime response: {err}")))?;
    if !envelope.ok {
        return Err(ApiError::SourceRuntime(
            envelope
                .error
                .unwrap_or_else(|| "source runtime failed".to_string()),
        ));
    }

    envelope
        .data
        .ok_or_else(|| ApiError::SourceRuntime("source runtime returned empty data".to_string()))
}

fn runtime_error(stdout: &str, stderr: &str) -> String {
    let stdout = stdout.trim();
    let stderr = stderr.trim();
    if !stderr.is_empty() {
        stderr.to_string()
    } else if !stdout.is_empty() {
        stdout.to_string()
    } else {
        "source runtime exited without output".to_string()
    }
}
