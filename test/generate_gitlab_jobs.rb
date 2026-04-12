#!/usr/bin/env ruby

require "open3"
require "yaml"

BRANCH = "stable/cinc".freeze

# Skip health check when it is not relevant
HEALTH_CHECK_SKIP_LIST = %w{ cacerts config_guess xproto util-macros musl gem-permissions go-uninstall preparation rust-uninstall shebang-cleanup version-manifest }.freeze
DEPRECATED_SKIP_LIST = %w{ cmake }.freeze
WINDOWS_ONLY_LIST = %w{ git-windows ruby-msys2-devkit }.freeze
OPENSSL_VALIDATION_TYPES = %w{ executable ruby providers }.freeze

# ---------------------------------------------------------------------------
# Extract version strings from a software definition file.
# When +build_all+ is true, only default_version lines are extracted (nightly).
# Otherwise all version/default_version lines are extracted (MR mode).
# ---------------------------------------------------------------------------
def parse_versions(file, build_all)
  versions = []

  File.readlines(file, encoding: "utf-8").each do |line|
    if build_all
      next unless line.match?(/^\s*default_version\b/)
    else
      next unless line.match?(/^\s*(default_)?version\b/)
    end

    # Extract the quoted version string; skip lines using variables only
    # For lines like: version("1.2.3") { source sha256: "abc..." }
    #   → first quoted string is the version
    # For lines like: default_version ENV["FOO"] || "1.1.1t"
    #   → skip ENV key, take the fallback value
    quoted = line.scan(/["']([^"']+)["']/).flatten
    quoted.reject! { |s| s.match?(/^[A-Z_]+$/) } # drop ENV key names
    quoted.reject! { |s| s.length == 64 && s.match?(/\A[0-9a-f]+\z/) } # drop sha256 hashes

    versions << quoted.first if quoted.first
  end

  versions.compact.uniq
end

# ---------------------------------------------------------------------------
# Collect the list of software definition files to build.
# ---------------------------------------------------------------------------
def collect_files_all
  Dir.glob("config/software/*.rb").select do |file|
    !File.readlines(file, encoding: "utf-8").any? { |l| l.match(/^\s*deprecated/) }
  end
end

def collect_files_mr
  _, status = Open3.capture2e("git config --global --add safe.directory /workdir")
  return nil unless status.success?

  _, status = Open3.capture2e("git fetch origin #{BRANCH}")
  return nil unless status.success?

  stdout, status = Open3.capture2("git diff --name-status origin/#{BRANCH}...HEAD config/software")
  return nil unless status.success?

  files = stdout.lines
    .map(&:chomp)
    .select { |l| l.match?(/^[AM]\t/) }
    .map { |l| l.sub(/^[AM]\t/, "") }
    .compact.uniq

  files.empty? ? nil : files
end

# ---------------------------------------------------------------------------
# Generate the CI job definitions from a list of software files.
# ---------------------------------------------------------------------------
def generate_jobs(files, build_all)
  jobs = {}

  files.each do |file|
    software = File.basename(file, ".rb")
    next if DEPRECATED_SKIP_LIST.include?(software)

    versions = parse_versions(file, build_all)

    versions.each do |ver|
      next if software == "chef" && ver == "local_source"

      skip_health_check = HEALTH_CHECK_SKIP_LIST.include?(software) ? "true" : ""
      safe_ver = ver.gsub("/", "_")
      build_template = WINDOWS_ONLY_LIST.include?(software) ? ".build:windows" : ".build"

      job_name = "build:#{software}_#{safe_ver}"
      jobs[job_name] = {
        "extends" => build_template,
        "cache" => {
          "key" => "#{software}-#{safe_ver}",
        },
        "variables" => {
          "SOFTWARE" => software,
          "VERSION" => ver,
          "CI" => "true",
          "SKIP_HEALTH_CHECK" => skip_health_check,
        },
      }

      if software == "openssl"
        # FIPS-enabled build job
        fips_job_name = "build:#{software}-fips_#{safe_ver}"
        jobs[fips_job_name] = {
          "extends" => ".build",
          "cache" => {
            "key" => "#{software}-fips-#{safe_ver}",
          },
          "variables" => {
            "SOFTWARE" => software,
            "VERSION" => ver,
            "CI" => "true",
            "OMNIBUS_FIPS_MODE" => "true",
            "SKIP_HEALTH_CHECK" => skip_health_check,
          },
        }

        # Ruby build jobs (builds Ruby linked against specific OpenSSL version)
        ruby_build_name = "build:openssl-ruby_#{safe_ver}"
        jobs[ruby_build_name] = {
          "extends" => ".build",
          "cache" => { "key" => "openssl-ruby-#{safe_ver}" },
          "variables" => {
            "SOFTWARE" => "ruby",
            "OPENSSL_VERSION" => ver,
            "CI" => "true",
            "SKIP_HEALTH_CHECK" => "",
          },
        }

        ruby_fips_build_name = "build:openssl-fips-ruby_#{safe_ver}"
        jobs[ruby_fips_build_name] = {
          "extends" => ".build",
          "cache" => { "key" => "openssl-fips-ruby-#{safe_ver}" },
          "variables" => {
            "SOFTWARE" => "ruby",
            "OPENSSL_VERSION" => ver,
            "CI" => "true",
            "OMNIBUS_FIPS_MODE" => "true",
            "SKIP_HEALTH_CHECK" => "",
          },
        }

        # Validation jobs for both non-fips and fips builds
        builds = {
          job_name => { suffix: "", ruby_build: ruby_build_name },
          fips_job_name => { suffix: "-fips", ruby_build: ruby_fips_build_name },
        }

        builds.each do |build_job, opts|
          fips = opts[:suffix] == "-fips"

          OPENSSL_VALIDATION_TYPES.each do |type|
            if type == "ruby"
              validate_dep = opts[:ruby_build]
              validate_script = "test/validation/validate_openssl_ruby.rb"
            else
              validate_dep = build_job
              validate_script = "test/validation/validate_openssl_#{type}.sh"
            end

            variables = {
              "SOFTWARE" => software,
              "VERSION" => ver,
              "CI" => "true",
            }
            variables["OMNIBUS_FIPS_MODE"] = "true" if fips

            jobs["validate:openssl#{opts[:suffix]}-#{type}_#{safe_ver}"] = {
              "extends" => ".validate",
              "cache" => { "key" => "openssl-validate#{opts[:suffix]}-#{type}-#{safe_ver}" },
              "needs" => [validate_dep],
              "variables" => variables,
              "script" => [validate_script],
            }
          end
        end
      end
    end
  end

  jobs
end

# ---------------------------------------------------------------------------
# Main entry point — only runs when executed directly
# ---------------------------------------------------------------------------
if __FILE__ == $PROGRAM_NAME
  build_all = ARGV.include?("--all")

  if build_all
    files = collect_files_all
  else
    files = collect_files_mr
    exit 0 if files.nil?
  end

  yaml_header = {
    "include" => [
      "local" => ".gitlab/build.yml",
    ],
    "stages" => %w{build validate},
  }

  jobs = generate_jobs(files, build_all)

  File.open("build-jobs.yml", "w") do |file|
    file.write(yaml_header.merge(jobs).to_yaml)
  end
end
