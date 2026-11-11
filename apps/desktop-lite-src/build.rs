fn main() {
    println!("cargo:rerun-if-changed=lite.rc");
    println!("cargo:rerun-if-changed=lite.manifest");
    println!("cargo:rerun-if-changed=res/oryvexcore.ico");
    let target = std::env::var("TARGET").unwrap_or_default();
    if target.contains("windows") {
        // Our own manifest (DPI aware, Windows 7 to 11) goes in as a resource; stop link.exe
        // from adding a second one.
        if target.contains("msvc") {
            println!("cargo:rustc-link-arg-bins=/MANIFEST:NO");
        }
        let _ = embed_resource::compile("lite.rc", embed_resource::NONE);
    }
}
