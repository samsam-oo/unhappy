use crate::config::Config;
use crate::protocol::{
    MachineDataPlaneHelloAckFrame, MachineDataPlaneHelloFrame, MachineDataPlaneKeyExchange,
    MachineDataPlaneRole, MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES,
    MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS, MACHINE_DATA_PLANE_PROTOCOL_VERSION,
    MACHINE_DATA_PLANE_SUBPROTOCOL,
};
use anyhow::{Context, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use futures_util::{SinkExt, StreamExt};
use hkdf::Hkdf;
use http::{header, Request};
use rand::RngCore;
use sha2::Sha256;
use tokio_tungstenite::{
    connect_async, tungstenite::protocol::Message, MaybeTlsStream, WebSocketStream,
};
use url::Url;
use uuid::Uuid;
use x25519_dalek::{PublicKey, StaticSecret};

pub type DataPlaneStream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

pub struct SessionCryptoContext {
    machine_data_key: [u8; 32],
    local_secret: StaticSecret,
    local_public: PublicKey,
    local_nonce: [u8; 32],
    role: MachineDataPlaneRole,
}

impl SessionCryptoContext {
    pub fn new(role: MachineDataPlaneRole, machine_data_key_base64url: &str) -> Result<Self> {
        let decoded = URL_SAFE_NO_PAD
            .decode(machine_data_key_base64url)
            .context("invalid UNHAPPY_MACHINE_DATA_KEY base64url")?;
        let machine_data_key: [u8; 32] = decoded
            .try_into()
            .map_err(|_| anyhow::anyhow!("UNHAPPY_MACHINE_DATA_KEY must decode to 32 bytes"))?;

        let mut local_nonce = [0_u8; 32];
        rand::thread_rng().fill_bytes(&mut local_nonce);
        let local_secret = StaticSecret::random_from_rng(rand::thread_rng());
        let local_public = PublicKey::from(&local_secret);

        Ok(Self {
            machine_data_key,
            local_secret,
            local_public,
            local_nonce,
            role,
        })
    }

    pub fn hello_frame(&self) -> MachineDataPlaneHelloFrame {
        MachineDataPlaneHelloFrame {
            v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
            t: "hello".to_string(),
            connection_id: Uuid::new_v4().to_string(),
            role: self.role,
            key_exchange: MachineDataPlaneKeyExchange {
                algorithm: "x25519-hkdf-sha256".to_string(),
                public_key: URL_SAFE_NO_PAD.encode(self.local_public.as_bytes()),
                nonce: URL_SAFE_NO_PAD.encode(self.local_nonce),
            },
            supports_chunk_ack: true,
            supports_resume: true,
            last_acked_stream_id: None,
        }
    }

    pub fn derive_session_key(&self, peer: &MachineDataPlaneKeyExchange) -> Result<[u8; 32]> {
        let peer_public_bytes = URL_SAFE_NO_PAD
            .decode(&peer.public_key)
            .context("invalid peer public key")?;
        let peer_nonce = URL_SAFE_NO_PAD
            .decode(&peer.nonce)
            .context("invalid peer nonce")?;

        let peer_public_array: [u8; 32] = peer_public_bytes
            .try_into()
            .map_err(|_| anyhow::anyhow!("peer public key must be 32 bytes"))?;
        let peer_nonce_array: [u8; 32] = peer_nonce
            .try_into()
            .map_err(|_| anyhow::anyhow!("peer nonce must be 32 bytes"))?;

        let shared_secret = self
            .local_secret
            .diffie_hellman(&PublicKey::from(peer_public_array));

        let mut ikm = Vec::with_capacity(64);
        ikm.extend_from_slice(shared_secret.as_bytes());
        ikm.extend_from_slice(&self.machine_data_key);

        let mut salt = Vec::with_capacity(64);
        match self.role {
            MachineDataPlaneRole::Native => {
                salt.extend_from_slice(&self.local_nonce);
                salt.extend_from_slice(&peer_nonce_array);
            }
            MachineDataPlaneRole::Daemon => {
                salt.extend_from_slice(&peer_nonce_array);
                salt.extend_from_slice(&self.local_nonce);
            }
        }

        let hk = Hkdf::<Sha256>::new(Some(&salt), &ikm);
        let mut output = [0_u8; 32];
        hk.expand(b"unhappy.machine-data-plane.session.v1", &mut output)
            .map_err(|_| anyhow::anyhow!("failed to derive session key"))?;
        Ok(output)
    }
}

pub async fn connect_and_handshake(config: &Config) -> Result<()> {
    let mut url = Url::parse(&config.server_url).context("invalid server url")?;
    match url.scheme() {
        "https" => url.set_scheme("wss").ok(),
        "http" => url.set_scheme("ws").ok(),
        "ws" | "wss" => Some(()),
        _ => None,
    };
    url.set_path(&format!("/v1/machines/{}/data-plane", config.machine_id));
    url.set_query(None);

    let request = Request::builder()
        .method("GET")
        .uri(url.as_str())
        .header(header::AUTHORIZATION, format!("Bearer {}", config.token))
        .header(
            header::SEC_WEBSOCKET_PROTOCOL,
            MACHINE_DATA_PLANE_SUBPROTOCOL,
        )
        .body(())
        .context("failed to build websocket request")?;

    let (mut socket, _) = connect_async(request)
        .await
        .context("failed to connect to machine data plane websocket")?;

    let crypto = SessionCryptoContext::new(
        MachineDataPlaneRole::Daemon,
        &config.machine_data_key_base64url,
    )?;
    let hello = crypto.hello_frame();
    socket
        .send(Message::Text(serde_json::to_string(&hello)?.into()))
        .await
        .context("failed to send hello frame")?;

    let next = socket.next().await.context("missing hello-ack frame")??;
    let ack = match next {
        Message::Text(text) => serde_json::from_str::<MachineDataPlaneHelloAckFrame>(&text)
            .context("failed to decode hello-ack frame")?,
        other => {
            return Err(anyhow::anyhow!(
                "unexpected websocket frame during handshake: {other:?}"
            ))
        }
    };

    let _session_key = crypto
        .derive_session_key(&ack.key_exchange)
        .context("failed to derive session key from hello-ack")?;

    if ack.max_chunk_bytes != MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES
        || ack.max_in_flight_streams != MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS
    {
        eprintln!(
            "warning: server advertised max_chunk_bytes={} max_in_flight_streams={}",
            ack.max_chunk_bytes, ack.max_in_flight_streams
        );
    }

    println!(
        "connected data plane session {} for machine {}",
        ack.session_id, config.machine_id
    );
    Ok(())
}
