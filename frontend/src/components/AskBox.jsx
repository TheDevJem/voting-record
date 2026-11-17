import { useEffect, useMemo, useRef, useState } from "react";
import {
  Accordion, AccordionDetails, AccordionSummary, Alert, Box, Button, Card, CardContent, Checkbox, Chip, Divider,
  LinearProgress, Link, Stack, Step, StepLabel, Stepper, TextField, Typography,
} from "@mui/material";
import AutoAwesomeIcon from "@mui/icons-material/AutoAwesome";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import { Link as RouterLink, useSearchParams } from "react-router-dom";
import { api } from "../api.js";
import { consumer } from "../cable.js";
import { partyColor } from "../party.js";

const EXAMPLES = [
  "How many Democrats support Israel?",
  "How many Democrats voted to fund Israel? List them.",
  "Which Republicans voted against abortion bans?",
  "Which senators cosponsored bills on Social Security?",
];

const STAGES = [
  ["planning", "Understanding the question"],
  ["searching", "Searching votes and bills"],
  ["reading", "Reading the matches"],
  ["counting", "Counting"],
  ["writing", "Writing the answer"],
];

// Status changes arrive over Action Cable; this slow poll only covers a WebSocket that can't connect.
const FALLBACK_POLL_MS = 60000;

// Loads a question by token and keeps it fresh while it's being answered.
function useQuestion(token) {
  const [question, setQuestion] = useState(null);
  const [error, setError] = useState(null);
  const timer = useRef(null);

  useEffect(() => {
    if (!token) {
      setQuestion(null);
      return undefined;
    }
    let live = true;
    const load = () => {
      clearTimeout(timer.current);
      api.question(token)
        .then((q) => {
          if (!live) return;
          setQuestion(q);
          setError(null);
          if (q.status === "pending" || q.status === "running") timer.current = setTimeout(load, FALLBACK_POLL_MS);
        })
        .catch((err) => live && setError(err));
    };
    setQuestion(null);
    load();
    const subscription = consumer.subscriptions.create(
      { channel: "QuestionChannel", token },
      { connected: load, received: load },
    );
    return () => {
      live = false;
      subscription.unsubscribe();
      clearTimeout(timer.current);
    };
  }, [token]);

  return { question, error };
}

// "Ask about votes and bills": a local model plans the search and reads the matches; the counts come from SQL.
export default function AskBox() {
  const [params, setParams] = useSearchParams();
  const token = params.get("question");
  const [text, setText] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState(null);
  const { question, error } = useQuestion(token);

  useEffect(() => {
    if (question?.text) setText(question.text);
  }, [question?.text]);

  const ask = async (q = text) => {
    const trimmed = q.trim();
    if (!trimmed) return;
    setText(trimmed);
    setSubmitting(true);
    setSubmitError(null);
    try {
      const created = await api.askQuestion(trimmed);
      setParams((p) => { p.set("question", created.token); return p; });
    } catch (err) {
      setSubmitError(err);
    } finally {
      setSubmitting(false);
    }
  };

  const busy = submitting || question?.status === "pending" || question?.status === "running";

  return (
    <Card variant="outlined" sx={{ mb: 5 }}>
      <CardContent>
        <Stack direction="row" spacing={1} sx={{ alignItems: "center", mb: 1 }}>
          <AutoAwesomeIcon color="primary" />
          <Typography variant="h5">Ask about votes and bills</Typography>
        </Stack>
        <Typography color="text.secondary" sx={{ mb: 2 }}>
          Ask how members voted or what they sponsored. A local AI model finds the matching votes or bills and
          decides which way each vote points; the counts come straight from the data. Takes a minute or two.
        </Typography>

        <Box component="form" onSubmit={(e) => { e.preventDefault(); ask(); }} sx={{ display: "flex", gap: 1.5, flexWrap: "wrap" }}>
          <TextField
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="e.g. How many Democrats voted to fund Israel?"
            size="small"
            sx={{ flex: "1 1 360px" }}
            slotProps={{ htmlInput: { maxLength: 500, "aria-label": "Question" } }}
          />
          <Button type="submit" variant="contained" disabled={!text.trim() || busy}>Ask</Button>
        </Box>
        <Stack direction="row" sx={{ flexWrap: "wrap", gap: 1, mt: 1.5 }}>
          {EXAMPLES.map((ex) => (
            <Chip key={ex} label={ex} size="small" variant="outlined" disabled={busy} onClick={() => ask(ex)} />
          ))}
        </Stack>

        {(submitError || error) && (
          <Alert severity="error" sx={{ mt: 2 }}>{(submitError || error).message}</Alert>
        )}
        {question && <QuestionView question={question} onRetry={() => ask(question.text)} />}
      </CardContent>
    </Card>
  );
}

