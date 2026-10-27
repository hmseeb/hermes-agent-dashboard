#!/usr/bin/env python3
"""Phase 6: click-deploy the template into a brand new project, the way the
marketplace button does (no projectId), with the deploy-form answers injected.

Usage: python3 deploy_as_stranger.py <openrouter-key> [telegram-bot-token] [telegram-allowed-users]
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.pi/agent/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

TEMPLATE_ID = "4817ec8c-5b12-4b0f-a2d6-7daa2cb9a6d9"
WORKSPACE = "fc4796db-2c6c-4354-a564-d4a1d900af53"
SERVICE = "396beb23-8458-4ad3-ae43-e09dc5d426c6"

answers = dict(zip(
    ["OPENROUTER_API_KEY", "TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_USERS"],
    sys.argv[1:4],
))
# Required deploy-form fields with no default: left blank, the dashboard refuses
# to bind, the healthcheck fails, and the failure counts against template health.
answers["HERMES_DASHBOARD_BASIC_AUTH_USERNAME"] = "admin"
answers["HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"] = __import__("secrets").token_urlsafe(16)

config = rw.gql(
    "query($id: String!){ template(id:$id){ serializedConfig } }", {"id": TEMPLATE_ID}
)["template"]["serializedConfig"]

for key, value in answers.items():
    config["services"][SERVICE]["variables"].setdefault(key, {})["defaultValue"] = value

out = rw.gql(
    "mutation($input: TemplateDeployV2Input!){ templateDeployV2(input:$input){ projectId workflowId } }",
    {"input": {"templateId": TEMPLATE_ID, "workspaceId": WORKSPACE, "serializedConfig": config}},
)
print(json.dumps(out, indent=1))
