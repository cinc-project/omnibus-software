require "tmpdir"
require "fileutils"
require "yaml"

# Load the script (guarded by __FILE__ == $PROGRAM_NAME so main won't run)
require_relative "../test/generate_gitlab_jobs"

RSpec.describe "generate_gitlab_jobs" do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  def write_software(name, content)
    path = File.join(tmpdir, "#{name}.rb")
    File.write(path, content)
    path
  end

  # -----------------------------------------------------------------------
  # parse_versions
  # -----------------------------------------------------------------------
  describe "#parse_versions" do
    it "extracts default_version in build_all mode" do
      path = write_software("zlib", <<~RUBY)
        name "zlib"
        default_version "1.3.1"
        version("1.3.0") { source sha256: "aaa" }
        version("1.3.1") { source sha256: "bbb" }
      RUBY
      expect(parse_versions(path, true)).to eq(["1.3.1"])
    end

    it "extracts all versions in MR mode" do
      path = write_software("zlib", <<~RUBY)
        name "zlib"
        default_version "1.3.1"
        version("1.3.0") { source sha256: "aaa" }
        version("1.3.1") { source sha256: "bbb" }
      RUBY
      expect(parse_versions(path, false)).to contain_exactly("1.3.1", "1.3.0")
    end

    it "strips block syntax from version lines" do
      path = write_software("curl", <<~RUBY)
        name "curl"
        default_version "8.7.1"
        version("8.7.1") do
          source sha256: "aaa"
        end
      RUBY
      expect(parse_versions(path, false)).to eq(["8.7.1"])
    end

    it "deduplicates versions" do
      path = write_software("test", <<~RUBY)
        name "test"
        default_version "2.0"
        version("2.0") { source sha256: "aaa" }
      RUBY
      expect(parse_versions(path, false)).to eq(["2.0"])
    end

    it "returns empty array when no versions found" do
      path = write_software("empty", <<~RUBY)
        name "empty"
        license "MIT"
      RUBY
      expect(parse_versions(path, true)).to eq([])
    end

    it "skips lines with only variable references" do
      path = write_software("ibm-jre", <<~RUBY)
        name "ibm-jre"
        app_version = "ibm-java-ppc64-80"
        default_version app_version
      RUBY
      expect(parse_versions(path, true)).to eq([])
    end

    it "extracts fallback version from ENV || pattern" do
      path = write_software("openssl", <<~RUBY)
        name "openssl"
        default_version ENV["CI_OPENSSL_VERSION"] || "1.1.1t"
      RUBY
      expect(parse_versions(path, true)).to eq(["1.1.1t"])
    end

    it "does not extract sha256 hashes as versions" do
      path = write_software("curl", <<~RUBY)
        name "curl"
        default_version "8.4.0"
        version("8.4.0") { source sha256: "816e41809c043ff285e8c0f06a75a1fa250211bbfb2dc0a037eeef39f1a9e427" }
      RUBY
      expect(parse_versions(path, false)).to eq(["8.4.0"])
    end

    it "ignores indented version lines only" do
      path = write_software("test", <<~RUBY)
        name "test"
          default_version "3.0"
          version("2.9") { source sha256: "abc" }
      RUBY
      expect(parse_versions(path, false)).to contain_exactly("3.0", "2.9")
    end
  end

  # -----------------------------------------------------------------------
  # generate_jobs
  # -----------------------------------------------------------------------
  describe "#generate_jobs" do
    it "generates a build job for each version" do
      path = write_software("zlib", <<~RUBY)
        name "zlib"
        default_version "1.3.1"
        version("1.3.0") { source sha256: "aaa" }
        version("1.3.1") { source sha256: "bbb" }
      RUBY
      jobs = generate_jobs([path], false)

      expect(jobs).to have_key("build:zlib_1.3.0")
      expect(jobs).to have_key("build:zlib_1.3.1")
      expect(jobs["build:zlib_1.3.1"]["variables"]["SOFTWARE"]).to eq("zlib")
      expect(jobs["build:zlib_1.3.1"]["variables"]["VERSION"]).to eq("1.3.1")
    end

    it "only builds default_version in build_all mode" do
      path = write_software("zlib", <<~RUBY)
        name "zlib"
        default_version "1.3.1"
        version("1.3.0") { source sha256: "aaa" }
        version("1.3.1") { source sha256: "bbb" }
      RUBY
      jobs = generate_jobs([path], true)

      expect(jobs).to have_key("build:zlib_1.3.1")
      expect(jobs).not_to have_key("build:zlib_1.3.0")
    end

    it "sets extends to .build" do
      path = write_software("curl", <<~RUBY)
        name "curl"
        default_version "8.7.1"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs["build:curl_8.7.1"]["extends"]).to eq(".build")
    end

    it "sets cache key from software and version" do
      path = write_software("curl", <<~RUBY)
        name "curl"
        default_version "8.7.1"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs["build:curl_8.7.1"]["cache"]["key"]).to eq("curl-8.7.1")
    end

    it "skips deprecated software" do
      path = write_software("cmake", <<~RUBY)
        name "cmake"
        default_version "3.19.7"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs).to be_empty
    end

    it "uses .build:windows template for windows-only software" do
      path = write_software("git-windows", <<~RUBY)
        name "git-windows"
        default_version "2.40.0"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs["build:git-windows_2.40.0"]["extends"]).to eq(".build:windows")
    end

    it "skips chef local_source version" do
      path = write_software("chef", <<~RUBY)
        name "chef"
        default_version "local_source"
        version("18.4.2") { source sha256: "aaa" }
      RUBY
      jobs = generate_jobs([path], false)
      expect(jobs).not_to have_key("build:chef_local_source")
      expect(jobs).to have_key("build:chef_18.4.2")
    end

    it "sets SKIP_HEALTH_CHECK for cacerts" do
      path = write_software("cacerts", <<~RUBY)
        name "cacerts"
        default_version "2024-03-11"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs["build:cacerts_2024-03-11"]["variables"]["SKIP_HEALTH_CHECK"]).to eq("true")
    end

    it "leaves SKIP_HEALTH_CHECK empty for normal software" do
      path = write_software("zlib", <<~RUBY)
        name "zlib"
        default_version "1.3.1"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs["build:zlib_1.3.1"]["variables"]["SKIP_HEALTH_CHECK"]).to eq("")
    end

    it "replaces slashes in version for job name and cache key" do
      path = write_software("test", <<~RUBY)
        name "test"
        default_version "v1/beta"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs).to have_key("build:test_v1_beta")
      expect(jobs["build:test_v1_beta"]["cache"]["key"]).to eq("test-v1_beta")
    end

    # -----------------------------------------------------------------------
    # OpenSSL validation jobs
    # -----------------------------------------------------------------------
    context "openssl validation jobs" do
      it "generates build and fips build jobs for openssl" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        expect(jobs).to have_key("build:openssl_3.5.5")
        expect(jobs).to have_key("build:openssl-fips_3.5.5")
        expect(jobs["build:openssl-fips_3.5.5"]["variables"]["OMNIBUS_FIPS_MODE"]).to eq("true")
      end

      it "generates ruby build jobs for openssl validation" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        expect(jobs).to have_key("build:openssl-ruby_3.5.5")
        expect(jobs["build:openssl-ruby_3.5.5"]["variables"]["SOFTWARE"]).to eq("ruby")
        expect(jobs["build:openssl-ruby_3.5.5"]["variables"]["OPENSSL_VERSION"]).to eq("3.5.5")

        expect(jobs).to have_key("build:openssl-fips-ruby_3.5.5")
        expect(jobs["build:openssl-fips-ruby_3.5.5"]["variables"]["SOFTWARE"]).to eq("ruby")
        expect(jobs["build:openssl-fips-ruby_3.5.5"]["variables"]["OMNIBUS_FIPS_MODE"]).to eq("true")
      end

      it "generates validation jobs for both non-fips and fips builds" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        %w{executable ruby providers}.each do |type|
          expect(jobs).to have_key("validate:openssl-#{type}_3.5.5")
          expect(jobs).to have_key("validate:openssl-fips-#{type}_3.5.5")
        end
      end

      it "validation jobs extend .validate" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        %w{executable ruby providers}.each do |type|
          expect(jobs["validate:openssl-#{type}_3.5.5"]["extends"]).to eq(".validate")
          expect(jobs["validate:openssl-fips-#{type}_3.5.5"]["extends"]).to eq(".validate")
        end
      end

      it "validation jobs run the correct validate script" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        expect(jobs["validate:openssl-executable_3.5.5"]["script"]).to eq(["test/validation/validate_openssl_executable.sh"])
        expect(jobs["validate:openssl-ruby_3.5.5"]["script"]).to eq(["test/validation/validate_openssl_ruby.rb"])
        expect(jobs["validate:openssl-providers_3.5.5"]["script"]).to eq(["test/validation/validate_openssl_providers.sh"])
      end

      it "executable and providers validations depend on openssl build" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        %w{executable providers}.each do |type|
          expect(jobs["validate:openssl-#{type}_3.5.5"]["needs"]).to eq(["build:openssl_3.5.5"])
          expect(jobs["validate:openssl-fips-#{type}_3.5.5"]["needs"]).to eq(["build:openssl-fips_3.5.5"])
        end
      end

      it "ruby validations depend on ruby build jobs" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        expect(jobs["validate:openssl-ruby_3.5.5"]["needs"]).to eq(["build:openssl-ruby_3.5.5"])
        expect(jobs["validate:openssl-fips-ruby_3.5.5"]["needs"]).to eq(["build:openssl-fips-ruby_3.5.5"])
      end

      it "fips validate jobs include OMNIBUS_FIPS_MODE" do
        path = write_software("openssl", <<~RUBY)
          name "openssl"
          default_version "3.5.5"
        RUBY
        jobs = generate_jobs([path], true)

        %w{executable ruby providers}.each do |type|
          expect(jobs["validate:openssl-fips-#{type}_3.5.5"]["variables"]["OMNIBUS_FIPS_MODE"]).to eq("true")
          expect(jobs["validate:openssl-#{type}_3.5.5"]["variables"]).not_to have_key("OMNIBUS_FIPS_MODE")
        end
      end

      it "does not generate validation jobs for non-openssl software" do
        path = write_software("curl", <<~RUBY)
          name "curl"
          default_version "8.7.1"
        RUBY
        jobs = generate_jobs([path], true)
        expect(jobs.keys.select { |k| k.start_with?("validate:") }).to be_empty
      end
    end

    # -----------------------------------------------------------------------
    # Multiple files
    # -----------------------------------------------------------------------
    it "processes multiple software files" do
      paths = [
        write_software("zlib", "default_version \"1.3.1\"\n"),
        write_software("curl", "default_version \"8.7.1\"\n"),
      ]
      jobs = generate_jobs(paths, true)

      expect(jobs).to have_key("build:zlib_1.3.1")
      expect(jobs).to have_key("build:curl_8.7.1")
    end

    it "handles files with no extractable versions" do
      path = write_software("empty", <<~RUBY)
        name "empty"
        license "MIT"
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs).to be_empty
    end

    it "handles variable-only versions gracefully" do
      path = write_software("ibm-jre", <<~RUBY)
        name "ibm-jre"
        app_version = "ibm-java-ppc64-80"
        default_version app_version
      RUBY
      jobs = generate_jobs([path], true)
      expect(jobs).to be_empty
    end
  end

  # -----------------------------------------------------------------------
  # collect_files_all
  # -----------------------------------------------------------------------
  describe "#collect_files_all" do
    it "returns config/software/*.rb files" do
      files = collect_files_all
      file_names = files.map { |f| File.basename(f, ".rb") }
      expect(file_names).to include("zlib")
      expect(file_names).to include("curl")
    end

    it "includes all software when none have deprecated directive" do
      files = collect_files_all
      expect(files.length).to be > 50
    end
  end

  # -----------------------------------------------------------------------
  # Integration: real software definitions
  # -----------------------------------------------------------------------
  describe "integration with real definitions" do
    it "generates valid jobs for all non-deprecated software" do
      files = collect_files_all
      jobs = generate_jobs(files, true)

      expect(jobs).not_to be_empty

      jobs.each do |name, job|
        next if name.start_with?("validate:")

        expect(job["extends"]).to be_a(String).and(satisfy { |v| [".build", ".build:windows"].include?(v) })
        expect(job["variables"]["SOFTWARE"]).to be_a(String)
        # Ruby build jobs for openssl validation use OPENSSL_VERSION instead of VERSION
        if job["variables"]["OPENSSL_VERSION"]
          expect(job["variables"]["OPENSSL_VERSION"]).not_to be_empty
        else
          expect(job["variables"]["VERSION"]).to be_a(String)
          expect(job["variables"]["VERSION"]).not_to be_empty
        end
      end
    end
  end
end
