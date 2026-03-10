fn main() {
    uniffi::generate_scaffolding("src/plc_core.udl").unwrap();
}
