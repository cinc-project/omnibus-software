#
# Copyright:: Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

name "curl"
default_version "8.19.0"

dependency "zlib"
dependency "openssl"
dependency "cacerts"
dependency "libnghttp2"

license "MIT"
license_file "COPYING"
skip_transitive_dependency_licensing true

# version_list: url=https://curl.se/download/ filter=*.tar.gz
version("8.19.0") { source sha256: "2a2c11db4c122691aa23b4363befda1bfd801770bfebf41e1d21cee4f2ab0f71" }

source url: "https://curl.haxx.se/download/curl-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "curl-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  delete "#{project_dir}/src/tool_hugehelp.c"

  configure_options = [
    "--prefix=#{install_dir}/embedded",
    "--disable-option-checking",
    "--disable-manual",
    "--disable-debug",
    "--enable-optimize",
    "--disable-ldap",
    "--disable-ldaps",
    "--disable-rtsp",
    "--enable-proxy",
    "--disable-pop3",
    "--disable-imap",
    "--disable-smtp",
    "--disable-gopher",
    "--disable-dependency-tracking",
    "--enable-ipv6",
    "--without-brotli",
    "--without-libidn2",
    "--without-gnutls",
    "--without-librtmp",
    "--without-zsh-functions-dir",
    "--without-fish-functions-dir",
    "--disable-mqtt",
    "--with-ssl=#{install_dir}/embedded",
    "--with-zlib=#{install_dir}/embedded",
    "--with-ca-bundle=#{install_dir}/embedded/ssl/certs/cacert.pem",
    "--without-zstd",
    "--without-libpsl",
  ]

  configure(*configure_options, env: env)

  make "-j #{workers}", env: env
  make "install", env: env
end
