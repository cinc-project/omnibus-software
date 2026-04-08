#
# Copyright 2014 Chef Software, Inc.
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

name "expat"
default_version "2.7.5"

relative_path "expat-#{version}"
dependency "config_guess"

license "MIT"
license_file "COPYING"
skip_transitive_dependency_licensing true

# version_list: url=https://github.com/libexpat/libexpat/releases filter=*.tar.gz
source url: "https://github.com/libexpat/libexpat/releases/download/R_#{version.gsub(".", "_")}/expat-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

version("2.7.5") { source sha256: "9931f9860d18e6cf72d183eb8f309bfb96196c00e1d40caa978e95bc9aa978b6" }

build do
  env = with_standard_compiler_flags(with_embedded_path)

  update_config_guess(target: "conftools")

  command "./configure" \
          " --without-examples" \
          " --without-tests" \
          " --prefix=#{install_dir}/embedded", env: env

  make "-j #{workers}", env: env
  make "install", env: env
end
