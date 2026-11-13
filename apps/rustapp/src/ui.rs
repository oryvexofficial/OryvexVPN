use crate::api::{first, items, text, Api};
use eframe::egui::{self, Color32, RichText, ScrollArea, Stroke, Vec2};
use serde_json::{json, Value};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Tab {
    Home,
    Browse,
    Models,
    Status,
    Social,
    Developers,
    CheckHost,
    Account,
    Player,
}

#[derive(Clone)]
pub struct VideoItem {
    pub title: String,
    pub url: String,
    pub thumbnail: String,
    pub duration: String,
    pub provider: String,
}

#[derive(Clone)]
pub struct StreamQuality {
    pub label: String,
    pub url: String,
    pub is_fallback: bool,
}

#[derive(Clone)]
pub struct ModelItem {
    pub name: String,
    pub slug: String,
    pub image_url: String,
    pub country: String,
}

pub enum Msg {
    ConfigLoaded(Value),
    CatalogLoaded {
        provider: String,
        page: u32,
        videos: Vec<VideoItem>,
    },
    StreamsExtracted {
        title: String,
        streams: Vec<StreamQuality>,
    },
    ModelsLoaded {
        models: Vec<ModelItem>,
        has_more: bool,
    },
    ModelProfileLoaded(Value),
    StatusLoaded(Value),
    SocialLoaded(Value),
    DevelopersLoaded(Value),
    CheckHostResult(Value),
    AccountLoaded(Value),
    AuthSuccess {
        token: String,
        account: Value,
    },
    Error(String),
}

pub struct VexoApp {
    pub api: Api,
    pub tab: Tab,
    pub provider: String,
    pub providers: Vec<(String, String)>,
    pub search_query: String,
    pub catalog_page: u32,
    pub videos: Vec<VideoItem>,
    pub loading: bool,
    pub error_message: Option<String>,
    pub paste_url: String,

    pub active_video: Option<VideoItem>,
    pub stream_title: String,
    pub stream_qualities: Vec<StreamQuality>,
    pub selected_stream: Option<String>,

    pub models: Vec<ModelItem>,
    pub models_gender: String,
    pub models_search: String,
    pub models_page: u32,
    pub active_model: Option<Value>,

    pub status_data: Option<Value>,
    pub social_data: Option<Value>,
    pub dev_data: Option<Value>,

    pub check_host_target: String,
    pub check_host_type: String,
    pub check_host_output: String,

    pub auth_username: String,
    pub auth_password: String,
    pub auth_signup: bool,
    pub auth_notice: Option<String>,
    pub account: Option<Value>,

    tx: Sender<Msg>,
    rx: Receiver<Msg>,
}

