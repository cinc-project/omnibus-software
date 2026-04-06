#!/usr/bin/env ruby
#
# check_upstream_versions.rb
#
# Uses the omnibus gem to load software definitions from config/software/,
# checks upstream sources for newer versions, and auto-creates GitLab merge
# requests when updates are found.
#
# Usage:
#   ruby scripts/check_upstream_versions.rb            # check all
#   ruby scripts/check_upstream_versions.rb openssl    # check specific software
#
# Environment:
#   CI_JOB_TOKEN   - GitLab token for creating MRs (set by CI)
#   CI_PROJECT_ID  - GitLab project ID (set by CI)
#   CI_SERVER_URL  - GitLab server URL (set by CI)
#   DRY_RUN        - set to "true" to skip MR creation
#

require "net/http"
require "uri"
require "json"

# Load the omnibus-software library which provides OmnibusSoftware.for_each_software
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "omnibus-software"

CI_JOB_TOKEN = ENV["CI_JOB_TOKEN"]
CI_PROJECT_ID = ENV["CI_PROJECT_ID"]
CI_SERVER_URL = ENV["CI_SERVER_URL"] || "https://gitlab.com"
DRY_RUN = ENV["DRY_RUN"] == "true"
DEFAULT_BRANCH = "stable/cinc"

# Suppress omnibus logging noise
Omnibus.logger.level = :fatal

# ---------------------------------------------------------------------------
# GitHub: fetch tags and find highest semver
# ---------------------------------------------------------------------------
def check_github_tags(owner, repo, prefix: "v")
  uri = URI("https://api.github.com/repos/#{owner}/#{repo}/tags?per_page=100")
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/vnd.github.v3+json"
  req["User-Agent"] = "omnibus-software-version-checker"

  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  return nil unless resp.code == "200"

  tags = JSON.parse(resp.body).map { |t| t["name"] }
  versions = tags.filter_map do |tag|
    cleaned = tag.sub(/^#{Regexp.escape(prefix)}/, "")
    begin
      Gem::Version.new(cleaned)
      cleaned
    rescue ArgumentError
      nil
    end
  end

  versions.reject { |v| v.include?("rc") || v.include?("beta") || v.include?("alpha") || v.include?("pre") }
           .max_by { |v| Gem::Version.new(v) }
end

# ---------------------------------------------------------------------------
# HTTP directory listing: find latest version from an index page
# ---------------------------------------------------------------------------
def check_http_directory(url, name_pattern)
  uri = URI(url)
  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                         open_timeout: 10, read_timeout: 15) do |http|
    http.request(Net::HTTP::Get.new(uri))
  end
  return nil unless resp.code == "200"

  versions = resp.body.scan(name_pattern).filter_map do |match|
    ver = match.is_a?(Array) ? match.first : match
    begin
      Gem::Version.new(ver)
      ver
    rescue ArgumentError
      nil
    end
  end

  versions.reject { |v| v.include?("rc") || v.include?("beta") || v.include?("alpha") || v.include?("pre") }
           .max_by { |v| Gem::Version.new(v) }
rescue StandardError => e
  $stderr.puts "  HTTP check failed for #{url}: #{e.message}"
  nil
end

# ---------------------------------------------------------------------------
# Mapping: software name -> how to check for updates
# ---------------------------------------------------------------------------
GITHUB_SOURCES = {
  "libarchive" => { owner: "libarchive", repo: "libarchive", prefix: "v" },
  "libffi" => { owner: "libffi", repo: "libffi", prefix: "v" },
  "libsodium" => { owner: "jedisct1", repo: "libsodium", prefix: "" },
  "libxcrypt" => { owner: "besser82", repo: "libxcrypt", prefix: "v" },
  "libzmq" => { owner: "zeromq", repo: "libzmq", prefix: "v" },
  "libnghttp2" => { owner: "nghttp2", repo: "nghttp2", prefix: "v" },
  "expat" => { owner: "libexpat", repo: "libexpat", prefix: "R_" },
  "logrotate" => { owner: "logrotate", repo: "logrotate" },
  "patchelf" => { owner: "NixOS", repo: "patchelf" },
  "erlang" => { owner: "erlang", repo: "otp", prefix: "OTP-" },
  "keydb" => { owner: "Snapchat", repo: "KeyDB", prefix: "v" },
  "valkey" => { owner: "valkey-io", repo: "valkey" },
}.freeze

