use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use taskchampion::{storage::{AccessMode, sqlite::SqliteStorage}, Replica, TaskData};
use uuid::Uuid;

#[derive(Deserialize)]
struct Request {
    path: String,
    command: String,
    id: Option<Uuid>,
    attributes: Option<HashMap<String, String>>,
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
        let runtime = tokio::runtime::Builder::new_current_thread().build().map_err(|e| e.to_string())?;
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
