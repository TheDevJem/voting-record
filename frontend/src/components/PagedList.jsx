import { useState } from "react";
import { Box, Pagination, Typography } from "@mui/material";
import { useFetch } from "../useFetch.js";
import Status from "./Status.jsx";

// Fetches one page at a time with `load(page)` and renders each item with `renderItem`.
export default function PagedList({ load, deps, renderItem, empty }) {
  const [page, setPage] = useState(1);
  const { data, error, loading, reload } = useFetch(() => load(page), [...deps, page]);

  return (
    <Status loading={loading} error={error} onRetry={reload}>
      {data && data.total === 0 && <Typography color="text.secondary" sx={{ py: 2 }}>{empty}</Typography>}
      {data && data.total > 0 && (
        <>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>{data.total} total</Typography>
          {data.items.map(renderItem)}
          {data.total_pages > 1 && (
            <Box sx={{ display: "flex", justifyContent: "center", mt: 2 }}>
              <Pagination count={data.total_pages} page={page} onChange={(_, p) => setPage(p)} color="primary" />
            </Box>
          )}
        </>
      )}
    </Status>
  );
}
