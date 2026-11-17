class RollCall < ApplicationRecord
  has_many :vote_positions, dependent: :destroy

  # Congress.gov's House vote API gives compact type codes ("HRES 1247"); senate.gov and bills use citation
  # style ("H.Res. 1247"). Showing one style everywhere lets people (and the summary model) match a vote to a bill.
  BILL_TYPE_LABELS = {
    "HR" => "H.R.", "HRES" => "H.Res.", "HJRES" => "H.J.Res.", "HCONRES" => "H.Con.Res.",
    "S" => "S.", "SRES" => "S.Res.", "SJRES" => "S.J.Res.", "SCONRES" => "S.Con.Res."
  }.freeze

  def self.legislation_label(raw)
    type, number = raw.to_s.split(" ", 2)
    label = BILL_TYPE_LABELS[type.to_s.upcase]
    label && number ? "#{label} #{number}" : raw.presence
  end

  def legislation_label = self.class.legislation_label(legislation)
end
