#
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

name "gecode"
default_version "6.2.0"

license "MIT"
license_file "LICENSE"
skip_transitive_dependency_licensing true

# version_list: url=https://github.com/Gecode/gecode/releases/ filter=gecode-release-*.tar.gz

version("6.2.0") { source sha256: "27d91721a690db1e96fa9bb97cec0d73a937e9dc8062c3327f8a4ccb08e951fd" }

source url: "https://github.com/Gecode/gecode/archive/refs/tags/release-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/release-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "gecode-release-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  patch source: "gecode-6.2.0-autoconf_builtin.patch", plevel: 1
  patch source: "gecode-6.2.0-builtin_unreachable.patch", plevel: 1
  patch source: "gecode-6.2.0-fix_warnings.patch", plevel: 1
  patch source: "gecode-6.2.0-const_removal.patch", plevel: 1

  command "./configure" \
          " --prefix=#{install_dir}/embedded" \
          " --disable-doc-dot" \
          " --disable-doc-search" \
          " --disable-doc-tagfile" \
          " --disable-doc-chm" \
          " --disable-doc-docset" \
          " --disable-qt" \
          " --disable-examples", env: env

  make "-j #{workers}", env: env
  make "install", env: env
end
