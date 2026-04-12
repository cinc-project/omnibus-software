#
# Copyright 2026 Oregon State University
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

name "rebar3"
default_version "3.27.0"

license "Apache-2.0"
license_file "LICENSE"

dependency "erlang"

# versions_list: https://github.com/erlang/rebar3/tags filter=*.tar.gz
version("3.27.0") { source sha256: "985cae6e957334cfa549190b9f5efb9185c184a18fc181c87b8dde096ba79f38" }

source url: "https://github.com/erlang/rebar3/archive/refs/tags/#{version}.tar.gz"

relative_path "rebar3-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  command "./bootstrap", env: env
  copy "#{project_dir}/rebar3", "#{install_dir}/embedded/bin/"
end
