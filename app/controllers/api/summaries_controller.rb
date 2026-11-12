module Api
  # GET  /api/members/:member_id/summary  -> current summary (starts generating one if needed)
  # POST /api/members/:member_id/summary  -> force regeneration
  class SummariesController < ApplicationController
    before_action :set_member

    def show
      render_summary(*MemberSummaries.ensure(@member))
    end

    def create
      render_summary(*MemberSummaries.ensure(@member, force: true))
    end

    private

    def set_member
      @member = Member.find_by!(bioguide_id: params[:member_id].upcase)
    end

    def render_summary(summary, fingerprint)
      render status: summary.in_progress? ? :accepted : :ok, json: {
        status: summary.status,
        content: summary.content,
        stale: summary.content.present? && summary.stale?(fingerprint),
        error: summary.error,
        model: summary.model,
        generated_at: summary.generated_at,
        started_at: summary.in_progress? ? summary.updated_at : nil,
        stats: summary.stats
      }
    end
  end
end
