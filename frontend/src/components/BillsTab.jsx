import { Box, Chip, Divider, Link, Stack, Typography } from "@mui/material";
import { api } from "../api.js";
import PagedList from "./PagedList.jsx";

export default function BillsTab({ id, role }) {
  return (
    <PagedList
      load={(page) => api.bills(id, role, page)}
      deps={[id, role]}
      empty={role === "sponsor" ? "No sponsored bills this Congress." : "No cosponsored bills this Congress."}
      renderItem={(b) => (
        <Box key={b.id}>
          <Box sx={{ py: 1.5 }}>
            <Stack direction="row" spacing={1} sx={{ alignItems: "center", mb: 0.5, flexWrap: "wrap" }}>
              {b.url ? (
                <Link href={b.url} target="_blank" rel="noreferrer" fontWeight={700}>{b.label}</Link>
              ) : (
                <Typography fontWeight={700}>{b.label}</Typography>
              )}
              {b.policy_area && <Chip label={b.policy_area} size="small" variant="outlined" />}
              <Typography variant="caption" color="text.secondary">Introduced {b.introduced_date}</Typography>
            </Stack>
            <Typography>{b.title}</Typography>
            {b.latest_action_text && (
              <Typography variant="body2" color="text.secondary">
                Latest action ({b.latest_action_date}): {b.latest_action_text}
              </Typography>
            )}
          </Box>
          <Divider />
        </Box>
      )}
    />
  );
}