impl VexoApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.override_text_color = Some(Color32::from_rgb(244, 245, 248));
        visuals.panel_fill = Color32::from_rgb(11, 13, 19);
        visuals.window_fill = Color32::from_rgb(4, 6, 10);
        visuals.faint_bg_color = Color32::from_rgb(18, 21, 28);
        visuals.extreme_bg_color = Color32::from_rgb(18, 21, 28);
        visuals.widgets.noninteractive.bg_fill = Color32::from_rgb(11, 13, 19);
        visuals.widgets.noninteractive.bg_stroke =
            Stroke::new(1.0, Color32::from_rgb(32, 35, 42));
        visuals.widgets.inactive.bg_fill = Color32::from_rgb(18, 21, 28);
        visuals.widgets.hovered.bg_fill = Color32::from_rgb(28, 31, 39);
        visuals.widgets.active.bg_fill = Color32::from_rgb(55, 142, 255);
        visuals.selection.bg_fill = Color32::from_rgb(55, 142, 255);
        cc.egui_ctx.set_visuals(visuals);

        let (tx, rx) = channel();
        let app = Self {
            api: Api::new(),
            tab: Tab::Home,
            provider: "pornhub".into(),
            providers: vec![
                ("pornhub".into(), "Pornhub".into()),
                ("xvideos".into(), "XVideos".into()),
                ("xnxx".into(), "XNXX".into()),
                ("redtube".into(), "RedTube".into()),
                ("youporn".into(), "YouPorn".into()),
            ],
            search_query: String::new(),
            catalog_page: 1,
            videos: Vec::new(),
            loading: false,
            error_message: None,
            paste_url: String::new(),

            active_video: None,
            stream_title: String::new(),
            stream_qualities: Vec::new(),
            selected_stream: None,

            models: Vec::new(),
            models_gender: "women".into(),
            models_search: String::new(),
            models_page: 1,
            active_model: None,

            status_data: None,
            social_data: None,
            dev_data: None,

            check_host_target: "vexostream.bond".into(),
            check_host_type: "http".into(),
            check_host_output: String::new(),

            auth_username: String::new(),
            auth_password: String::new(),
            auth_signup: false,
            auth_notice: None,
            account: None,

            tx,
            rx,
        };

        app.fetch_config();
        app.fetch_catalog("pornhub", "trending", 1);
        app
    }

    fn fetch_config(&self) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        thread::spawn(move || {
            match api.request("/config", &[], None) {
                Ok(data) => {
                    let _ = tx.send(Msg::ConfigLoaded(data));
                }
                Err(e) => {
                    let _ = tx.send(Msg::Error(e));
                }
            }
        });
    }

    pub fn fetch_catalog(&self, provider: &str, q: &str, page: u32) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        let prov = provider.to_owned();
        let query = q.to_owned();
        thread::spawn(move || {
            let params = vec![
                ("provider".into(), prov.clone()),
                ("q".into(), query),
                ("page".into(), page.to_string()),
            ];
            match api.request("/catalog", &params, None) {
                Ok(res) => {
                    let list = items(&res, &["videos", "results", "items", "data"]);
                    let mut videos = Vec::new();
                    for item in list {
                        let url = first(&item, &["url", "video_url", "link", "href"]);
                        let thumb = first(
                            &item,
                            &[
                                "thumbnail",
                                "thumbnail_url",
                                "thumb",
                                "poster",
                                "image",
                                "preview",
                            ],
                        );
                        if !url.is_empty() {
                            videos.push(VideoItem {
                                title: first(
                                    &item,
                                    &["title", "name", "video_title"],
                                ),
                                url,
                                thumbnail: thumb,
                                duration: first(&item, &["duration", "length"]),
                                provider: first(&item, &["provider", "source"]),
                            });
                        }
                    }
                    let _ = tx.send(Msg::CatalogLoaded {
                        provider: prov,
                        page,
                        videos,
                    });
                }
                Err(e) => {
                    let _ = tx.send(Msg::Error(e));
                }
            }
        });
    }

    pub fn extract_video(&self, url: &str) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        let target = url.to_owned();
        thread::spawn(move || {
            let body = json!({ "url": target });
            match api.request("/videos/extract", &[], Some(body)) {
                Ok(res) => {
                    let title = text(&res["title"]);
                    let streams_obj = &res["streams"];
                    let qualities = items(streams_obj, &["qualities"]);
                    let fallback = items(streams_obj, &["fallback"]);
                    let mut list = Vec::new();
                    for q in qualities {
                        if let Ok(proxy_url) = api.stream_url(&q) {
                            let label = first(&q, &["quality", "type"]);
                            list.push(StreamQuality {
                                label: if label.is_empty() {
                                    "Stream".into()
                                } else {
                                    label
                                },
                                url: proxy_url,
                                is_fallback: false,
                            });
                        }
                    }
                    // Only use main qualities for the UI, keep fallback internal
                    if list.is_empty() {
                        for f in fallback {
                            if let Ok(proxy_url) = api.stream_url(&f) {
                                let label = first(&f, &["quality", "type"]);
                                list.push(StreamQuality {
                                    label: if label.is_empty() {
                                        "Stream".into()
                                    } else {
                                        label
                                    },
                                    url: proxy_url,
                                    is_fallback: true,
                                });
                            }
                        }
                    }
                    let _ = tx.send(Msg::StreamsExtracted {
                        title,
                        streams: list,
                    });
                }
                Err(e) => {
                    let _ = tx.send(Msg::Error(e));
                }
            }
        });
    }

    pub fn fetch_models(&self, gender: &str, search: &str, page: u32) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        let g = gender.to_owned();
        let s = search.to_owned();
        thread::spawn(move || {
            let mut params = vec![("gender".into(), g), ("page".into(), page.to_string())];
            if !s.is_empty() {
                params.push(("search".into(), s));
            }
            match api.request("/models", &params, None) {
                Ok(res) => {
                    let list = items(&res, &["models", "results", "items", "data"]);
                    let has_more = res["has_more"].as_bool().unwrap_or(false);
                    let mut models = Vec::new();
                    for m in list {
                        models.push(ModelItem {
                            name: first(&m, &["name", "title"]),
                            slug: first(&m, &["slug", "id"]),
                            image_url: first(
                                &m,
                                &["image_url", "image", "thumbnail", "photo"],
                            ),
                            country: first(&m, &["country_name", "country"]),
                        });
                    }
                    let _ = tx.send(Msg::ModelsLoaded { models, has_more });
                }
                Err(e) => {
                    let _ = tx.send(Msg::Error(e));
                }
            }
        });
    }

    pub fn fetch_model_profile(&self, slug: &str) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        let path = format!("/models/{slug}");
        thread::spawn(move || match api.request(&path, &[], None) {
            Ok(res) => {
                let _ = tx.send(Msg::ModelProfileLoaded(res));
            }
            Err(e) => {
                let _ = tx.send(Msg::Error(e));
            }
        });
    }

    pub fn fetch_status(&self) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        thread::spawn(move || match api.request("/status", &[], None) {
            Ok(res) => {
                let _ = tx.send(Msg::StatusLoaded(res));
            }
            Err(e) => {
                let _ = tx.send(Msg::Error(e));
            }
        });
    }

    pub fn fetch_social(&self) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        thread::spawn(move || match api.request("/social", &[], None) {
            Ok(res) => {
                let _ = tx.send(Msg::SocialLoaded(res));
            }
            Err(e) => {
                let _ = tx.send(Msg::Error(e));
            }
        });
    }

    pub fn fetch_developers(&self) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        thread::spawn(move || match api.request("/developers", &[], None) {
            Ok(res) => {
                let _ = tx.send(Msg::DevelopersLoaded(res));
            }
            Err(e) => {
                let _ = tx.send(Msg::Error(e));
            }
        });
    }

    pub fn run_check_host(&self, host: &str, check_type: &str) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        let h = host.to_owned();
        let ct = check_type.to_owned();
        thread::spawn(move || {
            let params = vec![("host".into(), h), ("type".into(), ct)];
            match api.request("/check-host/start", &params, None) {
                Ok(res) => {
                    let _ = tx.send(Msg::CheckHostResult(res));
                }
                Err(e) => {
                    let _ = tx.send(Msg::Error(e));
                }
            }
        });
    }

    pub fn authenticate(&self) {
        let api = self.api.clone();
        let tx = self.tx.clone();
        let username = self.auth_username.clone();
        let password = self.auth_password.clone();
        let signup = self.auth_signup;
        thread::spawn(move || {
            let path = if signup {
                "/auth/signup"
            } else {
                "/auth/login"
            };
            let body = if signup {
                json!({
                    "username": username,
                    "password": password,
                    "passwordConfirm": password,
                    "adult": true
                })
            } else {
                json!({
                    "username": username,
                    "password": password
                })
            };
            match api.request(path, &[], Some(body)) {
                Ok(res) => {
                    let token = text(&res["token"]);
                    let account = res["account"].clone();
                    let _ = tx.send(Msg::AuthSuccess { token, account });
                }
                Err(e) => {
                    let _ = tx.send(Msg::Error(e));
                }
            }
        });
    }

    fn handle_messages(&mut self) {
        while let Ok(msg) = self.rx.try_recv() {
            self.loading = false;
            match msg {
                Msg::ConfigLoaded(cfg) => {
                    if let Some(arr) = cfg["providers"].as_array() {
                        self.providers = arr
                            .iter()
                            .filter_map(|p| {
                                let id = text(&p["id"]);
                                let name = text(&p["name"]);
                                if !id.is_empty() {
                                    Some((id, name))
                                } else {
                                    None
                                }
                            })
                            .collect();
                    }
                    if let Some(def) = cfg["defaultProvider"].as_str() {
                        if !def.is_empty() {
                            self.provider = def.into();
                        }
                    }
                }
                Msg::CatalogLoaded {
                    provider,
                    page,
                    videos,
                } => {
                    self.provider = provider;
                    self.catalog_page = page;
                    self.videos = videos;
                    self.error_message = None;
                }
                Msg::StreamsExtracted { title, streams } => {
                    self.stream_title = title;
                    self.stream_qualities = streams;
                    self.selected_stream =
                        self.stream_qualities.first().map(|q| q.url.clone());
                    self.tab = Tab::Player;
                }
                Msg::ModelsLoaded { models, .. } => {
                    self.models = models;
                    self.error_message = None;
                }
                Msg::ModelProfileLoaded(val) => {
                    self.active_model = Some(val);
                }
                Msg::StatusLoaded(val) => {
                    self.status_data = Some(val);
                }
                Msg::SocialLoaded(val) => {
                    self.social_data = Some(val);
                }
                Msg::DevelopersLoaded(val) => {
                    self.dev_data = Some(val);
                }
                Msg::CheckHostResult(val) => {
                    self.check_host_output = serde_json::to_string_pretty(&val)
                        .unwrap_or_else(|_| "Check completed.".into());
                }
                Msg::AccountLoaded(val) => {
                    self.account = Some(val);
                }
                Msg::AuthSuccess { token, account } => {
                    self.api.token = token;
                    self.account = Some(account);
                    self.auth_notice = Some("Signed in successfully.".into());
                    self.tab = Tab::Account;
                }
                Msg::Error(e) => {
                    self.error_message = Some(e);
                }
            }
        }
    }
}

