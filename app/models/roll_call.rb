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

  # [congress, bill_type, number] of the bill this vote was on ("HR 2102" or "S.J.Res. 138"), or nil for nominations,
  # amendments and other votes without a bill number.
  def bill_key
    type, number = legislation.to_s.split(" ", 2)
    return unless number.to_s.match?(/\A\d+\z/)

    bill_type = type.delete(".").upcase
    [ congress, bill_type, number ] if Bill::LABELS.key?(bill_type)
  end

  # { bill_key => Bill } for the bills these roll calls were on, in one query.
  def self.bills_for(roll_calls)
    keys = roll_calls.filter_map(&:bill_key).uniq
    return {} if keys.empty?

    # The three IN lists over-match (any congress x type x number combination), so keep only the exact keys.
    wanted = keys.to_set
    Bill.where(congress: keys.map(&:first).uniq, bill_type: keys.map(&:second).uniq, number: keys.map(&:third).uniq)
        .index_by { |b| [ b.congress, b.bill_type, b.number ] }.select { |key, _| wanted.include?(key) }
  end

  # "Grothman of Wisconsin Part A Amendment No. 316" -> "Grothman of Wisconsin"
  def amendment_sponsor = amendment_author.to_s.sub(/\s+(?:Part [A-Z]+ )?Amendment No\..*\z/i, "").presence

  # House vote descriptions are just the vote type ("Yea-and-Nay"), which says nothing about the topic.
  def topical_description
    description unless description.to_s.match?(/\A(?:2\/3 )?(?:yea-and-nay|recorded vote|quorum)\z/i)
  end
end
