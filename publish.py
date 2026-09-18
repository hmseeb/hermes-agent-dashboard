#!/usr/bin/env python3
"""Publish the template, plus two sibling listings that carry the same verified
config under different names.

Railway mints the slug from the name at first publish and never changes it, and
templateUpsertConfig is a true upsert: a fresh client-generated UUID creates a
new template. Every service and volume UUID inside serializedConfig has to be
fresh too, or the server rejects the write with "ID collision".
"""
import pathlib
import sys
import uuid

sys.path.insert(0, str(pathlib.Path("~/.pi/agent/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

BASE_TEMPLATE = "4817ec8c-5b12-4b0f-a2d6-7daa2cb9a6d9"
BASE_SERVICE = "396beb23-8458-4ad3-ae43-e09dc5d426c6"
WORKSPACE = "fc4796db-2c6c-4354-a564-d4a1d900af53"
CATEGORY = "Automation"
ICON = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/website/static/img/apple-touch-icon.png"
README = (pathlib.Path(__file__).parent / "TEMPLATE_OVERVIEW.md").read_text()

# name -> 75-char description. The name is what search ranks on for closeness;
# the description is the only other indexed field, so each one carries the
# channel keywords rather than repeating the name.
LISTINGS = [
    ("Hermes Agent (w/ Dashboard)", "Hermes AI agent for Telegram, Discord and Slack with a locked web dashboard"),
    ("Hermes Agent (Telegram)", "AI agent for Telegram, Discord and Slack with a locked web dashboard"),
    ("Hermes Agent (Multi-Channel)", "Always-on AI agent for Telegram, Discord and Slack with a web dashboard"),
]


def clone_config(config, new_service):
    """Rewrite every service and volume UUID so the upsert is not an ID collision."""
    svc = config["services"].pop(BASE_SERVICE)
    svc["volumeMounts"] = {new_service: list(svc["volumeMounts"].values())[0]}
    config["services"][new_service] = svc
    return config


def main():
    base = rw.gql(
        "query($id: String!){ template(id:$id){ serializedConfig } }", {"id": BASE_TEMPLATE}
    )["template"]["serializedConfig"]

    for i, (name, description) in enumerate(LISTINGS):
        assert len(description) <= 75, f"{name}: description is {len(description)} chars"

        if i == 0:
            tid = BASE_TEMPLATE
        else:
            tid = str(uuid.uuid4())
            service = str(uuid.uuid4())
            import copy
            config = clone_config(copy.deepcopy(base), service)
            rw.gql(
                "mutation($id: String!, $input: TemplateUpsertConfigInput!){ templateUpsertConfig(id:$id, input:$input){ id } }",
                {"id": tid, "input": {
                    "name": name, "workspaceId": WORKSPACE,
                    "serializedConfig": config,
                    "canvasConfig": {"groups": {}, "groupRefs": {service: None}, "positions": {}},
                }},
                internal=True,
            )

        rw.gql(
            "mutation($id: String!, $input: TemplateUpsertSettingsInput!){ templateUpsertSettings(id:$id, input:$input){ id name } }",
            {"id": tid, "input": {"workspaceId": WORKSPACE, "name": name,
                                  "description": description, "image": ICON}},
            internal=True,
        )

        out = rw.gql(
            "mutation($id: String!, $input: TemplatePublishInput!){ templatePublish(id:$id, input:$input){ id code name status } }",
            {"id": tid, "input": {"category": CATEGORY, "description": description,
                                  "readme": README, "workspaceId": WORKSPACE}},
        )["templatePublish"]
        print(f"{out['name']}  ->  https://railway.com/deploy/{out['code']}   ({out['status']})")


if __name__ == "__main__":
    main()
