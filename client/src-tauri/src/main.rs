// Prevents an extra console window on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(target_os = "linux")]
mod linux_startup;

fn main() {
    #[cfg(target_os = "linux")]
    if let Err(message) = linux_startup::configure() {
        eprintln!("{message}");
        std::process::exit(2);
    }
    linger_client_lib::run();
}
