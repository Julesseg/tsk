use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use taskchampion::{storage::{AccessMode, sqlite::SqliteStorage}, Replica, ServerConfig, TaskData};
use uuid::Uuid;

#[derive(Deserialize)]
struct Request {
    path: String,
    command: String,
    id: Option<Uuid>,
    attributes: Option<HashMap<String, String>>,
    changes: Option<HashMap<String, Option<String>>>,
    configuration: Option<SyncConfiguration>,
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
            for (key, value) in request.attributes.ok_or("Missing attributes")? {
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
            if changes.keys().any(|key| ["uuid", "id", "entry", "recur", "parent", "mask", "imask"].contains(&key.as_str())) {
                return Err("Reserved task attribute cannot be changed by this action".into());
            }
            if let Some(status) = changes.get("status") {
                if status.as_deref() != Some("completed") { return Err("Unsupported status transition".into()); }
                if task.get("status") == Some("completed") { return Ok(record(task)); }
            }
            let mut operations = vec![taskchampion::Operation::UndoPoint];
            for (key, value) in changes { task.update(key, value, &mut operations); }
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
            replica.sync(&mut server, true).await.map_err(|e| format!("{e:#}"))?;
            Ok(json!(true))
        }
        _ => Err("Unsupported replica command".into()),
    }
}

fn record(task: TaskData) -> Value {
    json!({"id": task.get_uuid(), "attributes": task.iter().collect::<HashMap<_, _>>()})
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
