# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- If a change touches server code that needs to be deployed or rebuilt remotely, merge the working branch into `main` and push `main` after verification.
- If a change touches daemon code or daemon-facing CLI runtime/control paths, reinstall `unhappy-cli` globally and restart the daemon with `unhappy daemon start`, then confirm status.
