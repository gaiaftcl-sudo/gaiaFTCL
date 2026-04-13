use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_path = PathBuf::from(&crate_dir)
        .parent().unwrap()
        .join("include/gaia_metal_renderer.h");

    cbindgen::Builder::new()
        .with_crate(&crate_dir)
        .with_language(cbindgen::Language::C)
        .with_pragma_once(true)
        .with_include_guard("GAIA_METAL_RENDERER_H")
        .generate()
        .expect("Unable to generate C header")
        .write_to_file(&out_path);
    
    println!("cargo:rerun-if-changed=src/");
}
