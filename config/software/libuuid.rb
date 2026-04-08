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
# expeditor/ignore: deprecated 2021-11
#

name "libuuid"
default_version "2.42"

license "LGPL-2.1"
license_file "COPYING"

source url: "https://www.kernel.org/pub/linux/utils/util-linux/v#{version}/util-linux-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/util-linux-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

# version_list: url=https://www.kernel.org/pub/linux/utils/util-linux/ filter=v*.tar.gz

version("2.42") { source sha256: "a27118475651ef3d8f0ef1f516121f20a3527e45234f55546f31832bba943768" }

relative_path "util-linux-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  configure "--disable-all-programs", "--enable-libuuid", "--without-python",
            "--disable-nls", "--disable-asciidoc", "--disable-poman",
            "--disable-bash-completion", env: env

  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env

  # Remove man pages installed by util-linux
  delete "#{install_dir}/embedded/share/man/man3/uuid*"
  delete "#{install_dir}/embedded/share/man/man5/terminal-colors.d.5"
end
