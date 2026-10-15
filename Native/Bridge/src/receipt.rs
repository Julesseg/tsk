use serde_json::{json, Value};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

pub fn load(path: &str) -> Result<Option<Value>, String> {
    let file = Path::new(path).join("synchronization-receipt.json");
    let bytes = match fs::read(file) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("Final synchronization receipt could not be read: {error}")),
    };
    let value: Value = serde_json::from_slice(&bytes).map_err(|error| format!("Final synchronization receipt is corrupt: {error}"))?;
    if value["version"].as_u64() != Some(1) || !value["baseline"].is_array() || !(value["success"].is_null() || value["success"].is_object()) {
        return Err("Unsupported final synchronization receipt. Existing data was preserved.".into());
    }
    Ok(Some(value))
}

pub fn initialize(path: &str, baseline: Value) -> Result<Value, String> {
    let value = json!({"version": 1, "baseline": baseline, "success": null});
    save(path, &value)?;
    Ok(value)
}

pub fn save(path: &str, value: &Value) -> Result<(), String> {
    let directory = Path::new(path);
    let temporary = directory.join("synchronization-receipt.pending");
    let bytes = serde_json::to_vec(value).map_err(|error| error.to_string())?;
    let mut file = OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&temporary).map_err(|error| error.to_string())?;
    file.write_all(&bytes).map_err(|error| error.to_string())?;
    file.sync_all().map_err(|error| error.to_string())?;
    fs::rename(temporary, directory.join("synchronization-receipt.json")).map_err(|error| error.to_string())?;
    File::open(directory).and_then(|file| file.sync_all()).map_err(|error| error.to_string())
}
