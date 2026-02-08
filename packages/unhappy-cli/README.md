# Unhappy

Code on the go — control AI coding agents from your mobile device.

Free. Open source. Code anywhere.

## Installation

```bash
npm install -g unhappy-coder
```

## Usage

### Claude (default)

```bash
unhappy
```

This will:

1. Start a Claude Code session
2. Display a QR code to connect from your mobile device
3. Allow real-time session sharing between Claude Code and your mobile app

### Gemini

```bash
unhappy gemini
```

Start a Gemini CLI session with remote control capabilities.

**First time setup:**

```bash
# Authenticate with Google
unhappy connect gemini
```

## Commands

### Main Commands

- `unhappy` – Start Claude Code session (default)
- `unhappy gemini` – Start Gemini CLI session
- `unhappy codex` – Start Codex mode

### Utility Commands

- `unhappy auth` – Manage authentication
- `unhappy connect` – Store AI vendor API keys in Unhappy cloud
- `unhappy notify` – Send a push notification to your devices
- `unhappy daemon` – Manage background service
- `unhappy doctor` – System diagnostics & troubleshooting

### Connect Subcommands

```bash
unhappy connect gemini     # Authenticate with Google for Gemini
unhappy connect claude     # Authenticate with Anthropic
unhappy connect codex      # Authenticate with OpenAI
unhappy connect status     # Show connection status for all vendors
```

### Gemini Subcommands

```bash
unhappy gemini                      # Start Gemini session
unhappy gemini model set <model>    # Set default model
unhappy gemini model get            # Show current model
unhappy gemini project set <id>     # Set Google Cloud Project ID (for Workspace accounts)
unhappy gemini project get          # Show current Google Cloud Project ID
```

**Available models:** `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`

## Options

### Claude Options

- `-m, --model <model>` - Claude model to use (default: sonnet)
- `-p, --permission-mode <mode>` - Permission mode: auto, default, or plan
- `--claude-env KEY=VALUE` - Set environment variable for Claude Code
- `--claude-arg ARG` - Pass additional argument to Claude CLI

### Global Options

- `-h, --help` - Show help
- `-v, --version` - Show version

## Environment Variables

### Unhappy Configuration

- `UNHAPPY_SERVER_URL` - Custom server URL (default: https://api.unhappy.im)
- `UNHAPPY_WEBAPP_URL` - Custom web app URL (default: https://app.happy.engineering)
- `UNHAPPY_HOME_DIR` - Custom home directory for Unhappy data (default: ~/.unhappy)
- `UNHAPPY_DISABLE_CAFFEINATE` - Disable macOS sleep prevention (set to `true`, `1`, or `yes`)
- `UNHAPPY_EXPERIMENTAL` - Enable experimental features (set to `true`, `1`, or `yes`)

### Gemini Configuration

- `GEMINI_MODEL` - Override default Gemini model
- `GOOGLE_CLOUD_PROJECT` - Google Cloud Project ID (required for Workspace accounts)

## Gemini Authentication

### Personal Google Account

Personal Gmail accounts work out of the box:

```bash
unhappy connect gemini
unhappy gemini
```

### Google Workspace Account

Google Workspace (organization) accounts require a Google Cloud Project:

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the Gemini API
3. Set the project ID:

```bash
unhappy gemini project set your-project-id
```

Or use environment variable:

```bash
GOOGLE_CLOUD_PROJECT=your-project-id unhappy gemini
```

**Guide:** https://goo.gle/gemini-cli-auth-docs#workspace-gca

## Contributing

Interested in contributing? See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## Requirements

- Node.js >= 20.0.0

### For Claude

- Claude CLI installed & logged in (`claude` command available in PATH)

### For Gemini

- Gemini CLI installed (`npm install -g @google/gemini-cli`)
- Google account authenticated via `unhappy connect gemini`

## License

MIT
