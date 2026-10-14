use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use taskchampion::{storage::{AccessMode, sqlite::SqliteStorage}, Replica, ServerConfig, TaskData};
use uuid::Uuid;
mod admission;
mod migration;
use admission::{LocalAccess, SyncAccess, interrupt_sync, sync_generation};

#[derive(Deserialize)]
struct Attribute<T> {
    key: String,
    value: T,
}

#[derive(Deserialize)]
struct Request {
    path: String,
    command: String,
    id: Option<Uuid>,
    attributes: Option<Vec<Attribute<String>>>,
    changes: Option<Vec<Attribute<Option<String>>>>,
    configuration: Option<SyncConfiguration>,
    #[serde(rename = "syncGeneration")]
    sync_generation: Option<u64>,
    source: Option<String>,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct SyncConfiguration {
    #[serde(rename = "serverURL")]
    server_url: String,
    #[serde(rename = "clientID")]
    client_id: Uuid,
    encryption_secret: String,
}

impl SyncConfiguration {
    fn validate(&self) -> Result<(), String> {
        let url = url::Url::parse(&self.server_url).map_err(|e| e.to_string())?;
        if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() || !url.username().is_empty() || url.password().is_some() || url.query().is_some() || url.fragment().is_some() || self.server_url.chars().any(char::is_whitespace) { return Err("Invalid synchronization server URL".into()); }
        if self.encryption_secret.is_empty() { return Err("Empty encryption secret".into()); }
        Ok(())
    }
}

async fn execute(request: Request) -> Result<Value, String> {
    if request.command == "prepareShared" {
        migration::prepare(&request.path, request.source.as_deref().ok_or("Missing legacy storage path")?).await?;
        return Ok(json!(true));
    }
    if std::path::Path::new(&request.path).join(".tsk-migrated-to").exists() { return Err("This replica migrated to shared storage. Reopen through the common session.".into()); }
    let synchronization = if request.command == "synchronize" { Some(SyncAccess::new(&request.path, request.sync_generation).await?) } else { None };
    let _local = if synchronization.is_none() { Some(LocalAccess::new(&request.path)?) } else { None };
    if std::path::Path::new(&request.path).join(".tsk-migrated-to").exists() { return Err("This replica migrated to shared storage. Reopen through the common session.".into()); }
    if request.command.starts_with("configuration") {
        let file = std::path::Path::new(&request.path).join("sync-configuration.json");
        return match request.command.as_str() {
            "configurationLoad" => {
                if !file.exists() { return Ok(Value::Null); }
                let config: SyncConfiguration = serde_json::from_slice(&std::fs::read(file).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
                config.validate()?;
                serde_json::to_value(config).map_err(|e| e.to_string())
            }
            "configurationSave" => {
                let config = request.configuration.ok_or("Missing synchronization configuration")?;
                config.validate()?;
                let temporary = file.with_extension("json.pending");
                let data = serde_json::to_vec(&config).map_err(|e| e.to_string())?;
                use std::io::Write;
                use std::os::unix::fs::OpenOptionsExt;
                let mut output = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&temporary).map_err(|e| e.to_string())?;
                output.write_all(&data).and_then(|_| output.sync_all()).map_err(|e| e.to_string())?;
                std::fs::rename(temporary, file).map_err(|e| e.to_string())?;
                Ok(json!(true))
            }
            "configurationRemove" => {
                if file.exists() { std::fs::remove_file(file).map_err(|e| e.to_string())?; }
                Ok(json!(true))
            }
            _ => Err("Unsupported configuration command".into())
        };
    }
    let storage = SqliteStorage::new(&request.path, AccessMode::ReadWrite, true).await.map_err(|e| e.to_string())?;
    let mut replica = Replica::new(storage);
    match request.command.as_str() {
        "tasks" => {
            let tasks = replica.all_task_data().await.map_err(|e| e.to_string())?;
            Ok(json!(tasks.into_values().map(record).collect::<Vec<_>>()))
        }
        "create" => {
            let id = request.id.ok_or("Missing task identity")?;
            if replica.get_task_data(id).await.map_err(|e| e.to_string())?.is_some() {
                return Err("Task identity already exists".into());
            }
            let mut operations = taskchampion::Operations::new();
            let mut task = TaskData::create(id, &mut operations);
            for Attribute { key, value } in request.attributes.ok_or("Missing attributes")? {
                task.update(key, Some(value), &mut operations);
            }
            replica.commit_operations(operations).await.map_err(|e| e.to_string())?;
            Ok(record(task))
        }
        "update" => {
            let id = request.id.ok_or("Missing task identity")?;
            let mut task = replica.get_task_data(id).await.map_err(|e| e.to_string())?.ok_or("Task no longer exists")?;
            let changes = request.changes.ok_or("Missing task changes")?;
            if task.get("status") == Some("recurring") || ["recur", "parent", "mask", "imask"].iter().any(|key| task.has(key)) {
                return Err("Recurring task mutations require compatible series bookkeeping".into());
            }
            if !matches!(task.get("status"), Some("pending") | Some("completed")) {
                return Err("Unsupported task state".into());
            }
            if changes.iter().any(|attribute| ["uuid", "id", "entry", "recur", "parent", "mask", "imask"].contains(&attribute.key.as_str())) {
                return Err("Reserved task attribute cannot be changed by this action".into());
            }
            if let Some(status) = changes.iter().find(|attribute| attribute.key == "status") {
                if status.value.as_deref() != Some("completed") { return Err("Unsupported status transition".into()); }
                if task.get("status") == Some("completed") { return Ok(record(task)); }
            }
            let mut operations = vec![taskchampion::Operation::UndoPoint];
            for Attribute { key, value } in changes { task.update(key, value, &mut operations); }
            replica.commit_operations(operations).await.map_err(|e| e.to_string())?;
            Ok(record(task))
        }
        "synchronize" => {
            let config = request.configuration.ok_or("Missing synchronization configuration")?;
            let mut server = ServerConfig::Remote {
                url: config.server_url,
                client_id: config.client_id,
                encryption_secret: config.encryption_secret.into_bytes(),
            }.into_server().await.map_err(|e| e.to_string())?;
            let access = synchronization.as_ref().ok_or("Missing sync admission")?;
            tokio::select! {
                biased;
                result = access.interrupted() => { result?; Err("TSK_SYNC_INTERRUPTED".to_owned()) },
                result = replica.sync(&mut server, true) => {
                    result.map_err(|e| format!("{e:#}"))?;
                    Ok(json!(true))
                }
            }
        }
        _ => Err("Unsupported replica command".into()),
    }
}

fn record(task: TaskData) -> Value {
    json!({"id": task.get_uuid(), "attributes": task.iter().map(|(key, value)| json!({"key": key, "value": value})).collect::<Vec<_>>()})
}

#[no_mangle]
pub unsafe extern "C" fn tsk_tc_request(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if input.is_null() { return Err("Missing request".to_string()); }
        let input = CStr::from_ptr(input).to_str().map_err(|e| e.to_string())?;
        let request: Request = serde_json::from_str(input).map_err(|e| e.to_string())?;
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|e| e.to_string())?;
        runtime.block_on(execute(request))
    }).unwrap_or_else(|_| Err("TaskChampion aborted the operation".into()));
    let output = match result {
        Ok(value) => json!({"value": value}),
        Err(error) => json!({"error": error}),
    };
    CString::new(output.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn tsk_tc_free(output: *mut c_char) {
    if !output.is_null() { drop(CString::from_raw(output)); }
}

#[no_mangle]
pub unsafe extern "C" fn tsk_tc_interrupt_sync(path: *const c_char) -> i32 {
    if path.is_null() { return 0; }
    match CStr::from_ptr(path).to_str() {
        Ok(path) => i32::from(interrupt_sync(path).is_ok()),
        Err(_) => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tsk_tc_sync_generation(path: *const c_char) -> u64 {
    if path.is_null() { return 0; }
    match CStr::from_ptr(path).to_str() {
        Ok(path) => sync_generation(path).unwrap_or(0),
        Err(_) => 0,
    }
}