function QuestionView({ question: q, onRetry }) {
  if (q.status === "pending" || q.status === "running") return <Progress question={q} />;
  if (q.status === "failed") {
    return (
      <Alert severity="warning" sx={{ mt: 2 }} action={<Button color="inherit" size="small" onClick={onRetry}>Ask again</Button>}>
        {q.error || "Couldn't answer that question."}
      </Alert>
    );
  }
  return <Answer key={q.token} question={q} />; // key: a new question resets the ticked votes
}

function Progress({ question: q }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(tick);
  }, []);
  const elapsed = Math.max(0, Math.round((now - new Date(q.started_at || q.created_at)) / 1000));
  const active = q.status === "pending" ? -1 : STAGES.findIndex(([key]) => key === q.stage);

  return (
    <Box sx={{ mt: 3 }}>
      <LinearProgress sx={{ mb: 2 }} />
      <Stepper activeStep={active} alternativeLabel sx={{ mb: 1 }}>
        {STAGES.map(([key, label]) => <Step key={key}><StepLabel>{label}</StepLabel></Step>)}
      </Stepper>
      <Typography variant="body2" color="text.secondary" sx={{ textAlign: "center" }}>
        {q.status === "pending" ? "Waiting for the local model (it answers one request at a time)" : "Working"} ·{" "}
        {Math.floor(elapsed / 60)}:{String(elapsed % 60).padStart(2, "0")} elapsed
      </Typography>
    </Box>
  );
}

function Answer({ question: q }) {
  const plan = q.plan || {};
  const result = q.result || {};
  const votes = result.votes || [];
  const bills = result.bills || result.items || []; // `items`: questions saved before votes and bills were combined
  const [keptVotes, toggleVote] = useToggleSet(votes.map((v) => v.roll_call_id));
  const [keptBills, toggleBill] = useToggleSet(bills.map((b) => b.bill_id));
  const showVotes = result.votes !== undefined;
  const showBills = result.bills !== undefined || result.items !== undefined;

  return (
    <Box sx={{ mt: 3 }}>
      <Typography sx={{ mb: 1 }}>{q.answer}</Typography>
      <Typography variant="caption" color="text.secondary" component="p" sx={{ mb: 2 }}>
        Written by <strong>{q.model}</strong> running locally, from the votes and bills below. AI answers can contain
        mistakes; check what it used and how it read each one.
      </Typography>

      <Stack direction="row" sx={{ flexWrap: "wrap", gap: 1, mb: 2 }}>
        <Chip size="small" label={`Searched for: ${plan.search}`} />
        <Chip size="small" label={`Looked at: ${{ votes: "votes", bills: "bills", both: "votes and bills" }[result.kind] || result.kind}`} />
        {plan.party_filter && <Chip size="small" label={`Party: ${plan.party_filter}`} />}
        {plan.chamber_filter && <Chip size="small" label={`Chamber: ${plan.chamber_filter}`} />}
        {plan.stance && <Chip size="small" label={`Counting: ${plan.stance}`} />}
        {plan.role_filter && <Chip size="small" label={`Role: ${plan.role_filter}`} />}
      </Stack>

      <Totals votes={votes.filter((v) => keptVotes.has(v.roll_call_id))} bills={bills.filter((b) => keptBills.has(b.bill_id))}
        plan={plan} showVotes={showVotes} showBills={showBills} />

      {showVotes && (
        <Section title={`Votes used (${keptVotes.size} of ${votes.length})`} empty={votes.length === 0 && "No matching votes were found in the synced roll calls."}>
          {votes.map((v) => (
            <VoteCard key={v.roll_call_id} vote={v} plan={plan} included={keptVotes.has(v.roll_call_id)} onToggle={() => toggleVote(v.roll_call_id)} />
          ))}
        </Section>
      )}
      {showBills && (
        <Section title={`Bills used (${keptBills.size} of ${bills.length})`} empty={bills.length === 0 && "No matching bills were found."}>
          {bills.map((b) => (
            <BillCard key={b.bill_id} bill={b} plan={plan} included={keptBills.has(b.bill_id)} onToggle={() => toggleBill(b.bill_id)} />
          ))}
        </Section>
      )}
      {result.rejected?.length > 0 && <Rejected items={result.rejected} />}
    </Box>
  );
}

