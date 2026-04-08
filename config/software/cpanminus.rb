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

name "cpanminus"
default_version "1.7902"

license "Artistic-2.0"
license_file "http://dev.perl.org/licenses/artistic.html"
skip_transitive_dependency_licensing true

dependency "perl"

# version_list: url=https://metacpan.org/pod/App::cpanminus filter=*.tar.gz

version("1.7902") { source sha256: "7cbcd88430df9c66fd9fdf38e364db0eafa64ecda3ecdba3e2e8d19e9282a06e" }

source url: "https://github.com/miyagawa/cpanminus/archive/#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"
relative_path "cpanminus-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  command "cat cpanm | perl - App::cpanminus", env: env
end

# Perl after 5.18 does not come with this by default
build do
  env = with_standard_compiler_flags(with_embedded_path)

  command "cpanm Module::Build", env: env
end

