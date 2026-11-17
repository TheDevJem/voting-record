module Summaries
  # Scores a batch of summaries with Evaluation, prints a report, and saves it to tmp/evals/*.json so you can
  # compare runs (a different model, a new prompt version) with `bin/rails summaries:eval:compare`.
  class EvalRun
    DIR = Rails.root.join("tmp/evals")

    attr_reader :rows

    def initialize(source:, model:, prompt_version:)
      @meta = { source:, model:, prompt_version:, started_at: Time.current.iso8601 }
      @rows = []
    end

    def add(member, content:, input:, prompt_version: @meta[:prompt_version], note: nil, stats: nil)
      evaluation = Evaluation.new(content, input)
      @rows << { bioguide_id: member.bioguide_id, name: member.full_name, prompt_version:, note:,
                 score: evaluation.score.round(3), checks: evaluation.results.map(&:to_h), content:, input:, stats: }.compact
    end

    # The model's answer couldn't be used at all (bad JSON, missing fields). Scores 0 so it drags the run down.
    def add_failure(member, error)
      @rows << { bioguide_id: member.bioguide_id, name: member.full_name, prompt_version: @meta[:prompt_version],
                 score: 0.0, error: }
    end

    def save
      DIR.mkpath
      slug = [ Time.current.strftime("%Y%m%d-%H%M%S"), @meta[:source], @meta[:model], "v#{@meta[:prompt_version]}" ]
      path = DIR.join("#{slug.join('-').parameterize}.json")
      path.write(JSON.pretty_generate(@meta.merge(summary: self.class.summarize(@rows), rows: @rows)))
      path
    end

    def report = self.class.report(@meta.merge(summary: self.class.summarize(@rows), rows: @rows))

    # { "evidence_grounded" => [passed, total], ..., overall score, and how many summaries couldn't be scored }
    def self.summarize(rows)
      scored = rows.reject { |r| r[:error] || r["error"] }
      checks = scored.flat_map { |r| r[:checks] || r["checks"] }.group_by { |c| (c[:name] || c["name"]).to_s }
      {
        count: rows.size,
        unusable: rows.size - scored.size,
        score: rows.any? ? rows.sum { |r| r[:score] || r["score"] }.fdiv(rows.size).round(3) : nil,
        checks: checks.transform_values { |cs| [ cs.count { |c| c[:passed] || c["passed"] }, cs.size ] }
      }
    end

    def self.report(run)
      run = run.deep_symbolize_keys
      s = run[:summary]
      out = [ "Eval: #{run[:source]} summaries, #{run[:model]}, prompt v#{run[:prompt_version]} (#{run[:started_at]})", "" ]
      out << "Check pass rates (#{s[:count]} summaries#{", #{s[:unusable]} unusable" if s[:unusable].positive?}):"
      s[:checks].each { |name, (passed, total)| out << format("  %-26s %3d/%-3d %4d%%", name, passed, total, pct(passed, total)) }
      out << format("  %-26s %12d%%", "overall score", (s[:score].to_f * 100).round) << "" << "Per summary:"
      run[:rows].each do |r|
        line = format("  %-8s %-24s v%-2s %4d%%", r[:bioguide_id], r[:name].truncate(24), r[:prompt_version], (r[:score] * 100).round)
        line += "  (#{r[:note]})" if r[:note]
        out << line
        out << "      UNUSABLE: #{r[:error]}" if r[:error]
        Array(r[:checks]).reject { |c| c[:passed] }.each { |c| out << "      ✗ #{c[:name]}: #{c[:detail].truncate(180)}" }
      end
      out.join("\n")
    end

    # Side-by-side pass rates for saved runs (default: the 4 most recent).
    def self.compare(paths = nil)
      paths = Array(paths).presence || DIR.glob("*.json").max_by(4, &:mtime).sort_by(&:mtime)
      return "No saved runs in #{DIR}. Run bin/rails summaries:eval first." if paths.empty?

      runs = paths.map { |p| JSON.parse(File.read(p)).deep_symbolize_keys.merge(file: File.basename(p, ".json")) }
      names = runs.flat_map { |r| r[:summary][:checks].keys }.uniq
      width = 14
      out = runs.each_with_index.map { |r, i| "  [#{i + 1}] #{r[:file]}  (#{r[:source]}, #{r[:model]}, prompt v#{r[:prompt_version]})" }
      out << "" << format("  %-26s", "") + runs.each_index.map { |i| "[#{i + 1}]".rjust(width) }.join
      names.each do |name|
        cells = runs.map { |r| (p, t = r[:summary][:checks][name]) && t ? "#{pct(p, t)}% (#{p}/#{t})" : "-" }
        out << format("  %-26s", name) + cells.map { _1.rjust(width) }.join
      end
      out << format("  %-26s", "overall score") + runs.map { |r| "#{(r[:summary][:score].to_f * 100).round}%".rjust(width) }.join
      out << format("  %-26s", "summaries (unusable)") + runs.map { |r| "#{r[:summary][:count]} (#{r[:summary][:unusable]})".rjust(width) }.join
      out.join("\n")
    end

    def self.pct(passed, total) = total.zero? ? 0 : (100.0 * passed / total).round
  end
end
