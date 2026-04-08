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

name "redis"

if version && version.satisfies?(">= 8")
  license "AGPLv3"
  license_file "LICENSE.txt"
else
  license "BSD-3-Clause"
  license_file "COPYING"
end
skip_transitive_dependency_licensing true

dependency "config_guess"
default_version "8.6.2"

version("8.6.2") { source sha256: "cea46526594fe05f05b9ff733179eb1263deccf4269059cf081fdef222634c88" }
version("5.0.14") { source sha256: "3ea5024766d983249e80d4aa9457c897a9f079957d0fb1f35682df233f997f32" }

source url: "https://download.redis.io/releases/redis-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "redis-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path).merge(
    "PREFIX" => "#{install_dir}/embedded"
  )

  update_config_guess

  if version.satisfies?("< 6.0")
    patch source: "password-from-environment.patch", plevel: 1, env: env
  end

  make "-j #{workers}", env: env
  make "install", env: env
end
