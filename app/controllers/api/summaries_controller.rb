module Api
  # GET  /api/members/:member_id/summary  -> current summary (read-only; status "none" if never generated)
  # POST /api/members/:member_id/summary  -> generate or regenerate
  class SummariesController < ApplicationController
    before_action :set_member

    def show
      render_summary(*MemberSummaries.current(@member))
    end

    def create
      render_summary(*MemberSummaries.generate(@member))
    end

    private

    def set_member
      @member = Member.find_by!(bioguide_id: params[:member_id].upcase)
    end

    def render_summary(summary, fingerprint)
      return render(json: { status: "none", content: nil, stale: false }) if summary.nil?

      if summary.stalled?
        return render(json: { status: "failed", content: summary.content, stale: false,
                              error: "Generation stopped responding (the jobs process may have restarted).",
                              model: summary.model, generated_at: summary.generated_at, stats: summary.stats })
      end

      render status: summary.in_progress? ? :accepted : :ok, json: {
        status: summary.status,
        content: summary.content,
        stale: fingerprint.present? && summary.content.present? && summary.stale?(fingerprint),
        error: summary.error,
        model: summary.model,
        generated_at: summary.generated_at,
        started_at: summary.in_progress? ? summary.updated_at : nil,
        stats: summary.stats
      }
    end
  end
end
