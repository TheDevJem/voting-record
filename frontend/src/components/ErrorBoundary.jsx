import { Component } from "react";
import { Alert, AlertTitle, Button } from "@mui/material";

// Last line of defense: a rendering bug shows a message instead of a blank page.
export default class ErrorBoundary extends Component {
  state = { error: null };

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error("UI error:", error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <Alert severity="error" action={<Button color="inherit" size="small" onClick={() => window.location.reload()}>Reload</Button>}>
        <AlertTitle>Something went wrong</AlertTitle>
        This page hit an unexpected problem. Reloading usually fixes it.
      </Alert>
    );
  }
}
