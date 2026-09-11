Read the most recent email thread the user is referring to using `gmail_read_thread` or `gmail_search_messages`. If the user named a sender or subject, search for it first.

Identify the voice context:
- Look at the thread labels, sender domain and subject
- Match them against the **Context signals** table in the user's private profile at
  `$MEMORY_VAULT_PATH/personal/profile.md`
- No match → Personal voice; profile missing → ask which voice to use

Delegate to the personal-voice agent to draft a reply in the identified voice.

Create the draft via `gmail_create_draft`:
- Set the correct `to` address (the sender of the last email in the thread)
- Set `subject` with "Re: " prefix if not already present
- Set `threadId` to keep it in the same thread

Confirm with: "Draft created for '[subject]' in Gmail Drafts."

Do not send. Do not summarize the thread back to the user unless they ask.
