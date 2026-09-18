#!/usr/bin/env python3
"""Repair the generated template config.

templateGenerate strips every literal variable value, so the skeleton it
produces would prompt a deployer for nine variables and still boot broken (no
dashboard, wrong bind, v6-only listener). This puts the literals back, converts
the two credentials into per-deployment generators, and adds the messaging
prompts the source project never carried.

Writes through templateUpsertConfig on the internal endpoint, then reads the
config back and asserts field by field.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.pi/agent/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

TEMPLATE_ID = "4817ec8c-5b12-4b0f-a2d6-7daa2cb9a6d9"
WORKSPACE = "fc4796db-2c6c-4354-a564-d4a1d900af53"  # Auromations
NAME = "Hermes Agent (w/ Dashboard)"
SERVICE = "396beb23-8458-4ad3-ae43-e09dc5d426c6"

# defaultValue carries the literal; isOptional false means the deploy form
# blocks on an empty value, which is what we want for the provider key only.
VARIABLES = {
    "HERMES_DASHBOARD": {
        "isOptional": False, "defaultValue": "true",
        "description": "Runs the Hermes web dashboard as a supervised service. Leave as true.",
    },
    "HERMES_DASHBOARD_HOST": {
        "isOptional": False, "defaultValue": "::",
        "description": "Bind address. Railway's edge reaches containers over IPv6.",
    },
    "HERMES_DASHBOARD_PORT": {
        "isOptional": False, "defaultValue": "8080",
        "description": "Port the dashboard listens on. Matches the service domain target port.",
    },
    # Username and password are the only two required fields on the deploy form:
    # they are the credentials the deployer needs in hand the moment the service
    # comes up, and no default can supply them safely. Everything else either has
    # a working default or can be added from the dashboard after boot.
    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": {
        "isOptional": False,
        "description": "Choose the username for the dashboard login page.",
    },
    # Deliberately no defaultValue: this becomes a required field on the deploy
    # form, so the deployer picks the password and knows it before the service
    # exists. A ${{secret(32)}} default deploys fine but leaves people hunting
    # through the Variables tab for a login they never saw.
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD": {
        "isOptional": False,
        "description": "Choose the password for the dashboard login page. Clearing it later does not open the dashboard up, it stops the dashboard from starting.",
    },
    "HERMES_DASHBOARD_BASIC_AUTH_SECRET": {
        "isOptional": False, "defaultValue": "${{secret(64)}}",
        "description": "Signs dashboard session cookies so logins survive restarts and redeploys.",
    },
    "HERMES_DASHBOARD_PUBLIC_URL": {
        "isOptional": False, "defaultValue": "https://${{RAILWAY_PUBLIC_DOMAIN}}",
        "description": "Public origin Hermes builds OAuth redirect URIs from.",
    },
    "OPENROUTER_API_KEY": {
        "isOptional": True,
        "description": "Optional. Inference provider key, free from openrouter.ai/keys. You can also add this, or any other provider, from the dashboard's Keys tab after deploying.",
    },
    "TELEGRAM_BOT_TOKEN": {
        "isOptional": True,
        "description": "Optional. Bot token from @BotFather. Discord, Slack, Matrix and the rest are configured the same way, see the Hermes docs.",
    },
    "TELEGRAM_ALLOWED_USERS": {
        "isOptional": True,
        "description": "Optional. Comma separated numeric Telegram IDs allowed to talk to the agent, no brackets or quotes. Get yours from @userinfobot. Leave empty to approve senders from the dashboard instead.",
    },
}

CONFIG = {
    "buckets": {},
    "services": {
        SERVICE: {
            "icon": None,
            "name": "hermes",
            "deploy": {
                "startCommand": None,
                "healthcheckPath": "/login",
                "restartPolicyType": "ON_FAILURE",
                "restartPolicyMaxRetries": 10,
            },
            "source": {"repo": "https://github.com/hmseeb/hermes-agent-dashboard", "rootDirectory": None},
            "variables": VARIABLES,
            "networking": {"serviceDomains": {"<hasDomain>:8080": {"port": 8080}}},
            "volumeMounts": {SERVICE: {"mountPath": "/opt/data"}},
        }
    },
}

CANVAS = {"groups": {}, "groupRefs": {SERVICE: None}, "positions": {}}


def main():
    rw.gql(
        "mutation($id: String!, $input: TemplateUpsertConfigInput!) { templateUpsertConfig(id: $id, input: $input) { id } }",
        {"id": TEMPLATE_ID, "input": {
            "name": NAME, "workspaceId": WORKSPACE,
            "serializedConfig": CONFIG, "canvasConfig": CANVAS,
        }},
        internal=True,
    )

    got = rw.gql(
        "query($id: String!){ template(id:$id){ name serializedConfig } }",
        {"id": TEMPLATE_ID},
    )["template"]
    svc = got["serializedConfig"]["services"][SERVICE]

    failures = []
    if got["name"] != NAME:
        failures.append(f"name is {got['name']!r}")
    if svc["deploy"]["healthcheckPath"] != "/login":
        failures.append("healthcheckPath did not stick")
    if svc["deploy"]["startCommand"] is not None:
        failures.append("startCommand must stay null or the image ENTRYPOINT is discarded")
    if svc["volumeMounts"][SERVICE]["mountPath"] != "/opt/data":
        failures.append("volume mount path did not stick")
    if svc["networking"]["serviceDomains"]["<hasDomain>:8080"]["port"] != 8080:
        failures.append("domain target port did not stick")
    for key, want in VARIABLES.items():
        have = svc["variables"].get(key)
        if have is None:
            failures.append(f"{key} missing")
            continue
        if have.get("defaultValue") != want.get("defaultValue"):
            failures.append(f"{key} defaultValue is {have.get('defaultValue')!r}")
        if have.get("isOptional") != want["isOptional"]:
            failures.append(f"{key} isOptional is {have.get('isOptional')!r}")
        if not have.get("description"):
            failures.append(f"{key} lost its description")

    print(json.dumps(svc["variables"], indent=1))
    if failures:
        print("FAILED assertions:")
        for f in failures:
            print(" -", f)
        sys.exit(1)
    print("all repaired fields asserted back through the API")


if __name__ == "__main__":
    main()
