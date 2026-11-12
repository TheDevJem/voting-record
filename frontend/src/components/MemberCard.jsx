import { Avatar, Box, Card, CardActionArea, Chip, Typography } from "@mui/material";
import { useNavigate } from "react-router-dom";
import { partyColor, partyLetter, seatLabel } from "../party.js";

export default function MemberCard({ member: m, subtitle }) {
  const navigate = useNavigate();
  return (
    <Card variant="outlined">
      <CardActionArea
        onClick={() => navigate(`/members/${m.bioguide_id}`)}
        sx={{ display: "flex", justifyContent: "flex-start", gap: 2, p: 1.5 }}
      >
        <Avatar src={m.image_url} alt={m.full_name} sx={{ width: 52, height: 52 }} />
        <Box sx={{ minWidth: 0 }}>
          <Typography fontWeight={600} noWrap>{m.full_name}</Typography>
          <Typography variant="body2" color="text.secondary" noWrap>{subtitle || seatLabel(m)}</Typography>
        </Box>
        <Chip
          label={partyLetter(m.party)}
          size="small"
          sx={{ ml: "auto", bgcolor: partyColor(m.party), color: "#fff", fontWeight: 700 }}
        />
      </CardActionArea>
    </Card>
  );
}
