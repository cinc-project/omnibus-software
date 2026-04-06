#!/usr/bin/env ruby

require "open3"
require "yaml"

BUILD_ALL = ARGV.include?("--all")
BRANCH = "stable/cinc".freeze

# Read in all the versions that are specified by SOFTWARE
def version(version = nil)
  $versions << version
end

def default_version(version = nil)
  $versions << version
end

if BUILD_ALL
  # Nightly mode: build all non-deprecated software (default_version only)
  files = Dir.glob("config/software/*.rb").select do |file|
    !File.readlines(file).any? { |l| l.match(/^\s*deprecated/) }
  end
else
  # MR mode: build only changed software definitions
  _, status = Open3.capture2e("git config --global --add safe.directory /workdir")
  exit 1 if status != 0
  _, status = Open3.capture2e("git fetch origin #{BRANCH}")
  exit 1 if status != 0
  stdout, status = Open3.capture2("git diff --name-status origin/#{BRANCH}...HEAD config/software | awk 'match($1, \"A\"){print $2; next} match($1, \"M\"){print $2}'")
  exit 1 if status != 0

  files = stdout.lines.compact.uniq.map(&:chomp)
  exit 0 if files.empty?
end

jobs = {}
yaml_header = {
  "include" => [
    "local" => ".gitlab/build.yml",
  ],
}

# Skip health check when it is not relevant
health_check_skip_list = %w{ cacerts xproto util-macros }
deprecated_skip_list = %w{ git-windows cmake ruby-msys2-devkit }

files.each do |file|
  software = File.basename(file, ".rb")
  next if deprecated_skip_list.include?(software)

  $versions = []

  File.readlines(file).each do |line|
    if BUILD_ALL
      # Nightly: only build default_version
      if line.match(/^\s*default_version/)
        line.sub!(/\s*(do|{).*/, "")
        # rubocop:disable Security/Eval
        eval(line)
      end
    else
      # MR: build all defined versions
      if line.match(/^\s*(default_)?version/)
        line.sub!(/\s*(do|{).*/, "")
        # rubocop:disable Security/Eval
        eval(line)
      end
    end
  end

  $versions.compact.uniq.each do |version|
    next if software == "chef" && version == "local_source"

    skip_health_check = ""
    if health_check_skip_list.include?(software)
      skip_health_check = "1"
    end

    job_name = "build:#{software}_#{version.gsub("/", "_")}"
    jobs[job_name] = {
      "extends" => ".build",
      "cache" => {
        "key" => "#{software}-#{version.gsub("/", "_")}",
      },
      "variables" => {
        "SOFTWARE" => software,
        "VERSION" => version,
        "CI" => "true",
        "SKIP_HEALTH_CHECK" => skip_health_check,
      },
    }

    # OpenSSL validation jobs
    if software == "openssl" && Gem::Version.new(version) >= Gem::Version.new("3.0.9")
      safe_ver = version.gsub("/", "_")

      jobs["validate:openssl-executable_#{safe_ver}"] = {
        "extends" => ".build",
        "cache" => { "key" => "openssl-validate-exec-#{safe_ver}" },
        "needs" => [job_name],
        "variables" => {
          "SOFTWARE" => software,
          "VERSION" => version,
          "CI" => "true",
        },
        "script" => [
          "cd test",
          "bash ../test/validation/build_and_validate_openssl_executable.sh",
        ],
      }

      jobs["validate:openssl-ruby_#{safe_ver}"] = {
        "extends" => ".build",
        "cache" => { "key" => "openssl-validate-ruby-#{safe_ver}" },
        "needs" => [job_name],
        "variables" => {
          "SOFTWARE" => software,
          "VERSION" => version,
          "CI" => "true",
        },
        "script" => [
          "cd test",
          "bash ../test/validation/build_and_validate_openssl_ruby.sh",
        ],
      }

      jobs["validate:openssl-providers_#{safe_ver}"] = {
        "extends" => ".build",
        "cache" => { "key" => "openssl-validate-providers-#{safe_ver}" },
        "needs" => [job_name],
        "variables" => {
          "SOFTWARE" => software,
          "VERSION" => version,
          "CI" => "true",
        },
        "script" => [
          "cd test",
          "bash ../test/validation/build_and_validate_openssl_providers.sh",
        ],
      }
    end
  end
end

File.open("build-jobs.yml", "w") do |file|
  file.write(yaml_header.merge(jobs).to_yaml)
end
