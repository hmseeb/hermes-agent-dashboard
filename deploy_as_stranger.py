#!/usr/bin/env python3
"""Phase 6: click-deploy the template into a brand new project, the way the
marketplace button does (no projectId), with the deploy-form answers injected.

Usage: python3 deploy_as_stranger.py <openrouter-key> [telegram-bot-token] [telegram-allowed-users]
"""
import json
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.pi/agent/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

TEMPLATE_ID = os.environ.get("TEMPLATE_ID", "4817ec8c-5b12-4b0f-a2d6-7daa2cb9a6d9")
# My Projects while Auromations billing is pending (repo AGENTS.md); override to go back.
WORKSPACE = os.environ.get("WORKSPACE_ID", "d10da65a-297f-4ba4-8cef-2fa9bb45fdef")

answers = dict(zip(
    ["OPENROUTER_API_KEY", "TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_USERS"],
    sys.argv[1:4],
))
# Required deploy-form fields with no default: left blank, the dashboard refuses
# to bind, the healthcheck fails, and the failure counts against template health.
answers["HERMES_DASHBOARD_BASIC_AUTH_USERNAME"] = os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_USERNAME", "admin")
answers["HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"] = os.environ.get(
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD", __import__("secrets").token_urlsafe(16))

config = rw.gql(
    "query($id: String!){ template(id:$id){ serializedConfig } }", {"id": TEMPLATE_ID}
)["template"]["serializedConfig"]

# Each listing has its own service UUID, so take whichever one this template holds.
service = next(iter(config["services"].values()))
for key, value in answers.items():
    service["variables"].setdefault(key, {})["defaultValue"] = value

out = rw.gql(
    "mutation($input: TemplateDeployV2Input!){ templateDeployV2(input:$input){ projectId workflowId } }",
    {"input": {"templateId": TEMPLATE_ID, "workspaceId": WORKSPACE, "serializedConfig": config}},
)
print(json.dumps(out, indent=1))
