import { Box, Chip, Divider, Link, List, ListItem, ListItemText, Typography } from "@mui/material";

function Seat({ c, inset }) {
  const role = c.title || (c.side === "majority" ? "Majority member" : c.side === "minority" ? "Minority member" : "Member");
  return (
    <ListItem sx={{ pl: inset ? 5 : 2 }} secondaryAction={<Chip size="small" label={role} color={c.title ? "primary" : "default"} variant={c.title ? "filled" : "outlined"} />}>
      <ListItemText
        primary={c.url ? <Link href={c.url} target="_blank" rel="noreferrer">{c.name}</Link> : c.name}
        slotProps={{ primary: { fontWeight: inset ? 400 : 600 } }}
      />
    </ListItem>
  );
}

export default function CommitteesTab({ committees }) {
  if (!committees.length) return <Typography color="text.secondary" sx={{ py: 2 }}>No committee assignments found.</Typography>;
  return (
    <List disablePadding>
      {committees.map((c) => (
        <Box key={c.code}>
          <Seat c={c} />
          {c.subcommittees.map((s) => <Seat key={s.code} c={s} inset />)}
          <Divider />
        </Box>
      ))}
    </List>
  );
}
