import { useState } from "react";
import {
  Avatar, Box, Breadcrumbs, Card, CardContent, Chip, Link, Paper, Stack, Tab, Tabs, Typography,
} from "@mui/material";
import LanguageIcon from "@mui/icons-material/Language";
import PhoneIcon from "@mui/icons-material/Phone";
import PlaceIcon from "@mui/icons-material/Place";
import { Link as RouterLink, useParams } from "react-router-dom";
import { api } from "../api.js";
import { useFetch } from "../useFetch.js";
import { CHAMBER_LABELS, partyColor, seatLabel } from "../party.js";
import Status from "../components/Status.jsx";
import VotesTab from "../components/VotesTab.jsx";
import BillsTab from "../components/BillsTab.jsx";
import CommitteesTab from "../components/CommitteesTab.jsx";
import SummaryCard from "../components/SummaryCard.jsx";

export default function MemberProfile() {
  const { id } = useParams();
  const { data: m, error, loading, reload } = useFetch(() => api.member(id), [id]);
  const [tab, setTab] = useState("votes");

  return (
    <Status loading={loading} error={error} onRetry={reload}>
      {m && (
        <>
          <Breadcrumbs sx={{ mb: 2 }}>
            <Link component={RouterLink} to="/" underline="hover" color="inherit">Chambers</Link>
            <Link component={RouterLink} to={`/chamber/${m.chamber}`} underline="hover" color="inherit">
              {CHAMBER_LABELS[m.chamber]}
            </Link>
            <Typography color="text.primary">{m.full_name}</Typography>
          </Breadcrumbs>

          <Card variant="outlined" sx={{ mb: 3 }}>
            <CardContent sx={{ display: "flex", gap: 3, flexWrap: "wrap", alignItems: "center" }}>
              <Avatar src={m.image_url} alt={m.full_name} sx={{ width: 112, height: 112 }} />
              <Box sx={{ flex: "1 1 280px" }}>
                <Typography variant="h4">{m.full_name}</Typography>
                <Stack direction="row" spacing={1} sx={{ my: 1, flexWrap: "wrap" }}>
                  <Chip label={m.party} size="small" sx={{ bgcolor: partyColor(m.party), color: "#fff" }} />
                  <Chip label={m.chamber === "senate" ? "Senator" : "Representative"} size="small" variant="outlined" />
                  <Chip label={seatLabel(m)} size="small" variant="outlined" />
                </Stack>
                <Stack spacing={0.5} sx={{ color: "text.secondary" }}>
                  {m.website_url && (
                    <Contact icon={<LanguageIcon fontSize="small" />}>
                      <Link href={m.website_url} target="_blank" rel="noreferrer">{m.website_url.replace(/^https?:\/\//, "")}</Link>
                    </Contact>
                  )}
                  {m.phone && <Contact icon={<PhoneIcon fontSize="small" />}>{m.phone}</Contact>}
                  {m.office_address && <Contact icon={<PlaceIcon fontSize="small" />}>{m.office_address}</Contact>}
                </Stack>
              </Box>
              <Stack direction="row" spacing={2}>
                <Stat label="Votes synced" value={m.counts.votes} />
                <Stat label="Sponsored" value={m.counts.sponsored} />
                <Stat label="Cosponsored" value={m.counts.cosponsored} />
                <Stat label="Committees" value={m.committees.length} />
              </Stack>
            </CardContent>
          </Card>

          <SummaryCard id={m.bioguide_id} />

          <Paper variant="outlined">
            <Tabs value={tab} onChange={(_, v) => setTab(v)} variant="scrollable" sx={{ borderBottom: 1, borderColor: "divider" }}>
              <Tab value="votes" label="Votes" />
              <Tab value="committees" label="Committees" />
              <Tab value="sponsor" label="Sponsored bills" />
              <Tab value="cosponsor" label="Cosponsored bills" />
            </Tabs>
            <Box sx={{ p: 2 }}>
              {tab === "votes" && <VotesTab id={m.bioguide_id} breakdown={m.vote_breakdown} />}
              {tab === "committees" && <CommitteesTab committees={m.committees} />}
              {(tab === "sponsor" || tab === "cosponsor") && <BillsTab key={tab} id={m.bioguide_id} role={tab} />}
            </Box>
          </Paper>
        </>
      )}
    </Status>
  );
}

function Contact({ icon, children }) {
  return (
    <Stack direction="row" spacing={1} sx={{ alignItems: "center" }}>
      {icon}
      <Typography variant="body2" component="span">{children}</Typography>
    </Stack>
  );
}

function Stat({ label, value }) {
  return (
    <Box sx={{ textAlign: "center", minWidth: 72 }}>
      <Typography variant="h5" fontWeight={700}>{value}</Typography>
      <Typography variant="caption" color="text.secondary">{label}</Typography>
    </Box>
  );
}
