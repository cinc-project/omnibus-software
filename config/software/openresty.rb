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

name "openresty"
license "BSD-2-Clause"
license_file "README.markdown"
skip_transitive_dependency_licensing true
default_version "1.29.2.3"

dependency "pcre"
dependency "openssl"
dependency "zlib"

# versions_list: https://openresty.org/download/ filter=*.tar.gz
version("1.29.2.3") { source sha256: "315e49fa4568747fec4bdada9614d2ba287e7aed4b3430d7ea25685e24cc43ff" }

source url: "https://openresty.org/download/openresty-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "openresty-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)
  env["PATH"] += "#{env["PATH"]}:/usr/sbin:/sbin"

  configure = [
    "./configure",
    "--prefix=#{install_dir}/embedded",
    "--sbin-path=#{install_dir}/embedded/sbin/nginx",
    "--conf-path=#{install_dir}/embedded/conf/nginx.conf",
    "--with-http_ssl_module",
    "--with-debug",
    "--with-http_stub_status_module",
    # Building Nginx with non-system OpenSSL
    # http://www.ruby-forum.com/topic/207287#902308
    "--with-ld-opt=\"-L#{install_dir}/embedded/lib -Wl,-rpath,#{install_dir}/embedded/lib -lssl -lcrypto -ldl -lz\"",
    "--with-cc-opt=\"-L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include\"",
    # Options inspired by the OpenResty Cookbook
    "--with-md5-asm",
    "--with-sha1-asm",
    "--with-pcre-jit",
    "--without-http_ssi_module",
    "--without-mail_smtp_module",
    "--without-mail_imap_module",
    "--without-mail_pop3_module",
    "--with-http_v2_module",
    "--with-ipv6",
    # AIO support define in Openresty cookbook. Requires Kernel >= 2.6.22
    # Ubuntu 10.04 reports: 2.6.32-38-server #83-Ubuntu SMP
    # However, they require libatomic-ops-dev and libaio
    # '--with-file-aio',
    # '--with-libatomic'
  ]

  configure << "--with-luajit"

  command configure.join(" "), env: env

  make "-j #{workers}", env: env
  make "install", env: env

  touch "#{install_dir}/embedded/nginx/logs/.gitkeep"
end
