#!/usr/bin/env python3
"""Edits the PUBLISHED template's config in place.

Reads the template's own serializedConfig and canvas and writes them back with
the deploy-form credentials turned into required prompts. Unlike repair.py this
keeps everything else exactly as published: the icon, the canvas layout and the
service and volume UUIDs.

Then run test/template_form.py to assert the form.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.claude/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

TEMPLATE_ID = "4817ec8c-5b12-4b0f-a2d6-7daa2cb9a6d9"
WORKSPACE = "fc4796db-2c6c-4354-a564-d4a1d900af53"  # Auromations
NAME = "Hermes Agent (w/ Dashboard)"

# isOptional false with an EMPTY default is what renders as a field the
# deployer must fill. Hermes accepts any non-empty value (verified on v0.23.1:
# one character, spaces inside, symbols, unicode), so a required prompt cannot
# crash the boot. The one value that cannot log in is a password with spaces at
# either end: Hermes strips the env value before hashing but not the typed one.
CREDENTIALS = {
    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": "Choose the username for the dashboard login page.",
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD": (
        "Choose the password for the dashboard login page. Use a long, unique "
        "value with no spaces at the start or end. Clearing it later does not "
        "open the dashboard up, it stops the dashboard from starting."
    ),
}

template = rw.gql(
    "query($id: String!){ template(id:$id){ serializedConfig canvasConfig } }", {"id": TEMPLATE_ID}
)["template"]
config = template["serializedConfig"]
for service in config["services"].values():
    for key, description in CREDENTIALS.items():
        service["variables"][key] = {"isOptional": False, "defaultValue": "", "description": description}

rw.gql(
    "mutation($id: String!, $input: TemplateUpsertConfigInput!) { templateUpsertConfig(id: $id, input: $input) { id } }",
    {"id": TEMPLATE_ID, "input": {
        "name": NAME, "workspaceId": WORKSPACE,
        "serializedConfig": config, "canvasConfig": template["canvasConfig"],
    }},
    internal=True,
)
print("saved")