function useToggleSet(ids) {
  const [set, setSet] = useState(() => new Set(ids));
  const toggle = (id) => setSet((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  return [set, toggle];
}

function Section({ title, empty, children }) {
  return (
    <Box sx={{ mb: 2 }}>
      <Typography variant="subtitle1" fontWeight={700} sx={{ mb: 1 }}>{title}</Typography>
      {empty ? <Alert severity="info">{empty}</Alert> : children}
    </Box>
  );
}

// Distinct members across the ticked votes and bills, computed here so unticking updates it (the server computes
// the same counts for the written answer). With a stance, members are split into matching and opposite sides.
function Totals({ votes, bills, plan, showVotes, showBills }) {
  const members = useMemo(() => {
    const byId = new Map();
    const entry = (m) => byId.get(m.bioguide_id) || byId.set(m.bioguide_id, { ...m, forVotes: 0, forBills: 0, against: 0, bills: 0 }).get(m.bioguide_id);
    votes.filter((v) => v.counts_as).forEach((v) => v.members.forEach((m) => {
      if (m.position === v.counts_as) entry(m).forVotes += 1;
      else if (m.position === "Yea" || m.position === "Nay") entry(m).against += 1;
    }));
    bills.forEach((b) => b.members.forEach((m) => {
      if (!plan.stance) entry(m).bills += 1;
      else if (b.supports === true) entry(m).forBills += 1;
      else if (b.supports === false) entry(m).against += 1;
    }));
    return [...byId.values()];
  }, [votes, bills, plan.stance]);

  const who = plan.party_filter ? `${plan.party_filter} members` : "members";

  if (!plan.stance) {
    if (!showBills || bills.length === 0) return null;
    const onBills = members.filter((m) => m.bills > 0).sort((a, b) => b.bills - a.bills || a.name.localeCompare(b.name));
    return (
      <TotalsBox title={`${onBills.length} ${who} on ${bills.length} bills`}>
        <MemberChips members={onBills} suffix={(m) => (bills.length > 1 ? ` ×${m.bills}` : "")} />
      </TotalsBox>
    );
  }

  const counted = votes.filter((v) => v.counts_as).length + bills.filter((b) => b.supports !== null && b.supports !== undefined).length;
  if (counted === 0) {
    return <Alert severity="info" sx={{ mb: 2 }}>None of the votes or bills below could be read as for or against "{plan.stance}".</Alert>;
  }
  const matching = members.filter((m) => m.forVotes + m.forBills > 0)
    .sort((a, b) => b.forVotes + b.forBills - (a.forVotes + a.forBills) || a.name.localeCompare(b.name));
  const opposite = members.filter((m) => m.against > 0 && m.forVotes + m.forBills === 0).sort((a, b) => b.against - a.against || a.name.localeCompare(b.name));
  const mixed = matching.filter((m) => m.against > 0).length;
  const how = (m) => [m.forVotes && `${m.forVotes} vote${m.forVotes > 1 ? "s" : ""}`, m.forBills && `${m.forBills} bill${m.forBills > 1 ? "s" : ""}`]
    .filter(Boolean).join(", ");
  const parts = [showVotes && `${matching.filter((m) => m.forVotes).length} by vote`, showBills && `${matching.filter((m) => m.forBills).length} by bill`].filter(Boolean);

  return (
    <TotalsBox title={`${matching.length} ${who} ${plan.stance} (${parts.join(", ")})`}>
      {mixed > 0 && (
        <Typography variant="body2" color="text.secondary">{mixed} of them also took the opposite position at least once.</Typography>
      )}
      <MemberChips members={matching} suffix={(m) => ` · ${how(m)}`} />
      {opposite.length > 0 && (
        <Accordion disableGutters elevation={0} sx={{ bgcolor: "transparent", mt: 1, "&:before": { display: "none" } }}>
          <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ px: 0, minHeight: 0 }}>
            <Typography variant="body2">{opposite.length} {who} only took the opposite position</Typography>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 0 }}><MemberChips members={opposite} /></AccordionDetails>
        </Accordion>
      )}
    </TotalsBox>
  );
}

