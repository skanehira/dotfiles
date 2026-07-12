# gmail (v1)

```bash
gws gmail <resource> <method> [flags]
```

## Helper Commands

| Command      | Description                                              |
| ------------ | -------------------------------------------------------- |
| `+send`      | Send an email                                            |
| `+triage`    | Show unread inbox summary (sender, subject, date)        |
| `+reply`     | Reply to a message (handles threading automatically)     |
| `+reply-all` | Reply-all to a message (handles threading automatically) |
| `+forward`   | Forward a message to new recipients                      |
| `+read`      | Read a message and extract its body or headers           |
| `+watch`     | Watch for new emails and stream them as NDJSON           |

## API Resources

### users

  - `getProfile` — Gets the current user's Gmail profile.
  - `stop` — Stop receiving push notifications for the given user mailbox.
  - `watch` — Set up or update a push notification watch on the given user mailbox.
  - `drafts` — Operations on the 'drafts' resource
  - `history` — Operations on the 'history' resource
  - `labels` — Operations on the 'labels' resource
  - `messages` — Operations on the 'messages' resource
  - `settings` — Operations on the 'settings' resource
  - `threads` — Operations on the 'threads' resource
