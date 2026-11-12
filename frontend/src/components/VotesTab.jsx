import { Box, Chip, Divider, Link, Stack, Typography } from "@mui/material";
import OpenInNewIcon from "@mui/icons-material/OpenInNew";
import { api } from "../api.js";
import PagedList from "./PagedList.jsx";

const POSITION_COLORS = { Yea: "success", Nay: "error", Guilty: "success", "Not Guilty": "error", Present: "info" };

export default function VotesTab({ id, breakdown }) {
  return (
    <>
      <Stack direction="row" spacing={1} sx={{ mb: 2, flexWrap: "wrap" }}>
        {Object.entries(breakdown || {}).map(([position, count]) => (
          <Chip key={position} label={`${position}: ${count}`} color={POSITION_COLORS[position] || "default"} variant="outlined" />
        ))}
      </Stack>
      <PagedList
        load={(page) => api.votes(id, page)}
        deps={[id]}
        empty="No roll-call votes synced for this member yet."
        renderItem={(v) => (
          <Box key={v.id}>
            <Stack direction="row" spacing={2} sx={{ py: 1.5, alignItems: "flex-start" }}>
              <Chip label={v.position} color={POSITION_COLORS[v.position] || "default"} sx={{ minWidth: 96 }} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography fontWeight={600}>
                  {v.question}
                  {v.legislation && <> · {v.legislation}</>}
                </Typography>
                {v.description && <Typography variant="body2" color="text.secondary">{v.description}</Typography>}
                <Typography variant="caption" color="text.secondary">
                  {new Date(v.voted_at).toLocaleDateString(undefined, { dateStyle: "medium" })} · Roll call {v.number} ·{" "}
                  {v.result} ({v.yeas}–{v.nays})
                  {v.source_url && (
                    <>
                      {" · "}
                      <Link
                        href={v.source_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        aria-label={`Official record of roll call ${v.number} (opens in a new tab)`}
                        sx={{ display: "inline-flex", alignItems: "center", gap: 0.25 }}
                      >
                        official record <OpenInNewIcon sx={{ fontSize: 12 }} />
                      </Link>
                    </>
                  )}
                </Typography>
              </Box>
            </Stack>
            <Divider />
          </Box>
        )}
      />
    </>
  );
}
