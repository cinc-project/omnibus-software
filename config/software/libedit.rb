
# Copyright 2012-2014 Chef Software, Inc.
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

name "libedit"
default_version "20251016-3.1"

license "BSD-3-Clause"
license_file "COPYING"
skip_transitive_dependency_licensing true

dependency "ncurses"
dependency "config_guess"

# version_list: url=http://thrysoee.dk/editline/ filter=*.tar.gz

version("20251016-3.1") { source sha256: "21362b00653bbfc1c71f71a7578da66b5b5203559d43134d2dd7719e313ce041" }

source url: "https://www.thrysoee.dk/editline/libedit-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "libedit-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  update_config_guess

  command "./configure" \
          " --prefix=#{install_dir}/embedded", env: env

  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env
end
