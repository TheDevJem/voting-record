class Bill < ApplicationRecord
  has_many :bill_sponsorships, dependent: :destroy

  # e.g. "H.R. 1234", "S. 56", "H.J.Res. 7"
  LABELS = { "HR" => "H.R.", "S" => "S.", "HRES" => "H.Res.", "SRES" => "S.Res.",
             "HJRES" => "H.J.Res.", "SJRES" => "S.J.Res.", "HCONRES" => "H.Con.Res.",
             "SCONRES" => "S.Con.Res." }.freeze

  def label = "#{LABELS.fetch(bill_type, bill_type)} #{number}"

  def congress_gov_url
    slug = { "HR" => "house-bill", "S" => "senate-bill", "HRES" => "house-resolution",
             "SRES" => "senate-resolution", "HJRES" => "house-joint-resolution",
             "SJRES" => "senate-joint-resolution", "HCONRES" => "house-concurrent-resolution",
             "SCONRES" => "senate-concurrent-resolution" }[bill_type]
    "https://www.congress.gov/bill/#{congress}th-congress/#{slug}/#{number}" if slug
  end
end
