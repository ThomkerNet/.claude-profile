---
name: todoist-ref
description: Todoist API reference with project IDs and curl examples. Load when working with Todoist tasks.
---

# Todoist Reference

## API Versions

- **REST API v2:** CRUD operations
- **Sync API v9:** Batch operations, moves

## Credential

Retrieve from Bitwarden:
```bash
bw get item "Todoist" | jq -r '.fields[] | select(.name=="API Key") | .value'
```

Or use `/bw-ref` for full credential access patterns.

---

## Projects

| Project | ID | Purpose |
|---------|-----|---------|
| Inbox | 2310975157 | Quick capture |
| Personal | 2314378138 | Solo: MSc, health, hobbies |
| Thomker Home | 2364972779 | Shared w/ Charlotte: house, life admin |

---

## API Operations

### List Tasks

```bash
curl -s "https://api.todoist.com/rest/v2/tasks?project_id=${PROJECT_ID}" \
  -H "Authorization: Bearer $TODOIST_API_KEY"
```

### Create Task

```bash
curl -s -X POST "https://api.todoist.com/rest/v2/tasks" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Task description",
    "project_id": "2310975157",
    "due_string": "tomorrow",
    "priority": 2
  }'
```

### Complete Task

```bash
curl -s -X POST "https://api.todoist.com/rest/v2/tasks/${TASK_ID}/close" \
  -H "Authorization: Bearer $TODOIST_API_KEY"
```

### Move Task (Sync API)

```bash
curl -s -X POST "https://api.todoist.com/sync/v9/sync" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "commands=[{\"type\":\"item_move\",\"uuid\":\"$(uuidgen)\",\"args\":{\"id\":\"${TASK_ID}\",\"project_id\":\"${TARGET_PROJECT_ID}\"}}]"
```

---

## Common Patterns

### Get all tasks with labels

```bash
curl -s "https://api.todoist.com/rest/v2/tasks" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | \
  jq '.[] | select(.labels | length > 0)'
```

### Tasks due today

```bash
curl -s "https://api.todoist.com/rest/v2/tasks?filter=today" \
  -H "Authorization: Bearer $TODOIST_API_KEY"
```

---

## Priority Mapping

| Priority | API Value | Display |
|----------|-----------|---------|
| P1 (urgent) | 4 | Red |
| P2 (high) | 3 | Orange |
| P3 (medium) | 2 | Blue |
| P4 (normal) | 1 | No color |

---

## Error Handling

Always check response:
```bash
response=$(curl -s -w "\n%{http_code}" ...)
body=$(echo "$response" | head -n -1)
status=$(echo "$response" | tail -n 1)
if [ "$status" != "200" ] && [ "$status" != "204" ]; then
  echo "Error: $status - $body" >&2
  exit 1
fi
```
