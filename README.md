# Voting Record

Browse the current members of the U.S. Senate and House of Representatives: their recent roll-call votes,
committee assignments, and the bills they've sponsored or cosponsored. Find your own representatives by
street address or state, and read an AI-generated summary of each member produced by a **local** language model.

- **Backend:** Rails 8 API (`app/`), PostgreSQL
- **Frontend:** React + Vite + MUI (`frontend/`), with live updates over Action Cable
- **AI summaries:** [Ollama](https://ollama.com) running `qwen3:14b` on your own machine (free, nothing leaves your computer)

## Features

- **Find your representatives:** enter a street address (matched to the exact congressional district through the
  Census Geocoder) or a state name or code on the home page to get your two senators and House member(s).
  Address and state suggestions appear as you type (from [Photon](https://photon.komoot.io), OpenStreetMap data);
  pick one to search right away, or just press Enter on what you typed.
- **Ask about votes and bills (experimental):** type a question like "How many Democrats support Israel?",
  "How many Democrats voted to fund Israel?", "Which senators cosponsored bills on Social Security?" or "Give me
  the highlights of the last 7 days", then ask follow-ups ("What about Republicans?"). General questions draw on
  both votes and sponsored bills. A local model finds the matching votes and bills and decides
  which way each one points; the counts and member lists come straight from the database. The page shows
  every vote or bill it used, how it read each vote, and the party breakdown, and you can untick any to update
  the totals. See [Asking questions](#asking-questions).
- **Browse by chamber:** Senate or House, then a member list you can search by name or state and filter by party.
- **Member profiles:**
  - Header: party, seat, photo, website, phone and office address, plus counts of synced votes, sponsored and
    cosponsored bills, and committees.
  - **AI summary** (on demand): click **Generate summary** to get an overview, 2–4 key issues with cited bills,
    the member's party-agreement percentage and notable party breaks, and a note on what the data doesn't cover.
    Progress updates live while it's being written, and the card tells you when the summary is out of date.
  - **Votes:** Yea/Nay/Not Voting totals, then each roll call (newest first) with the question, the bill,
    the result, the tally, and a link to the official record.
  - **Committees:** committee and subcommittee seats with roles such as Chairman or Ranking Member.
  - **Sponsored / Cosponsored bills:** policy area, introduction date, latest action, and a link to Congress.gov.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Ruby | 3.4.9 | See `.tool-versions` (asdf). rbenv/rvm/mise work too. |
| Node.js | 20+ (developed on 22.12) | For the Vite frontend |
| PostgreSQL | 14+ (developed on 17) | Must be reachable over TCP on `localhost`, with the [pgvector](https://github.com/pgvector/pgvector) extension (0.8+) installed. See [step 2](#2-install-dependencies-and-create-the-database) |
| Ollama | 0.6+ | Only needed for AI summaries and the question box. [Download](https://ollama.com/download) |
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

**pgvector:** the migrations enable the `vector` extension, so install it into your Postgres first. Packages exist
for most systems (`brew install pgvector`, `apt install postgresql-17-pgvector`, or the `pgvector/pgvector` Docker
image). For a Postgres installed with asdf or from source, build it against that install's `pg_config`:

```bash
git clone --branch v0.8.0 --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector
cd /tmp/pgvector && make PG_CONFIG="$(which pg_config)" && make install PG_CONFIG="$(which pg_config)"
```

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
ollama pull nomic-embed-text   # ~270 MB; search embeddings for the question box
bin/rails search:index         # build the question box's search index (first run ~40 min on CPU)
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
`bin/rails db:prepare` along with the main one. Live summary updates use Action Cable. In development its
`postgresql` adapter relays messages from the `jobs` process to the browser through the main database
(LISTEN/NOTIFY), so no Redis is needed. Vite forwards the `/cable` WebSocket to Rails.

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
| `ASK_MODEL` | `OLLAMA_MODEL` | Model used by the question box, if you want a different (e.g. smaller, faster) one |
| `EMBED_MODEL` | `nomic-embed-text` | Embedding model for the search index (768 dimensions; changing it means a new migration and re-index) |
| `VOTE_LIMIT` | `500` (`.env.example` sets `100` for a faster first sync) | Most recent roll calls to sync per chamber |
| `BILL_MIN_CONGRESS` | the current Congress | Oldest Congress of bills to keep |

## Data sync

Data is copied into Postgres so the app is fast and doesn't hit external APIs on every page view.

| Source | What | Key needed |
|---|---|---|
| [Congress.gov API](https://api.congress.gov) | Current members (and their chamber), contact info, sponsored/cosponsored bills, House roll-call votes, House amendment purposes, CRS bill summaries | `CONGRESS_KEY` |
| [senate.gov roll-call XML](https://www.senate.gov/legislative/votes_new.htm) | Senate votes, matched to members by state + last name | No |
| [unitedstates/congress-legislators](https://github.com/unitedstates/congress-legislators) | Committee and subcommittee assignments (not in the Congress.gov API) | No |
| [US Census Geocoder](https://geocoding.geo.census.gov) | Address → congressional district, looked up live when someone searches | No |
| [Photon](https://photon.komoot.io) (komoot's public demo server) | Address/state suggestions while typing, looked up live (not synced) | No |

```bash
bin/rails congress:sync                     # everything, in order
bin/rails congress:members                  # run this first if running steps individually
bin/rails congress:committees
bin/rails congress:votes                    # VOTE_LIMIT=500: most recent roll calls per chamber
bin/rails congress:bills                    # BILL_MIN_CONGRESS=119: oldest Congress of bills to keep
bin/rails congress:vote_details             # House amendment purposes + CRS summaries of voted-on bills (incremental)
```

House roll-call records only name the bill an amendment belongs to ("H.R. 8800"), so `congress:vote_details` looks
up each House amendment vote's amendment (number, sponsor, purpose), and the Congressional Research Service summary
of every bill that was voted on. The question box searches that text, and the Votes cards show it. Each vote is
looked up once; summaries are re-checked after 30 days, since CRS adds new ones as a bill advances.

Re-run `congress:sync` whenever you want fresh data (e.g. weekly). It's safe to repeat: members who leave office
are removed and only new votes are downloaded. It finishes by updating the question box's search index (only new or
changed votes and bills are embedded); if Ollama isn't running it skips that step with a warning. AI summaries aren't regenerated automatically when data changes
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
   Jobs run in the separate `jobs` process (Solid Queue) with a single thread for the `summaries` queue, since a
   local model generates one summary at a time. Keeping slow jobs out of the web server means they can never block
   page loads.
4. Each status change (queued → running → complete/failed) is broadcast on `MemberSummaryChannel`, and the card
   refetches the summary when it hears one, with an elapsed-time clock while it waits. If the WebSocket can't
   connect, the card falls back to checking once a minute.

Opening a profile never starts generation. A summary is only written when someone clicks **Generate summary**
(or **Regenerate** / **Retry**), and the result is saved and reused. When a member's data or the prompt version
changes, the card says the summary is out of date and offers **Regenerate**. A job that hasn't finished after
20 minutes (for example because the `jobs` process restarted) is shown as failed with a **Retry** button. Only one
job per member runs at a time. The exact data sent to the model is saved with each summary
(`member_summaries.input`), so you can see what it was given.

**Experimenting with prompts:** edit `prompt.rb`, bump `Prompt::VERSION`, and click **Regenerate** on a
profile to see the new prompt's output. To try a prompt without the UI:

```bash
bin/rails runner 'puts JSON.pretty_generate(Summaries::Generator.new.call(Member.find_by!(bioguide_id: "S000148"))[:content])'
```

## Asking questions

The **Ask about votes and bills** box on the home page answers topic questions in five stages, shown live on the page
(`Ask::Pipeline`, `app/services/ask/`). It's retrieval-augmented, but the model never counts:

1. **Plan:** the model turns the question into a search phrase and keywords, a party and chamber filter, and the
   stance being asked about ("support Israel"), and decides whether it's about votes, sponsored bills, or both
   (general "do they support X" questions use both).
2. **Search:** `Search::Retriever` finds candidate votes or bills in `search_documents`, combining embedding
   similarity (pgvector, `nomic-embed-text`) with Postgres full-text search weighted by how rare each word is.
   House "rule" votes (on floor procedure) are left out, and near-identical votes collapse to one.
3. **Read:** the model decides which candidates are on topic, and for bills whether sponsoring one matches the
   stance or works against it (a resolution disapproving an arms sale counts against "support Israel"). For each vote, `Ask::VoteMeaning` first works out
   **what a Yea means** from the motion and the measure using fixed rules. For example, a Yea on discharging a
   *disapproval* resolution moves the resolution that would block an arms sale, so it's opposition to the sale.
   The model only says whether a Yea matches the stance. (Asked to work out direction on its own, it read those
   votes backwards.)
4. **Count:** SQL (`Ask::Tally`) gives each vote's party breakdown and member list and each bill's sponsors;
   `Ask::Combined` counts distinct members across all of them: matching by vote, by bill, in total, on the
   opposite side, and on both sides.
5. **Write:** the model writes 2–4 sentences from those computed numbers.

The page shows every vote or bill used, how each vote was read, and what was found but judged not relevant. Unticking
a vote or bill updates the totals.

**Recent activity.** Questions like "Give me the highlights of the last 7 days" or "What did the House do this
week?" skip search and reading. `Ask::Activity` gathers everything in the window (1–90 days, 7 by default) in SQL:

- every roll-call vote, grouped by measure (a nomination's cloture and confirmation votes together), with each
  party's breakdown, whether it was party-line, and who broke with their party
- bills introduced, by sponsor party and policy area, the most-cosponsored ones, and the most active sponsors
- older bills whose latest action in the window moved them forward (passed a chamber, reported, sent to the
  President, became law), rather than a referral to committee

The model writes a short digest from a compact version of that, and the page lists all of it. Only each bill's
*latest* action is synced, so a bill that passed and then got another action later in the window shows the later
one.

**Conversations.** Questions belong to a conversation (`conversations`, `?conversation=<token>` in the URL), so you
can ask follow-ups like "What about Republicans?", "And in the House?" or "What did Democrats introduce?". The
planner sees the last three answered questions with the plans they used and carries over the topic and filters;
the writer sees the earlier answers so it doesn't repeat them. Each turn still searches and counts from scratch, so
every number comes from that turn's own data. A follow-up waits until the answer before it is finished. Older
`?question=<token>` links open the question's conversation.

Limits: answers only cover the synced data (the most recent roll calls per chamber and current members' bills
in the 119th Congress). Vague stances need judgment calls (is a resolution requesting a human-rights report
"against" a country?), which is why every reason is shown and every item can be unticked. A question about both
votes and bills reads each separately, so it takes about a minute longer. Like summaries, questions run in the `jobs` process on the single-threaded `summaries` queue, and take a
few minutes with a 14B–27B model on CPU. Set `ASK_MODEL` to a smaller model to trade accuracy for speed.

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

### Evaluating summaries

To tell whether a prompt or model change actually helped, score summaries automatically.
`Summaries::Evaluation` (`app/services/summaries/evaluation.rb`) checks each summary against the record it was
written from. Each check matches one rule in the prompt:

| Check | Fails when |
|---|---|
| `evidence_grounded` | An evidence item isn't in the record, either word for word or as a rewording whose bill numbers, nominations and dates are all real, pairs a real bill number with a title the record doesn't give it, or isn't a bill or vote at all (e.g. `"Health (52 bills)"`) |
| `cited_ids_exist` | Any bill or nomination number anywhere in the summary isn't in the record |
| `party_agreement` | `voting_pattern` gives a different percentage, computes extra ones, or says it's out of a different number of votes than `party_agreement_vote_count` |
| `party_breaks_from_record` | `voting_pattern` mentions more than two votes, a vote not in `votes_against_party_majority`, or the wrong Yea/Nay for one |
| `neutral_language` | Labels like "progressive", "moderate" or "pro-…" appear (unless the record itself uses the word) |
| `no_tenure_claim` | It says when they took office or how long they've served ("serving since 2025", "current term began in 2025"), which the record can't show |
| `topics_from_policy_areas` | A key issue isn't one of `top_policy_areas`, or is one with no tagged bills in the recent lists |
| `evidence_on_topic` | A bill tagged `[Taxation]` in the record is used as evidence for a different topic (areas must match exactly: `[Law]` isn't "Crime and Law Enforcement"), or a bill with no policy area is used at all (strict on purpose; votes are exempt) |
| `limitations_match_scope` | `limitations` leaves out the Congress or the roll-call count from `data_scope` |
| `format` | Wrong number of issues (2-4, fewer only when fewer areas have tagged recent bills), duplicate topics, more than 3 evidence items, sentence counts off, or markdown in the text |

Bill numbers are recognized in citation style (`H.Res. 1247`) and in the compact style of House vote data
(`HRES 1247`). These checks catch mistakes a program can see. They can't tell whether a sentence fairly describes
a bill, or whether prose mentions a bill under the wrong topic, so keep reading some summaries yourself.

```bash
bin/rails summaries:eval                                   # score summaries already saved in the app
bin/rails summaries:eval:generate MODEL=qwen3:8b LIMIT=5   # generate fresh ones (not saved to the app) and score them
bin/rails summaries:eval:compare                           # last 4 runs side by side
```

`generate` defaults to members that already have a saved summary, so runs line up. You can also pass
`MEMBERS=S000033,F000479`. Each run is saved to `tmp/evals/*.json`, along with each summary's text, the record it was
written from, and check details, so `compare` can show which change moved which check. Summaries saved before the app stored their input
are skipped, because rebuilding the record from today's data flags bills that have since dropped off the "recent"
lists. A typical loop: run `generate`, change `prompt.rb` and bump `VERSION`, run `generate` again, then `compare`.
Small models vary from run to run, so treat a difference of one summary as noise.

## API

The frontend uses these JSON endpoints. Errors come back as `{ "error": { "code", "message" } }`.

| Endpoint | Returns |
|---|---|
| `GET /api/members?chamber=senate\|house&q=` | Member list (`q` matches name or state) |
| `GET /api/members/:bioguide_id` | Profile, contact info, committees, counts, vote breakdown |
| `GET /api/members/:bioguide_id/votes?page=` | Roll-call votes (20 per page) |
| `GET /api/members/:bioguide_id/bills?role=sponsor\|cosponsor&page=` | Bills (20 per page) |
| `GET /api/members/:bioguide_id/summary` | AI summary, read-only (`status: "none"` if never generated, `202` while generating) |
| `POST /api/members/:bioguide_id/summary` | Generate or regenerate the AI summary |
| `POST /api/questions` `{ "q": "...", "conversation": token? }` | Starts answering a question (`202`); returns its `token` and `conversation` (a new one if none was given; `409` while the conversation's last question is still being answered) |
| `GET /api/questions/:token` | Status and stage, then the answer, plan, and the votes/bills (or recent activity) used with counts |
| `GET /api/conversations/:token` | Every question in the conversation, oldest first, in the same shape |
| `GET /api/address_suggestions?q=<partial address or state>` | Up to 5 `{ label, kind: "address"\|"state" }` suggestions (3+ characters; cached for a day) |
| `GET /api/representatives?q=<address or state>` | Senators + House member(s); for an address, also the matched address and district |
| `WS /cable` → `MemberSummaryChannel` (`member_id`) | Summary status changes (Action Cable) |
| `WS /cable` → `QuestionChannel` (`token`) | Question stage and status changes |
| `WS /cable` → `ConversationChannel` (`token`) | Stage and status changes for any question in the conversation |

## Project layout

```
app/controllers/api/        JSON API
app/channels/               Action Cable channels for live summary, question and conversation status
app/services/congress/      Data sync from Congress.gov, senate.gov, congress-legislators
app/services/summaries/     AI summary: data packet, prompt + schema, Ollama client, evaluation
app/services/search/        Search index for the question box: embeddings, indexer, hybrid retriever
app/services/ask/           Question box: pipeline, prompts, vote meaning rules, SQL tally, recent activity
app/services/district_lookup.rb   Address -> district via the Census Geocoder
app/services/address_suggestions.rb  Address autocomplete via Photon
app/services/member_summaries.rb  When to start a summary job
app/jobs/                   Background summary generation
lib/tasks/congress.rake     Sync tasks
lib/tasks/summaries.rake    Summary evaluation tasks
lib/tasks/search.rake       Search index task
frontend/src/               React app (pages/, components/)
test/                       Minitest tests (summary evaluation, address suggestions, search, question pipeline)
Procfile.dev, bin/dev       Run Rails + Vite + jobs together
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
in another terminal. After 20 minutes the card shows it as failed with a Retry button.

**`collation version mismatch` warnings, or `db:create` fails on `template1`**
The OS updated glibc, which can change how Postgres sorts text. For each database listed (including `template1`),
rebuild its indexes and record the new version:
`psql -d <db> -c 'REINDEX DATABASE "<db>";' -c 'ALTER DATABASE "<db>" REFRESH COLLATION VERSION;'`

**No address suggestions appear**
They need 3+ characters and a short pause in typing. Suggestions come from Photon's free public server, which
throttles heavy use and can be down; when it fails the box quietly works as a plain search, and the Rails log
shows `AddressSuggestions unavailable`. Only full street addresses and states are suggested, since those are what
the district lookup can resolve.

**Address search says the lookup is unavailable**
The Census Geocoder is down or rejecting requests (it sometimes returns a "Request Rejected" page). Searching by
state still works.

**The question box says it needs a search index**
Run `ollama pull nomic-embed-text`, then `bin/rails search:index`. `PG::UndefinedFile ... extension "vector"` during
`db:prepare` means pgvector isn't installed in your Postgres (see [step 2](#2-install-dependencies-and-create-the-database)).

**Questions or summaries are much slower than usual**
Check `ollama ps`. If the PROCESSOR column shows most of the chat model on CPU, something else is using GPU or RAM
(another model, or a big app). With ~8 GB of GPU memory a 27B model only partly fits; a 14B model fits much better.

**AI summaries are very slow**
That's expected on CPU-only machines (a few minutes each). Try a smaller model (see above). Only one summary
generates at a time; others wait in line.

**Port 5173 or 3000 already in use**
Stop the other process (`lsof -t -i :5173 | xargs kill`) or change the port in `Procfile.dev`.

## Development

```bash
bin/rails db:test:prepare test      # Minitest suite (the first part creates/updates voting_record_test)
bin/rubocop                         # Ruby lint
bin/brakeman && bin/bundler-audit   # security scans
npm --prefix frontend run build     # production build of the frontend (checks it compiles)
```

Tests cover `Summaries::Evaluation`, `AddressSuggestions`, the search retriever, and the question pipeline
(with a scripted fake model, so no Ollama needed). GitHub Actions (`.github/workflows/ci.yml`) runs Brakeman,
bundler-audit, RuboCop and the tests on each push and pull request.
