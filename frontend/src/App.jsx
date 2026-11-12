import { AppBar, Container, Toolbar, Typography } from "@mui/material";
import AccountBalanceIcon from "@mui/icons-material/AccountBalance";
import { Link as RouterLink, Route, Routes, useLocation } from "react-router-dom";
import ChamberPicker from "./pages/ChamberPicker.jsx";
import MemberList from "./pages/MemberList.jsx";
import MemberProfile from "./pages/MemberProfile.jsx";
import ErrorBoundary from "./components/ErrorBoundary.jsx";

export default function App() {
  const location = useLocation();
  return (
    <>
      <AppBar position="sticky" elevation={0}>
        <Toolbar>
          <AccountBalanceIcon sx={{ mr: 1.5 }} />
          <Typography variant="h6" component={RouterLink} to="/" sx={{ color: "inherit", textDecoration: "none" }}>
            Voting Record
          </Typography>
        </Toolbar>
      </AppBar>
      <Container maxWidth="lg" sx={{ py: 4 }}>
        <ErrorBoundary key={location.pathname}>
        <Routes>
          <Route path="/" element={<ChamberPicker />} />
          <Route path="/chamber/:chamber" element={<MemberList />} />
          <Route path="/members/:id" element={<MemberProfile />} />
        </Routes>
        </ErrorBoundary>
      </Container>
    </>
  );
}
