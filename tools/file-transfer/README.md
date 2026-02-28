# Agent File Transfer

Inter-agent file transfer CLI for OS-1 agents.

## Architecture

**Current (v1.0): Filesystem-based**
- Uses shared `/home/ubuntu/clawd/shared/transfers/` directory
- Instant transfers with zero latency
- Notifications via `tq_messages` Postgres table

**Future (v2.0): S3-based** (when multi-VM scaling needed)
- S3 bucket with presigned URLs
- Same CLI interface, swappable backend

## Installation

```bash
# Add to PATH
ln -sf /path/to/agent-infra/tools/file-transfer/agent-transfer /usr/local/bin/

# Or use directly
./agent-transfer --help
```

## Usage

### Send a file
```bash
agent-transfer send ./spec.pdf --to jared
agent-transfer send ./data.csv --to all --message "Weekly report"
```

### Check your inbox
```bash
agent-transfer inbox
```

### Receive a file
```bash
agent-transfer get spec.pdf
agent-transfer get spec.pdf --output ./downloads/
```

### List all transfers
```bash
agent-transfer list
```

### Clean old transfers
```bash
agent-transfer clean --days 7
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_NAME` | `$USER` | Your agent name (jean/jared/sam) |
| `TRANSFER_BASE` | `/home/ubuntu/clawd/shared/transfers` | Base directory |
| `NEON_DATABASE_URL` | (Neon connection string) | For tq_messages notifications |

## Directory Structure

```
/home/ubuntu/clawd/shared/transfers/
├── inbox/
│   ├── jean/        # Files waiting for Jean
│   ├── jared/       # Files waiting for Jared
│   └── sam/         # Files waiting for Sam
├── .metadata/       # Transfer metadata JSON
└── .locks/          # Atomic operation locks
```

## Notifications

When a file is sent, a notification is posted to the `tq_messages` table:

```json
{
  "type": "file_transfer",
  "transfer_id": "20260228-002345-a1b2c3d4",
  "filename": "spec.pdf",
  "size": 27000,
  "message": "Review this"
}
```

Agents can check for pending transfers via:
```sql
SELECT * FROM tq_messages 
WHERE to_agent = 'jean' 
  AND message_type = 'file_transfer' 
  AND read_at IS NULL;
```

## Future S3 Backend

The CLI is designed for backend swappability. To add S3 support:

1. Add `--backend s3` flag
2. Implement S3 upload with presigned URL generation
3. Store presigned URL in metadata/tq_messages
4. Auto-detect: use filesystem if shared dir accessible, else S3

This maintains the same UX while enabling multi-VM scaling.

## Authors

- Jean (initial filesystem MVP)
- Jared (S3 design, future implementation)
- Sam (architecture review)

## License

MIT - OS-1 Project