function TotalsBox({ title, children }) {
  return (
    <Box sx={{ mb: 3, p: 2, borderRadius: 2, bgcolor: "action.hover" }}>
      <Typography fontWeight={700}>{title}</Typography>
      {children}
    </Box>
  );
}

function VoteCard({ vote: v, included, onToggle, plan }) {
  const positions = ["Yea", "Nay", "Present", "Not Voting"];
  const grouped = positions.map((p) => [p, v.members.filter((m) => m.position === p)]).filter(([, ms]) => ms.length);
  return (
    <ItemCard included={included} onToggle={onToggle} noun="vote">
      <Typography variant="body2" color="text.secondary">
        {v.chamber === "senate" ? "Senate" : "House"} roll call {v.number} · {v.date} · {v.question}
        {v.legislation && <> · {v.bill_url ? <Link href={v.bill_url} target="_blank" rel="noreferrer">{v.legislation}</Link> : v.legislation}</>}
        {v.amendment?.label && <> · {v.amendment.label}{v.amendment.sponsor && ` (${v.amendment.sponsor})`}</>}
      </Typography>
      <Typography fontWeight={600}>{v.amendment?.purpose || v.title}</Typography>
      {v.amendment?.purpose && v.title && <Typography variant="body2" color="text.secondary">Amendment to: {v.title}</Typography>}
      <Typography variant="body2" color="text.secondary">
        {v.result} ({v.yeas}–{v.nays})
        {v.source_url && <> · <Link href={v.source_url} target="_blank" rel="noreferrer">Official record</Link></>}
      </Typography>
      <Summary text={v.summary} />
      <Alert severity={v.counts_as ? "info" : "success"} icon={false} sx={{ mt: 1, py: 0 }}>
        {v.counts_as ? <><strong>Counted {v.counts_as}</strong> as "{plan.stance}". </> : null}
        {v.reason}
        {v.meaning && (
          <Typography variant="caption" component="p" color="text.secondary" sx={{ mt: 0.5 }}>
            What a Yea means (worked out from the motion, not by the AI): {v.meaning}
          </Typography>
        )}
      </Alert>
      <Breakdown breakdown={v.breakdown} />
      <Accordion disableGutters elevation={0} sx={{ bgcolor: "transparent", "&:before": { display: "none" } }}>
        <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ px: 0, minHeight: 0 }}>
          <Typography variant="body2">{plan.party_filter ? `${plan.party_filter} members` : "Members"} ({v.members.length})</Typography>
        </AccordionSummary>
        <AccordionDetails sx={{ px: 0 }}>
          {grouped.map(([p, ms]) => (
            <Box key={p} sx={{ mb: 1 }}>
              <Typography variant="caption" fontWeight={700}>{p} ({ms.length})</Typography>
              <MemberChips members={ms} />
            </Box>
          ))}
        </AccordionDetails>
      </Accordion>
    </ItemCard>
  );
}

