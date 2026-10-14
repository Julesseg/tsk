use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::time::Duration;

const INTERRUPTED: &str = "TSK_SYNC_INTERRUPTED";

struct FileLock(File);

impl FileLock {
    fn open(path: &Path) -> Result<Self, String> {
        let file = OpenOptions::new().read(true).write(true).create(true).truncate(false).open(path).map_err(|e| e.to_string())?;
        Ok(Self(file))
    }

    fn try_lock(&self, mode: i32) -> Result<bool, String> {
        if unsafe { libc::flock(self.0.as_raw_fd(), mode | libc::LOCK_NB) } == 0 { return Ok(true); }
        let error = std::io::Error::last_os_error();
        if error.kind() == std::io::ErrorKind::WouldBlock { Ok(false) } else { Err(error.to_string()) }
    }

    fn lock(&self, mode: i32) -> Result<(), String> {
        while !self.try_lock(mode)? { std::thread::sleep(Duration::from_millis(5)); }
        Ok(())
    }
}

impl Drop for FileLock {
    fn drop(&mut self) { unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN); } }
}

fn directory(path: &str) -> Result<PathBuf, String> {
    fs::create_dir_all(path).map_err(|e| e.to_string())?;
    fs::canonicalize(path).map_err(|e| e.to_string())
}

fn generation_at(path: &Path, advance: bool) -> Result<u64, String> {
    let mut lock = FileLock::open(&path.join(".tsk-sync-generation"))?;
    lock.lock(libc::LOCK_EX)?;
    let mut bytes = [0; 8];
    let count = lock.0.read(&mut bytes).map_err(|e| e.to_string())?;
    if count != 0 && count != 8 { return Err("Invalid synchronization coordination state".into()); }
    let value = u64::from_le_bytes(bytes);
    if !advance { return Ok(value); }
    let value = value.wrapping_add(1);
    lock.0.seek(SeekFrom::Start(0)).map_err(|e| e.to_string())?;
    lock.0.write_all(&value.to_le_bytes()).map_err(|e| e.to_string())?;
    lock.0.sync_all().map_err(|e| e.to_string())?;
    Ok(value)
}

pub struct LocalAccess {
    _priority: FileLock,
    _operation: FileLock,
}

impl LocalAccess {
    pub fn new(path: &str) -> Result<Self, String> {
        let path = directory(path)?;
        let priority = FileLock::open(&path.join(".tsk-local-priority"))?;
        priority.lock(libc::LOCK_SH)?;
        generation_at(&path, true)?;
        let operation = FileLock::open(&path.join(".tsk-operation"))?;
        operation.lock(libc::LOCK_EX)?;
        Ok(Self { _priority: priority, _operation: operation })
    }
}

pub struct SyncAccess {
    path: PathBuf,
    generation: u64,
    _operation: FileLock,
}

impl SyncAccess {
    pub async fn new(path: &str, expected: Option<u64>) -> Result<Self, String> {
        let path = directory(path)?;
        let generation = expected.unwrap_or(generation_at(&path, false)?);
        loop {
            if generation_at(&path, false)? != generation { return Err(INTERRUPTED.into()); }
            let priority = FileLock::open(&path.join(".tsk-local-priority"))?;
            if priority.try_lock(libc::LOCK_EX)? {
                let operation = FileLock::open(&path.join(".tsk-operation"))?;
                if operation.try_lock(libc::LOCK_EX)? {
                    if generation_at(&path, false)? != generation { return Err(INTERRUPTED.into()); }
                    return Ok(Self { path, generation, _operation: operation });
                }
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }

    pub async fn interrupted(&self) -> Result<(), String> {
        loop {
            if generation_at(&self.path, false)? != self.generation { return Ok(()); }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }
}

pub fn interrupt_sync(path: &str) -> Result<(), String> {
    generation_at(&directory(path)?, true).map(|_| ())
}

pub fn sync_generation(path: &str) -> Result<u64, String> {
    generation_at(&directory(path)?, false)
}

pub struct SemanticAccess { _lock: FileLock }

impl SemanticAccess {
    pub fn new(path: &str) -> Result<Self, String> {
        let path = directory(path)?;
        let lock = FileLock::open(&path.join(".tsk-semantic-mutation"))?;
        lock.lock(libc::LOCK_EX)?;
        Ok(Self { _lock: lock })
    }
}
