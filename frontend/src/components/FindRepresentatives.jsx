import { useState } from "react";
import { Alert, Box, Button, Card, CardContent, InputAdornment, TextField, Typography } from "@mui/material";
import PlaceIcon from "@mui/icons-material/Place";
import { api } from "../api.js";
import Status from "./Status.jsx";
import MemberCard from "./MemberCard.jsx";
import { seatLabel } from "../party.js";

const GRID = { display: "grid", gap: 1.5, gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr" } };

// "Who represents me?" — search by street address (exact district) or state (all members for the state).
export default function FindRepresentatives() {
  const [query, setQuery] = useState("");
  const [state, setState] = useState({ data: null, error: null, loading: false });

  const search = async (q = query) => {
    const trimmed = q.trim();
    if (!trimmed) return;
    setState({ data: null, error: null, loading: true });
    try {
      setState({ data: await api.representatives(trimmed), error: null, loading: false });
    } catch (error) {
      setState({ data: null, error, loading: false });
    }
  };

  const { data, error, loading } = state;

  return (
    <Card variant="outlined" sx={{ mb: 5 }}>
      <CardContent>
        <Typography variant="h5" gutterBottom>Find your representatives</Typography>
        <Typography color="text.secondary" sx={{ mb: 2 }}>
          Enter your street address to see your two senators and your House representative, or a state to see everyone
          who represents it.
        </Typography>
        <Box
          component="form"
          onSubmit={(e) => {
            e.preventDefault();
            search();
          }}
          sx={{ display: "flex", gap: 1.5, flexWrap: "wrap" }}
        >
          <TextField
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="e.g. 100 State St, Montpelier, VT  or  Ohio"
            size="small"
            sx={{ flex: "1 1 320px" }}
            slotProps={{
              input: { startAdornment: <InputAdornment position="start"><PlaceIcon /></InputAdornment> },
              htmlInput: { "aria-label": "Address or state" },
            }}
          />
          <Button type="submit" variant="contained" disabled={!query.trim() || loading}>
            Find
          </Button>
        </Box>

        {(loading || error) && (
          <Box sx={{ mt: 2 }}>
            <Status loading={loading} error={error} onRetry={() => search()} homeOnNotFound={false} />
          </Box>
        )}
        {data && <Results data={data} />}
      </CardContent>
    </Card>
  );
}

function Results({ data }) {
  const where =
    data.match_type === "address"
      ? `${data.matched_address} · ${
          data.district ? `District ${data.district}` : data.house[0] ? seatLabel(data.house[0]).split(" · ")[1] : "At-large seat"
        }`
      : data.state;

  return (
    <Box sx={{ mt: 3 }}>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Showing results for <strong>{where}</strong>
      </Typography>

      <Typography variant="subtitle1" fontWeight={700} gutterBottom>Senators</Typography>
      {data.senators.length ? (
        <Box sx={GRID}>{data.senators.map((m) => <MemberCard key={m.bioguide_id} member={m} subtitle={`Senator · ${m.state}`} />)}</Box>
      ) : (
        <Alert severity="info">{data.state || "This location"} has no U.S. senators.</Alert>
      )}

      <Typography variant="subtitle1" fontWeight={700} sx={{ mt: 3 }} gutterBottom>
        {data.match_type === "address" ? "House representative" : `House delegation (${data.house.length})`}
      </Typography>
      {data.house.length ? (
        <Box sx={GRID}>{data.house.map((m) => <MemberCard key={m.bioguide_id} member={m} />)}</Box>
      ) : (
        <Alert severity="info">This House seat is currently vacant.</Alert>
      )}
    </Box>
  );
}
