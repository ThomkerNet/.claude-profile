---
description: Instruct user to elevate Vaultwarden access for RW operations
---

To perform write operations on Vaultwarden, you need to elevate your session.

**Run this command in YOUR terminal** (not here):

```bash
bun run ~/.claude/tools/vaultwarden/bw-elevate.ts \
  --collection <COLLECTION> \
  --reason "Your reason here"
```

**Available collections:**
- `bnx-infra` - BoroughNexus infrastructure
- `bnx-secrets` - BoroughNexus application secrets
- `briefhours-deploy` - BriefHours deployment

**Example:**
```bash
bun run ~/.claude/tools/vaultwarden/bw-elevate.ts \
  --collection briefhours-deploy \
  --reason "Deploying webapp v1.2.3"
```

Once complete, let me know and I can proceed with the write operation.
