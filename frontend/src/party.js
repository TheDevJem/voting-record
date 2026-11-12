export function partyColor(party = "") {
  if (party.startsWith("Democrat")) return "#1565c0";
  if (party.startsWith("Republican")) return "#c62828";
  return "#6a1b9a";
}

export function partyLetter(party = "") {
  return party ? party[0] : "?";
}

export const CHAMBER_LABELS = { senate: "Senate", house: "House of Representatives" };

// DC and territories elect non-voting delegates (Puerto Rico's is the Resident Commissioner).
const TERRITORIES = ["DC", "PR", "GU", "VI", "AS", "MP"];

export function seatLabel(m) {
  if (m.chamber === "senate") return m.state;
  if (m.district === null || m.district === undefined) {
    if (m.state_code === "PR") return `${m.state} · Resident Commissioner`;
    if (TERRITORIES.includes(m.state_code)) return `${m.state} · Delegate`;
    return `${m.state} · At-large`;
  }
  return `${m.state} · District ${m.district}`;
}
