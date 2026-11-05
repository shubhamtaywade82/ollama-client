# frozen_string_literal: true

# Upstream docs drift watch for ollama-client (stdlib-only, no gem deps).
#
# Compares every pinned docs source in .github/upstream-pins.json against the
# latest ollama/ollama commit touching it. Mirrors the ollama-sdk upstream-watch
# design: on drift it reports the per-source diff so a human can decide whether
# the client surface needs updating — the automation never merges anything.
#
# Usage:
#   ruby script/upstream_drift.rb
#     exit 0 = no drift, exit 1 = drift found, exit 2 = the check itself failed
#
#   ruby script/upstream_drift.rb --report /tmp/drift.md
#     additionally writes a markdown report (drift table + unified diffs)
#
#   ruby script/upstream_drift.rb --json /tmp/drift.json
#     additionally writes machine-readable JSON ({ "drift": bool, "pins": [...] })
#
#   ruby script/upstream_drift.rb --write-pins
#     rewrites pinned_sha/pinned_at/pinned_commit in the pins file to the latest
#     SHAs (used by the upstream-watch workflow on the candidate PR branch only)
#
# Authentication: uses GITHUB_TOKEN or GH_TOKEN when set (higher rate limit),
# otherwise falls back to unauthenticated GitHub API (60 req/h).

require "json"
require "net/http"
require "time"
require "tempfile"

require_relative "upstream_drift/report_writer"

module UpstreamDrift
  DEFAULT_PINS_PATH = File.expand_path("../.github/upstream-pins.json", __dir__)
  LATEST_COMMIT_TPL = "https://api.github.com/repos/%<repo>s/commits?path=%<path>s&per_page=1"
  RAW_CONTENT_TPL = "https://raw.githubusercontent.com/%<repo>s/%<sha>s/%<path>s"
  USER_AGENT = "ollama-client-upstream-drift"

  # Raised when the check itself cannot run (network, API error, bad pin).
  class CheckFailed < StandardError; end

  module_function

  def run(pins_path: DEFAULT_PINS_PATH, report_path: nil, json_path: nil, write_pins: false)
    manifest = JSON.parse(File.read(pins_path))
    results = collect_results(manifest.fetch("repo"), manifest.fetch("pins"))
    drift = results.any? { |r| r["drifted"] }

    write_report(report_path, manifest.fetch("repo"), results) if report_path
    write_json(json_path, drift, results) if json_path
    ReportWriter.rewrite_pins(pins_path, results) if write_pins

    ReportWriter.print_summary(results)
    drift ? 1 : 0
  end

  def collect_results(repo, pins)
    pins.map { |pin| result_for(repo, pin) }
  end

  def result_for(repo, pin)
    latest = latest_commit(repo, pin.fetch("path"))
    entry = {
      "id" => pin.fetch("id"),
      "path" => pin.fetch("path"),
      "drifted" => latest[:sha] != pin.fetch("pinned_sha"),
      "pinned_sha" => pin.fetch("pinned_sha"),
      "latest_sha" => latest[:sha],
      "latest_commit" => latest[:message],
      "latest_date" => latest[:date]
    }
    entry["diff"] = unified_diff(repo, pin.fetch("path"), pin.fetch("pinned_sha"), latest[:sha]) if entry["drifted"]
    entry
  rescue CheckFailed => e
    raise CheckFailed, "pin #{pin.fetch("id")}: #{e.message}"
  end

  def latest_commit(repo, path)
    uri = URI(format(LATEST_COMMIT_TPL, repo: repo, path: path))
    commits = get_json(uri)
    raise CheckFailed, "no commits returned for #{path}" if commits.empty?

    commit = commits.first
    { sha: commit["sha"],
      date: commit.dig("commit", "committer", "date"),
      message: commit.dig("commit", "message").to_s.lines.first.to_s.strip }
  end

  def unified_diff(repo, path, old_sha, new_sha)
    old_body = fetch_raw(repo, old_sha, path)
    new_body = fetch_raw(repo, new_sha, path)
    return nil if old_body == new_body

    Tempfile.create("upstream-old") do |a|
      Tempfile.create("upstream-new") do |b|
        File.write(a.path, old_body)
        File.write(b.path, new_body)
        raw = `diff -u "#{a.path}" "#{b.path}"`
        raw.gsub(a.path, "#{path}@#{old_sha[0, 7]}").gsub(b.path, "#{path}@#{new_sha[0, 7]}")
           .lines[2..].join
      end
    end
  end

  def write_json(path, drift, results)
    ReportWriter.write_json(path, drift, results)
  end

  def write_report(path, repo, results)
    ReportWriter.write_report(path, repo, results)
  end

  def get_json(uri)
    headers = { "Accept" => "application/vnd.github+json" }
    if (t = ENV.fetch("GITHUB_TOKEN") { ENV.fetch("GH_TOKEN", nil) })
      headers["Authorization"] = "Bearer #{t}"
    end
    res = http_get(uri, headers)
    raise CheckFailed, "GitHub API #{res.code} for #{uri.path}?#{uri.query}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  def fetch_raw(repo, sha, path)
    uri = URI(format(RAW_CONTENT_TPL, repo: repo, sha: sha, path: path))
    res = http_get(uri)
    raise CheckFailed, "raw.githubusercontent.com #{res.code} for #{sha}/#{path}" unless res.is_a?(Net::HTTPSuccess)

    res.body
  end

  def http_get(uri, headers = {})
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    headers.each { |key, value| req[key] = value }
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: 15, read_timeout: 60) { |http| http.request(req) }
  end
end

if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  opts = { pins_path: UpstreamDrift::DEFAULT_PINS_PATH, report_path: nil, json_path: nil, write_pins: false }
  until args.empty?
    case args.shift
    when "--pins" then opts[:pins_path] = args.shift
    when "--report" then opts[:report_path] = args.shift
    when "--json" then opts[:json_path] = args.shift
    when "--write-pins" then opts[:write_pins] = true
    else warn "unknown argument ignored"
    end
  end

  begin
    exit(UpstreamDrift.run(**opts))
  rescue StandardError => e
    warn "upstream-drift check failed: #{e.class}: #{e.message}"
    exit 2
  end
end
