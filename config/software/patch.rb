#
# Copyright 2015-2018 Chef Software, Inc.
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

name "patch"

dependency "config_guess"

license "GPL-3.0"
license_file "COPYING"
skip_transitive_dependency_licensing true

default_version "2.8"

# version_list: url=https://ftp.osuosl.org/pub/gnu/patch/ filter=*.tar.gz

version("2.8") { source sha256: "308a4983ff324521b9b21310bfc2398ca861798f02307c79eb99bb0e0d2bf980" }

source url: "https://ftp.osuosl.org/pub/gnu/patch/patch-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "patch-#{version}"

env = with_standard_compiler_flags(with_embedded_path)

build do

  update_config_guess(target: "build-aux")

  configure "--disable-xattr", env: env
  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env
end
