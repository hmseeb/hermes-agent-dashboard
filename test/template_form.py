#!/usr/bin/env python3
"""Asserts the PUBLISHED template's deploy form: the deployer must type the
dashboard username and password, and nothing else is required.

A row prompts only when isOptional is false AND defaultValue is empty. Any
default (a literal like 'admin' or a ${{secret()}} generator) turns it into a
preset the form never shows, which leaves deployers hunting through the
Variables tab for a login they never saw.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.claude/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

TEMPLATE_ID = "4817ec8c-5b12-4b0f-a2d6-7daa2cb9a6d9"
WANT = {"HERMES_DASHBOARD_BASIC_AUTH_PASSWORD", "HERMES_DASHBOARD_BASIC_AUTH_USERNAME"}

config = rw.gql(
    "query($id: String!){ template(id:$id){ serializedConfig } }", {"id": TEMPLATE_ID}
)["template"]["serializedConfig"]
variables = next(iter(config["services"].values()))["variables"]
prompted = {k for k, v in variables.items() if not v.get("isOptional") and not v.get("defaultValue")}
secret = variables.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET", {}).get("defaultValue", "")

problems = []
if prompted != WANT:
    problems.append(f"required form fields are {sorted(prompted)}, want {sorted(WANT)}")
if "secret(" not in secret:
    problems.append(f"session secret must stay generated, is {secret!r}")
for line in problems:
    print("FAIL", line)
print("PASS" if not problems else f"{len(problems)} problems")
sys.exit(1 if problems else 0)
