use crate::{
    control_server::{ListChild, ProviderSessionStartedRequest, SpawnSessionRequest},
    provider::Provider,
    session_store::PersistedTrackedSession,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackedSession {
    started_by: String,
    provider: Option<Provider>,
    provider_session_id: Option<String>,
    pid: u32,
    metadata: Option<Value>,
}

impl TrackedSession {
    pub fn pending_spawn(pid: u32, request: &SpawnSessionRequest) -> Self {
        let mut metadata = serde_json::Map::new();
        metadata.insert(
            "directory".to_string(),
            Value::String(request.directory.clone()),
        );
        metadata.insert(
            "agent".to_string(),
            Value::String(request.agent.command_name().to_string()),
        );
        if let Some(value) = request
            .codex_resume_thread_id
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "codexResumeThreadId".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request
            .claude_resume_session_id
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "claudeResumeSessionId".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request
            .model
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert("model".to_string(), Value::String(value.trim().to_string()));
        }
        if let Some(value) = request
            .reasoning_effort
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "reasoningEffort".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request
            .codex_home_dir
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "codexHomeDir".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request
            .agent_session_id
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "agentSessionId".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request
            .agent_conversation_id
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "agentConversationId".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request
            .agent_transcript_path
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "agentTranscriptPath".to_string(),
                Value::String(value.trim().to_string()),
            );
        }
        if let Some(value) = request.agent_control_port {
            metadata.insert("agentControlPort".to_string(), Value::Number(value.into()));
        }
        if let Some(environment_variables) = request.environment_variables.as_ref() {
            let env_object = environment_variables.iter().fold(
                serde_json::Map::new(),
                |mut map, (key, value)| {
                    map.insert(key.clone(), Value::String(value.clone()));
                    map
                },
            );
            metadata.insert(
                "environmentVariables".to_string(),
                Value::Object(env_object),
            );
        }
        if let Some(token) = request
            .token
            .as_ref()
            .filter(|value| !value.trim().is_empty())
        {
            metadata.insert(
                "providerTokenPresent".to_string(),
                Value::Bool(!token.trim().is_empty()),
            );
        }

        Self {
            started_by: "daemon".to_string(),
            provider: Some(request.agent),
            provider_session_id: None,
            pid,
            metadata: Some(Value::Object(metadata)),
        }
    }

    pub fn from_provider_session_started(
        pid: u32,
        request: &ProviderSessionStartedRequest,
    ) -> Self {
        Self {
            started_by: extract_started_by(&request.metadata)
                .unwrap_or_else(|| "provider directly".to_string()),
            provider: Some(request.provider),
            provider_session_id: Some(request.provider_session_id.clone()),
            pid,
            metadata: Some(request.metadata.clone()),
        }
    }

    pub fn with_provider_session_started(
        self,
        pid: u32,
        request: &ProviderSessionStartedRequest,
    ) -> Self {
        let merged_metadata = merge_metadata(self.metadata, Some(request.metadata.clone()));
        Self {
            started_by: self.started_by,
            provider: Some(request.provider),
            provider_session_id: Some(request.provider_session_id.clone()),
            pid,
            metadata: merged_metadata,
        }
    }

    pub fn to_list_child(&self) -> Option<ListChild> {
        self.provider_session_id
            .as_ref()
            .map(|provider_session_id| ListChild {
                started_by: self.started_by.clone(),
                provider: self.provider,
                provider_session_id: provider_session_id.clone(),
                pid: self.pid,
                metadata: self.metadata.clone(),
            })
    }

    pub fn provider_session_id(&self) -> Option<&str> {
        self.provider_session_id.as_deref()
    }

    pub fn pid(&self) -> u32 {
        self.pid
    }

    pub fn to_persisted(&self) -> PersistedTrackedSession {
        PersistedTrackedSession {
            started_by: self.started_by.clone(),
            provider: self.provider,
            provider_session_id: self.provider_session_id.clone(),
            pid: self.pid,
            metadata: self.metadata.clone(),
        }
    }
}

impl From<PersistedTrackedSession> for TrackedSession {
    fn from(value: PersistedTrackedSession) -> Self {
        Self {
            started_by: value.started_by,
            provider: value.provider,
            provider_session_id: value.provider_session_id,
            pid: value.pid,
            metadata: value.metadata,
        }
    }
}

fn extract_started_by(metadata: &Value) -> Option<String> {
    metadata
        .get("startedBy")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

fn merge_metadata(existing: Option<Value>, incoming: Option<Value>) -> Option<Value> {
    match (existing, incoming) {
        (Some(Value::Object(mut existing_map)), Some(Value::Object(incoming_map))) => {
            for (key, value) in incoming_map {
                existing_map.insert(key, value);
            }
            Some(Value::Object(existing_map))
        }
        (None, incoming) => incoming,
        (existing, None) => existing,
        (_, incoming @ Some(_)) => incoming,
    }
}
