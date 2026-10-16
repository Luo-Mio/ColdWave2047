import json

path = r"C:\Users\chris\.gemini\antigravity\brain\2038ed65-adf9-4ed0-aa13-b78032cdd916\.system_generated\logs\transcript_full.jsonl"
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        if '"step_index":20667' in line:
            obj = json.loads(line)
            print("Thinking length:", len(obj.get("thinking", "")))
            print("Thinking end:\n", obj.get("thinking", "")[-2500:])
            break

