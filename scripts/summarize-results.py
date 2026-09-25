#!/usr/bin/env python3
"""Make a readable local comparison from an exported Flow State experiment."""
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
report = json.loads(source.read_text())
lines = [
    f"# {report['sourceName']}", "",
    f"Pipeline {report['pipelineVersion']} · {report['osVersion']}", "",
    "Exploratory measurements. Compare recognition and editing against the original audio.", "",
    "| Speech pass | Preparation | Transcription | Audio duration | Real-time factor |",
    "| --- | ---: | ---: | ---: | ---: |",
]
for item in report['passes']:
    inference = item['elapsedSeconds'] - item['preparationSeconds']
    duration = item['audioDurationSeconds']
    lines.append(f"| {item['locale']} / {item['engine']} | {item['preparationSeconds']:.2f} s | {inference:.2f} s | {duration:.2f} s | {inference / duration:.3f} |")
lines += ["", "| Cleanup trial | Time | Outcome |", "| --- | ---: | --- |"]
for item in report['trials']:
    outcome = item.get('result', {}).get('method', item.get('error', 'No output'))
    lines.append(f"| {item['title']} | {item['elapsedSeconds']:.2f} s | {outcome} |")
for issue in report['issues']:
    lines += ["", f"Issue: {issue}"]
for item in report['passes']:
    lines += ["", f"## Raw transcript: {item['locale']}", "", item['text']]
if report.get('merge'):
    lines += ["", "## Experimental confidence merge", "", report['merge']['text']]
for item in report['trials']:
    lines += ["", f"## {item['title']}", ""]
    if 'result' in item:
        lines += [item['result']['text'], "", item['result']['note']]
    if 'error' in item:
        lines += [f"Failed: {item['error']}"]
destination = source.with_name(source.stem + '-comparison.md')
destination.write_text('\n'.join(lines) + '\n')
print(destination)
