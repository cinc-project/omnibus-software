#
# Copyright 2019-2020 Chef Software, Inc.
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

# This software definition installs project called 'patchelf' which can be
# used to change rpath of a precompiled binary.

name "patchelf"

default_version "0.18.0"

license :project_license

skip_transitive_dependency_licensing true

# version_list: url=https://github.com/NixOS/patchelf/releases filter=*.tar.gz

version("0.18.0") { source sha256: "64de10e4c6b8b8379db7e87f58030f336ea747c0515f381132e810dbf84a86e7" }

source url: "https://github.com/NixOS/patchelf/releases/download/#{version}/patchelf-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "patchelf-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)
  configure "--prefix #{install_dir}/embedded"
  make env: env
  make "install", env: env
end
