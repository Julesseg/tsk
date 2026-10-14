use crate::admission::{LocalAccess, SemanticAccess};
use std::fs;
use std::path::{Path, PathBuf};
use taskchampion::{storage::{AccessMode, sqlite::SqliteStorage}, Replica};

fn copy_directory(source: &Path, destination: &Path) -> Result<(), String> {
    fs::create_dir_all(destination).map_err(|e| e.to_string())?;
    for entry in fs::read_dir(source).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        if [".tsk-sync-generation", ".tsk-operation", ".tsk-local-priority", ".tsk-semantic-mutation", ".tsk-migrated-to", ".tsk-shared-ready"].iter().any(|name| entry.file_name() == *name) { continue; }
        let kind = entry.file_type().map_err(|e| e.to_string())?;
        if kind.is_symlink() { return Err("Legacy storage contains an unsupported symbolic link".into()); }
        let target = destination.join(entry.file_name());
        if kind.is_dir() { copy_directory(&entry.path(), &target)?; }
        else { fs::copy(entry.path(), target).map_err(|e| e.to_string())?; }
    }
    Ok(())
}

async fn records(path: &Path) -> Result<serde_json::Value, String> {
    let storage = SqliteStorage::new(path, AccessMode::ReadWrite, true).await.map_err(|e| e.to_string())?;
    let mut replica = Replica::new(storage);
    let tasks = replica.all_task_data().await.map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(tasks.into_iter().map(|(id, task)| (id.to_string(), task.iter().map(|(key, value)| (key.to_owned(), value.to_owned())).collect::<std::collections::BTreeMap<_, _>>())).collect::<std::collections::BTreeMap<_, _>>()).map_err(|e| e.to_string())?)
}

pub async fn prepare(destination: &str, source: &str, allow_migration: bool) -> Result<(), String> {
    let destination = PathBuf::from(destination);
    let parent = destination.parent().ok_or("Invalid shared task storage location")?;
    let _migration = LocalAccess::new(parent.join(".tsk-migration-lock").to_str().ok_or("Invalid shared task storage path")?)?;
    let marker = destination.join(".tsk-shared-ready");
    if marker.exists() { let _destination = LocalAccess::new(destination.to_str().ok_or("Invalid shared path")?)?; records(&destination).await?; return Ok(()); }
    if !allow_migration { return Err("Open tsk to finish shared storage migration before using this action".into()); }
    if destination.exists() { return Err("Shared storage is not initialized; existing data was preserved. Open the app to resolve migration.".into()); }
    let source = PathBuf::from(source);
    let staging = parent.join(".tsk-migration-staging");
    if staging.exists() { fs::remove_dir_all(&staging).map_err(|e| e.to_string())?; }
    if source.exists() {
        let _semantic = SemanticAccess::new(source.to_str().ok_or("Invalid legacy task storage path")?)?;
        let _source = LocalAccess::new(source.to_str().ok_or("Invalid legacy task storage path")?)?;
        let configuration = source.join("sync-configuration.json");
        if configuration.exists() {
            let configuration: crate::SyncConfiguration = serde_json::from_slice(&fs::read(configuration).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
            configuration.validate()?;
        }
        let before = records(&source).await?;
        copy_directory(&source, &staging)?;
        let after = records(&staging).await?;
        if before != after { return Err("Shared storage migration validation failed; original data was preserved".into()); }
        finish(&staging, &destination)?;
        fs::write(source.join(".tsk-migrated-to"), destination.to_string_lossy().as_bytes()).map_err(|e| e.to_string())?;
    } else {
        records(&staging).await?;
        finish(&staging, &destination)?;
    }
    Ok(())
}

fn sync_tree(path: &Path) -> Result<(), String> {
    for entry in fs::read_dir(path).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        if entry.file_type().map_err(|e| e.to_string())?.is_dir() { sync_tree(&entry.path())?; }
        else { fs::File::open(entry.path()).and_then(|file| file.sync_all()).map_err(|e| e.to_string())?; }
    }
    fs::File::open(path).and_then(|file| file.sync_all()).map_err(|e| e.to_string())
}

fn finish(staging: &Path, destination: &Path) -> Result<(), String> {
    sync_tree(staging)?;
    let marker = staging.join(".tsk-shared-ready");
    fs::write(&marker, b"1").map_err(|e| e.to_string())?;
    fs::File::open(marker).and_then(|file| file.sync_all()).map_err(|e| e.to_string())?;
    fs::File::open(staging).and_then(|file| file.sync_all()).map_err(|e| e.to_string())?;
    fs::rename(staging, destination).map_err(|e| e.to_string())?;
    fs::File::open(destination.parent().ok_or("Missing shared container")?).and_then(|file| file.sync_all()).map_err(|e| e.to_string())?;
    Ok(())
}
