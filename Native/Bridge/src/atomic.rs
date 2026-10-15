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

struct GuardedStorage {
    inner: SqliteStorage,
    expected: Vec<(Uuid, TaskMap)>,
}

#[async_trait]
impl Storage for GuardedStorage {
    async fn txn<'a>(&'a mut self) -> Result<Box<dyn StorageTxn + Send + 'a>, Error> {
        let mut transaction = self.inner.txn().await?;
        for (id, expected) in &self.expected {
            if transaction.get_task(*id).await?.as_ref() != Some(expected) {
                return Err(Error::Database("Tasks changed while this action was being saved. Reopen the task and retry.".into()));
            }
        }
        Ok(transaction)
    }
}

pub async fn update(storage: SqliteStorage, updates: Vec<Update>) -> Result<Value, String> {
    if updates.is_empty() { return Err("Missing atomic updates".into()); }
    let mut identities = std::collections::HashSet::new();
    if updates.iter().any(|update| !identities.insert(update.id)) { return Err("Duplicate atomic task identity".into()); }
    let expected = updates.iter().map(|update| (update.id, update.expected.iter().map(|attribute| (attribute.key.clone(), attribute.value.clone())).collect())).collect();
    let mut replica = Replica::new(GuardedStorage { inner: storage, expected });
    let mut operations = vec![taskchampion::Operation::UndoPoint];
    let mut saved = Vec::new();
    for update in updates {
        let mut task = replica.get_task_data(update.id).await.map_err(|e| e.to_string())?.ok_or("Task no longer exists")?;
        for Attribute { key, value } in update.changes { task.update(key, value, &mut operations); }
        saved.push(record(task));
    }
    replica.commit_operations(operations).await.map_err(|e| e.to_string())?;
    Ok(serde_json::json!(saved))
}
