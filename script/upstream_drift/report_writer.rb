# frozen_string_literal: true

# Markdown report, JSON dump, pins rewrite, and console summary for the
# upstream drift watch. Split out of script/upstream_drift.rb to keep both
# files focused (see script/live_branch_smoke/ for the same pattern).

module UpstreamDrift
  module ReportWriter
    module_function

    def write_json(path, drift, results)
      File.write(path, JSON.pretty_generate({ "generated_at" => Time.now.utc.iso8601, "drift" => drift,
                                              "pins" => results }))
    end

    def write_report(path, repo, results)
      File.open(path, "w") do |file|
        file.puts "# Upstream docs drift report"
        file.puts
        file.puts "Source repo: [`#{repo}`](https://github.com/#{repo}) — generated #{Time.now.utc.iso8601}"
        file.puts
        file.puts "| Pin | Path | Status | Latest commit |"
        file.puts "|---|---|---|---|"
        results.each { |row| file.puts report_row(row) }
        file.puts
        append_diffs(file, results)
        append_checklist(file)
      end
    end

    def report_row(row)
      status = row["drifted"] ? "**DRIFTED**" : "up-to-date"
      "| `#{row["id"]}` | `#{row["path"]}` | #{status} | #{row["latest_commit"]} |"
    end

    def append_diffs(file, results)
      results.select { |row| row["drifted"] && row["diff"] }.each do |row|
        file.puts "## Diff for `#{row["path"]}`"
        file.puts
        file.puts "#{row["pinned_sha"][0, 7]} → #{row["latest_sha"][0, 7]}"
        file.puts
        file.puts "```diff"
        file.write(row["diff"])
        file.puts unless row["diff"].end_with?("\n")
        file.puts "```"
        file.puts
      end
    end

    def append_checklist(file)
      file.puts "## Before merging"
      file.puts
      file.puts "- [ ] Review each diff: does the change affect an endpoint this gem implements?"
      file.puts "- [ ] If yes: open a follow-up issue (or extend this PR) with the client-side change"
      file.puts "- [ ] If no: merging the re-pin alone is fine (pins are metadata; no code references them)"
    end

    def rewrite_pins(pins_path, results)
      manifest = JSON.parse(File.read(pins_path))
      manifest["pins"].each do |pin|
        row = results.find { |x| x["id"] == pin["id"] }
        next unless row && row["drifted"]

        pin["pinned_sha"] = row["latest_sha"]
        pin["pinned_at"] = Time.now.utc.strftime("%Y-%m-%d")
        pin["pinned_commit"] = row["latest_commit"]
      end
      File.write(pins_path, "#{JSON.pretty_generate(manifest)}\n")
    end

    def print_summary(results)
      results.each do |row|
        state = row["drifted"] ? "DRIFTED" : "up-to-date"
        puts format("  %<id>-16s %<path>-42s %<state>s", id: row["id"], path: row["path"], state: state)
      end
    end
  end
end
