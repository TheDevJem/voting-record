# Tells the summary card when a member's summary changes status (pending -> running -> complete/failed),
# so the browser refetches once per change instead of polling while a generation runs.
class MemberSummaryChannel < ApplicationCable::Channel
  def self.stream_for_member(bioguide_id) = "member_summary:#{bioguide_id.to_s.upcase}"

  def subscribed
    member = Member.find_by(bioguide_id: params[:member_id].to_s.upcase)
    member ? stream_from(self.class.stream_for_member(member.bioguide_id)) : reject
  end
end