function BillCard({ bill: b, included, onToggle, plan }) {
  const direction = b.supports === true ? "Sponsoring counted as" : b.supports === false ? "Sponsoring counted as the opposite of" : null;
  return (
    <ItemCard included={included} onToggle={onToggle} noun="bill">
      <Typography variant="body2" color="text.secondary">
        {b.url ? <Link href={b.url} target="_blank" rel="noreferrer">{b.label}</Link> : b.label}
        {b.policy_area && <> · {b.policy_area}</>} · Introduced {b.introduced_date}
      </Typography>
      <Typography fontWeight={600}>{b.title}</Typography>
      <Summary text={b.summary} />
      <Alert severity={direction ? "info" : "success"} icon={false} sx={{ mt: 1, py: 0 }}>
        {direction && <><strong>{direction}</strong> "{plan.stance}". </>}
        {b.reason}
      </Alert>
      <Typography variant="caption" fontWeight={700} component="p" sx={{ mt: 1 }}>
        {plan.party_filter ? `${plan.party_filter} sponsors and cosponsors` : "Sponsors and cosponsors"} ({b.members.length})
      </Typography>
      <MemberChips members={b.members} suffix={(m) => (m.role === "sponsor" ? " (sponsor)" : "")} />
    </ItemCard>
  );
}

function ItemCard({ included, onToggle, noun, children }) {
  return (
    <Card variant="outlined" sx={{ mb: 1.5, opacity: included ? 1 : 0.55 }}>
      <CardContent sx={{ pb: "12px !important" }}>
        <Stack direction="row" spacing={1} sx={{ alignItems: "flex-start" }}>
          <Checkbox size="small" checked={included} onChange={onToggle}
            slotProps={{ input: { "aria-label": `${included ? "Exclude" : "Include"} this ${noun} in the totals` } }} />
          <Box sx={{ minWidth: 0, flex: 1 }}>{children}</Box>
        </Stack>
      </CardContent>
    </Card>
  );
}

// The CRS summary, collapsed to two lines until clicked.
function Summary({ text }) {
  const [open, setOpen] = useState(false);
  if (!text) return null;
  return (
    <Typography variant="body2" onClick={() => setOpen((o) => !o)} title={open ? "Show less" : "Show the full summary"}
      sx={{ mt: 0.5, cursor: "pointer", ...(!open && { display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }) }}>
      <strong>Summary (CRS):</strong> {text}
    </Typography>
  );
}

function Breakdown({ breakdown = {} }) {
  return (
    <Stack direction="row" sx={{ flexWrap: "wrap", gap: 2, mt: 1 }}>
      {Object.entries(breakdown).map(([party, counts]) => (
        <Typography key={party} variant="body2">
          <Box component="span" sx={{ color: partyColor(party), fontWeight: 700 }}>{party}</Box>:{" "}
          {Object.entries(counts).map(([pos, n]) => `${n} ${pos}`).join(", ")}
        </Typography>
      ))}
    </Stack>
  );
}

function MemberChips({ members, suffix = () => "" }) {
  return (
    <Stack direction="row" sx={{ flexWrap: "wrap", gap: 0.5, mt: 0.5 }}>
      {members.map((m) => (
        <Chip key={m.bioguide_id} size="small" variant="outlined" clickable component={RouterLink} to={`/members/${m.bioguide_id}`}
          label={`${m.name} (${m.party[0]}-${m.state_code})${suffix(m)}`}
          sx={{ borderColor: partyColor(m.party) }} />
      ))}
    </Stack>
  );
}

function Rejected({ items }) {
  return (
    <Accordion disableGutters variant="outlined" sx={{ mt: 2 }}>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="body2">Also found, judged not relevant ({items.length})</Typography>
      </AccordionSummary>
      <AccordionDetails>
        {items.map((x, i) => (
          <Box key={i} sx={{ mb: 1 }}>
            <Typography variant="body2">{x.kind === "bill" ? "Bill · " : x.kind === "vote" ? "Vote · " : ""}{x.text}</Typography>
            <Typography variant="caption" color="text.secondary">{x.reason}</Typography>
            {i < items.length - 1 && <Divider sx={{ mt: 1 }} />}
          </Box>
        ))}
      </AccordionDetails>
    </Accordion>
  );
}