impl eframe::App for VexoApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.handle_messages();

        egui::SidePanel::left("nav_sidebar")
            .resizable(false)
            .default_width(220.0)
            .show(ctx, |ui| {
                ui.add_space(16.0);
                ui.horizontal(|ui| {
                    ui.heading(RichText::new("VexoStream").color(Color32::from_rgb(55, 142, 255)).strong().size(22.0));
                    ui.label(RichText::new("RUST").color(Color32::from_rgb(120, 125, 135)).small());
                });
                ui.add_space(8.0);
                ui.label(RichText::new("Native Windows Edition (No WebView)").color(Color32::from_rgb(171, 174, 182)).size(11.0));
                ui.separator();
                ui.add_space(12.0);

                let nav_items = [
                    (Tab::Home, "🏠  Home"),
                    (Tab::Browse, "🎬  Browse / Search"),
                    (Tab::Models, "⭐  OnlyFans Models"),
                    (Tab::Status, "📊  Status"),
                    (Tab::Social, "💬  Social"),
                    (Tab::Developers, "⚡  Developers"),
                    (Tab::CheckHost, "🌐  Check Host"),
                    (Tab::Account, if self.api.token.is_empty() { "👤  Sign In" } else { "👤  Account" }),
                ];

                for (t, label) in nav_items {
                    let selected = self.tab == t;
                    let resp = ui.selectable_label(selected, RichText::new(label).size(14.0));
                    if resp.clicked() {
                        self.tab = t;
                        match t {
                            Tab::Models => {
                                if self.models.is_empty() {
                                    self.loading = true;
                                    self.fetch_models(&self.models_gender.clone(), &self.models_search.clone(), self.models_page);
                                }
                            }
                            Tab::Status => {
                                self.loading = true;
                                self.fetch_status();
                            }
                            Tab::Social => {
                                self.loading = true;
                                self.fetch_social();
                            }
                            Tab::Developers => {
                                self.loading = true;
                                self.fetch_developers();
                            }
                            _ => {}
                        }
                    }
                }

                ui.add_space(20.0);
                ui.separator();
                ui.label(RichText::new("Libraries").color(Color32::from_rgb(120, 125, 135)).strong().size(12.0));
                for (id, name) in &self.providers {
                    let is_active = self.tab == Tab::Browse && self.provider == *id;
                    if ui.selectable_label(is_active, format!("▶  {name}")).clicked() {
                        self.provider = id.clone();
                        self.tab = Tab::Browse;
                        self.catalog_page = 1;
                        self.loading = true;
                        self.fetch_catalog(id, "trending", 1);
                    }
                }
            });

        egui::CentralPanel::default().show(ctx, |ui| {
            if let Some(err) = &self.error_message {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(format!("⚠️ {err}")).color(Color32::from_rgb(248, 84, 82)));
                });
                ui.separator();
            }

            match self.tab {
                Tab::Home => self.render_home(ui),
                Tab::Browse => self.render_browse(ui),
                Tab::Models => self.render_models(ui),
                Tab::Player => self.render_player(ui),
                Tab::Status => self.render_status(ui),
                Tab::Social => self.render_social(ui),
                Tab::Developers => self.render_developers(ui),
                Tab::CheckHost => self.render_check_host(ui),
                Tab::Account => self.render_account(ui),
            }
        });
    }
}

