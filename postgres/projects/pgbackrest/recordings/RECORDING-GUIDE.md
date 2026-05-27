# pgBackRest Video Recording Guide

## Setup Before Recording

### Terminal
- Font size: 20pt minimum (viewers on phones need to read it)
- Terminal width: 120 columns max (avoids line wrapping)
- Dark background, light text (matches the lab aesthetic)
- Clear scrollback before each video: `clear`
- Set PS1 to show context clearly:
  ```bash
  # As ec2-user
  export PS1='[ec2-user@pg-backup ~]$ '
  # As postgres
  export PS1='[postgres@pg-backup ~]$ '
  ```

### Recording Software
- OBS Studio (free) or QuickTime (Mac built-in)
- Record screen + microphone only (no webcam needed)
- 1920x1080 resolution
- Audio: use a decent mic, record in a quiet room

### Before Each Video
1. SSH into the student server (use HA001 or your test server)
2. Verify the server is in the correct state for that guide
3. Have the BUILD guide open in a browser (second monitor or split screen - but only record the terminal)
4. Do one dry run silently to make sure every command works
5. Clear terminal: `clear`

## Recording Flow

### Intro (30 seconds)
- "This is [MODULE] BUILD [NUMBER]: [TITLE]"
- "By the end of this video, you will [1-2 sentence goal]"
- "Make sure you have [prerequisites] before starting"

### Each Step
1. Read the step title out loud
2. Explain what you are about to do and why (1-2 sentences)
3. TYPE the command - do not paste (students need to see you type)
4. Press Enter
5. While output appears, narrate what you see
6. Point out the key lines in the output
7. If there is a Concept callout, explain it in your own words
8. Pause 2 seconds before moving to next step

### Outro (15 seconds)
- "That is [TITLE] complete"
- "In the next video, we will [preview next guide]"
- "Pause this video and practice on your own server before moving on"

## Naming Convention

```
pgbackrest-build-01-install.mp4
pgbackrest-build-02-stanza.mp4
pgbackrest-build-03-wal-archiving.mp4
pgbackrest-build-04-full-backup.mp4
pgbackrest-build-05-diff-incr.mp4
pgbackrest-build-06-restore-pitr.mp4
pgbackrest-build-07-retention.mp4
pgbackrest-concepts-fundamentals.mp4
pgbackrest-survive-01-stanza-misconfigured.mp4
pgbackrest-survive-02-archive-broken.mp4
...
```

## Upload Checklist

1. Upload to YouTube as Unlisted
2. Title format: "pgBackRest BUILD 01: Install pgBackRest | SUTA Labs"
3. Description: paste the "What you will learn" section from the guide
4. Copy the YouTube URL
5. Add the URL to the guide markdown (see placeholder at top of each guide)

## Tips

- If you make a mistake, just fix it on camera and say "let me fix that" - students learn from mistakes
- Keep videos under 15 minutes. If a guide runs longer, that is fine - do not rush
- Speak slower than you think you need to. Beginners are processing while you talk
- When you switch users (sudo -i -u postgres), explicitly say "Now I am switching to the postgres user"
- When you exit (exit, \q), say "Now I am exiting back to [user/tool]"
- For SURVIVE videos, start by showing the broken state. Let it sink in. Then diagnose step by step.
