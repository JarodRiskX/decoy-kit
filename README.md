# Decoy kit

Plant fake keys and files on your computer so you get an email the moment an intruder
uses them, whether that's a person or an AI agent.

These decoys are called canary tokens. They come from [canarytokens.org](https://canarytokens.org),
a free service run since 2015 by Thinkst, a security company. Its code is
[public on GitHub](https://github.com/thinkst/canarytokens). It needs no account. It asks only
for the email address that should get the alerts.

Each decoy is unique to you, so this kit contains no tokens. You make your own four, and
`place-decoys.sh` puts each one where an intruder would look. The script makes no network
calls, never overwrites a file, and never sets off a decoy.

## The four decoys

| Decoy | Where it goes | You get an email when someone… |
|---|---|---|
| Fake AWS key | `~/.aws/credentials` | tries to use the key |
| Fake server | `~/.ssh/config` | tries to connect to that server |
| Fake database export | `~/Documents/client-export.sql` | loads it into a MySQL database |
| Fake document | `~/Documents/Client fees 2026.pdf` | opens it in Adobe Acrobat Reader |

None of them can touch your real accounts or cost you money. They just look valuable.

## Setup (about 10 minutes)

```bash
git clone <this repo> decoy-kit && cd decoy-kit
chmod +x place-decoys.sh
```

For each token on canarytokens.org: pick the type, enter your email, and write a note saying
**where you're putting it**, e.g. "MacBook ~/.aws/credentials". The note appears in the alert
email, so you'll know exactly which decoy fired.

**1. Fake AWS key.** Choose **AWS keys** and click Create. Copy the text it shows into a file,
say `aws.txt`, then run:

```bash
./place-decoys.sh aws aws.txt
```

If you already have a real `~/.aws/credentials`, the script stops rather than touch it. Add the
decoy as an extra profile instead; it backs up your file first:

```bash
./place-decoys.sh aws aws.txt --profile backup-admin
```

Then delete `aws.txt`.

**2. Fake server.** Choose **DNS**, click Create, and copy the hostname (something like
`abc123.canarytokens.com`). Then run:

```bash
./place-decoys.sh ssh abc123.canarytokens.com db-backup
```

**3. Fake database export.** Choose **MySQL**, click Create, then **Download a MySQL Dump file**.
Then run:

```bash
./place-decoys.sh mysql ~/Downloads/<the file>.sql
```

**4. Fake document.** Choose **Acrobat Reader PDF**, click Create, then download the PDF. The
script checks that the PDF contains no scripts or embedded files before placing it. Then run:

```bash
./place-decoys.sh pdf ~/Downloads/<the file>.pdf
```

Check what's in place (key values are never printed):

```bash
./place-decoys.sh status
```

## Things to know

- **Don't set them off yourself.** Don't `ssh db-backup`. Don't run AWS commands with the decoy
  profile. Opening the PDF in Preview on a Mac is fine; only Acrobat Reader fires it.
- **If you really use AWS,** use `--profile` so your tools never pick the decoy by accident.
  Tools that grab whatever AWS key they find can cause a false alarm, e.g. a "doctor" or
  health-check command in an AI agent that supports Amazon Bedrock. If an alert arrives right
  after you ran something like that, that was you.
- **The DNS alert's IP address is your internet provider's lookup server,** not the intruder's.
- **Each alert email has a "Manage" link** to see alert history or switch the token off. Anyone
  with that link can manage the token, so don't post it anywhere.
- **Your email goes to Thinkst.** That's the only personal data involved.
- **Never commit or share your own decoy files.** Each token is tied to your email.

## If you use AI coding agents

Your own agents shouldn't read secret folders anyway. With them blocked, a well-behaved agent
never trips a decoy. For Claude Code, add these deny rules to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "deny": ["Read(~/.ssh/**)", "Read(~/.aws/**)", "Read(//**/.env)", "Read(//**/.env.*)"]
  }
}
```

Deny rules only block Claude's file-reading tool. A shell command can still reach those files,
so also tell your agents never to use credentials they find in files.

Don't list your decoy locations in agent instruction files like `AGENTS.md` or `CLAUDE.md`.
An intruder's agent reads those too.

## Removing a decoy

Delete the file, or the `Host` block in `~/.ssh/config`, or the decoy profile in
`~/.aws/credentials`. The script keeps a `.before-decoy` copy of any file it added to. Then
switch the token off with the Manage link from any alert email, or just leave it, since an
unused token costs nothing.

## What this doesn't do

Decoys tell you someone got in. They don't keep anyone out. The basics still matter more:
keep secrets in a password manager or keychain instead of plain files, keep your OS updated,
and give each app and agent only the access it needs.
