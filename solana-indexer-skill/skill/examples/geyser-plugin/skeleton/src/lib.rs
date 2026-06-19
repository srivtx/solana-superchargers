// src/lib.rs — Custom Geyser plugin that forwards account updates to Postgres
// Build: cargo build --release
// The resulting libmy_geyser_indexer.so is loaded by the Solana validator

use solana_geyser_plugin_interface::geyser_plugin_interface::{
    GeyserPlugin, GeyserPluginError, ReplicaAccountInfoVersions, ReplicaBlockInfoVersions,
    ReplicaTransactionInfoVersions,
};
use std::sync::Arc;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;
use tracing::{error, info};

/// The plugin struct. Holds a tokio runtime for async I/O.
/// The receiver for the event channel lives in the writer task.
#[derive(Debug)]
pub struct MyGeyserIndexer {
    runtime: Arc<Runtime>,
    tx: mpsc::UnboundedSender<PluginEvent>,
}

/// Events extracted from the validator. Sent to the background writer for
/// batching into Postgres.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type")]
pub enum PluginEvent {
    AccountUpdate {
        pubkey: String,
        owner: String,
        lamports: u64,
        slot: u64,
        data: Vec<u8>,
    },
    Transaction {
        signature: String,
        slot: u64,
        success: bool,
    },
    BlockMeta {
        slot: u64,
        blockhash: String,
    },
}

impl GeyserPlugin for MyGeyserIndexer {
    fn name(&self) -> &'static str {
        "my-geyser-indexer"
    }

    fn on_load(
        &mut self,
        config_file: &str,
        _is_reload: bool,
    ) -> Result<(), GeyserPluginError> {
        info!("loading my-geyser-indexer, config: {}", config_file);

        // Create the receiver here; the sender is held by the plugin.
        // We need a NEW channel since the original one was used to construct us.
        let (tx, rx) = mpsc::unbounded_channel::<PluginEvent>();
        self.tx = tx;

        // Spawn the background writer with the receiver
        let runtime = self.runtime.clone();
        runtime.spawn(async move {
            if let Err(e) = run_writer(rx).await {
                error!(error = %e, "writer task failed");
            }
        });

        Ok(())
    }

    fn on_unload(&mut self) {
        info!("unloading my-geyser-indexer");
        // Sender is dropped here; writer task sees channel closed and exits
    }

    fn notify_end_of_startup(&self) -> Result<(), GeyserPluginError> {
        info!("startup complete, ready to serve live data");
        Ok(())
    }

    fn update_account(
        &self,
        account: ReplicaAccountInfoVersions,
        slot: u64,
        is_startup: bool,
    ) -> Result<(), GeyserPluginError> {
        // CRITICAL: skip startup snapshot replay
        if is_startup {
            return Ok(());
        }

        let (pubkey, owner, lamports, data) = match account {
            ReplicaAccountInfoVersions::V0_0_1(a) => {
                (a.pubkey.to_vec(), a.owner.to_vec(), a.lamports, a.data.to_vec())
            }
            ReplicaAccountInfoVersions::V0_0_2(a) => {
                (a.pubkey.to_vec(), a.owner.to_vec(), a.lamports, a.data.to_vec())
            }
            ReplicaAccountInfoVersions::V0_0_3(a) => {
                (a.pubkey.to_vec(), a.owner.to_vec(), a.lamports, a.data.to_vec())
            }
        };
        let _ = self.tx.send(PluginEvent::AccountUpdate {
            pubkey: bs58::encode(pubkey).into_string(),
            owner: bs58::encode(owner).into_string(),
            lamports,
            slot,
            data,
        });
        Ok(())
    }

    fn notify_transaction(
        &self,
        transaction: ReplicaTransactionInfoVersions,
        slot: u64,
    ) -> Result<(), GeyserPluginError> {
        let (signature, is_vote) = match transaction {
            ReplicaTransactionInfoVersions::V0_0_1(t) => (t.signature.as_ref(), t.is_vote),
            ReplicaTransactionInfoVersions::V0_0_2(t) => (t.signature.as_ref(), t.is_vote),
        };
        let _ = self.tx.send(PluginEvent::Transaction {
            signature: bs58::encode(signature).into_string(),
            slot,
            success: !is_vote,
        });
        Ok(())
    }

    fn notify_block_metadata(
        &self,
        blockinfo: ReplicaBlockInfoVersions,
    ) -> Result<(), GeyserPluginError> {
        let (slot, blockhash) = match blockinfo {
            ReplicaBlockInfoVersions::V0_0_1(b) => (b.slot, b.blockhash.to_string()),
            ReplicaBlockInfoVersions::V0_0_2(b) => (b.slot, b.blockhash.to_string()),
            ReplicaBlockInfoVersions::V0_0_3(b) => (b.slot, b.blockhash.to_string()),
        };
        let _ = self.tx.send(PluginEvent::BlockMeta { slot, blockhash });
        Ok(())
    }

    fn account_data_notifications_enabled(&self) -> bool { true }
    fn transaction_notifications_enabled(&self) -> bool { true }
}

