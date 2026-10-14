use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::{Arc, Mutex, OnceLock};
use tokio::sync::Notify;
use taskchampion::{storage::{AccessMode, sqlite::SqliteStorage}, Replica, ServerConfig, TaskData};
use uuid::Uuid;


struct PathAdmission {
    locals: usize,
    generation: u64,
    synchronization: Option<Arc<Notify>>,
    available: Arc<Notify>,
}

impl Default for PathAdmission {
    fn default() -> Self {
        Self { locals: 0, generation: 0, synchronization: None, available: Arc::new(Notify::new()) }
    }
}

static ADMISSION: OnceLock<Mutex<HashMap<String, PathAdmission>>> = OnceLock::new();

fn admission() -> &'static Mutex<HashMap<String, PathAdmission>> {
    ADMISSION.get_or_init(|| Mutex::new(HashMap::new()))
}

struct LocalAccess(String);

impl LocalAccess {
    fn new(path: &str) -> Self {
        let mut paths = admission().lock().unwrap_or_else(|poison| poison.into_inner());
        let slot = paths.entry(path.to_owned()).or_default();
        slot.locals += 1;
        slot.generation += 1;
        if let Some(signal) = &slot.synchronization { signal.notify_one(); }
        Self(path.to_owned())
    }
}

impl Drop for LocalAccess {
    fn drop(&mut self) {
        let mut paths = admission().lock().unwrap_or_else(|poison| poison.into_inner());
        if let Some(slot) = paths.get_mut(&self.0) {
            slot.locals -= 1;
            if slot.locals == 0 { slot.available.notify_one(); }
        }
    }
}

struct SyncAccess {
    path: String,
    interrupted: Arc<Notify>,
}

impl SyncAccess {
    async fn new(path: &str, expected_generation: Option<u64>) -> Result<Self, String> {
        loop {
            let available = {
                let mut paths = admission().lock().unwrap_or_else(|poison| poison.into_inner());
                let slot = paths.entry(path.to_owned()).or_default();
                if expected_generation.is_some_and(|generation| generation != slot.generation) {
                    return Err("TSK_SYNC_INTERRUPTED".to_owned());
                }
                if slot.locals == 0 && slot.synchronization.is_none() {
                    let interrupted = Arc::new(Notify::new());
                    slot.synchronization = Some(interrupted.clone());
                    return Ok(Self { path: path.to_owned(), interrupted });
                }
                slot.available.clone()
            };
            available.notified().await;
        }
    }
}

impl Drop for SyncAccess {
    fn drop(&mut self) {
        let mut paths = admission().lock().unwrap_or_else(|poison| poison.into_inner());
        if let Some(slot) = paths.get_mut(&self.path) {
            slot.synchronization = None;
            slot.available.notify_one();
        }
    }
}

fn interrupt_sync(path: &str) -> bool {
    let mut paths = admission().lock().unwrap_or_else(|poison| poison.into_inner());
    let slot = paths.entry(path.to_owned()).or_default();
    slot.generation += 1;
    slot.available.notify_one();
    if let Some(signal) = &slot.synchronization {
        signal.notify_one();
        true
    } else { false }
}

fn sync_generation(path: &str) -> u64 {
    let mut paths = admission().lock().unwrap_or_else(|poison| poison.into_inner());
    paths.entry(path.to_owned()).or_default().generation
}

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
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncConfiguration {
    #[serde(rename = "serverURL")]
    server_url: String,
    #[serde(rename = "clientID")]
    client_id: Uuid,
    encryption_secret: String,
}

async fn execute(request: Request) -> Result<Value, String> {
    let synchronization = if request.command == "synchronize" { Some(SyncAccess::new(&request.path, request.sync_generation).await?) } else { None };
    let _local = if synchronization.is_none() { Some(LocalAccess::new(&request.path)) } else { None };
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
                _ = access.interrupted.notified() => Err("TSK_SYNC_INTERRUPTED".to_owned()),
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
        Ok(path) => i32::from(interrupt_sync(path)),
        Err(_) => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tsk_tc_sync_generation(path: *const c_char) -> u64 {
    if path.is_null() { return 0; }
    match CStr::from_ptr(path).to_str() {
        Ok(path) => sync_generation(path),
        Err(_) => 0,
    }
}
