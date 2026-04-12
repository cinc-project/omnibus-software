name "test"
maintainer "Chef Software, Inc."
homepage "https://www.chef.io"

install_dir "#{default_root}/#{name}"

# Required for MSI packaging on Windows
if windows?
  package :msi do
    upgrade_code "2CD7259C-776D-4DDB-A4C8-6E544E580AA1"
    fast_msi true
  end
end

build_version   Omnibus::BuildVersion.semver
build_iteration 1

dependency ENV["SOFTWARE"]

if ENV["VERSION"]
  override ENV["SOFTWARE"].to_sym, version: ENV["VERSION"]
end

if ENV["OPENSSL_VERSION"]
  override :openssl, version: ENV["OPENSSL_VERSION"]
end