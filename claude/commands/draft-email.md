The user wants to compose a new email.

1. Extract the recipient and topic from the user's request
2. If no recipient is provided, ask: "Who should this be sent to?"
3. If no topic is provided, ask: "What should this email be about?"

Identify the voice context from the recipient's domain, using the **Context signals** table in
the user's private profile at `$MEMORY_VAULT_PATH/personal/profile.md`. If no signal matches,
use the Personal voice. If the profile is missing, ask which voice to use.

Delegate to the personal-voice agent to compose the message in the identified voice.

Create the draft via `gmail_create_draft`:
- Set the `to` field to the recipient's email address
- Compose a clear, appropriate subject line
- Draft the body in the correct voice

Confirm with: "Draft created: '[subject]' to [recipient] in Gmail Drafts."

Do not send. Do not ask for approval — just create the draft.
