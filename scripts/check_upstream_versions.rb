#!/usr/bin/env ruby
#
# check_upstream_versions.rb
#
# Loads software definitions via the omnibus gem, auto-detects upstream
# sources from their download URLs, checks for newer versions, and
# auto-creates GitLab merge requests when updates are found.
#
# Most GitHub and HTTP directory sources are auto-detected from the source
# URL in each software definition. SOURCE_OVERRIDES handles the few cases
# where the check URL or strategy differs from what can be inferred.
#
# Usage:
#   bundle exec ruby scripts/check_upstream_versions.rb            # check all
#   bundle exec ruby scripts/check_upstream_versions.rb openssl    # check specific
#
# Environment:
#   CINC_PROJECT_TOKEN - Project/group access token with api scope (for MR creation)
#   CI_PROJECT_ID  - GitLab project ID (set by CI)
#   CI_SERVER_URL  - GitLab server URL (set by CI)
#   DRY_RUN        - set to "true" to skip MR creation
#

require "net/http"
require "uri"
require "json"
require "digest"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "omnibus-software"

GITLAB_TOKEN = ENV["CINC_PROJECT_TOKEN"] || ENV["CI_JOB_TOKEN"]
CI_PROJECT_ID = ENV["CI_PROJECT_ID"]
CI_SERVER_URL = ENV["CI_SERVER_URL"] || "https://gitlab.com"
DRY_RUN = ENV["DRY_RUN"] == "true"
DEFAULT_BRANCH = "stable/cinc".freeze

Omnibus.logger.level = :fatal

DEPRECATED_COMMENT = "# expeditor/ignore: deprecated".freeze