HTTP_SOURCES = {
  "openssl" => { url: "https://openssl-library.org/source/", pattern: /openssl-(3\.\d+\.\d+)\.tar\.gz/ },
  "curl" => { url: "https://curl.se/download/", pattern: /curl-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "ruby" => { url: "https://cache.ruby-lang.org/pub/ruby/3.4/", pattern: /ruby-(3\.4\.\d+)\.tar\.gz/ },
  "git" => { url: "https://www.kernel.org/pub/software/scm/git/", pattern: /git-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "zlib" => { url: "https://zlib.net/fossils/", pattern: /zlib-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "libyaml" => { url: "https://pyyaml.org/download/libyaml/", pattern: /yaml-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "ncurses" => { url: "https://ftp.osuosl.org/pub/gnu/ncurses/", pattern: /ncurses-(\d+\.\d+)\.tar\.gz/ },
  "libiconv" => { url: "https://ftp.osuosl.org/pub/gnu/libiconv/", pattern: /libiconv-(\d+\.\d+)\.tar\.gz/ },
  "libtool" => { url: "https://ftp.osuosl.org/pub/gnu/libtool/", pattern: /libtool-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "gmp" => { url: "https://ftp.osuosl.org/pub/gnu/gmp/", pattern: /gmp-(\d+\.\d+\.\d+)\.tar\.bz2/ },
  "bash" => { url: "https://ftp.osuosl.org/pub/gnu/bash/", pattern: /bash-(\d+\.\d+[\.\d]*)\.tar\.gz/ },
  "make" => { url: "https://ftp.osuosl.org/pub/gnu/make/", pattern: /make-(\d+\.\d+[\.\d]*)\.tar\.gz/ },
  "gtar" => { url: "https://ftp.osuosl.org/pub/gnu/tar/", pattern: /tar-(\d+\.\d+[\.\d]*)\.tar\.gz/ },
  "bzip2" => { url: "https://sourceware.org/pub/bzip2/", pattern: /bzip2-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "pcre" => { url: "https://sourceforge.net/projects/pcre/files/pcre/", pattern: /(\d+\.\d+)/ },
  "liblzma" => { url: "https://github.com/tukaani-project/xz/releases", pattern: /v(\d+\.\d+\.\d+)/ },
  "libxml2" => { url: "https://download.gnome.org/sources/libxml2/cache.json", pattern: /(\d+\.\d+\.\d+)/ },
  "libxslt" => { url: "https://download.gnome.org/sources/libxslt/cache.json", pattern: /(\d+\.\d+\.\d+)/ },
  "cacerts" => { url: "https://curl.se/ca/", pattern: /cacert-(\d{4}-\d{2}-\d{2})\.pem/ },
}.freeze

DEPRECATED_COMMENT = "# expeditor/ignore: deprecated".freeze

# ---------------------------------------------------------------------------
# Check a single software for updates
# ---------------------------------------------------------------------------
def check_for_update(name, current_version)
  return nil unless current_version

  latest = nil

  if GITHUB_SOURCES.key?(name)
    gh = GITHUB_SOURCES[name]
    prefix = gh[:prefix] || "v"
    latest = check_github_tags(gh[:owner], gh[:repo], prefix: prefix)
  elsif HTTP_SOURCES.key?(name)
    hs = HTTP_SOURCES[name]
    latest = check_http_directory(hs[:url], hs[:pattern])
  else
    return nil
  end

  return nil unless latest

  begin
    if Gem::Version.new(latest) > Gem::Version.new(current_version)
      { name: name, current: current_version, latest: latest }
    end
  rescue ArgumentError
    # Non-semver versions (e.g., dates for cacerts)
    if latest > current_version
      { name: name, current: current_version, latest: latest }
    end
  end
rescue StandardError => e
  $stderr.puts "Error checking #{name}: #{e.message}"
  nil
end

# ---------------------------------------------------------------------------
# GitLab API helpers
# ---------------------------------------------------------------------------
def gitlab_api(method, path, body = nil)
  uri = URI("#{CI_SERVER_URL}/api/v4#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"

  case method
  when :get
    req = Net::HTTP::Get.new(uri)
  when :post
    req = Net::HTTP::Post.new(uri)
    req.body = body.to_json if body
    req["Content-Type"] = "application/json"
  end

  req["JOB-TOKEN"] = CI_JOB_TOKEN
  http.request(req)
end

def branch_exists?(branch_name)
  encoded = URI.encode_www_form_component(branch_name)
  resp = gitlab_api(:get, "/projects/#{CI_PROJECT_ID}/repository/branches/#{encoded}")
  resp.code == "200"
end

def create_branch(branch_name)
  gitlab_api(:post, "/projects/#{CI_PROJECT_ID}/repository/branches", {
    branch: branch_name,
    ref: DEFAULT_BRANCH,
  })
end

def create_commit(branch_name, file_path, content, commit_message)
  gitlab_api(:post, "/projects/#{CI_PROJECT_ID}/repository/commits", {
    branch: branch_name,
    commit_message: commit_message,
    actions: [{ action: "update", file_path: file_path, content: content }],
  })
end

def create_merge_request(source_branch, title, description)
  gitlab_api(:post, "/projects/#{CI_PROJECT_ID}/merge_requests", {
    source_branch: source_branch,
    target_branch: DEFAULT_BRANCH,
    title: title,
    description: description,
    remove_source_branch: true,
  })
end

# ---------------------------------------------------------------------------
# Update a software definition file with new default_version
# ---------------------------------------------------------------------------
def update_default_version(file, old_version, new_version)
  content = File.read(file)
  updated = content.sub(
    /^(default_version\s+["'])#{Regexp.escape(old_version)}(["'])/,
    "\\1#{new_version}\\2"
  )

  if updated == content
    $stderr.puts "  WARNING: Could not find default_version #{old_version} in #{file}"
    return nil
  end

  updated
end

# ---------------------------------------------------------------------------
# Create a merge request for a version update
# ---------------------------------------------------------------------------
def create_version_update_mr(update)
  name = update[:name]
  current = update[:current]
  latest = update[:latest]

  branch_name = "auto/update-#{name}-#{latest}"

  if branch_exists?(branch_name)
    puts "  Branch #{branch_name} already exists, skipping MR creation"
    return
  end

  file_path = "config/software/#{name}.rb"
  full_path = File.join(OmnibusSoftware.root, file_path)
  new_content = update_default_version(full_path, current, latest)
  return unless new_content

  puts "  Creating branch #{branch_name}"
  resp = create_branch(branch_name)
  unless resp.code == "201"
    $stderr.puts "  Failed to create branch: #{resp.code} #{resp.body}"
    return
  end

  commit_msg = "Update #{name} default to #{latest}\n\nAutomated update from #{current} to #{latest}."
  resp = create_commit(branch_name, file_path, new_content, commit_msg)
  unless resp.code == "201"
    $stderr.puts "  Failed to create commit: #{resp.code} #{resp.body}"
    return
  end

  title = "Update #{name} to #{latest}"
  description = <<~MD
    Automated version update for **#{name}**.

    | | Version |
    |---|---|
    | Current | `#{current}` |
    | Latest | `#{latest}` |

    > **Note**: This MR only updates `default_version`. You may also need to:
    > - Add a new `version("#{latest}")` line with the correct sha256 checksum
    > - Verify the build succeeds in CI before merging
  MD

  resp = create_merge_request(branch_name, title, description)
  if resp.code == "201"
    mr = JSON.parse(resp.body)
    puts "  Created MR !#{mr["iid"]}: #{title}"
  else
    $stderr.puts "  Failed to create MR: #{resp.code} #{resp.body}"
  end
end

# ---------------------------------------------------------------------------
# Check if a software file has the deprecated comment marker
# ---------------------------------------------------------------------------
def deprecated_software?(name)
  filepath = File.join(OmnibusSoftware.root, "config", "software", "#{name}.rb")
  return false unless File.exist?(filepath)

  File.foreach(filepath).any? { |line| line.include?(DEPRECATED_COMMENT) }
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
filter = ARGV.first

puts "Loading software definitions via omnibus..."

updates = []
skipped = 0
checked = 0

OmnibusSoftware.for_each_software do |software|
  name = software.name
  current_version = software.default_version

  next if filter && name != filter
  next if deprecated_software?(name)

  checked += 1
  print "Checking #{name}..."

  update = check_for_update(name, current_version)
  if update
    puts " UPDATE AVAILABLE: #{update[:current]} -> #{update[:latest]}"
    updates << update
  elsif current_version && (GITHUB_SOURCES.key?(name) || HTTP_SOURCES.key?(name))
    puts " up to date (#{current_version})"
  else
    puts " skipped (no checker configured)"
    skipped += 1
  end
end

puts ""
puts "=" * 60
puts "Results: #{updates.length} updates found, #{checked} checked, #{skipped} skipped (no checker)"
puts "=" * 60

# Write report
report = {
  checked_at: Time.now.utc.iso8601,
  updates: updates,
  total_checked: checked,
  skipped: skipped,
}

File.write("version_report.json", JSON.pretty_generate(report))
puts "Report written to version_report.json"

# Create MRs if in CI and not dry run
if updates.any? && CI_JOB_TOKEN && CI_PROJECT_ID && !DRY_RUN
  puts ""
  puts "Creating merge requests..."
  updates.each do |update|
    puts "Processing #{update[:name]}..."
    create_version_update_mr(update)
  end
elsif updates.any? && DRY_RUN
  puts ""
  puts "DRY_RUN=true, skipping MR creation. Updates that would be proposed:"
  updates.each { |u| puts "  #{u[:name]}: #{u[:current]} -> #{u[:latest]}" }
elsif updates.any?
  puts ""
  puts "Not in CI (no CI_JOB_TOKEN/CI_PROJECT_ID). Run in GitLab CI to create MRs."
end
