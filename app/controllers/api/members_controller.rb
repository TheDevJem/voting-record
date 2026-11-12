module Api
  class MembersController < ApplicationController
    PER_PAGE = 20

    before_action :set_member, except: :index

    # GET /api/members?chamber=senate|house&q=smith
    def index
      members = Member.order(:state, :last_name)
      members = members.where(chamber: params[:chamber]) if Member::CHAMBERS.include?(params[:chamber])
      if params[:q].present?
        term = "%#{Member.sanitize_sql_like(params[:q])}%"
        members = members.where("full_name ILIKE :t OR state ILIKE :t OR state_code ILIKE :t", t: term)
      end

      render json: members.map { |m| summary(m) }
    end

    # GET /api/members/:id  (id = bioguide id)
    def show
      memberships = @member.committee_memberships.includes(committee: :parent)
      parents, subs = memberships.partition { |cm| cm.committee.parent_id.nil? }

      committees = parents.sort_by { |cm| cm.committee.name }.map do |cm|
        membership(cm).merge(subcommittees: subs.select { |s| s.committee.parent_id == cm.committee_id }
                                                .sort_by { |s| s.committee.name }.map { |s| membership(s) })
      end
      # Subcommittee seats whose parent committee seat isn't listed
      orphan_subs = subs.reject { |s| parents.any? { |p| p.committee_id == s.committee.parent_id } }

      render json: summary(@member).merge(
        website_url: @member.website_url, office_address: @member.office_address, phone: @member.phone,
        term_start_year: @member.term_start_year,
        committees: committees + orphan_subs.map { |s| membership(s).merge(subcommittees: []) },
        counts: {
          sponsored: @member.bill_sponsorships.where(role: "sponsor").count,
          cosponsored: @member.bill_sponsorships.where(role: "cosponsor").count,
          votes: @member.vote_positions.count
        },
        vote_breakdown: @member.vote_positions.group(:position).count
      )
    end

    # GET /api/members/:id/votes?page=1
    def votes
      scope = @member.vote_positions.joins(:roll_call).includes(:roll_call).order("roll_calls.voted_at DESC")
      render json: paginate(scope) { |vp|
        rc = vp.roll_call
        { id: rc.id, position: vp.position, voted_at: rc.voted_at, question: rc.question, description: rc.description,
          result: rc.result, legislation: rc.legislation, yeas: rc.yeas, nays: rc.nays, source_url: rc.source_url,
          congress: rc.congress, session: rc.session, number: rc.number }
      }
    end

    # GET /api/members/:id/bills?role=sponsor|cosponsor&page=1
    def bills
      role = params[:role] == "cosponsor" ? "cosponsor" : "sponsor"
      scope = Bill.joins(:bill_sponsorships).where(bill_sponsorships: { member_id: @member.id, role: })
                  .order(introduced_date: :desc, id: :desc)
      render json: paginate(scope) { |b|
        { id: b.id, label: b.label, title: b.title, congress: b.congress, introduced_date: b.introduced_date,
          latest_action_text: b.latest_action_text, latest_action_date: b.latest_action_date,
          policy_area: b.policy_area, url: b.congress_gov_url }
      }
    end

    private

    def set_member
      @member = Member.find_by!(bioguide_id: params[:id].upcase)
    end

    def summary(m)
      m.slice(:bioguide_id, :chamber, :full_name, :first_name, :last_name, :party, :state, :state_code, :district, :image_url)
    end

    def membership(cm)
      { code: cm.committee.code, name: cm.committee.name, chamber: cm.committee.chamber,
        url: cm.committee.url, title: cm.title, side: cm.side, rank: cm.rank }
    end

    def paginate(scope, &serialize)
      page = [ params[:page].to_i, 1 ].max
      total = scope.count
      { items: scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map(&serialize),
        page:, per_page: PER_PAGE, total:, total_pages: (total.to_f / PER_PAGE).ceil }
    end
  end
end
