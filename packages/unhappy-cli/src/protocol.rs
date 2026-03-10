use serde::{Deserialize, Serialize};

pub const MACHINE_DATA_PLANE_PROTOCOL_VERSION: u8 = 1;
pub const MACHINE_DATA_PLANE_SUBPROTOCOL: &str = "unhappy-machine-dp.v1";
pub const MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES: u32 = 262_144;
pub const MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS: u16 = 8;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum MachineDataPlaneRole {
    Native,
    Daemon,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneKeyExchange {
    pub algorithm: String,
    pub public_key: String,
    pub nonce: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneSealedBody {
    pub algorithm: String,
    pub nonce: String,
    pub ciphertext: String,
    pub tag: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum MachineDataPlaneOperation {
    #[serde(rename = "machine.listModels")]
    MachineListModels,
    #[serde(rename = "daemon.stop")]
    DaemonStop,
    #[serde(rename = "daemon.update")]
    DaemonUpdate,
    #[serde(rename = "provider.spawn")]
    ProviderSpawn,
    #[serde(rename = "project.list")]
    ProjectList,
    #[serde(rename = "project.sessions")]
    ProjectSessions,
    #[serde(rename = "project.open")]
    ProjectOpen,
    #[serde(rename = "project.remove")]
    ProjectRemove,
    #[serde(rename = "codex.listThreads")]
    CodexListThreads,
    #[serde(rename = "codex.archiveThread")]
    CodexArchiveThread,
    #[serde(rename = "codex.openThread")]
    CodexOpenThread,
    #[serde(rename = "codex.listMessages")]
    CodexListMessages,
    #[serde(rename = "codex.sendMessage")]
    CodexSendMessage,
    #[serde(rename = "claude.listSessions")]
    ClaudeListSessions,
    #[serde(rename = "claude.listMessages")]
    ClaudeListMessages,
    #[serde(rename = "claude.sendMessage")]
    ClaudeSendMessage,
    #[serde(rename = "gemini.listSessions")]
    GeminiListSessions,
    #[serde(rename = "gemini.listMessages")]
    GeminiListMessages,
    #[serde(rename = "gemini.sendMessage")]
    GeminiSendMessage,
    #[serde(rename = "fs.listDirectory")]
    FsListDirectory,
    #[serde(rename = "fs.getDirectoryTree")]
    FsGetDirectoryTree,
    #[serde(rename = "fs.readFile")]
    FsReadFile,
    #[serde(rename = "fs.writeFile")]
    FsWriteFile,
    #[serde(rename = "exec.bash")]
    ExecBash,
    #[serde(rename = "search.ripgrep")]
    SearchRipgrep,
    #[serde(rename = "diff.difftastic")]
    DiffDifftastic,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneHelloFrame {
    pub v: u8,
    pub t: String,
    pub connection_id: String,
    pub role: MachineDataPlaneRole,
    pub key_exchange: MachineDataPlaneKeyExchange,
    pub supports_chunk_ack: bool,
    pub supports_resume: bool,
    pub last_acked_stream_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneHelloAckFrame {
    pub v: u8,
    pub t: String,
    pub connection_id: String,
    pub session_id: String,
    pub key_exchange: MachineDataPlaneKeyExchange,
    pub max_chunk_bytes: u32,
    pub max_in_flight_streams: u16,
    pub idle_timeout_seconds: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneRequestFrame {
    pub v: u8,
    pub t: String,
    pub stream_id: String,
    pub op: MachineDataPlaneOperation,
    pub body: MachineDataPlaneSealedBody,
    pub expects_chunks: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneCompleteFrame {
    pub v: u8,
    pub t: String,
    pub stream_id: String,
    pub seq: u32,
    pub body: MachineDataPlaneSealedBody,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub has_more: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineDataPlaneErrorFrame {
    pub v: u8,
    pub t: String,
    pub stream_id: String,
    pub code: String,
    pub message: String,
    pub retryable: bool,
}