// ─── background writer ────────────────────────────────────────────────
async fn run_writer(mut rx: mpsc::UnboundedReceiver<PluginEvent>) -> anyhow::Result<()> {
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost/geyser".into());

    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS accounts (
          pubkey    BYTEA PRIMARY KEY,
          owner     BYTEA NOT NULL,
          lamports  BIGINT NOT NULL,
          slot      BIGINT NOT NULL,
          data      BYTEA,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE IF NOT EXISTS transactions (
          signature BYTEA PRIMARY KEY,
          slot      BIGINT NOT NULL,
          success   BOOLEAN NOT NULL,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        "#,
    )
    .execute(&pool)
    .await?;

    let mut buf: Vec<PluginEvent> = Vec::with_capacity(1000);

    while let Some(first) = rx.recv().await {
        buf.push(first);
        while let Ok(e) = rx.try_recv() {
            buf.push(e);
            if buf.len() >= 1000 { break; }
        }
        if let Err(e) = flush_batch(&pool, &mut buf).await {
            error!(error = %e, "flush failed");
        }
    }
    Ok(())
}

async fn flush_batch(pool: &sqlx::PgPool, buf: &mut Vec<PluginEvent>) -> anyhow::Result<()> {
    let mut accounts: Vec<(Vec<u8>, Vec<u8>, i64, i64, Vec<u8>)> = Vec::new();
    let mut transactions: Vec<(Vec<u8>, i64, bool)> = Vec::new();

    for ev in buf.drain(..) {
        match ev {
            PluginEvent::AccountUpdate { pubkey, owner, lamports, slot, data } => {
                let pk = bs58::decode(pubkey).into_vec().unwrap_or_default();
                let ow = bs58::decode(owner).into_vec().unwrap_or_default();
                accounts.push((pk, ow, lamports as i64, slot as i64, data));
            }
            PluginEvent::Transaction { signature, slot, success } => {
                let sig = bs58::decode(signature).into_vec().unwrap_or_default();
                transactions.push((sig, slot as i64, success));
            }
            PluginEvent::BlockMeta { .. } => {}
        }
    }

    if !accounts.is_empty() {
        let pk_refs: Vec<&[u8]> = accounts.iter().map(|(p,_,_,_,_)| p.as_slice()).collect();
        let ow_refs: Vec<&[u8]> = accounts.iter().map(|(_,o,_,_,_)| o.as_slice()).collect();
        let data_refs: Vec<Option<&[u8]>> = accounts.iter().map(|(_,_,_,_,d)| Some(d.as_slice())).collect();
        let lams: Vec<i64> = accounts.iter().map(|(_,_,l,_,_)| *l).collect();
        let slots: Vec<i64> = accounts.iter().map(|(_,_,_,s,_)| *s).collect();

        sqlx::query(
            r#"
            INSERT INTO accounts (pubkey, owner, lamports, slot, data)
            SELECT * FROM UNNEST($1::bytea[], $2::bytea[], $3::bigint[], $4::bigint[], $5::bytea[])
            ON CONFLICT (pubkey) DO UPDATE SET
              owner = EXCLUDED.owner,
              lamports = EXCLUDED.lamports,
              slot = EXCLUDED.slot,
              data = EXCLUDED.data,
              updated_at = now()
            WHERE accounts.slot < EXCLUDED.slot
            "#,
        )
        .bind(&pk_refs)
        .bind(&ow_refs)
        .bind(&lams)
        .bind(&slots)
        .bind(&data_refs)
        .execute(pool)
        .await?;
    }

    if !transactions.is_empty() {
        let sig_refs: Vec<&[u8]> = transactions.iter().map(|(s,_,_)| s.as_slice()).collect();
        let slots: Vec<i64> = transactions.iter().map(|(_,s,_)| *s).collect();
        let successes: Vec<bool> = transactions.iter().map(|(_,_,s)| *s).collect();

        sqlx::query(
            r#"
            INSERT INTO transactions (signature, slot, success)
            SELECT * FROM UNNEST($1::bytea[], $2::bigint[], $3::boolean[])
            ON CONFLICT (signature) DO NOTHING
            "#,
        )
        .bind(&sig_refs)
        .bind(&slots)
        .bind(&successes)
        .execute(pool)
        .await?;
    }

    Ok(())
}

// ─── entry point ───────────────────────────────────────────────────────
// This is the entry point for the Geyser plugin. The validator loads the
// compiled .so and calls this function to get the plugin instance.
//
// In your validator config:
//   {
//     "libpath": "/path/to/libmy_geyser_indexer.so",
//     "name": "my-geyser-indexer",
//     "config_file": "/path/to/config.json"
//   }

#[no_mangle]
pub unsafe extern "C" fn _create_plugin() -> *mut dyn GeyserPlugin {
    let runtime = Arc::new(
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .expect("failed to build tokio runtime"),
    );
    // Dummy channel; the real one is created in on_load
    let (tx, _rx) = mpsc::unbounded_channel::<PluginEvent>();
    let plugin = MyGeyserIndexer { runtime, tx };
    let boxed: Box<dyn GeyserPlugin> = Box::new(plugin);
    Box::into_raw(boxed)
}
