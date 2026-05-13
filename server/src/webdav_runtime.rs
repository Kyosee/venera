use std::{path::Path, time::Duration};

use serde::{de::DeserializeOwned, Deserialize, Serialize};
use tokio::{process::Command, time::timeout};

use crate::{
    config::AppConfig,
    error::{ApiError, ApiResult},
    models::{WebDavDownloadResponse, WebDavListResponse},
};

#[derive(Clone)]
pub struct WebDavConfig {
    pub endpoint_url: String,
    pub username: Option<String>,
    pub password: Option<String>,
    pub root_path: String,
}

#[derive(Serialize)]
struct RuntimePayload<'a> {
    endpoint_url: &'a str,
    username: Option<&'a str>,
    password: Option<&'a str>,
    root_path: &'a str,
    path: &'a str,
    local_path: Option<&'a str>,
}

#[derive(Deserialize)]
struct RuntimeEnvelope<T> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

pub async fn list(
    app_config: &AppConfig,
    webdav_config: &WebDavConfig,
    path: &str,
) -> ApiResult<WebDavListResponse> {
    run(
        app_config,
        "list",
        RuntimePayload {
            endpoint_url: &webdav_config.endpoint_url,
            username: webdav_config.username.as_deref(),
            password: webdav_config.password.as_deref(),
            root_path: &webdav_config.root_path,
            path,
            local_path: None,
        },
    )
    .await
}

pub async fn download(
    app_config: &AppConfig,
    webdav_config: &WebDavConfig,
    path: &str,
    local_path: &Path,
) -> ApiResult<WebDavDownloadResponse> {
    let local_path = local_path
        .to_str()
        .ok_or_else(|| ApiError::WebDav("invalid local import path".to_string()))?;
    run(
        app_config,
        "download",
        RuntimePayload {
            endpoint_url: &webdav_config.endpoint_url,
            username: webdav_config.username.as_deref(),
            password: webdav_config.password.as_deref(),
            root_path: &webdav_config.root_path,
            path,
            local_path: Some(local_path),
        },
    )
    .await
}

async fn run<T: DeserializeOwned>(
    app_config: &AppConfig,
    action: &str,
    payload: RuntimePayload<'_>,
) -> ApiResult<T> {
    let payload = serde_json::to_string(&payload)
        .map_err(|err| ApiError::WebDav(format!("invalid webdav payload: {err}")))?;
    let mut command = Command::new(&app_config.node_bin);
    command
        .arg(app_config.runtime_dir.join("webdav-client.mjs"))
        .arg(action)
        .arg(payload);

    let output = timeout(Duration::from_secs(45), command.output())
        .await
        .map_err(|_| ApiError::WebDav("webdav request timed out".to_string()))?
        .map_err(|err| ApiError::WebDav(err.to_string()))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        return Err(ApiError::WebDav(runtime_error(&stdout, &stderr)));
    }

    let envelope: RuntimeEnvelope<T> = serde_json::from_str(stdout.trim())
        .map_err(|err| ApiError::WebDav(format!("invalid webdav response: {err}")))?;
    if !envelope.ok {
        return Err(ApiError::WebDav(
            envelope
                .error
                .unwrap_or_else(|| "webdav request failed".to_string()),
        ));
    }

    envelope
        .data
        .ok_or_else(|| ApiError::WebDav("webdav response was empty".to_string()))
}

fn runtime_error(stdout: &str, stderr: &str) -> String {
    let stdout = stdout.trim();
    let stderr = stderr.trim();
    if !stderr.is_empty() {
        stderr.to_string()
    } else if !stdout.is_empty() {
        stdout.to_string()
    } else {
        "webdav request failed".to_string()
    }
}
