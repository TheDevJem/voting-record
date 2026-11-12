import { Box, Card, CardActionArea, CardContent, Typography } from "@mui/material";
import GavelIcon from "@mui/icons-material/Gavel";
import GroupsIcon from "@mui/icons-material/Groups";
import { useNavigate } from "react-router-dom";
import FindRepresentatives from "../components/FindRepresentatives.jsx";

const CHAMBERS = [
  { key: "senate", title: "Senate", blurb: "100 senators, two per state", Icon: GavelIcon },
  { key: "house", title: "House of Representatives", blurb: "435 representatives plus non-voting delegates", Icon: GroupsIcon },
];

export default function ChamberPicker() {
  const navigate = useNavigate();
  return (
    <>
      <FindRepresentatives />
      <Typography variant="h4" gutterBottom>
        Browse by chamber
      </Typography>
      <Typography color="text.secondary" sx={{ mb: 4 }}>
        Choose a chamber to browse its members, then pick a member to see their votes, committees and bills.
      </Typography>
      <Box sx={{ display: "grid", gap: 3, gridTemplateColumns: { xs: "1fr", md: "1fr 1fr" } }}>
        {CHAMBERS.map(({ key, title, blurb, Icon }) => (
          <Card key={key} variant="outlined">
            <CardActionArea onClick={() => navigate(`/chamber/${key}`)} sx={{ p: 2 }}>
              <CardContent>
                <Icon color="primary" sx={{ fontSize: 48, mb: 1 }} />
                <Typography variant="h5">{title}</Typography>
                <Typography color="text.secondary">{blurb}</Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        ))}
      </Box>
    </>
  );
}
