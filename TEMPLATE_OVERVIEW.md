# Deploy and Host Hermes Agent on Railway

Hermes Agent is an autonomous AI agent by Nous Research that lives on your own server, connects to your messaging channels, and keeps its memory, skills and history on disk between conversations. This template runs the official Hermes image and also serves the Hermes web dashboard on your Railway domain, behind a login.

## About Hosting Hermes Agent

Hermes runs as a long-lived gateway process that connects out to Telegram, Discord, Slack, Matrix and the other platforms it supports, and answers the people you allow. There is no inbound webhook to configure. Alongside the gateway, the official image can supervise the Hermes dashboard, a web UI with chat, provider keys, skills, a kanban board, analytics and a console.

This template deploys one container carrying both. The gateway is the container's main process, so if it dies Railway restarts the deployment. The dashboard runs beside it under the image's own s6 supervisor, so a dashboard crash is restarted in place without touching the agent. All state lives on a Railway volume mounted at the image's own data directory, so redeploys and version bumps keep your history, memories, credentials and pairing decisions.

The dashboard is protected by Hermes' own auth gate. A username and a generated password are set for you at deploy time, anonymous visitors get a login page, and the session cookie signing key is generated per deployment so logins survive restarts.

## Common Use Cases

- A personal assistant in Telegram or Discord that remembers context across days and can run tools on its own server
- A shared team agent in Slack that reads links, writes summaries and keeps a working memory of a project
- A long-running automation agent with scheduled jobs, reachable from chat, with a web console for inspection

## Dependencies for Hermes Agent Hosting

- An inference provider key. OpenRouter is the default and issues free keys.
- At least one messaging platform token, for example a Telegram bot token from @BotFather.

### Deployment Dependencies

- Hermes Agent: https://github.com/NousResearch/hermes-agent
- Official image: https://hub.docker.com/r/nousresearch/hermes-agent
- OpenRouter keys: https://openrouter.ai/keys
- Telegram BotFather: https://t.me/BotFather

### Implementation Details

Deploy, then open the service domain. You get a login page. Sign in as `admin` with the `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` value shown in the service's Variables tab.

Message your bot to start talking to the agent. Unknown senders are denied by default, which is deliberate. Either approve the pairing request from the dashboard, or set `TELEGRAM_ALLOWED_USERS` to your numeric Telegram ID as a comma separated list with no brackets or quotes. Your ID comes from @userinfobot.

First boot takes around a minute before the login page answers, which is Hermes warming its agent machinery. The deployment is healthy as soon as the login page responds.

Variables you may want to change:

- `OPENROUTER_API_KEY`: to use another provider, clear this and set that provider's key variable instead. Anthropic, Google, xAI, DeepSeek, Qwen, GLM, Kimi, MiniMax, Bedrock and OpenAI-compatible endpoints are all supported upstream, and additional keys can be added from the dashboard's Keys tab.
- `TELEGRAM_BOT_TOKEN`: swap for `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN` plus `SLACK_APP_TOKEN`, or any other platform Hermes supports.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`: change it to your own value at any time. Clearing it does not make the dashboard public, it stops the dashboard from starting, because Hermes refuses to serve an unauthenticated public dashboard.

To upgrade Hermes, change the `HERMES_IMAGE_VERSION` build argument in the repository's Dockerfile, currently pinned to `v2026.9.14`, and redeploy. Do not run `hermes update` inside the container: the image is immutable, so the upgrade disappears on the next deploy while your persisted config stays ahead of the code.

Troubleshooting:

- The bot never answers: check the platform token, then check that your user ID is allowed or that the pairing request was approved.
- `401 Missing Authentication header` in the logs: the provider key is missing or wrong for the selected provider.
- State disappeared after a redeploy: confirm the volume is still mounted at `/opt/data`.

Deliberately not included: no Postgres or Redis, because Hermes keeps its state in SQLite on the volume, and no second replica, because one volume cannot be shared by two services.

## Why Deploy Hermes Agent on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Hermes Agent on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

An agent is only useful if it is always on, and always-on is exactly what a laptop is not. Railway gives the gateway a persistent home, a volume that survives deploys, a domain for the dashboard, and a restart policy that brings the agent back without you watching it.
