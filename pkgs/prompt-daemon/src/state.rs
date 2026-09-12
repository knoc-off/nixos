use std::time::Duration;

use tokio::sync::RwLock;

use crate::cache::store::CacheStore;
use crate::config::schema::DaemonConfig;
use crate::scheduler::Scheduler;

/// Shared daemon state passed to each connection handler.
pub struct DaemonState {
    pub config: DaemonConfig,
    pub store: RwLock<CacheStore>,
    pub scheduler: Scheduler,
}

impl DaemonState {
    pub fn new(config: DaemonConfig, idle_timeout: Duration) -> Self {
        Self {
            config,
            store: RwLock::new(CacheStore::new()),
            scheduler: Scheduler::new(idle_timeout),
        }
    }
}
