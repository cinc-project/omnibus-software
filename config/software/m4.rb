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
# version_list: url=https://ftp.osuosl.org/pub/gnu/m4/ filter=m4-*.tar.gz

name "m4"
default_version "1.4.21"

license "GPL-3.0"
license_file "COPYING"
skip_transitive_dependency_licensing true

version("1.4.21") { source sha256: "38ae59f7a30bf9c108193cc5c25fbb06014f21e230c7ede2eff614f7b7c37ed8" }

source url: "https://ftp.osuosl.org/pub/gnu/m4/m4-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/m4-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"
relative_path "m4-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  command "./configure --prefix=#{install_dir}/embedded", env: env

  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env
end
