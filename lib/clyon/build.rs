use std::env;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR env var is not defined");

    let config = cbindgen::Config::from_file("cbindgen.toml")
        .expect("Unable to find cbindgen.toml configuration file");

    // cli: cbindgen --crate clyon --output clyon.h
    cbindgen::generate_with_config(&crate_dir, config)
        .unwrap()
        .write_to_file("clyon.h");
}