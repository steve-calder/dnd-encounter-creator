#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates db/data/srd_monsters.json from the pinned upstream monster dataset.
#
# Dev-only: the catalog import, tests, and CI never run this. It is the only
# code that touches the network, and only when no local upstream file is given.
#
#   script/extract_srd_monsters.rb                    # download the pinned upstream file
#   script/extract_srd_monsters.rb path/to/monsters.json   # use a local copy instead
#
# Output is deterministic: records are kept verbatim, sorted by book then name,
# and the header carries no timestamp, so re-running yields a byte-identical file.

require "digest"
require "fileutils"
require "json"
require "net/http"
require "uri"

class SrdMonsterExtractor
  REPOSITORY = "nick-aschenbach/dnd-data"
  COMMIT = "649f7f964b20835852bff3659aa36875dd7c35df"
  PATH = "data/monsters.json"
  SHA256 = "cee519309b7241ed6cd45b2217f9e37e481d451aa3fd9ce251dfbd7a4ef302c7"
  BOOKS = [ "Free Basic Rules (2014)", "Free Basic Rules (2024)" ].freeze
  OUTPUT = File.expand_path("../db/data/srd_monsters.json", __dir__)

  class ChecksumMismatch < StandardError; end
  class DownloadFailed < StandardError; end

  def self.source_url
    "https://raw.githubusercontent.com/#{REPOSITORY}/#{COMMIT}/#{PATH}"
  end

  attr_reader :sha256, :books

  def initialize(sha256: SHA256, books: BOOKS)
    @sha256 = sha256
    @books = books
  end

  # Verifies, filters, and writes. Leaves +output+ untouched on any failure.
  def run(output: OUTPUT, input: nil)
    bytes = input ? File.binread(input) : download
    document = build(bytes)
    write(document, output)
    document
  end

  def build(bytes)
    verify!(bytes)
    records = select(JSON.parse(bytes))
    { "source" => header(records.size), "monsters" => records }
  end

  def verify!(bytes)
    actual = Digest::SHA256.hexdigest(bytes)
    return if actual == sha256

    raise ChecksumMismatch, "upstream SHA-256 mismatch: expected #{sha256}, got #{actual}"
  end

  # Keeps records from +books+ verbatim, sorted by book then name. The original
  # position breaks ties so the order never depends on sort stability.
  def select(records)
    records.each_with_index
      .select { |record, _| books.include?(record["book"]) }
      .sort_by { |record, index| [ record["book"], record["name"], index ] }
      .map(&:first)
  end

  def render(document)
    "#{JSON.pretty_generate(document)}\n"
  end

  private
    def header(record_count)
      {
        "repository" => REPOSITORY,
        "commit" => COMMIT,
        "path" => PATH,
        "sha256" => sha256,
        "books" => books,
        "record_count" => record_count,
        "generated_by" => "script/extract_srd_monsters.rb (do not edit by hand)"
      }
    end

    def write(document, output)
      FileUtils.mkdir_p(File.dirname(output))
      temp = "#{output}.tmp-#{Process.pid}"
      File.write(temp, render(document))
      File.rename(temp, output)
    ensure
      FileUtils.rm_f(temp) if temp
    end

    def download
      response = Net::HTTP.get_response(URI(self.class.source_url))
      raise DownloadFailed, "GET #{self.class.source_url} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
end

if $PROGRAM_NAME == __FILE__
  begin
    document = SrdMonsterExtractor.new.run(input: ARGV[0])
    puts "Wrote #{document["source"]["record_count"]} records to #{SrdMonsterExtractor::OUTPUT}"
  rescue SrdMonsterExtractor::ChecksumMismatch, SrdMonsterExtractor::DownloadFailed => e
    warn e.message
    exit 1
  end
end
