require "webmock/rspec"
require "json"
require "tmpdir"
require "fileutils"

# Load the script (guarded by __FILE__ == $PROGRAM_NAME so main won't run)
require_relative "../scripts/check_upstream_versions"

RSpec.describe "check_upstream_versions" do
  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.allow_net_connect!
  end

  # -----------------------------------------------------------------------
  # check_github_tags
  # -----------------------------------------------------------------------
  describe "#check_github_tags" do
    let(:tags_url) { "https://api.github.com/repos/libffi/libffi/tags?per_page=100" }

    it "returns the highest stable version with prefix stripped" do
      tags = [
        { "name" => "v3.5.2" },
        { "name" => "v3.5.1" },
        { "name" => "v3.4.6" },
      ]
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = check_github_tags("libffi", "libffi", prefix: "v")
      expect(result).to eq("3.5.2")
    end

    it "filters out pre-release versions" do
      tags = [
        { "name" => "v4.0.0-rc1" },
        { "name" => "v3.5.2-beta" },
        { "name" => "v3.5.1" },
        { "name" => "v3.4.0-alpha" },
        { "name" => "v3.3.0-pre1" },
      ]
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = check_github_tags("libffi", "libffi", prefix: "v")
      expect(result).to eq("3.5.1")
    end

    it "handles empty prefix" do
      tags_url = "https://api.github.com/repos/jedisct1/libsodium/tags?per_page=100"
      tags = [
        { "name" => "1.0.21-RELEASE" },
        { "name" => "1.0.20-RELEASE" },
        { "name" => "1.0.18" },
      ]
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = check_github_tags("jedisct1", "libsodium", prefix: "")
      expect(result).to eq("1.0.21-RELEASE")
    end

    it "handles version_separator for underscore-delimited tags" do
      tags_url = "https://api.github.com/repos/libexpat/libexpat/tags?per_page=100"
      tags = [
        { "name" => "R_2_7_5" },
        { "name" => "R_2_6_4" },
        { "name" => "R_2_6_3" },
      ]
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = check_github_tags("libexpat", "libexpat", prefix: "R_", version_separator: "_")
      expect(result).to eq("2.7.5")
    end

    it "skips non-semver tags" do
      tags = [
        { "name" => "not-a-version" },
        { "name" => "v3.5.2" },
        { "name" => "latest" },
      ]
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = check_github_tags("libffi", "libffi", prefix: "v")
      expect(result).to eq("3.5.2")
    end

    it "returns nil on non-200 response" do
      stub_request(:get, tags_url).to_return(status: 404)

      result = check_github_tags("libffi", "libffi", prefix: "v")
      expect(result).to be_nil
    end

    it "returns nil when no valid versions found" do
      tags = [
        { "name" => "some-branch" },
        { "name" => "not-semver" },
      ]
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = check_github_tags("libffi", "libffi", prefix: "v")
      expect(result).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # check_http_directory
  # -----------------------------------------------------------------------
  describe "#check_http_directory" do
    let(:dir_url) { "https://ftp.osuosl.org/pub/gnu/bash/" }

    it "returns the highest version matching the pattern" do
      html = <<~HTML
        <a href="bash-5.2.15.tar.gz">bash-5.2.15.tar.gz</a>
        <a href="bash-5.1.16.tar.gz">bash-5.1.16.tar.gz</a>
        <a href="bash-5.0.tar.gz">bash-5.0.tar.gz</a>
        <a href="bash-4.4.18.tar.gz">bash-4.4.18.tar.gz</a>
      HTML
      stub_request(:get, dir_url).to_return(status: 200, body: html)

      result = check_http_directory(dir_url, /bash-(\d+\.\d+[\.\d]*)\.tar\.gz/)
      expect(result).to eq("5.2.15")
    end

    it "filters out pre-release versions" do
      html = <<~HTML
        <a href="thing-2.0.0-rc1.tar.gz">thing-2.0.0-rc1.tar.gz</a>
        <a href="thing-1.5.0.tar.gz">thing-1.5.0.tar.gz</a>
        <a href="thing-1.4.0-beta.tar.gz">thing-1.4.0-beta.tar.gz</a>
      HTML
      stub_request(:get, dir_url).to_return(status: 200, body: html)

      result = check_http_directory(dir_url, /thing-([^\s"<>]+?)\.tar\.gz/)
      expect(result).to eq("1.5.0")
    end

    it "returns nil on non-200 response" do
      stub_request(:get, dir_url).to_return(status: 403)

      result = check_http_directory(dir_url, /bash-(\d+)\.tar\.gz/)
      expect(result).to be_nil
    end

    it "returns nil when no versions match" do
      stub_request(:get, dir_url).to_return(status: 200, body: "<html>empty</html>")

      result = check_http_directory(dir_url, /bash-(\d+\.\d+)\.tar\.gz/)
      expect(result).to be_nil
    end

    it "returns nil and logs on network error" do
      stub_request(:get, dir_url).to_timeout

      expect {
        result = check_http_directory(dir_url, /bash-(\d+)\.tar\.gz/)
        expect(result).to be_nil
      }.to output(/HTTP check failed/).to_stderr
    end
  end

  # -----------------------------------------------------------------------
  # infer_github_prefix
  # -----------------------------------------------------------------------
  describe "#infer_github_prefix" do
    it "detects 'v' prefix from releases/download URL" do
      url = "https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz"
      expect(infer_github_prefix(url, "3.5.2")).to eq("v")
    end

    it "detects 'OTP-' prefix from archive URL" do
      url = "https://github.com/erlang/otp/archive/OTP-26.2.5.14.tar.gz"
      expect(infer_github_prefix(url, "26.2.5.14")).to eq("OTP-")
    end

    it "detects empty prefix from archive URL with no prefix" do
      url = "https://github.com/logrotate/logrotate/archive/3.21.0.tar.gz"
      expect(infer_github_prefix(url, "3.21.0")).to eq("")
    end

    it "detects prefix from refs/tags URL" do
      url = "https://github.com/Snapchat/KeyDB/archive/refs/tags/v6.3.4.tar.gz"
      expect(infer_github_prefix(url, "6.3.4")).to eq("v")
    end

    it "detects 'release-' prefix" do
      url = "https://github.com/Gecode/gecode/archive/refs/tags/release-3.7.3.tar.gz"
      expect(infer_github_prefix(url, "3.7.3")).to eq("release-")
    end

    it "defaults to 'v' when no tag found in URL" do
      url = "https://github.com/miyagawa/cpanminus/archive/1.7046.tar.gz"
      expect(infer_github_prefix(url, "1.7046")).to eq("")
    end
  end

  # -----------------------------------------------------------------------
  # infer_check_strategy
  # -----------------------------------------------------------------------
  describe "#infer_check_strategy" do
    it "returns override for software in SOURCE_OVERRIDES" do
      strategy = infer_check_strategy("openssl", "https://www.openssl.org/source/openssl-1.1.1t.tar.gz", "1.1.1t")
      expect(strategy[:type]).to eq(:http)
      expect(strategy[:url]).to eq("https://openssl-library.org/source/")
    end

    it "returns nil for software in SKIP_VERSION_CHECK" do
      strategy = infer_check_strategy("go", "https://dl.google.com/go/go1.19.5.linux-amd64.tar.gz", "1.19.5")
      expect(strategy).to be_nil
    end

    it "auto-detects GitHub releases URL" do
      strategy = infer_check_strategy(
        "libffi",
        "https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz",
        "3.5.2"
      )
      expect(strategy).to eq({ type: :github, owner: "libffi", repo: "libffi", prefix: "v" })
    end

    it "auto-detects GitHub archive URL" do
      strategy = infer_check_strategy(
        "erlang",
        "https://github.com/erlang/otp/archive/OTP-26.2.5.14.tar.gz",
        "26.2.5.14"
      )
      expect(strategy).to eq({ type: :github, owner: "erlang", repo: "otp", prefix: "OTP-" })
    end

    it "auto-detects HTTP directory listing URL" do
      strategy = infer_check_strategy(
        "bash",
        "https://ftp.osuosl.org/pub/gnu/bash/bash-5.2.15.tar.gz",
        "5.2.15"
      )
      expect(strategy[:type]).to eq(:http)
      expect(strategy[:url]).to eq("https://ftp.osuosl.org/pub/gnu/bash/")
      expect("bash-5.3.tar.gz").to match(strategy[:pattern])
    end

    it "auto-detects HTTP with different archive extension" do
      strategy = infer_check_strategy(
        "gmp",
        "https://ftp.osuosl.org/pub/gnu/gmp/gmp-6.3.0.tar.bz2",
        "6.3.0"
      )
      expect(strategy[:type]).to eq(:http)
      expect(strategy[:url]).to eq("https://ftp.osuosl.org/pub/gnu/gmp/")
      expect("gmp-6.4.0.tar.bz2").to match(strategy[:pattern])
      expect("gmp-6.4.0.tar.gz").not_to match(strategy[:pattern])
    end

    it "returns nil for nil source_url without override" do
      strategy = infer_check_strategy("chef", nil, "stable/cinc")
      expect(strategy).to be_nil
    end

    it "returns nil for nil version" do
      strategy = infer_check_strategy("something", "https://example.com/file.tar.gz", nil)
      expect(strategy).to be_nil
    end

    it "returns nil when version not found in filename" do
      strategy = infer_check_strategy(
        "something",
        "https://example.com/downloads/package.tar.gz",
        "1.0.0"
      )
      expect(strategy).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # check_for_update
  # -----------------------------------------------------------------------
  describe "#check_for_update" do
    it "returns update hash when newer version exists (GitHub)" do
      tags = [{ "name" => "v3.6.0" }, { "name" => "v3.5.2" }]
      stub_request(:get, "https://api.github.com/repos/libffi/libffi/tags?per_page=100")
        .to_return(status: 200, body: tags.to_json, headers: { "Content-Type" => "application/json" })

      strategy = { type: :github, owner: "libffi", repo: "libffi", prefix: "v" }
      result = check_for_update("libffi", strategy, "3.5.2")

      expect(result).to eq({ name: "libffi", current: "3.5.2", latest: "3.6.0" })
    end

    it "returns nil when current is already latest" do
      tags = [{ "name" => "v3.5.2" }, { "name" => "v3.5.1" }]
      stub_request(:get, "https://api.github.com/repos/libffi/libffi/tags?per_page=100")
        .to_return(status: 200, body: tags.to_json, headers: { "Content-Type" => "application/json" })

      strategy = { type: :github, owner: "libffi", repo: "libffi", prefix: "v" }
      result = check_for_update("libffi", strategy, "3.5.2")

      expect(result).to be_nil
    end

    it "returns update hash when newer version exists (HTTP)" do
      html = '<a href="zlib-1.4.0.tar.gz">zlib-1.4.0.tar.gz</a>'
      stub_request(:get, "https://zlib.net/fossils/")
        .to_return(status: 200, body: html)

      strategy = { type: :http, url: "https://zlib.net/fossils/", pattern: /zlib-([^\s"<>]+?)\.tar\.gz/ }
      result = check_for_update("zlib", strategy, "1.3.2")

      expect(result).to eq({ name: "zlib", current: "1.3.2", latest: "1.4.0" })
    end

    it "handles non-semver versions via string comparison" do
      html = '<a href="cacert-2026-01-01.pem">cacert-2026-01-01.pem</a>'
      stub_request(:get, "https://curl.se/ca/")
        .to_return(status: 200, body: html)

      strategy = { type: :http, url: "https://curl.se/ca/", pattern: /cacert-(\d{4}-\d{2}-\d{2})\.pem/ }
      result = check_for_update("cacerts", strategy, "2025-12-02")

      expect(result).to eq({ name: "cacerts", current: "2025-12-02", latest: "2026-01-01" })
    end

    it "returns nil on API failure" do
      stub_request(:get, "https://api.github.com/repos/libffi/libffi/tags?per_page=100")
        .to_return(status: 500)

      strategy = { type: :github, owner: "libffi", repo: "libffi", prefix: "v" }
      result = check_for_update("libffi", strategy, "3.5.2")

      expect(result).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # updated_default_version_content
  # -----------------------------------------------------------------------
  describe "#updated_default_version_content" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(tmpdir) }

    it "replaces default_version with double quotes" do
      file = File.join(tmpdir, "test.rb")
      File.write(file, <<~RUBY)
        name "zlib"
        default_version "1.3.2"

        version("1.3.2") { source sha256: "abc123" }
      RUBY

      result = updated_default_version_content(file, "1.3.2", "1.4.0")
      expect(result).to include('default_version "1.4.0"')
      expect(result).to include('version("1.3.2")') # should NOT change version lines
    end

    it "replaces default_version with single quotes" do
      file = File.join(tmpdir, "test.rb")
      File.write(file, "default_version '2.0.0'\n")

      result = updated_default_version_content(file, "2.0.0", "2.1.0")
      expect(result).to include("default_version '2.1.0'")
    end

    it "returns nil when version not found" do
      file = File.join(tmpdir, "test.rb")
      File.write(file, 'default_version "3.0.0"')

      expect {
        result = updated_default_version_content(file, "2.0.0", "2.1.0")
        expect(result).to be_nil
      }.to output(/WARNING/).to_stderr
    end
  end

  # -----------------------------------------------------------------------
  # update_local_file
  # -----------------------------------------------------------------------
  describe "#update_local_file" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(tmpdir) }

    before do
      sw_dir = File.join(tmpdir, "config", "software")
      FileUtils.mkdir_p(sw_dir)
      File.write(File.join(sw_dir, "zlib.rb"), <<~RUBY)
        name "zlib"
        default_version "1.3.2"
      RUBY
      allow(OmnibusSoftware).to receive(:root).and_return(Pathname.new(tmpdir))
    end

    it "updates the file on disk and returns true" do
      expect(update_local_file("zlib", "1.3.2", "1.4.0")).to be true
      content = File.read(File.join(tmpdir, "config", "software", "zlib.rb"))
      expect(content).to include('default_version "1.4.0"')
    end

    it "returns false when version not found" do
      expect {
        expect(update_local_file("zlib", "9.9.9", "10.0.0")).to be false
      }.to output(/WARNING/).to_stderr
    end
  end

  # -----------------------------------------------------------------------
  # GitLab API helpers
  # -----------------------------------------------------------------------
  describe "GitLab API helpers" do
    before do
      stub_const("CI_SERVER_URL", "https://gitlab.com")
      stub_const("GITLAB_TOKEN", "test-token")
      stub_const("CI_PROJECT_ID", "12345")
    end

    describe "#branch_exists?" do
      it "returns true when branch exists" do
        stub_request(:get, "https://gitlab.com/api/v4/projects/12345/repository/branches/auto%2Fupdate-zlib-1.4.0")
          .to_return(status: 200, body: '{"name": "auto/update-zlib-1.4.0"}')

        expect(branch_exists?("auto/update-zlib-1.4.0")).to be true
      end

      it "returns false when branch does not exist" do
        stub_request(:get, "https://gitlab.com/api/v4/projects/12345/repository/branches/auto%2Fupdate-zlib-1.4.0")
          .to_return(status: 404)

        expect(branch_exists?("auto/update-zlib-1.4.0")).to be false
      end
    end

    describe "#create_branch" do
      it "sends correct POST request" do
        stub_request(:post, "https://gitlab.com/api/v4/projects/12345/repository/branches")
          .with(body: { branch: "auto/update-zlib-1.4.0", ref: "stable/cinc" }.to_json)
          .to_return(status: 201, body: '{"name": "auto/update-zlib-1.4.0"}')

        resp = create_branch("auto/update-zlib-1.4.0")
        expect(resp.code).to eq("201")
      end
    end

    describe "#create_merge_request" do
      it "sends correct POST request" do
        stub_request(:post, "https://gitlab.com/api/v4/projects/12345/merge_requests")
          .with(body: hash_including(
            "source_branch" => "auto/update-zlib-1.4.0",
            "target_branch" => "stable/cinc",
            "title" => "Update zlib to 1.4.0"
          ))
          .to_return(status: 201, body: '{"iid": 42}')

        resp = create_merge_request("auto/update-zlib-1.4.0", "Update zlib to 1.4.0", "desc")
        expect(resp.code).to eq("201")
      end
    end
  end

  # -----------------------------------------------------------------------
  # create_version_update_mr (integration)
  # -----------------------------------------------------------------------
  describe "#create_version_update_mr" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(tmpdir) }

    before do
      stub_const("CI_SERVER_URL", "https://gitlab.com")
      stub_const("GITLAB_TOKEN", "test-token")
      stub_const("CI_PROJECT_ID", "12345")

      sw_dir = File.join(tmpdir, "config", "software")
      FileUtils.mkdir_p(sw_dir)
      File.write(File.join(sw_dir, "zlib.rb"), <<~RUBY)
        name "zlib"
        default_version "1.3.2"
      RUBY
      allow(OmnibusSoftware).to receive(:root).and_return(Pathname.new(tmpdir))
    end

    it "creates branch, commit, and MR" do
      branch_check = stub_request(:get, "https://gitlab.com/api/v4/projects/12345/repository/branches/auto%2Fupdate-zlib-1.4.0")
        .to_return(status: 404)
      branch_create = stub_request(:post, "https://gitlab.com/api/v4/projects/12345/repository/branches")
        .to_return(status: 201, body: "{}")
      commit_create = stub_request(:post, "https://gitlab.com/api/v4/projects/12345/repository/commits")
        .to_return(status: 201, body: "{}")
      mr_create = stub_request(:post, "https://gitlab.com/api/v4/projects/12345/merge_requests")
        .to_return(status: 201, body: '{"iid": 42}')

      update = { name: "zlib", current: "1.3.2", latest: "1.4.0" }
      create_version_update_mr(update)

      expect(branch_check).to have_been_requested
      expect(branch_create).to have_been_requested
      expect(commit_create).to have_been_requested
      expect(mr_create).to have_been_requested
    end

    it "skips when branch already exists" do
      stub_request(:get, "https://gitlab.com/api/v4/projects/12345/repository/branches/auto%2Fupdate-zlib-1.4.0")
        .to_return(status: 200, body: '{"name": "auto/update-zlib-1.4.0"}')

      update = { name: "zlib", current: "1.3.2", latest: "1.4.0" }
      expect { create_version_update_mr(update) }.to output(/already exists/).to_stdout
    end
  end

  # -----------------------------------------------------------------------
  # SOURCE_OVERRIDES coverage
  # -----------------------------------------------------------------------
  describe "SOURCE_OVERRIDES" do
    it "has valid type for every entry" do
      SOURCE_OVERRIDES.each do |name, override|
        expect(%i{github http}).to include(override[:type]), "#{name} has invalid type #{override[:type]}"
      end
    end

    it "github overrides have owner and repo" do
      SOURCE_OVERRIDES.select { |_, v| v[:type] == :github }.each do |name, override|
        expect(override[:owner]).to be_a(String), "#{name} missing owner"
        expect(override[:repo]).to be_a(String), "#{name} missing repo"
      end
    end

    it "http overrides have url and pattern" do
      SOURCE_OVERRIDES.select { |_, v| v[:type] == :http }.each do |name, override|
        expect(override[:url]).to be_a(String), "#{name} missing url"
        expect(override[:pattern]).to be_a(Regexp), "#{name} missing pattern"
      end
    end
  end

  # -----------------------------------------------------------------------
  # SKIP_VERSION_CHECK
  # -----------------------------------------------------------------------
  describe "SKIP_VERSION_CHECK" do
    it "skips all listed software" do
      SKIP_VERSION_CHECK.each do |name|
        strategy = infer_check_strategy(name, "https://example.com/#{name}-1.0.tar.gz", "1.0")
        expect(strategy).to be_nil, "Expected #{name} to be skipped"
      end
    end
  end

  # -----------------------------------------------------------------------
  # End-to-end: infer + check round-trip
  # -----------------------------------------------------------------------
  describe "infer + check round-trip" do
    it "GitHub release: detects update for libarchive" do
      strategy = infer_check_strategy(
        "libarchive",
        "https://github.com/libarchive/libarchive/releases/download/v3.8.6/libarchive-3.8.6.tar.gz",
        "3.8.6"
      )
      expect(strategy[:type]).to eq(:github)

      tags = [{ "name" => "v3.9.0" }, { "name" => "v3.8.6" }]
      stub_request(:get, "https://api.github.com/repos/libarchive/libarchive/tags?per_page=100")
        .to_return(status: 200, body: tags.to_json, headers: { "Content-Type" => "application/json" })

      result = check_for_update("libarchive", strategy, "3.8.6")
      expect(result[:latest]).to eq("3.9.0")
    end

    it "HTTP directory: detects update for ncurses" do
      strategy = infer_check_strategy(
        "ncurses",
        "https://ftp.osuosl.org/pub/gnu/ncurses/ncurses-6.6.tar.gz",
        "6.6"
      )
      expect(strategy[:type]).to eq(:http)

      html = <<~HTML
        <a href="ncurses-6.6.tar.gz">ncurses-6.6.tar.gz</a>
        <a href="ncurses-6.7.tar.gz">ncurses-6.7.tar.gz</a>
      HTML
      stub_request(:get, "https://ftp.osuosl.org/pub/gnu/ncurses/")
        .to_return(status: 200, body: html)

      result = check_for_update("ncurses", strategy, "6.6")
      expect(result[:latest]).to eq("6.7")
    end

    it "override: detects update for openssl" do
      strategy = infer_check_strategy(
        "openssl",
        "https://www.openssl.org/source/openssl-1.1.1t.tar.gz",
        "1.1.1t"
      )
      expect(strategy[:type]).to eq(:http)
      expect(strategy[:url]).to eq("https://openssl-library.org/source/")

      html = '<a href="openssl-3.6.1.tar.gz">openssl-3.6.1.tar.gz</a>'
      stub_request(:get, "https://openssl-library.org/source/")
        .to_return(status: 200, body: html)

      result = check_for_update("openssl", strategy, "1.1.1t")
      expect(result[:latest]).to eq("3.6.1")
    end

    it "override: detects update for expat with underscore tags" do
      strategy = infer_check_strategy(
        "expat",
        "https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-2.6.4.tar.gz",
        "2.6.4"
      )
      expect(strategy[:type]).to eq(:github)

      tags = [{ "name" => "R_2_7_5" }, { "name" => "R_2_6_4" }]
      stub_request(:get, "https://api.github.com/repos/libexpat/libexpat/tags?per_page=100")
        .to_return(status: 200, body: tags.to_json, headers: { "Content-Type" => "application/json" })

      result = check_for_update("expat", strategy, "2.6.4")
      expect(result[:latest]).to eq("2.7.5")
    end
  end

  # -----------------------------------------------------------------------
  # Edge cases
  # -----------------------------------------------------------------------
  describe "edge cases" do
    it "infer_check_strategy handles invalid URI gracefully" do
      strategy = infer_check_strategy("bad", "not a url at all", "1.0")
      expect(strategy).to be_nil
    end

    it "check_for_update handles exception gracefully" do
      stub_request(:get, "https://api.github.com/repos/boom/boom/tags?per_page=100")
        .to_raise(Errno::ECONNREFUSED)

      strategy = { type: :github, owner: "boom", repo: "boom", prefix: "v" }
      expect {
        result = check_for_update("boom", strategy, "1.0")
        expect(result).to be_nil
      }.to output(/Error checking boom/).to_stderr
    end
  end
end
