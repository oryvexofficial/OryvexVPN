#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod api;
mod ui;

use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("VexoStream")
            .with_inner_size([1360.0, 860.0])
            .with_min_inner_size([740.0, 520.0]),
        ..Default::default()
    };
    eframe::run_native(
        "VexoStream",
        options,
        Box::new(|cc| Box::new(ui::VexoApp::new(cc))),
    )
}
