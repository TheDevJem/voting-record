# Searchable text (with its embedding) for one roll call or bill. Built by Search::Indexer, queried by Search::Retriever.
class SearchDocument < ApplicationRecord
  KINDS = %w[vote bill].freeze

  belongs_to :record, polymorphic: true
  has_neighbors :embedding

  validates :kind, inclusion: { in: KINDS }
end
