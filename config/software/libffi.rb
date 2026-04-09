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

name "libffi"
default_version "3.5.2"

license "MIT"
license_file "LICENSE"
skip_transitive_dependency_licensing true

# version_list: url=https://github.com/libffi/libffi/releases  filter=*.tar.gz

version("3.5.2") { source sha256: "f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc" }

source url: "https://github.com/libffi/libffi/releases/download/v#{version}/libffi-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "libffi-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  configure_command = ["--disable-docs",
                       "--disable-multi-os-directory",
  ]

  configure(*configure_command, env: env)

  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env

  # libffi's default install location of header files is awful...
  mkdir "#{install_dir}/embedded/include"
  copy "#{install_dir}/embedded/lib/libffi-#{version}/include/*", "#{install_dir}/embedded/include/"

end
