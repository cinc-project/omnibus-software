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

name "libtool"
default_version "2.5.4"

license "GPL-2.0"
license_file "COPYING"
skip_transitive_dependency_licensing true

dependency "config_guess"

# version_list: url=https://ftp.osuosl.org/pub/gnu/libtool/ filter=*.tar.gz

version("2.5.4") { source sha256: "da8ebb2ce4dcf46b90098daf962cffa68f4b4f62ea60f798d0ef12929ede6adf" }

source url: "https://ftp.osuosl.org/pub/gnu/libtool/libtool-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "libtool-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  update_config_guess
  update_config_guess(target: "libltdl/config")

  command "./configure" \
          " --prefix=#{install_dir}/embedded", env: env

  make env: env
  make "install", env: env
end
