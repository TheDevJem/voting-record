# Search index for the question box. See "Asking questions" in the README.
namespace :search do
  desc "Embed new or changed roll calls and bills for the question box (first run ~40 min on CPU; needs `ollama pull nomic-embed-text`)"
  task index: :environment do
    Search::Indexer.new.call
  end
end
