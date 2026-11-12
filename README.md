# Voting Record

Browse the current members of the U.S. Senate and House of Representatives: their recent roll-call votes,
committee assignments, and the bills they've sponsored or cosponsored. Find your own representatives by
street address or state, and read an AI-generated summary of each member produced by a **local** language model.

- **Backend:** Rails 8 API (`app/`), PostgreSQL
- **Frontend:** React + Vite + MUI (`frontend/`)
- **AI summaries:** [Ollama](https://ollama.com) running `qwen3:14b` on your own machine (free, nothing leaves your computer)

## Features

- **Find your representatives:** enter a street address (exact congressional district) or a state on the home page.
- **Browse by chamber:** Senate or House, then a searchable member list filterable by party.
- **Member profiles:** contact info, an AI summary, recent votes (with Yea/Nay breakdown), committee and
  subcommittee seats, and sponsored/cosponsored bills.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Ruby | 3.3.5 | See `.tool-versions` (asdf). rbenv/rvm/mise work too. |
| Node.js | 20+ (developed on 22) | For the Vite frontend |
| PostgreSQL | 14+ (developed on 17) | Must be reachable over TCP on `localhost` |
| Ollama | 0.6+ | Only needed for AI summaries. [Download](https://ollama.com/download) |
| Congress.gov API key | — | Free: [sign up here](https://api.congress.gov/sign-up/). Has an hourly request limit. |

Hardware for AI summaries: `qwen3:14b` is a ~9 GB download and needs **16 GB+ RAM**. It runs on CPU if you
have no supported GPU (expect 3–6 minutes per summary); a GPU makes it much faster. See
[Choosing a model](#choosing-a-model) for lighter options.

## Setup

```bash
git clone <this-repo-url> voting_record
cd voting_record
```

### 1. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env` and set at least:

- `CONGRESS_KEY`: your Congress.gov API key
- `DATABASE_USERNAME` / `DATABASE_PASSWORD`: a Postgres user that can create databases

All settings are described in [Configuration](#configuration). `.env` is git-ignored; never commit it.

### 2. Install dependencies and create the database

```bash
bin/setup --skip-server
```

This installs gems and frontend packages, then creates and migrates the database (the same as running `bundle install`,
`npm --prefix frontend install`, and `bin/rails db:prepare`).

### 3. Load Congress data

```bash
bin/rails congress:sync
```

The first sync takes **several hours** (about 4–5), almost all of it downloading each member's bills: Congress.gov
takes around 8 seconds per page of results. You don't have to wait for it: members, committees and votes load in
the first 10–15 minutes and the app is usable from then on; bills fill in alphabetically by last name. Later syncs
are shorter since they only add new votes. See [Data sync](#data-sync) for options, such as
`BILL_MIN_CONGRESS` and running steps individually.

### 4. Set up the local AI model (optional)

```bash
ollama pull qwen3:14b
```

Make sure Ollama is running (`ollama serve`, or the desktop app/system service). Without it, the app works normally
and the summary section just shows a message that it can't reach Ollama, with a Retry button.

### 5. Run the app

```bash
bin/dev
```

This starts three processes with foreman (`Procfile.dev`):

- `web`: Rails API on http://localhost:3000
- `frontend`: Vite on **http://localhost:5173**, which forwards `/api` requests to Rails
- `jobs`: Solid Queue worker (`bin/jobs`) that generates AI summaries in the background

Open http://localhost:5173. Press Ctrl+C to stop all three.

Background jobs use a second database (`voting_record_development_queue`), created by `bin/setup` /
`bin/rails db:prepare` along with the main one.

## Configuration

All settings come from environment variables, loaded from `.env` in development.

| Variable | Default | Purpose |
|---|---|---|
| `CONGRESS_KEY` | (required for sync) | Congress.gov API key |
| `DATABASE_HOST` | `localhost` | Postgres host |
| `DATABASE_PORT` | `5432` | Postgres port |
| `DATABASE_USERNAME` | your OS username | Postgres user |
| `DATABASE_PASSWORD` | (none) | Postgres password |
| `OLLAMA_URL` | `http://localhost:11434` | Ollama server |
| `OLLAMA_MODEL` | `qwen3:14b` | Model used for summaries (must be pulled first) |

## Data sync

Data is copied into Postgres so the app is fast and doesn't hit external APIs on every page view.

| Source | What | Key needed |
|---|---|---|
| [Congress.gov API](https://api.congress.gov) | Current members (and their chamber), contact info, sponsored/cosponsored bills, House roll-call votes | `CONGRESS_KEY` |
| [senate.gov roll-call XML](https://www.senate.gov/legislative/votes_new.htm) | Senate votes, matched to members by state + last name | No |
| [unitedstates/congress-legislators](https://github.com/unitedstates/congress-legislators) | Committee and subcommittee assignments (not in the Congress.gov API) | No |
| [US Census Geocoder](https://geocoding.geo.census.gov) | Address → congressional district, looked up live when someone searches | No |

```bash
bin/rails congress:sync                     # everything, in order
bin/rails congress:members                  # run this first if running steps individually
bin/rails congress:committees
bin/rails congress:votes                    # VOTE_LIMIT=100: most recent roll calls per chamber
bin/rails congress:bills                    # BILL_MIN_CONGRESS=119: oldest Congress of bills to keep
```

Re-run `congress:sync` whenever you want fresh data (e.g. weekly). It's safe to repeat: members who leave office
are removed and only new votes are downloaded. AI summaries aren't regenerated automatically when data changes
(each one takes minutes on a CPU); their card shows a "votes or bills have been updated" note with a Regenerate
button instead.

## AI summaries

Each member profile has an **AI summary** section between the header and the tabs. How it works:

1. `Summaries::MemberPacket` (`app/services/summaries/member_packet.rb`) builds a compact, factual record of the member
   from the database: committees, bill counts by policy area, recent bills, party-agreement percentage, and votes
   where they broke from their party. Numbers are calculated in Ruby, not by the model.
2. `Summaries::Prompt` (`app/services/summaries/prompt.rb`) holds the system prompt (use only the provided data,
   stay neutral, cite evidence) and a JSON schema the model's answer must follow.
3. `GenerateMemberSummaryJob` sends both to Ollama in the background and saves the result in `member_summaries`.
   The page checks every few seconds until it's ready. Jobs run in the separate `jobs` process (Solid Queue) with a
   single thread for the `summaries` queue, since a local model generates one summary at a time. Keeping slow jobs
   out of the web server means they can never block page loads.

Summaries are generated the first time a profile is opened and then reused. They regenerate automatically only
when the prompt version changes; when a member's data changes the card says so and offers **Regenerate**. The
exact data sent to the model is saved with each summary (`member_summaries.input`), so you can see what it was given.

**Experimenting with prompts:** edit `prompt.rb`, bump `Prompt::VERSION`, and open a profile: every summary
regenerates with the new prompt. To try a prompt without the UI:

```bash
bin/rails runner 'puts JSON.pretty_generate(Summaries::Generator.new.call(Member.find_by!(bioguide_id: "S000148"))[:content])'
```

### Choosing a model

Any Ollama model that supports structured output works. Set `OLLAMA_MODEL` in `.env`, run `ollama pull <model>`,
and restart `bin/dev`.

| Model | Download | RAM | Notes |
|---|---|---|---|
| `qwen3:14b` (default) | ~9 GB | 16 GB+ | Best instruction-following of these; slow on CPU |
| `qwen3:8b` | ~5 GB | 8 GB+ | About twice as fast; somewhat less precise |
| `qwen3:4b` | ~2.5 GB | 6 GB+ | Fast on CPU; noticeably more mistakes |

Smaller models are more likely to make mistakes, so check summaries against the Votes and Bills tabs. The
page labels every summary as AI-generated for this reason.

## API

The frontend uses these JSON endpoints. Errors come back as `{ "error": { "code", "message" } }`.

| Endpoint | Returns |
|---|---|
| `GET /api/members?chamber=senate\|house` | Member list |
| `GET /api/members/:bioguide_id` | Profile, committees, counts |
| `GET /api/members/:bioguide_id/votes?page=` | Roll-call votes (20 per page) |
| `GET /api/members/:bioguide_id/bills?role=sponsor\|cosponsor&page=` | Bills (20 per page) |
| `GET /api/members/:bioguide_id/summary` | AI summary (`202` while generating) |
| `POST /api/members/:bioguide_id/summary` | Regenerate the AI summary |
| `GET /api/representatives?q=<address or state>` | Senators + House member(s) |

## Project layout

```
app/controllers/api/        JSON API
app/services/congress/      Data sync from Congress.gov, senate.gov, congress-legislators
app/services/summaries/     AI summary: data packet, prompt + schema, Ollama client
app/services/district_lookup.rb   Address -> district via the Census Geocoder
app/jobs/                   Background summary generation
lib/tasks/congress.rake     Sync tasks
frontend/src/               React app (pages/, components/)
Procfile.dev, bin/dev       Run Rails + Vite together
```

## Troubleshooting

**`password authentication failed` / `connection refused` from Postgres**
Check `DATABASE_*` in `.env`. If more than one Postgres is installed (a system service, Docker, asdf/Homebrew),
see which one owns the port: `ss -ltnp | grep 543` (Linux) or `lsof -i :5432` (macOS). Point `DATABASE_PORT` at
the server your credentials belong to.

**The page says "API server isn't running"**
The frontend is up but Rails isn't. Use `bin/dev` to start both, or check the `web` lines in its output for errors.

**`CONGRESS_KEY is not set` during sync**
Add it to `.env`. Rails loads `.env` automatically in development and test.

**Sync pauses for a minute at a time**
That's the Congress.gov hourly rate limit (check yours with the `x-ratelimit-remaining` response header). The sync
backs off and continues on its own.

**AI summary says Ollama isn't reachable**
Start Ollama (`ollama serve`) and check `curl http://localhost:11434/api/version`. Make sure the model in
`OLLAMA_MODEL` appears in `ollama list`.

**AI summary stays on "queued" forever**
The `jobs` process isn't running. Start the app with `bin/dev` (not just `bin/rails server`), or run `bin/jobs`
in another terminal.

**AI summaries are very slow**
That's expected on CPU-only machines (a few minutes each). Try a smaller model (see above). Only one summary
generates at a time; others wait in line.

**Port 5173 or 3000 already in use**
Stop the other process (`lsof -t -i :5173 | xargs kill`) or change the port in `Procfile.dev`.

## Development

```bash
bin/rubocop                         # Ruby lint
npm --prefix frontend run build     # production build of the frontend (checks it compiles)
```

There's no automated test suite yet.