# ---------------------------------------------------------------------------
# Source overrides for software where the check strategy can't be
# auto-derived from source[:url]. Most GitHub and HTTP directory sources
# are auto-detected. Only override when the check differs from download.
# ---------------------------------------------------------------------------
SOURCE_OVERRIDES = {
  # Non-GitHub downloads that should check via GitHub tags
  "libsodium" => { type: :github, owner: "jedisct1", repo: "libsodium", prefix: "" },
  "liblzma" => { type: :github, owner: "tukaani-project", repo: "xz", prefix: "v" },
  # GitHub tags use underscores (R_2_6_4) instead of dots in version
  "expat" => { type: :github, owner: "libexpat", repo: "libexpat", prefix: "R_", version_separator: "_" },
  # Check URL or pattern differs from download URL
  "openssl" => { type: :http, url: "https://openssl-library.org/source/", pattern: /openssl-(3\.\d+\.\d+)\.tar\.gz/ },
  "curl" => { type: :http, url: "https://curl.se/download/", pattern: /curl-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "bzip2" => { type: :http, url: "https://sourceware.org/pub/bzip2/", pattern: /bzip2-(\d+\.\d+\.\d+)\.tar\.gz/ },
  "ruby" => { type: :http, url: "https://cache.ruby-lang.org/pub/ruby/3.4/", pattern: /ruby-(3\.4\.\d+)\.tar\.gz/ },
  "cacerts" => { type: :http, url: "https://curl.se/ca/", pattern: /cacert-(\d{4}-\d{2}-\d{2})\.pem/ },
  "pcre" => { type: :http, url: "https://sourceforge.net/projects/pcre/files/pcre/", pattern: %r{/pcre/(\d+\.\d+)/} },
  # GNOME: version discovery via cache.json rather than directory listing
  "libxml2" => { type: :http, url: "https://download.gnome.org/sources/libxml2/cache.json", pattern: /(\d+\.\d+\.\d+)/ },
  "libxslt" => { type: :http, url: "https://download.gnome.org/sources/libxslt/cache.json", pattern: /(\d+\.\d+\.\d+)/ },
}.freeze

# Software to skip (binary downloads, platform-specific, not meaningful to check)
SKIP_VERSION_CHECK = %w{
  server-open-jre ruby-msys2-devkit ruby-windows-devkit ruby-windows-devkit-bash
  nodejs-binary ibm-jre jre-from-jdk
  elasticsearch opensearch openssl-fips
  go
}.freeze

# ---------------------------------------------------------------------------
# GitHub: fetch tags and find highest semver
# ---------------------------------------------------------------------------
def check_github_tags(owner, repo, prefix: "v", version_separator: ".")
  uri = URI("https://api.github.com/repos/#{owner}/#{repo}/tags?per_page=100")
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/vnd.github.v3+json"
  req["User-Agent"] = "omnibus-software-version-checker"

  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  return nil unless resp.code == "200"

  tags = JSON.parse(resp.body).map { |t| t["name"] }
  versions = tags.filter_map do |tag|
    cleaned = tag.sub(/^#{Regexp.escape(prefix)}/, "")
    cleaned = cleaned.tr(version_separator, ".") if version_separator != "."
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
# Auto-detect check strategy from a software's source URL
# ---------------------------------------------------------------------------
def infer_github_prefix(url, version)
  tag = nil
  if url =~ %r{/releases/download/([^/]+)/}
    tag = $1
  elsif url =~ %r{/archive/(?:refs/tags/)?([^/]+)\.tar}
    tag = $1
  end
  return "v" unless tag

  if tag =~ /^(.*)#{Regexp.escape(version)}$/
    $1
  else
    ""
  end
end

def infer_check_strategy(name, source_url, version)
  return SOURCE_OVERRIDES[name] if SOURCE_OVERRIDES.key?(name)
  return nil unless source_url && version
  return nil if SKIP_VERSION_CHECK.include?(name)

  uri = URI(source_url)

  # GitHub source -> check via tags API
  if uri.host == "github.com"
    match = source_url.match(%r{github\.com/([^/]+)/([^/]+)/})
    return nil unless match

    owner, repo = match[1], match[2]
    prefix = infer_github_prefix(source_url, version)
    return { type: :github, owner: owner, repo: repo, prefix: prefix }
  end

  # HTTP source -> derive directory listing URL and filename pattern
  filename = File.basename(uri.path)
  return nil if filename.empty? || !filename.include?(version)

  dir_url = source_url.sub(%r{/[^/]+$}, "/")
  parts = filename.split(version, 2)
  return nil if parts.length != 2

  pre = Regexp.escape(parts[0])
  post = Regexp.escape(parts[1])
  pattern = /#{pre}([^\s"<>]+?)#{post}/

  { type: :http, url: dir_url, pattern: pattern }
rescue URI::InvalidURIError
  nil
end

# ---------------------------------------------------------------------------
# Check a single software for updates
# ---------------------------------------------------------------------------
def check_for_update(name, strategy, current_version)
  latest = nil

  if strategy[:type] == :github
    latest = check_github_tags(
      strategy[:owner], strategy[:repo],
      prefix: strategy[:prefix] || "v",
      version_separator: strategy[:version_separator] || "."
    )
  elsif strategy[:type] == :http
    latest = check_http_directory(strategy[:url], strategy[:pattern])
  end

  return nil unless latest

  begin
    if Gem::Version.new(latest) > Gem::Version.new(current_version)
      { name: name, current: current_version, latest: latest }
    end
  rescue ArgumentError
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
  when :put
    req = Net::HTTP::Put.new(uri)
    req.body = body.to_json if body
    req["Content-Type"] = "application/json"
  end

  if ENV["CINC_PROJECT_TOKEN"]
    req["PRIVATE-TOKEN"] = GITLAB_TOKEN
  else
    req["JOB-TOKEN"] = GITLAB_TOKEN
  end
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

def get_file_from_branch(branch_name, file_path)
  encoded_path = URI.encode_www_form_component(file_path)
  encoded_branch = URI.encode_www_form_component(branch_name)
  resp = gitlab_api(:get, "/projects/#{CI_PROJECT_ID}/repository/files/#{encoded_path}/raw?ref=#{encoded_branch}")
  return nil unless resp.code == "200"

  resp.body
end

def update_mr_description(mr_iid, description)
  gitlab_api(:put, "/projects/#{CI_PROJECT_ID}/merge_requests/#{mr_iid}", {
    description: description,
  })
end

def find_open_mr(branch_name)
  encoded = URI.encode_www_form_component(branch_name)
  resp = gitlab_api(:get, "/projects/#{CI_PROJECT_ID}/merge_requests?source_branch=#{encoded}&state=opened")
  return nil unless resp.code == "200"

  mrs = JSON.parse(resp.body)
  mrs.first
end

# ---------------------------------------------------------------------------
# Extract the source URL template from a software definition file.
# Returns the URL string with #{version} still as a literal placeholder.
# ---------------------------------------------------------------------------
def extract_source_url_template(file)
  content = File.read(file)
  # Match: source url: "https://...#{version}..."
  if content =~ /^\s*source\s+url:\s*["']([^"']*\#\{version\}[^"']*)["']/
    $1
  end
end

# ---------------------------------------------------------------------------
# Resolve a source URL template to a concrete URL for a given version.
# ---------------------------------------------------------------------------
def resolve_source_url(template, version)
  template.gsub('#{version}', version)
end

# ---------------------------------------------------------------------------
# Download a URL and compute its SHA256 hex digest. Follows redirects.
# Returns the hex digest string, or nil on failure.
# ---------------------------------------------------------------------------
def download_sha256(url, max_redirects: 5)
  uri = URI(url)
  max_redirects.times do
    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                           open_timeout: 15, read_timeout: 60) do |http|
                             http.request(Net::HTTP::Get.new(uri))
                           end

    case resp
    when Net::HTTPSuccess
      return Digest::SHA256.hexdigest(resp.body)
    when Net::HTTPRedirection
      uri = URI(resp["location"])
    else
      $stderr.puts "  Download failed for #{url}: HTTP #{resp.code}"
      return nil
    end
  end
  $stderr.puts "  Too many redirects for #{url}"
  nil
rescue StandardError => e
  $stderr.puts "  Download error for #{url}: #{e.message}"
  nil
end

# ---------------------------------------------------------------------------
# Build a version line: version("X.Y.Z") { source sha256: "abc..." }
# ---------------------------------------------------------------------------
def version_line(version, sha256)
  "version(\"#{version}\") { source sha256: \"#{sha256}\" }"
end

# ---------------------------------------------------------------------------
# Insert a version line into file content. Adds it after the last existing
# version(...) line so it appears at the top of the version block.
# Returns updated content, or original content if no version block found.
# ---------------------------------------------------------------------------
def insert_version_line(content, new_line)
  lines = content.lines
  last_version_idx = nil
  lines.each_with_index do |line, idx|
    last_version_idx = idx if line =~ /^version\(/
  end

  if last_version_idx
    # Find the first version line to insert at the top of the block
    first_version_idx = lines.index { |line| line =~ /^version\(/ }
    lines.insert(first_version_idx, "#{new_line}\n")
    lines.join
  else
    content
  end
end

# ---------------------------------------------------------------------------
# Update a software definition file with new default_version.
# Returns the updated content string without writing to disk.
# ---------------------------------------------------------------------------
def updated_default_version_content(file, old_version, new_version)
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
# Update default_version in the local software definition file on disk.
# ---------------------------------------------------------------------------
def update_local_file(name, old_version, new_version)
  file_path = File.join(OmnibusSoftware.root, "config", "software", "#{name}.rb")
  new_content = updated_default_version_content(file_path, old_version, new_version)
  return false unless new_content

  File.write(file_path, new_content)
  true
end

# ---------------------------------------------------------------------------
# Create a merge request for a version update
# ---------------------------------------------------------------------------
def create_version_update_mr(update)
  name = update[:name]
  current = update[:current]
  latest = update[:latest]

  branch_name = "auto/update-#{name}-#{latest}"
  file_path = "config/software/#{name}.rb"
  full_path = File.join(OmnibusSoftware.root, file_path)

  # Try to compute sha256 for the new version
  url_template = extract_source_url_template(full_path)
  sha256 = nil
  if url_template
    download_url = resolve_source_url(url_template, latest)
    puts "  Downloading #{download_url} for sha256..."
    sha256 = download_sha256(download_url)
    puts "  sha256: #{sha256}" if sha256
  end

  if branch_exists?(branch_name)
    return update_existing_mr(branch_name, file_path, name, current, latest, sha256)
  end

  new_content = updated_default_version_content(full_path, current, latest)
  return unless new_content

  if sha256
    new_content = insert_version_line(new_content, version_line(latest, sha256))
  else
    puts "  Could not compute sha256, MR will need manual checksum"
  end

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

  create_mr_with_description(branch_name, name, current, latest, sha256)
end

# ---------------------------------------------------------------------------
# Update an existing MR branch with checksum if missing
# ---------------------------------------------------------------------------
def update_existing_mr(branch_name, file_path, name, current, latest, sha256)
  unless sha256
    puts "  Branch #{branch_name} already exists, no checksum to add"
    return
  end

  # Fetch current file from the branch to check if checksum already present
  branch_content = get_file_from_branch(branch_name, file_path)
  unless branch_content
    puts "  Branch #{branch_name} exists but could not fetch file, skipping"
    return
  end

  if branch_content.include?("version(\"#{latest}\")")
    puts "  Branch #{branch_name} already has version line for #{latest}, skipping"
    return
  end

  # Add the version line
  new_content = insert_version_line(branch_content, version_line(latest, sha256))
  commit_msg = "Add sha256 checksum for #{name} #{latest}"
  resp = create_commit(branch_name, file_path, new_content, commit_msg)
  unless resp.code == "201"
    $stderr.puts "  Failed to add checksum commit: #{resp.code} #{resp.body}"
    return
  end

  puts "  Added checksum to existing branch #{branch_name}"

  # Update MR description if there's an open MR
  mr = find_open_mr(branch_name)
  if mr
    checksum_note = "> Checksum for `#{latest}` was computed automatically."
    description = <<~MD
      Automated version update for **#{name}**.

      | | Version |
      |---|---|
      | Current | `#{current}` |
      | Latest | `#{latest}` |

      #{checksum_note}
      > - Verify the build succeeds in CI before merging
    MD
    update_mr_description(mr["iid"], description)
    puts "  Updated MR !#{mr["iid"]} description"
  end
end

# ---------------------------------------------------------------------------
# Create MR with appropriate description
# ---------------------------------------------------------------------------
def create_mr_with_description(branch_name, name, current, latest, sha256)
  title = "Update #{name} to #{latest}"
  checksum_note = if sha256
                    "> Checksum for `#{latest}` was computed automatically."
                  else
                    "> **Note**: Could not compute sha256 automatically. You need to:\n" \
                    "> - Add a `version(\"#{latest}\")` line with the correct sha256 checksum"
                  end
  description = <<~MD
    Automated version update for **#{name}**.

    | | Version |
    |---|---|
    | Current | `#{current}` |
    | Latest | `#{latest}` |

    #{checksum_note}
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
# Main (only runs when executed directly, not when required by specs)
# ---------------------------------------------------------------------------
if __FILE__ == $PROGRAM_NAME
  filter = ARGV.first

  puts "Loading software definitions via omnibus..."

  updates = []
  skipped = 0
  checked = 0

  Omnibus::Config.local_software_dirs(OmnibusSoftware.root)
  project = Omnibus::Project.new.evaluate do
    name "version-check"
    install_dir "/tmp/version-check"
  end

  Dir.glob(OmnibusSoftware.root.join("config/software/*.rb")).sort.each do |filepath|
    sw_name = File.basename(filepath, ".rb")

    next if filter && sw_name != filter
    next if File.foreach(filepath).any? { |line| line.include?(DEPRECATED_COMMENT) }

    software = Omnibus::Software.load(project, sw_name, nil)
    current_version = software.default_version
    source_url = software.source && software.source[:url]

    # Skip software with no version, git-only sources (unless overridden), or no source
    next unless current_version
    next if !source_url && !SOURCE_OVERRIDES.key?(sw_name)

    strategy = infer_check_strategy(sw_name, source_url, current_version)
    unless strategy
      next unless filter # only show "skipped" when explicitly requested

      puts "Checking #{sw_name}... skipped (no checker)"
      skipped += 1
      next
    end

    checked += 1
    print "Checking #{sw_name}..."

    update = check_for_update(sw_name, strategy, current_version)
    if update
      puts " UPDATE AVAILABLE: #{update[:current]} -> #{update[:latest]}"
      updates << update
    else
      puts " up to date (#{current_version})"
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
  if updates.any? && GITLAB_TOKEN && CI_PROJECT_ID && !DRY_RUN
    puts ""
    puts "Creating merge requests..."
    updates.each do |update|
      puts "Processing #{update[:name]}..."
      create_version_update_mr(update)
    end
  elsif updates.any? && DRY_RUN
    puts ""
    puts "DRY_RUN=true, no files modified. Updates that would be applied:"
    updates.each { |u| puts "  #{u[:name]}: #{u[:current]} -> #{u[:latest]}" }
  elsif updates.any?
    puts ""
    puts "Updating local files..."
    updates.each do |update|
      full_path = File.join(OmnibusSoftware.root, "config", "software", "#{update[:name]}.rb")
      if update_local_file(update[:name], update[:current], update[:latest])
        puts "  Updated config/software/#{update[:name]}.rb"
        # Also compute and insert checksum
        url_template = extract_source_url_template(full_path)
        if url_template
          download_url = resolve_source_url(url_template, update[:latest])
          puts "  Downloading #{download_url} for sha256..."
          sha256 = download_sha256(download_url)
          if sha256
            puts "  sha256: #{sha256}"
            content = File.read(full_path)
            content = insert_version_line(content, version_line(update[:latest], sha256))
            File.write(full_path, content)
            puts "  Added version line with checksum"
          end
        end
      end
    end
    puts "Not in CI (no CINC_PROJECT_TOKEN/CI_PROJECT_ID), skipping MR creation."
  end
end # if __FILE__ == $PROGRAM_NAME
