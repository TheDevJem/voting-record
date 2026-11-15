# Evaluate AI member summaries. See "Evaluating summaries" in the README.
namespace :summaries do
  desc "Score the summaries already saved in the database (VERSION=3 for one prompt version, INCLUDE_REBUILT=1)"
  task eval: :environment do
    scope = MemberSummary.includes(:member).where(status: "complete").order(:id)
    scope = scope.where("fingerprint LIKE ?", "v#{ENV['VERSION']}:%") if ENV["VERSION"].present?
    # Older summaries didn't save the record they were written from. Rebuilding it from today's data drops bills
    # that have since fallen out of the "recent" lists, so real citations get flagged as made up. Skip by default.
    unless ENV["INCLUDE_REBUILT"].present?
      skipped = scope.where(input: nil).count
      scope = scope.where.not(input: nil)
      puts "Skipping #{skipped} summaries saved without their input (regenerate them, or INCLUDE_REBUILT=1).", "" if skipped.positive?
    end
    abort "No complete summaries to score. Open a few member profiles first." if scope.none?

    run = Summaries::EvalRun.new(source: "stored", model: scope.map(&:model).uniq.join("+"),
                                 prompt_version: ENV.fetch("VERSION", "mixed"))
    scope.each do |summary|
      version = summary.fingerprint.to_s[/\Av(\d+):/, 1]
      # Summaries saved before the input column existed: rebuild the record from today's data (may have drifted).
      input = summary.input || Summaries::MemberPacket.new(summary.member).to_h
      run.add(summary.member, content: summary.content, input:, prompt_version: version,
              note: ("input rebuilt from current data" unless summary.input))
    end
    puts run.report, "", "Saved #{run.save.relative_path_from(Rails.root)}"
  end

  namespace :eval do
    desc "Generate fresh summaries without saving them to the app, then score them " \
         "(MODEL=qwen3:8b, MEMBERS=S000033,F000479, LIMIT=5)"
    task generate: :environment do
      model = ENV.fetch("MODEL", ENV.fetch("OLLAMA_MODEL", "qwen3:14b"))
      members = if ENV["MEMBERS"].present?
        Member.where(bioguide_id: ENV["MEMBERS"].upcase.split(",").map(&:strip))
      else
        # Default to members that already have a saved summary, so this run lines up with `summaries:eval`.
        Member.joins(:summary).merge(MemberSummary.where(status: "complete")).order("member_summaries.id")
      end.limit(ENV.fetch("LIMIT", 5).to_i).to_a
      abort "No members to summarize. Pass MEMBERS=<bioguide ids>." if members.empty?

      generator = Summaries::Generator.new(client: Summaries::OllamaClient.new(model:))
      run = Summaries::EvalRun.new(source: "generated", model:, prompt_version: Summaries::Prompt::VERSION)
      puts "Generating #{members.size} summaries with #{model} (each can take a few minutes on CPU)..."

      members.each_with_index do |member, i|
        print "  [#{i + 1}/#{members.size}] #{member.full_name}... "
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = generator.call(member)
        run.add(member, content: result[:content], input: result[:input], stats: result[:stats])
        puts "#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round}s, score #{(run.rows.last[:score] * 100).round}%"
      rescue Summaries::Generator::InvalidOutput => e
        run.add_failure(member, e.message)
        puts "unusable: #{e.message}"
      rescue Summaries::OllamaClient::Unavailable => e
        abort e.message
      end
      puts "", run.report, "", "Saved #{run.save.relative_path_from(Rails.root)}"
    end

    desc "Compare saved eval runs side by side (RUNS=tmp/evals/a.json,tmp/evals/b.json; default: the 4 most recent)"
    task compare: :environment do
      puts Summaries::EvalRun.compare(ENV["RUNS"]&.split(","))
    end
  end
end
