import { useMemo, useState } from "react";
import {
  Alert, Box, Breadcrumbs, InputAdornment, Link, TextField, ToggleButton, ToggleButtonGroup, Typography,
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";
import { Link as RouterLink, useParams } from "react-router-dom";
import { api } from "../api.js";
import { useFetch } from "../useFetch.js";
import { CHAMBER_LABELS, partyLetter } from "../party.js";
import Status from "../components/Status.jsx";
import MemberCard from "../components/MemberCard.jsx";

export default function MemberList() {
  const { chamber } = useParams();
  const { data, error, loading, reload } = useFetch(() => api.members(chamber), [chamber]);
  const [query, setQuery] = useState("");
  const [party, setParty] = useState("all");

  const members = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (data || []).filter(
      (m) =>
        (party === "all" || partyLetter(m.party) === party) &&
        (!q || [m.full_name, m.state, m.state_code].some((v) => v?.toLowerCase().includes(q)))
    );
  }, [data, query, party]);

  return (
    <>
      <Breadcrumbs sx={{ mb: 2 }}>
        <Link component={RouterLink} to="/" underline="hover" color="inherit">Chambers</Link>
        <Typography color="text.primary">{CHAMBER_LABELS[chamber]}</Typography>
      </Breadcrumbs>
      <Typography variant="h4" gutterBottom>{CHAMBER_LABELS[chamber]}</Typography>

      <Box sx={{ display: "flex", gap: 2, flexWrap: "wrap", alignItems: "center", mb: 3 }}>
        <TextField
          size="small"
          placeholder="Search by name or state"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          sx={{ flex: "1 1 260px", bgcolor: "background.paper" }}
          slotProps={{ input: { startAdornment: <InputAdornment position="start"><SearchIcon /></InputAdornment> } }}
        />
        <ToggleButtonGroup size="small" exclusive value={party} onChange={(_, v) => v && setParty(v)}>
          <ToggleButton value="all">All</ToggleButton>
          <ToggleButton value="D">Democrat</ToggleButton>
          <ToggleButton value="R">Republican</ToggleButton>
          <ToggleButton value="I">Independent</ToggleButton>
        </ToggleButtonGroup>
        {data && <Typography color="text.secondary">{members.length} of {data.length}</Typography>}
      </Box>

      <Status loading={loading} error={error} onRetry={reload}>
        {data?.length === 0 && (
          <Alert severity="info">No members synced yet. Run <code>bin/rails congress:sync</code>.</Alert>
        )}
        <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr", md: "repeat(3, 1fr)" } }}>
          {members.map((m) => (
            <MemberCard key={m.bioguide_id} member={m} />
          ))}
        </Box>
      </Status>
    </>
  );
}