impl VexoApp {
    fn render_home(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.heading(RichText::new("VexoStream").size(28.0).strong());
            ui.label(RichText::new("Ad-Free HD Video Player • Streamed directly from the edge").color(Color32::from_rgb(171, 174, 182)));
            ui.add_space(16.0);

            ui.group(|ui| {
                ui.label(RichText::new("Paste any supported video link (Pornhub, XVideos, XNXX, RedTube, YouPorn):").strong());
                ui.horizontal(|ui| {
                    ui.text_edit_singleline(&mut self.paste_url);
                    if ui.button(RichText::new("▶ Play Link").strong()).clicked() && !self.paste_url.trim().is_empty() {
                        self.loading = true;
                        self.extract_video(&self.paste_url.clone());
                    }
                });
            });

            ui.add_space(20.0);
            ui.heading(RichText::new("Trending Videos").size(20.0));
            ui.separator();
            self.render_video_list(ui);
        });
    }

    fn render_browse(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.heading(RichText::new("Browse & Search").size(24.0).strong());
                ui.add_space(16.0);
                ui.text_edit_singleline(&mut self.search_query);
                if ui.button("🔍 Search").clicked() {
                    self.catalog_page = 1;
                    self.loading = true;
                    let q = if self.search_query.trim().is_empty() { "trending" } else { &self.search_query };
                    self.fetch_catalog(&self.provider.clone(), q, 1);
                }
            });

            ui.add_space(12.0);
            ui.horizontal(|ui| {
                for (id, name) in &self.providers {
                    let sel = self.provider == *id;
                    if ui.selectable_label(sel, name).clicked() {
                        self.provider = id.clone();
                        self.catalog_page = 1;
                        self.loading = true;
                        self.fetch_catalog(id, "trending", 1);
                    }
                }
            });

            ui.separator();
            ui.add_space(8.0);
            self.render_video_list(ui);

            ui.add_space(16.0);
            ui.horizontal(|ui| {
                if self.catalog_page > 1 && ui.button("◀ Previous").clicked() {
                    self.catalog_page -= 1;
                    self.loading = true;
                    let q = if self.search_query.trim().is_empty() { "trending" } else { &self.search_query };
                    self.fetch_catalog(&self.provider.clone(), q, self.catalog_page);
                }
                ui.label(format!("Page {}", self.catalog_page));
                if ui.button("Next ▶").clicked() {
                    self.catalog_page += 1;
                    self.loading = true;
                    let q = if self.search_query.trim().is_empty() { "trending" } else { &self.search_query };
                    self.fetch_catalog(&self.provider.clone(), q, self.catalog_page);
                }
            });
        });
    }

    fn render_video_list(&mut self, ui: &mut egui::Ui) {
        if self.loading {
            ui.label(RichText::new("Loading videos from edge...").italics());
            return;
        }

        let mut to_play: Option<String> = None;
        for v in &self.videos {
            ui.group(|ui| {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        ui.label(RichText::new(&v.title).strong().size(15.0));
                        ui.horizontal(|ui| {
                            if !v.provider.is_empty() {
                                ui.label(RichText::new(&v.provider).color(Color32::from_rgb(55, 142, 255)));
                            }
                            if !v.duration.is_empty() {
                                ui.label(format!("⏱ {}", v.duration));
                            }
                        });
                    });
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.button(RichText::new("▶ Play").strong()).clicked() {
                            to_play = Some(v.url.clone());
                        }
                    });
                });
            });
            ui.add_space(4.0);
        }

        if let Some(target) = to_play {
            self.loading = true;
            self.extract_video(&target);
        }
    }

    fn render_models(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.heading(RichText::new("OnlyFans Models Directory").size(24.0).strong());
            ui.label(RichText::new("Top popular performers with live podium rankings").color(Color32::from_rgb(171, 174, 182)));
            ui.add_space(12.0);

            ui.horizontal(|ui| {
                for (g, label) in [("women", "Women"), ("both", "Both"), ("men", "Men")] {
                    let sel = self.models_gender == g;
                    if ui.selectable_label(sel, label).clicked() {
                        self.models_gender = g.into();
                        self.models_page = 1;
                        self.loading = true;
                        self.fetch_models(g, &self.models_search.clone(), 1);
                    }
                }
                ui.add_space(16.0);
                ui.text_edit_singleline(&mut self.models_search);
                if ui.button("Search Models").clicked() {
                    self.models_page = 1;
                    self.loading = true;
                    self.fetch_models(&self.models_gender.clone(), &self.models_search.clone(), 1);
                }
            });

            ui.separator();
            ui.add_space(10.0);

            // Top 3 Podium: Render 2nd, 1st, 3rd in classic Olympic leaderboard style!
            if self.models.len() >= 3 && self.models_page == 1 && self.models_search.is_empty() {
                ui.group(|ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(RichText::new("🏆 LEADERBOARD • TOP 3").color(Color32::from_rgb(245, 174, 57)).strong().size(16.0));
                    });
                    ui.add_space(8.0);

                    ui.horizontal(|ui| {
                        // 2nd Place (Silver)
                        ui.vertical_centered(|ui| {
                            ui.label(RichText::new("🥈 #2 SILVER").color(Color32::from_rgb(192, 196, 204)).strong().size(14.0));
                            if let Some(m) = self.models.get(1) {
                                ui.label(RichText::new(&m.name).strong().size(15.0));
                                ui.label(RichText::new(&m.country).small());
                                if ui.button("View Profile").clicked() {
                                    self.fetch_model_profile(&m.slug);
                                }
                            }
                            ui.add_space(14.0);
                            ui.label(RichText::new("────── 2 ──────").monospace());
                        });

                        ui.separator();

                        // 1st Place (Gold - Elevated)
                        ui.vertical_centered(|ui| {
                            ui.label(RichText::new("🥇 #1 GOLD").color(Color32::from_rgb(255, 215, 0)).strong().size(16.0));
                            if let Some(m) = self.models.first() {
                                ui.label(RichText::new(&m.name).strong().size(18.0));
                                ui.label(RichText::new(&m.country).small());
                                if ui.button(RichText::new("View Profile").strong()).clicked() {
                                    self.fetch_model_profile(&m.slug);
                                }
                            }
                            ui.add_space(28.0);
                            ui.label(RichText::new("══════ 1 ══════").monospace());
                        });

                        ui.separator();

                        // 3rd Place (Bronze)
                        ui.vertical_centered(|ui| {
                            ui.label(RichText::new("🥉 #3 BRONZE").color(Color32::from_rgb(205, 127, 50)).strong().size(14.0));
                            if let Some(m) = self.models.get(2) {
                                ui.label(RichText::new(&m.name).strong().size(15.0));
                                ui.label(RichText::new(&m.country).small());
                                if ui.button("View Profile").clicked() {
                                    self.fetch_model_profile(&m.slug);
                                }
                            }
                            ui.add_space(6.0);
                            ui.label(RichText::new("────── 3 ──────").monospace());
                        });
                    });
                });
                ui.add_space(16.0);
            }

            // Display active model profile popup/section if selected
            if let Some(prof) = &self.active_model {
                ui.group(|ui| {
                    ui.horizontal(|ui| {
                        ui.heading(RichText::new(first(prof, &["name", "title"])).size(22.0));
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui.button("✕ Close Profile").clicked() {
                                self.active_model = None;
                            }
                        });
                    });
                    ui.label(format!("Country: {}", first(prof, &["country_name", "country"])));
                    let p = &prof["personal_details"];
                    if !p.is_null() {
                        ui.label(format!("Age: {} | Gender: {} | Career: {}", first(p, &["age"]), first(p, &["gender"]), first(p, &["career"])));
                    }
                    let a = &prof["physical_attributes"];
                    if !a.is_null() {
                        ui.label(format!("Height: {} | Hair: {} | Measurements: {}", first(a, &["height"]), first(a, &["hair_color"]), first(a, &["measurements"])));
                    }
                });
                ui.add_space(12.0);
            }

            ui.heading(RichText::new("All Models").size(18.0));
            ui.separator();
            for (idx, m) in self.models.iter().enumerate() {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(format!("#{}:", idx + 1)).strong());
                    ui.label(RichText::new(&m.name).strong());
                    ui.label(format!("({})", m.country));
                    if ui.button("Profile").clicked() {
                        self.fetch_model_profile(&m.slug);
                    }
                });
                ui.separator();
            }
        });
    }

    fn render_player(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                if ui.button("◀ Back to Catalog").clicked() {
                    self.tab = Tab::Browse;
                }
                ui.heading(RichText::new(&self.stream_title).size(20.0).strong());
            });
            ui.separator();
            ui.add_space(12.0);

            ui.label(RichText::new("Stream Resolution & Direct Links:").strong());
            ui.horizontal(|ui| {
                for q in &self.stream_qualities {
                    let sel = self.selected_stream.as_deref() == Some(&q.url);
                    if ui.selectable_label(sel, &q.label).clicked() {
                        self.selected_stream = Some(q.url.clone());
                    }
                }
            });

            ui.add_space(16.0);
            if let Some(url) = &self.selected_stream {
                ui.group(|ui| {
                    ui.label(RichText::new("Signed Stream URL (Plays directly or in external player):").strong());
                    ui.text_edit_singleline(&mut url.clone());
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        if ui.button(RichText::new("📋 Copy Stream Link").strong()).clicked() {
                            ui.output_mut(|o| o.copied_text = url.clone());
                        }
                        if ui.button(RichText::new("🚀 Launch in System Player / Browser").strong()).clicked() {
                            let _ = std::process::Command::new("cmd").args(["/C", "start", "", url]).spawn();
                        }
                    });
                });
            }
        });
    }

    fn render_status(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.heading(RichText::new("System Status").size(24.0).strong());
            ui.separator();
            if let Some(data) = &self.status_data {
                ui.label(RichText::new(format!("Overall: {}", text(&data["overall"]))).color(Color32::from_rgb(81, 198, 114)).strong().size(16.0));
                ui.add_space(10.0);
                if let Some(arr) = data["providers"].as_array() {
                    for p in arr {
                        ui.horizontal(|ui| {
                            ui.label(RichText::new(text(&p["name"])).strong());
                            ui.label(text(&p["status"]));
                        });
                    }
                }
            } else {
                ui.label("Loading status...");
            }
        });
    }

    fn render_social(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.heading(RichText::new("Social & Telegram Bots").size(24.0).strong());
            ui.separator();
            if let Some(data) = &self.social_data {
                if let Some(channel) = data["channel"].as_object() {
                    ui.label(RichText::new(format!("Channel: {}", text(&channel["title"]))).strong());
                    ui.label(text(&channel["url"]));
                }
                ui.add_space(12.0);
                ui.heading("Available Bots:");
                if let Some(bots) = data["bots"].as_array() {
                    for b in bots {
                        ui.label(format!("• {}: {}", text(&b["platform"]), text(&b["url"])));
                    }
                }
            } else {
                ui.label("Loading social channels...");
            }
        });
    }

    fn render_developers(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.heading(RichText::new("Developer Embed Code").size(24.0).strong());
            ui.separator();
            if let Some(data) = &self.dev_data {
                ui.label(RichText::new("Embed iframe snippet:").strong());
                let mut snippet = text(&data["embed"]);
                ui.text_edit_multiline(&mut snippet);
            } else {
                ui.label("Loading documentation...");
            }
        });
    }

    fn render_check_host(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            ui.heading(RichText::new("Check Host (Diagnostics)").size(24.0).strong());
            ui.separator();
            ui.horizontal(|ui| {
                ui.label("Target Host:");
                ui.text_edit_singleline(&mut self.check_host_target);
                for ct in ["http", "ping", "tcp", "dns"] {
                    let sel = self.check_host_type == ct;
                    if ui.selectable_label(sel, ct.to_uppercase()).clicked() {
                        self.check_host_type = ct.into();
                    }
                }
                if ui.button("Start Check").clicked() {
                    self.run_check_host(&self.check_host_target.clone(), &self.check_host_type.clone());
                }
            });

            ui.add_space(14.0);
            if !self.check_host_output.is_empty() {
                ui.group(|ui| {
                    ui.label(RichText::new("Results:").strong());
                    ui.monospace(&self.check_host_output);
                });
            }
        });
    }

    fn render_account(&mut self, ui: &mut egui::Ui) {
        ScrollArea::vertical().show(ui, |ui| {
            ui.add_space(8.0);
            if let Some(notice) = &self.auth_notice {
                ui.label(RichText::new(notice).color(Color32::from_rgb(81, 198, 114)));
            }
            if let Some(acc) = &self.account {
                ui.heading(RichText::new(format!("Welcome, {}", text(&acc["username"]))).size(24.0).strong());
                ui.label(format!("Role: {}", text(&acc["role"])));
                if ui.button("Sign Out").clicked() {
                    self.api.token.clear();
                    self.account = None;
                }
            } else {
                ui.heading(RichText::new(if self.auth_signup { "Create Account (18+)" } else { "Sign In" }).size(24.0).strong());
                ui.add_space(10.0);
                ui.horizontal(|ui| {
                    ui.label("Username: ");
                    ui.text_edit_singleline(&mut self.auth_username);
                });
                ui.horizontal(|ui| {
                    ui.label("Password: ");
                    ui.add(egui::TextEdit::singleline(&mut self.auth_password).password(true));
                });
                ui.add_space(8.0);
                ui.horizontal(|ui| {
                    if ui.button(if self.auth_signup { "Sign Up" } else { "Log In" }).clicked() {
                        self.authenticate();
                    }
                    if ui.button(if self.auth_signup { "Switch to Log In" } else { "Switch to Sign Up" }).clicked() {
                        self.auth_signup = !self.auth_signup;
                    }
                });
            }
        });
    }
}
