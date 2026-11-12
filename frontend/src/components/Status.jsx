import { Alert, AlertTitle, Box, Button, CircularProgress } from "@mui/material";
import { Link as RouterLink } from "react-router-dom";

const TITLES = {
  404: "Not found",
  api_unavailable: "API server isn't running",
  network_error: "Connection problem",
  address_not_found: "Address not found",
  lookup_unavailable: "Address lookup unavailable",
  no_members: "No members found",
  database_unavailable: "Database unavailable",
  database_error: "Data not ready",
};

// Shows a spinner while loading, a friendly error (with Retry when it can help), or the children.
export default function Status({ loading, error, onRetry, homeOnNotFound = true, children }) {
  if (loading)
    return (
      <Box sx={{ display: "flex", justifyContent: "center", py: 6 }}>
        <CircularProgress />
      </Box>
    );

  if (error) {
    const notFound = error.status === 404;
    const retryable = error.retryable ?? true;
    return (
      <Alert
        severity={notFound ? "info" : "error"}
        sx={{ my: 2 }}
        action={
          notFound ? (
            homeOnNotFound && <Button component={RouterLink} to="/" color="inherit" size="small">Home</Button>
          ) : (
            retryable && onRetry && <Button color="inherit" size="small" onClick={onRetry}>Retry</Button>
          )
        }
      >
        <AlertTitle>{TITLES[error.code] || TITLES[error.status] || "Something went wrong"}</AlertTitle>
        {error.message || "An unexpected error occurred."}
      </Alert>
    );
  }

  return children;
}
