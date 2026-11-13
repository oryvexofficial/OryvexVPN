use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::blocking::Client;
use serde_json::Value;
use std::time::Duration;
use url::Url;

pub const DEFAULT_BASE: &str = "https://vexostream.bond/api/v1";
pub const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) VexoStream-Windows/1.1";

#[derive(Clone)]
pub struct Api {
    client: Client,
    pub base: String,
    pub token: String,
    pub key: String,
}

impl Api {
    pub fn new() -> Self {
        Self {
            client: Client::builder()
                .user_agent(USER_AGENT)
                .timeout(Duration::from_secs(65))
                .build()
                .expect("HTTPS client setup"),
            base: DEFAULT_BASE.into(),
            token: String::new(),
            key: option_env!("APP_KEY").unwrap_or("").to_owned(),
        }
    }

    pub fn request(&self, path: &str, params: &[(String, String)], body: Option<Value>) -> Result<Value, String> {
        let url = format!("{}{}", self.base.trim_end_matches('/'), path);
        let mut req = if let Some(body) = body { self.client.post(&url).json(&body) } else { self.client.get(&url) };
        req = req.header("X-App-Key", &self.key).header("Accept-Language", "en-US,en;q=0.9").query(params);
        if !self.token.is_empty() { req = req.bearer_auth(&self.token); }
        let response = req.send().map_err(|e| format!("Connection failed: {e}"))?;
        let status = response.status();
        let value: Value = response.json().map_err(|_| format!("Invalid server response ({status})"))?;
        if !status.is_success() {
            return Err(value["error"].as_str().unwrap_or("Server rejected the request").to_string());
        }
        Ok(value)
    }

    pub fn image(&self, source: &str) -> Result<Vec<u8>, String> {
        let mut source = source.to_owned();
        if source.starts_with("//") { source = format!("https:{source}"); }
        let mut url = Url::parse(&self.base).map_err(|e| e.to_string())?;
        url.set_path("/api/v1/image");
        url.set_query(None);
        url.query_pairs_mut().append_pair("url", &source);
        let response = self.client.get(url).header("X-App-Key", &self.key).send().map_err(|e| e.to_string())?;
        if !response.status().is_success() { return Err(format!("Image HTTP {}", response.status())); }
        if response.content_length().unwrap_or(0) > 8_000_000 { return Err("Image too large".into()); }
        let bytes = response.bytes().map_err(|e| e.to_string())?;
        if bytes.len() > 8_000_000 { return Err("Image too large".into()); }
        Ok(bytes.to_vec())
    }

    pub fn stream_url(&self, quality: &Value) -> Result<String, String> {
        let encoded = quality["x_url"].as_str().ok_or("Missing stream link")?;
        let decoded = STANDARD.decode(encoded).map_err(|_| "Invalid stream encoding")?;
        let escaped = String::from_utf8(decoded).map_err(|_| "Invalid stream encoding")?;
        // The Worker uses btoa(encodeURIComponent(url)); decode exactly once.
        let raw = percent_decode(&escaped)?;
        let src = Url::parse(&raw).map_err(|_| "Invalid stream URL")?;
        if src.scheme() != "https" && src.scheme() != "http" { return Err("Invalid stream protocol".into()); }
        let kind = quality["type"].as_str().unwrap_or("").to_lowercase();
        let hls = kind.contains("hls") || raw.to_lowercase().contains(".m3u8");
        let mut proxy = Url::parse(&self.base).map_err(|_| "Invalid API URL")?;
        proxy.set_path(if hls { "/proxy-m3u8" } else { "/proxy-video" });
        proxy.set_query(None);
        proxy.query_pairs_mut()
            .append_pair("url", &raw)
            .append_pair("sig", quality["x_sig"].as_str().unwrap_or(""))
            .append_pair("exp", &text(&quality["x_exp"]));
        Ok(proxy.into())
    }
}

fn percent_decode(s: &str) -> Result<String, String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            if i + 2 >= bytes.len() { return Err("Invalid URL encoding".into()); }
            let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).map_err(|_| "Invalid URL encoding")?;
            out.push(u8::from_str_radix(hex, 16).map_err(|_| "Invalid URL encoding")?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).map_err(|_| "Invalid URL encoding".into())
}

pub fn text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        _ => String::new(),
    }
}

pub fn first(v: &Value, keys: &[&str]) -> String {
    keys.iter().map(|k| text(&v[*k])).find(|s| !s.trim().is_empty()).unwrap_or_default()
}

pub fn items(v: &Value, keys: &[&str]) -> Vec<Value> {
    if let Some(a) = v.as_array() { return a.clone(); }
    keys.iter().find_map(|k| v[*k].as_array()).cloned().unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn signed_hls_proxy_preserves_query_and_signature() {
        let api = Api::new();
        let q = json!({"x_url": STANDARD.encode("https%3A%2F%2Fcdn.example.test%2Fmaster.m3u8%3Ftoken%3Da%252Bb"), "x_sig":"signed", "x_exp":123});
        let parsed = Url::parse(&api.stream_url(&q).unwrap()).unwrap();
        assert_eq!(parsed.path(), "/proxy-m3u8");
        let pairs: std::collections::HashMap<_, _> = parsed.query_pairs().into_owned().collect();
        assert_eq!(pairs["url"], "https://cdn.example.test/master.m3u8?token=a%2Bb");
        assert_eq!(pairs["sig"], "signed");
        assert_eq!(pairs["exp"], "123");
    }
    #[test]
    fn nested_results_and_percent_decoding() {
        assert_eq!(items(&json!({"models":[{"name":"test"}]}), &["models"]).len(), 1);
        assert_eq!(percent_decode("x%2By").unwrap(), "x+y");
        assert!(percent_decode("%ZZ").is_err());
    }
}
