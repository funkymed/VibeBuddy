#!/bin/sh
# Hook espion : consigne ce qu'il reçoit, puis refuse avec un message reconnaissable.
IN=$(cat)
printf '%s\n' "$IN" >> /Users/cyrilpereira/Sites/notch/docs/spikes/hook/received.jsonl
printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"REFUS-SPIKE-7f3a"}}}'
