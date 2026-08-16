#!/usr/bin/env python3

import sys
from pathlib import Path

from openai import OpenAI


MODEL = "gpt-5"


src = Path(sys.argv[1]).read_text(
    encoding="utf-8",
    errors="replace",
)

system = src.split("# <SYSTEM>\n", 1)[1].split("# </SYSTEM>", 1)[0]
system = "\n".join(
    line[2:]
    if line.startswith("# ")
    else line[1:]
    if line.startswith("#")
    else line
    for line in system.splitlines()
)

response = OpenAI().responses.create(
    model=MODEL,
    instructions=system,
    input=src,
)

out = response.output_text
sys.stdout.write(out)

if out and not out.endswith("\n"):
    sys.stdout.write("\n")
