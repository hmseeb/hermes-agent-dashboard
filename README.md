# Hermes Agent (w/ Dashboard) — Railway Template

Deploy [Hermes Agent](https://github.com/NousResearch/hermes-agent) by [Nous Research](https://nousresearch.com/) on Railway: the gateway your messaging bots talk to, plus the official Hermes web dashboard, password protected, on your own domain.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/hermes-agent-w-dashboard)

## What this template does differently

It runs the **official `nousresearch/hermes-agent` image** unmodified except for three Railway-specific fixes, and turns on the dashboard that image already supervises.

- No source build. Deploys are fast and cannot break on an upstream dependency pin.
- The dashboard (Chat, Keys, Skills, Kanban, Analytics, Console) is served on your Railway domain behind HTTP basic auth, using Hermes' own auth gate. There is no custom admin server in front of it.
- The gateway and the dashboard are supervised by the image's own s6 tree, so a dashboard crash is restarted in place and a gateway crash restarts the container.

## Deploy

1. Click **Deploy on Railway**.
2. Provide an inference provider key. `OPENROUTER_API_KEY` is the default; a free key from [OpenRouter](https://openrouter.ai/keys) works.
3. Provide at least one messaging platform token, for example `TELEGRAM_BOT_TOKEN` from [@BotFather](https://t.me/BotFather).
4. Deploy, then open the service domain. You land on a login page; sign in as `admin` with the generated `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` (Variables tab).
5. Message your bot. Approve the pairing request from the dashboard, or set `TELEGRAM_ALLOWED_USERS` to your numeric Telegram ID (from [@userinfobot](https://t.me/userinfobot)).

## Variables

| Variable | Default | Description |
|---|---|---|
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` | `admin` | Dashboard login user |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` | generated | Dashboard login password. Clearing it does not open the dashboard up, it stops the dashboard from starting. |
| `HERMES_DASHBOARD_BASIC_AUTH_SECRET` | generated | Session cookie signing key. Keeps you logged in across restarts. |
| `HERMES_DASHBOARD_PUBLIC_URL` | your Railway domain | Origin Hermes builds OAuth redirect URIs from |
| `OPENROUTER_API_KEY` | prompted | Or any other provider key Hermes supports |
| `TELEGRAM_BOT_TOKEN` | prompted | Discord, Slack, Matrix and the rest work the same way |
| `TELEGRAM_ALLOWED_USERS` | empty | Comma separated numeric IDs, no brackets or quotes |

Every other Hermes variable is passed straight through from Railway. See the [upstream reference](https://github.com/NousResearch/hermes-agent); this template does not duplicate it.

## Upgrading

Change the `HERMES_IMAGE_VERSION` build argument (default `v2026.9.14`) and redeploy. Do not run `hermes update` inside the container: the image is immutable, so the change disappears on the next deploy while your persisted config stays ahead of the code.

## Persistence

A single volume is mounted at `/opt/data`, which is the image's own `HERMES_HOME`. It holds `config.yaml`, credentials, sessions, `state.db`, memories, skills and pairing state, and survives redeploys.

## Local run

```bash
docker build -t hermes-dashboard .
docker run --rm -p 8080:8080 -v hermes-data:/opt/data \
  -e HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin \
  -e HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=changeme \
  -e OPENROUTER_API_KEY=sk-... \
  -e TELEGRAM_BOT_TOKEN=... \
  hermes-dashboard
```

`test/contract.sh` runs the checks this template is verified against.

## Credits

[Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.
