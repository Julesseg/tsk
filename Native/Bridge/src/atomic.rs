use async_trait::async_trait;
use taskchampion::{storage::{Storage, StorageTxn, TaskMap, sqlite::SqliteStorage}, Error, Replica};
use uuid::Uuid;
use crate::{Attribute, record};
use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
pub struct Update {
    id: Uuid,
    expected: Vec<Attribute<String>>,
    changes: Vec<Attribute<Option<String>>>,
}

#[derive(Deserialize)]
pub struct Create {
    id: Uuid,
    attributes: Vec<Attribute<String>>,
}

#[derive(Deserialize)]
pub struct SnapshotRecord {
    id: Uuid,
    attributes: Vec<Attribute<String>>,
}

struct GuardedStorage {
    inner: SqliteStorage,
    expected: Vec<(Uuid, TaskMap)>,
    snapshot: Option<std::collections::HashMap<Uuid, TaskMap>>,
}

#[async_trait]
impl Storage for GuardedStorage {
    async fn txn<'a>(&'a mut self) -> Result<Box<dyn StorageTxn + Send + 'a>, Error> {
        let mut transaction = self.inner.txn().await?;
        if let Some(expected) = &self.snapshot {
            let actual: std::collections::HashMap<_, _> = transaction.all_tasks().await?.into_iter().collect();
            if &actual != expected { return Err(Error::Database("Tasks changed after the series preview. Preview again before saving.".into())); }
        }
        for (id, expected) in &self.expected {
            if transaction.get_task(*id).await?.as_ref() != Some(expected) {
                return Err(Error::Database("Tasks changed while this action was being saved. Reopen the task and retry.".into()));
            }
        }
        Ok(transaction)
    }
}

pub async fn update(storage: SqliteStorage, updates: Vec<Update>, snapshot: Option<Vec<SnapshotRecord>>, creates: Vec<Create>) -> Result<Value, String> {
    if updates.is_empty() && creates.is_empty() { return Err("Missing atomic mutations".into()); }
    let mut identities = std::collections::HashSet::new();
    if updates.iter().any(|update| !identities.insert(update.id)) { return Err("Duplicate atomic task identity".into()); }
    if creates.iter().any(|create| !identities.insert(create.id)) { return Err("Duplicate atomic task identity".into()); }
    if !creates.is_empty() && snapshot.is_none() { return Err("Atomic creation requires a complete snapshot".into()); }
    let expected = updates.iter().map(|update| (update.id, update.expected.iter().map(|attribute| (attribute.key.clone(), attribute.value.clone())).collect())).collect();
    let with_snapshot = snapshot.is_some();
    let snapshot = snapshot.map(|records| records.into_iter().map(|record| (record.id, record.attributes.into_iter().map(|attribute| (attribute.key, attribute.value)).collect())).collect());
    let mut replica = Replica::new(GuardedStorage { inner: storage, expected, snapshot });
    let mut tasks = if with_snapshot { Some(replica.all_task_data().await.map_err(|e| e.to_string())?) } else { None };
    let mut operations = vec![taskchampion::Operation::UndoPoint];
    let mut saved = Vec::new();
    for create in creates {
        if tasks.as_ref().map(|tasks| tasks.contains_key(&create.id)).unwrap_or(true) { return Err("Task identity already exists".into()); }
        let mut task = taskchampion::TaskData::create(create.id, &mut operations);
        for Attribute { key, value } in create.attributes { task.update(key, Some(value), &mut operations); }
        saved.push(record(task));
    }
    for update in updates {
        let mut task = match tasks.as_mut() {
            Some(tasks) => tasks.remove(&update.id),
            None => replica.get_task_data(update.id).await.map_err(|e| e.to_string())?,
        }.ok_or("Task no longer exists")?;
        for Attribute { key, value } in update.changes { task.update(key, value, &mut operations); }
        saved.push(record(task));
    }
    replica.commit_operations(operations).await.map_err(|e| e.to_string())?;
    Ok(serde_json::json!(saved))
}
