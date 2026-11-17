import { useEffect, useRef, useState } from "react";
import {
  Alert, Autocomplete, Box, Button, Card, CardContent, InputAdornment, Link, TextField, Typography,
} from "@mui/material";
import PlaceIcon from "@mui/icons-material/Place";
import MapIcon from "@mui/icons-material/Map";
import { api } from "../api.js";
import Status from "./Status.jsx";
import MemberCard from "./MemberCard.jsx";
import { seatLabel } from "../party.js";

const GRID = { display: "grid", gap: 1.5, gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr" } };
const SUGGEST_MIN_LENGTH = 3; // matches AddressSuggestions::MIN_LENGTH on the server
const SUGGEST_DELAY_MS = 300; // wait for a pause in typing: the free Photon server asks for light use

// Address/state suggestions from the server (Photon, OpenStreetMap data). Best effort: any failure just means
// no suggestions, and the box still works as a plain text search.
function useAddressSuggestions(query, enabled) {
  const [suggestions, setSuggestions] = useState([]);

  useEffect(() => {
    const q = query.trim();
    if (!enabled || q.length < SUGGEST_MIN_LENGTH) {
      setSuggestions([]);
      return undefined;
    }
    const controller = new AbortController();
    const timer = setTimeout(() => {
      api.addressSuggestions(q, controller.signal)
        .then((data) => setSuggestions(data.suggestions || []))
        .catch(() => {}); // aborted, offline, or Photon unavailable
    }, SUGGEST_DELAY_MS);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [query, enabled]);

  return suggestions;
}

// "Who represents me?" — search by street address (exact district) or state (all members for the state).
export default function FindRepresentatives() {
  const [query, setQuery] = useState("");
  const [state, setState] = useState({ data: null, error: null, loading: false });
  // Off right after a search or a picked suggestion, so the list doesn't reopen for text the user didn't type.
  const [suggesting, setSuggesting] = useState(true);
  const suggestions = useAddressSuggestions(query, suggesting);
  const inputRef = useRef(null);

  const search = async (q = query) => {
    const trimmed = q.trim();
    if (!trimmed) return;
    setSuggesting(false);
    inputRef.current?.blur();
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
          <Autocomplete
            freeSolo
            options={suggestions}
            filterOptions={(x) => x} // the server already matched them
            getOptionLabel={(o) => (typeof o === "string" ? o : o.label)}
            inputValue={query}
            onInputChange={(_, value, reason) => {
              if (reason !== "input") return; // "reset" fires when an option is chosen; onChange handles that
              setQuery(value);
              setSuggesting(true);
            }}
            // Picking a suggestion searches right away. Free text is submitted by the form (Enter or Find).
            onChange={(_, value, reason) => {
              if (reason !== "selectOption" || !value) return;
              const label = typeof value === "string" ? value : value.label;
              setQuery(label);
              search(label);
            }}
            renderOption={({ key, ...props }, o) => (
              <Box component="li" key={key} {...props} sx={{ display: "flex", gap: 1.5, alignItems: "center" }}>
                {o.kind === "state" ? <MapIcon fontSize="small" color="action" /> : <PlaceIcon fontSize="small" color="action" />}
                <span>{o.label}</span>
                {o.kind === "state" && <Typography variant="caption" color="text.secondary">State</Typography>}
              </Box>
            )}
            sx={{ flex: "1 1 320px" }}
            renderInput={(params) => (
              <TextField
                {...params}
                inputRef={inputRef}
                placeholder="e.g. 100 State St, Montpelier, VT  or  Ohio"
                size="small"
                // MUI 9 passes the Autocomplete's wiring (anchor ref, key handling, ARIA) in params.slotProps.
                slotProps={{
                  ...params.slotProps,
                  input: {
                    ...params.slotProps.input,
                    startAdornment: <InputAdornment position="start"><PlaceIcon /></InputAdornment>,
                  },
                  htmlInput: { ...params.slotProps.htmlInput, "aria-label": "Address or state" },
                }}
              />
            )}
          />
          <Button type="submit" variant="contained" disabled={!query.trim() || loading}>
            Find
          </Button>
        </Box>
        <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 0.75 }}>
          Suggestions by <Link href="https://photon.komoot.io" target="_blank" rel="noreferrer">Photon</Link> from{" "}
          <Link href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">© OpenStreetMap contributors</Link>.
          District lookup by the US Census Geocoder.
        </Typography>

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
